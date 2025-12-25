# EdgePulse — Multi-tenant Time-Series Anomaly Detection API (Cloudflare + AWS + Python/ML)

EdgePulse is an end-to-end, production-oriented micro-SaaS for ingesting time-series telemetry (IoT sensors, energy meters, industrial signals, and application/infra metrics) and detecting anomalies in near real time.

It is designed as a portfolio-grade system that demonstrates:
- **Cloud-native engineering** (Cloudflare Workers/Queues/R2/Pages + AWS Fargate/RDS/Scheduler)
- **Data engineering** (SQL-first persistence, durable ingestion, reproducible pipelines)
- **Applied ML** (baseline anomaly detection with scikit-learn; PyTorch-ready upgrade path)
- A clear path to **monetisation** as a subscription API (usage + retention + alerting tiers)

---

## Table of contents
- [What it does](#what-it-does)
- [Architecture](#architecture)
- [Tech stack](#tech-stack)
- [Repository layout](#repository-layout)
- [API overview](#api-overview)
- [Quick start (local)](#quick-start-local)
- [Configuration](#configuration)
- [ML pipeline](#ml-pipeline)
- [Alerts](#alerts)
- [Infrastructure & deployment](#infrastructure--deployment)
- [Roadmap](#roadmap)
- [Security](#security)
- [Contributing](#contributing)
- [Licence](#licence)

---

## What it does
EdgePulse provides:

- **Fast ingestion at the edge:** a Cloudflare Worker validates payloads, authenticates tenants via API keys, archives raw payloads, and buffers events asynchronously.
- **Reliable async processing:** Cloudflare Queues decouple ingestion from downstream processing for resilience and predictable latency.
- **Durable raw archive:** raw request payloads are stored in Cloudflare R2 for auditability and replay.
- **SQL-first system of record:** tenants, devices, metrics, datapoints, features, models, scores, and alert metadata are stored in Postgres (AWS RDS).
- **Baseline anomaly detection:** rolling-window feature extraction + Isolation Forest scoring (scikit-learn).
- **Alerting:** configurable anomaly rules trigger signed webhook notifications and create an auditable alert history.
- **Dashboard:** a lightweight UI to browse devices/metrics, inspect ingestion health, and visualise anomalies over time.
- **MLOps foundations:** model artefact versioning, containerised jobs, and scheduled orchestration on AWS Fargate.

---

## Architecture

### High-level flow
1. **Client → Worker (`POST /v1/ingest`)**  
   Validates schema, checks API key, enforces tenant scope.
2. **Worker → R2**  
   Stores the raw payload (immutable archive).
3. **Worker → Queue**  
   Publishes an async message for downstream normalisation.
4. **Consumer → Postgres**  
   Writes normalised datapoints and ingestion batch status.
5. **Scheduled ML jobs (Fargate)**  
   Compute features, train/update models, score new windows, store anomaly scores.
6. **Alert engine**  
   Evaluates alert rules and delivers webhook notifications.
7. **Dashboard (Pages)**  
   Displays devices, metrics, anomalies, and alert history via the API.

### Component diagram (conceptual)
```text
Devices/Apps
   |
   |  HTTPS (X-API-Key)
   v
Cloudflare Worker (API Gateway)
   |          \
   |           \--> R2 (raw archive)
   v
Cloudflare Queue  ---> Consumer ---> Postgres (RDS)
                               \
                                \--> AWS Fargate jobs (features/train/score)
                                          |
                                          v
                                   anomaly_scores + models
                                          |
                                          v
                                     Alert engine ---> Webhooks
                                          |
                                          v
                              Cloudflare Pages (Dashboard UI)
```

---

## Tech stack
**Cloudflare**
- Workers (API gateway)
- Queues (async buffering)
- R2 (raw payload archive)
- Pages (dashboard hosting)

**AWS**
- ECS Fargate (containerised ML jobs)
- EventBridge Scheduler (cron triggers)
- RDS Postgres (system of record)
- S3 (optional; model artefacts if not using R2)

**Data/ML**
- Python, SQL
- pandas, NumPy
- scikit-learn (baseline)
- PyTorch (planned upgrade path)

---

## Repository layout
```text
services/
  ingest-worker/          # Cloudflare Worker: auth, validation, R2 archive, Queue publish
  queue-consumer/         # Consumer (Worker or service): normalise + write to Postgres

jobs/
  ml-pipeline/            # Python pipeline: features/train/score (Dockerised for Fargate)

web/
  dashboard/              # Dashboard UI (Cloudflare Pages)

infra/
  terraform/              # IaC: Cloudflare + AWS (RDS, ECS, Scheduler, IAM, etc.)

docs/
  architecture.md         # Design decisions, diagrams, threat model (recommended)
  api/openapi.yaml        # OpenAPI spec
  db/schema.sql           # Database schema (if you keep SQL snapshots)

examples/
  device-simulator/       # Generate realistic telemetry + injected anomalies
  sample-payloads/        # Example JSON payloads
```

---

## API overview

### Authentication
All API calls (except `/v1/health`) require:
- `X-API-Key: <tenant_api_key>`

### Ingestion
`POST /v1/ingest`

Example payload:
```json
{
  "device_external_id": "meter-001",
  "metrics": [
    { "name": "voltage", "ts": "2025-12-25T08:45:00Z", "value": 229.5, "unit": "V" },
    { "name": "current", "ts": "2025-12-25T08:45:00Z", "value": 12.1, "unit": "A" }
  ]
}
```

Example request:
```bash
curl -X POST "http://localhost:8787/v1/ingest" \
  -H "Content-Type: application/json" \
  -H "X-API-Key: ep_dev_XXXXXXXXXXXXXXXX" \
  -d @examples/sample-payloads/ingest.json
```

### Query anomalies
`GET /v1/anomalies?metric_id=<uuid>&from=<iso>&to=<iso>`

### Manage entities (MVP)
- `GET/POST /v1/devices`
- `GET/POST /v1/metrics`
- `GET/POST /v1/alert-rules`
- `GET/POST /v1/webhooks`

See `docs/api/openapi.yaml` for the canonical API contract.

---

## Quick start (local)

### Prerequisites
- Node.js 18+ (or 20+)
- Python 3.10+ (3.11 recommended)
- Docker (recommended for local Postgres and for building ML job images)
- Cloudflare Wrangler CLI (for Workers/Pages local dev)

### 1) Start Postgres locally
```bash
docker run --name edgepulse-postgres \
  -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_DB=edgepulse \
  -p 5432:5432 \
  -d postgres:16
```

### 2) Apply the database schema
If you keep a SQL snapshot:
```bash
psql "postgresql://postgres:postgres@localhost:5432/edgepulse" \
  -f docs/db/schema.sql
```

Or use migrations (recommended) from `jobs/ml-pipeline` (e.g., Alembic), depending on your setup.

### 3) Run the Worker locally (ingestion API)
```bash
cd services/ingest-worker
npm install
npm run dev
```

The Worker should serve locally at a Wrangler URL (commonly `http://localhost:8787`).

### 4) Run the dashboard locally
```bash
cd web/dashboard
npm install
npm run dev
```

### 5) Run the ML scoring locally (developer mode)
```bash
cd jobs/ml-pipeline
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

python -m edgepulse_ml score --tenant <tenant_id> --metric <metric_id> --since "24h"
```

---

## Configuration

### Environment variables (typical)
**Worker (`services/ingest-worker`)**
- `DATABASE_URL` — Postgres connection string
- `R2_BUCKET_NAME` — R2 bucket for raw payloads
- `QUEUE_NAME` — Cloudflare Queue name
- `API_KEY_HASH_SALT` — salt/pepper for key hashing
- `RATE_LIMIT_*` — optional (plan-based quotas)

**ML jobs (`jobs/ml-pipeline`)**
- `DATABASE_URL`
- `MODEL_ARTEFACT_STORE` — `r2://...` or `s3://...`
- `FEATURE_WINDOW_SEC` — e.g., `300`
- `SCORE_INTERVAL_SEC` — e.g., `600`

**Dashboard (`web/dashboard`)**
- `VITE_API_BASE_URL` (or equivalent if you choose Next.js)

Commit `.env.example` files, never commit real secrets.

---

## ML pipeline

### MVP approach
1. **Windowing:** group datapoints into rolling windows per metric (e.g., 5 minutes).
2. **Feature extraction (robust + cheap):**
   - mean, std
   - median, MAD (robust dispersion)
   - min/max range
   - slope (trend)
   - missing rate
   - stuck-at detection (low variance)
3. **Model:** Isolation Forest per metric (or per metric family) trained on recent “mostly normal” history.
4. **Scoring:** compute anomaly score per window; assign labels (spike/drop/drift/missingness/stuck).

### Upgrade path (planned)
- PyTorch temporal autoencoder for reconstruction error
- Quantisation / sparse variants (“edge profile”) for efficient inference

---

## Alerts

### Webhook delivery
Alert rules evaluate anomaly scores and deliver signed webhooks.

A typical webhook payload includes:
- `tenant_id`, `metric_id`, `window_end`, `score`, `label`, `explanation`
- signature header (HMAC) for authenticity

Webhook retries with exponential backoff; deliveries are recorded in `alert_events`.

---

## Infrastructure & deployment

### Recommended approach
Use `infra/terraform` to provision:
- Cloudflare: Worker, Queue, R2 bucket, Pages project
- AWS: RDS Postgres, ECS cluster/services/tasks, EventBridge schedules, IAM roles/policies

Suggested deployment sequence:
1. Provision cloud infrastructure (Terraform).
2. Deploy Worker + consumer (Wrangler).
3. Deploy dashboard (Pages).
4. Build and push ML job image (ECR), then enable schedules.

This repo intentionally separates:
- low-latency ingestion (Cloudflare)
from
- compute-heavy training/scoring (AWS)

---

## Roadmap

### Milestone 1 — Ingestion + persistence
- Worker auth + validation
- R2 raw archive + Queue buffering
- Consumer normalisation to Postgres
- Basic dashboard views (devices/metrics/batches)

### Milestone 2 — Baseline anomaly scoring
- Feature extraction + Isolation Forest training
- Scheduled scoring job (Fargate)
- Metric detail page (values + scores)

### Milestone 3 — Alerts + billing foundations
- Alert rules + webhook delivery + audit trail
- Usage accounting (ingested points, scored windows)
- Plan enforcement (quotas + retention)

### Milestone 4 — Differentiators
- Edge agent (Python) for batching + signing
- PyTorch model option + “edge profile” export
- Drift monitoring + model refresh policies

---

## Security
- Never store raw API keys; store only **hashes** and a short lookup prefix.
- Do not commit secrets: use `.env` locally and secret managers in CI/cloud.
- Sign webhooks (HMAC) and verify signatures on the receiver side.
- Apply least-privilege IAM for AWS tasks and storage access.

---

## Contributing
Contributions are welcome:
1. Open an issue describing the change (bug, feature, refactor).
2. Keep PRs small and test-backed.
3. Ensure no secrets are included in commits.

If you plan to accept external contributions, add:
- `CODE_OF_CONDUCT.md`
- `CONTRIBUTING.md`
- Clear governance and security reporting guidance.

---

## Licence
See `LICENSE`.
