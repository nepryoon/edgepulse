-- Enable UUID generation (pgcrypto provides gen_random_uuid()).
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Core
CREATE TABLE tenants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  plan text NOT NULL DEFAULT 'free',
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  email text NOT NULL,
  role text NOT NULL DEFAULT 'admin',
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, email)
);

CREATE TABLE api_keys (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  name text NOT NULL,
  key_prefix text NOT NULL,          -- e.g., first 8-10 chars for lookup
  key_hash bytea NOT NULL,           -- store a hash (e.g., SHA-256) of the full key
  created_at timestamptz NOT NULL DEFAULT now(),
  last_used_at timestamptz,
  revoked_at timestamptz,
  UNIQUE (tenant_id, key_prefix)
);

CREATE TABLE devices (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  external_id text NOT NULL,         -- client-provided stable id
  label text NOT NULL,
  tags jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, external_id)
);

CREATE TABLE metrics (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  device_id uuid NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  name text NOT NULL,
  unit text,
  freq_hint_seconds int,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, device_id, name)
);

-- Ingestion
CREATE TABLE ingestion_batches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  device_id uuid NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  received_at timestamptz NOT NULL DEFAULT now(),
  r2_object_key text NOT NULL,
  message_count int NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'received',  -- received|processed|failed
  error text
);

-- Time-series datapoints (MVP: single table; partition later if needed)
CREATE TABLE datapoints (
  id bigserial PRIMARY KEY,
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  metric_id uuid NOT NULL REFERENCES metrics(id) ON DELETE CASCADE,
  ts timestamptz NOT NULL,
  value double precision NOT NULL,
  quality_flags smallint NOT NULL DEFAULT 0,
  inserted_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_datapoints_metric_time ON datapoints (tenant_id, metric_id, ts DESC);

-- Features + models
CREATE TABLE feature_sets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  metric_id uuid NOT NULL REFERENCES metrics(id) ON DELETE CASCADE,
  window_size_sec int NOT NULL,
  version int NOT NULL DEFAULT 1,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, metric_id, window_size_sec, version)
);

CREATE TABLE feature_rows (
  id bigserial PRIMARY KEY,
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  metric_id uuid NOT NULL REFERENCES metrics(id) ON DELETE CASCADE,
  window_start timestamptz NOT NULL,
  window_end timestamptz NOT NULL,
  feature_set_id uuid REFERENCES feature_sets(id) ON DELETE SET NULL,
  features jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_feature_rows_metric_end ON feature_rows (tenant_id, metric_id, window_end DESC);

CREATE TABLE models (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  metric_id uuid NOT NULL REFERENCES metrics(id) ON DELETE CASCADE,
  model_type text NOT NULL,                 -- isolation_forest|baseline|autoencoder (later)
  model_uri text NOT NULL,                  -- r2://... or s3://...
  trained_from timestamptz,
  trained_to timestamptz,
  training_metrics jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  active boolean NOT NULL DEFAULT false
);

CREATE INDEX idx_models_active ON models (tenant_id, metric_id) WHERE active = true;

-- Scoring + alerts
CREATE TABLE anomaly_scores (
  id bigserial PRIMARY KEY,
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  metric_id uuid NOT NULL REFERENCES metrics(id) ON DELETE CASCADE,
  model_id uuid REFERENCES models(id) ON DELETE SET NULL,
  window_end timestamptz NOT NULL,
  score double precision NOT NULL,
  label text,
  explanation jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_anomaly_scores_metric_end ON anomaly_scores (tenant_id, metric_id, window_end DESC);

CREATE TABLE webhooks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  url text NOT NULL,
  secret text NOT NULL,
  enabled boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE alert_rules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  metric_id uuid NOT NULL REFERENCES metrics(id) ON DELETE CASCADE,
  condition jsonb NOT NULL,         -- e.g., {"threshold":75,"min_consecutive":2}
  channels jsonb NOT NULL,          -- e.g., {"webhook_ids":[...], "email":false}
  enabled boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_alert_rules_metric ON alert_rules (tenant_id, metric_id) WHERE enabled = true;

CREATE TABLE alert_events (
  id bigserial PRIMARY KEY,
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  rule_id uuid NOT NULL REFERENCES alert_rules(id) ON DELETE CASCADE,
  metric_id uuid NOT NULL REFERENCES metrics(id) ON DELETE CASCADE,
  window_end timestamptz NOT NULL,
  score double precision NOT NULL,
  delivered_channels jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Billing / usage (stub for MVP)
CREATE TABLE subscriptions (
  tenant_id uuid PRIMARY KEY REFERENCES tenants(id) ON DELETE CASCADE,
  provider text NOT NULL DEFAULT 'stripe',
  provider_customer_id text,
  status text NOT NULL DEFAULT 'inactive',
  current_period_end timestamptz
);

CREATE TABLE usage_daily (
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  day date NOT NULL,
  ingested_points bigint NOT NULL DEFAULT 0,
  scored_windows bigint NOT NULL DEFAULT 0,
  alerts_sent bigint NOT NULL DEFAULT 0,
  PRIMARY KEY (tenant_id, day)
);
