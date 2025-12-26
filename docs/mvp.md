# EdgePulse MVP Specification

This document defines the Minimum Viable Product (MVP) scope for **EdgePulse**, a multi-tenant time-series telemetry ingestion and anomaly detection service built with Cloudflare (edge) + AWS (compute) + Postgres + Python ML.

## Goals
- Provide a production-grade ingestion API that is fast, secure, and auditable.
- Persist telemetry in a relational model suitable for analytics and scoring.
- Produce baseline anomaly scores on a schedule and expose them via API.
- Support basic operational visibility (health checks, ingestion status).
- Create a credible foundation for monetisation (tenant isolation, usage counting, retention).

## Non-goals
- Real-time streaming dashboards with sub-second latency.
- Complex multi-model ensembles or deep learning models (PyTorch upgrade is post-MVP).
- Full billing integration (Stripe), invoices, VAT, etc. (usage metering only).
- Full RBAC/SSO; only API key-based auth for MVP.
- Full alert escalation (SMS/phone/pager); webhooks only.

## Definitions
- **Tenant**: a paying customer boundary. Data must be isolated by tenant_id.
- **Device**: a telemetry source (external_id).
- **Metric**: a named series attached to a device (e.g., voltage/current/temperature).
- **Datapoint**: (ts, value, unit) for a given metric.
- **Window**: fixed interval (e.g., 300s) used for feature extraction and scoring.
- **Anomaly score**: numeric value per window (higher = more anomalous for MVP).

---

# Milestones and Acceptance Criteria

## MVP-1 — Ingestion and Persistence (Edge + DB)
### Scope
- `POST /v1/ingest` accepts telemetry payloads with API-key authentication.
- Payload is validated and archived to R2 (immutable raw archive).
- Ingestion is buffered through Cloudflare Queues.
- Queue consumer normalises and persists datapoints in Postgres.
- Minimal metadata upserts: devices and metrics.

### Acceptance criteria
1. **Auth**
   - Requests without `X-API-Key` return `401`.
   - Invalid keys return `401`.
   - No raw API keys are stored in DB (hash-only).

2. **Validation**
   - Invalid JSON returns `400`.
   - Schema validation errors return `400` with a useful error structure.

3. **Durability**
   - Every accepted ingest creates an R2 object (raw archive) using a deterministic key format.
   - Every accepted ingest enqueues exactly one message containing `{tenant_id, batch_id, r2_key}`.

4. **Normalisation**
   - Queue consumer reads the archived object and inserts datapoints into `datapoints`.
   - Device/metric linkage is consistent (tenant isolation preserved).

5. **Observability**
   - `GET /v1/health` returns 200 with service timestamp.
   - Basic logging includes batch_id and tenant_id for ingest and consumer.

---

## MVP-2 — Baseline Scoring (Scheduled ML Job)
### Scope
- Python CLI supports `features`, `train`, `score`.
- Train and score operate on one tenant+metric at a time (MVP simplification).
- Models are saved to `MODEL_DIR` and recorded in `models`.
- Scores are written to `anomaly_scores`.

### Acceptance criteria
1. **Feature generation**
   - Feature windows are produced with at least: mean, std, median, MAD, min/max range, count.
   - Empty input produces no windows and exits cleanly.

2. **Training**
   - A model artefact is produced and the path is stored in `models`.
   - Re-running training updates the model entry.

3. **Scoring**
   - Scoring writes rows to `anomaly_scores` with upsert semantics on `(tenant_id, metric_id, window_end)`.
   - A minimal query can retrieve scores for a time range.

4. **Scheduling**
   - A scheduled task exists (hourly is fine) to run scoring in AWS (ECS/Fargate).

---

## MVP-3 — Query API + Dashboard (Basic Consumption)
### Scope
- `GET /v1/anomalies` queries anomaly scores by metric_id + time range.
- A minimal dashboard lists devices/metrics and displays a chart/table of anomalies.

### Acceptance criteria
1. **API**
   - `GET /v1/anomalies?metric_id=...&from=...&to=...` returns 200 with scores.
   - Auth required via API key.
   - Errors are consistent (`400` for invalid params, `401` for auth).

2. **Dashboard**
   - Can configure API base URL via environment variable.
   - Shows at least: device list, metric list, and anomaly history for a selected metric.

---

## MVP-4 — Webhook Alerts (Optional if time permits)
### Scope
- Simple alert rule: threshold on anomaly score, evaluated during scoring.
- Webhook delivery with signature (HMAC) and retry policy.

### Acceptance criteria
- When a score crosses threshold, an alert event is stored and webhook is delivered.
- Webhook signatures are verifiable by the receiver.

---

# MVP Data Retention and Plans (lightweight)
- Default retention: 30 days of datapoints (configurable).
- Usage counters recorded per tenant:
  - datapoints ingested per day
  - windows scored per day
- Rate limiting can be added post-MVP; for now, log and measure.

---

# Definition of Done (DoD)
For an MVP issue to be “Done”:
- Code merged to main.
- Basic unit/integration test exists (where feasible).
- README updated if behaviour changes.
- No secrets committed; `.env.example` updated if new env vars are added.
