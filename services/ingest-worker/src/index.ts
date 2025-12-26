import { IngestRequestSchema } from "./validation";
import { sha256Hex } from "./crypto";
import { withPg } from "./db";

type IngestQueueMessage = {
  batch_id: string;
  tenant_id: string;
  r2_key: string;
  received_at: string; // ISO
};

export interface Env {
  RAW_BUCKET: R2Bucket;
  INGEST_QUEUE: Queue<IngestQueueMessage>;
  HYPERDRIVE: Hyperdrive;
  API_KEY_PEPPER: string;
}

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

function badRequest(details: unknown) {
  return json(400, { error: "bad_request", details });
}

function unauthorized() {
  return json(401, { error: "unauthorized" });
}

async function authenticateTenant(request: Request, env: Env): Promise<string | null> {
  const apiKey = request.headers.get("X-API-Key");
  if (!apiKey) return null;

  // Prefix speeds lookup; store only hash in DB.
  const keyPrefix = apiKey.slice(0, 8);
  const keyHash = await sha256Hex(`${env.API_KEY_PEPPER}:${apiKey}`);

  return await withPg(env, async (c) => {
    const res = await c.query(
      `SELECT tenant_id
         FROM tenant_api_keys
        WHERE key_prefix = $1
          AND key_hash = $2
          AND revoked_at IS NULL
        LIMIT 1`,
      [keyPrefix, keyHash],
    );
    return res.rowCount === 1 ? (res.rows[0].tenant_id as string) : null;
  });
}

async function upsertDeviceAndMetrics(env: Env, tenantId: string, deviceExternalId: string, metricNames: string[]) {
  return await withPg(env, async (c) => {
    await c.query("BEGIN");
    try {
      const devRes = await c.query(
        `INSERT INTO devices (tenant_id, external_id)
         VALUES ($1, $2)
         ON CONFLICT (tenant_id, external_id) DO UPDATE SET external_id = EXCLUDED.external_id
         RETURNING id`,
        [tenantId, deviceExternalId],
      );
      const deviceId = devRes.rows[0].id as string;

      const metricIds: Record<string, string> = {};
      for (const name of metricNames) {
        const mRes = await c.query(
          `INSERT INTO metrics (tenant_id, device_id, name)
           VALUES ($1, $2, $3)
           ON CONFLICT (tenant_id, device_id, name) DO UPDATE SET name = EXCLUDED.name
           RETURNING id`,
          [tenantId, deviceId, name],
        );
        metricIds[name] = mRes.rows[0].id as string;
      }

      await c.query("COMMIT");
      return { deviceId, metricIds };
    } catch (e) {
      await c.query("ROLLBACK");
      throw e;
    }
  });
}

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);

    if (url.pathname === "/v1/health" && request.method === "GET") {
      return json(200, { ok: true, service: "edgepulse-ingest", ts: new Date().toISOString() });
    }

    if (url.pathname === "/v1/ingest" && request.method === "POST") {
      const tenantId = await authenticateTenant(request, env);
      if (!tenantId) return unauthorized();

      let payload: unknown;
      try {
        payload = await request.json();
      } catch {
        return badRequest({ message: "Invalid JSON" });
      }

      const parsed = IngestRequestSchema.safeParse(payload);
      if (!parsed.success) return badRequest(parsed.error.flatten());

      const batchId = crypto.randomUUID();
      const receivedAt = new Date().toISOString();

      // Optional: pre-create device/metrics metadata (makes downstream normalisation easier)
      const metricNames = [...new Set(parsed.data.metrics.map((m) => m.name))];
      await upsertDeviceAndMetrics(env, tenantId, parsed.data.device_external_id, metricNames);

      // Archive raw payload to R2
      const day = receivedAt.slice(0, 10); // YYYY-MM-DD
      const r2Key = `tenant=${tenantId}/day=${day}/batch=${batchId}.json`;

      ctx.waitUntil(
        env.RAW_BUCKET.put(r2Key, JSON.stringify(parsed.data), {
          httpMetadata: { contentType: "application/json" },
          customMetadata: {
            tenant_id: tenantId,
            device_external_id: parsed.data.device_external_id,
            batch_id: batchId,
          },
        }),
      );

      // Enqueue async normalisation
      ctx.waitUntil(
        env.INGEST_QUEUE.send({
          batch_id: batchId,
          tenant_id: tenantId,
          r2_key: r2Key,
          received_at: receivedAt,
        }),
      );

      return json(202, { status: "accepted", batch_id: batchId, r2_key: r2Key });
    }

    return json(404, { error: "not_found" });
  },

  async queue(batch: MessageBatch<IngestQueueMessage>, env: Env, ctx: ExecutionContext): Promise<void> {
    // Normalise R2 payloads into datapoints
    for (const msg of batch.messages) {
      ctx.waitUntil(processIngestMessage(env, msg.body));
    }
  },
} satisfies ExportedHandler<Env>;

async function processIngestMessage(env: Env, m: IngestQueueMessage) {
  const obj = await env.RAW_BUCKET.get(m.r2_key);
  if (!obj) throw new Error(`R2 object not found: ${m.r2_key}`);

  const raw = await obj.text();
  const parsed = IngestRequestSchema.safeParse(JSON.parse(raw));
  if (!parsed.success) throw new Error(`Stored payload failed validation for ${m.r2_key}`);

  const { device_external_id, metrics } = parsed.data;

  await withPg(env, async (c) => {
    await c.query("BEGIN");
    try {
      const devRes = await c.query(
        `SELECT id FROM devices WHERE tenant_id = $1 AND external_id = $2 LIMIT 1`,
        [m.tenant_id, device_external_id],
      );
      if (devRes.rowCount !== 1) throw new Error("Device not found (expected pre-created)");

      const deviceId = devRes.rows[0].id as string;

      // Resolve metric IDs (created in pre-step)
      const names = [...new Set(metrics.map((x) => x.name))];
      const metRes = await c.query(
        `SELECT id, name FROM metrics WHERE tenant_id = $1 AND device_id = $2 AND name = ANY($3)`,
        [m.tenant_id, deviceId, names],
      );
      const nameToId = new Map<string, string>(metRes.rows.map((r) => [r.name as string, r.id as string]));

      // Insert datapoints
      for (const p of metrics) {
        const metricId = nameToId.get(p.name);
        if (!metricId) continue;

        await c.query(
          `INSERT INTO datapoints (tenant_id, metric_id, ts, value, unit, ingest_batch_id)
           VALUES ($1, $2, $3, $4, $5, $6)`,
          [m.tenant_id, metricId, p.ts, p.value, p.unit ?? null, m.batch_id],
        );
      }

      await c.query("COMMIT");
    } catch (e) {
      await c.query("ROLLBACK");
      throw e;
    }
  });
}
