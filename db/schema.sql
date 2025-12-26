CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE IF NOT EXISTS tenant_api_keys (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  key_prefix text NOT NULL,
  key_hash text NOT NULL,
  revoked_at timestamptz NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (key_prefix, key_hash)
);

CREATE TABLE IF NOT EXISTS devices (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  external_id text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, external_id)
);

CREATE TABLE IF NOT EXISTS metrics (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  device_id uuid NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  name text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, device_id, name)
);

CREATE TABLE IF NOT EXISTS datapoints (
  id bigserial PRIMARY KEY,
  tenant_id uuid NOT NULL,
  metric_id uuid NOT NULL REFERENCES metrics(id) ON DELETE CASCADE,
  ts timestamptz NOT NULL,
  value double precision NOT NULL,
  unit text NULL,
  ingest_batch_id uuid NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS models (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  metric_id uuid NOT NULL REFERENCES metrics(id) ON DELETE CASCADE,
  model_type text NOT NULL,
  artefact_path text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, metric_id, model_type)
);

CREATE TABLE IF NOT EXISTS anomaly_scores (
  id bigserial PRIMARY KEY,
  tenant_id uuid NOT NULL,
  metric_id uuid NOT NULL REFERENCES metrics(id) ON DELETE CASCADE,
  window_end timestamptz NOT NULL,
  anomaly_score double precision NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, metric_id, window_end)
);

CREATE INDEX IF NOT EXISTS idx_datapoints_metric_ts ON datapoints(metric_id, ts);
CREATE INDEX IF NOT EXISTS idx_anomaly_metric_window ON anomaly_scores(metric_id, window_end);
