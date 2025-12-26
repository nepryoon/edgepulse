import { Client } from "pg";

export interface Env {
  HYPERDRIVE: Hyperdrive;
}

export async function withPg<T>(env: Env, fn: (c: Client) => Promise<T>): Promise<T> {
  const client = new Client({ connectionString: env.HYPERDRIVE.connectionString });
  await client.connect();
  try {
    return await fn(client);
  } finally {
    await client.end();
  }
}
