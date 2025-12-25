# edgepulse
Multi-tenant time-series anomaly detection API and dashboard. Ingest telemetry via Cloudflare Workers/Queues, archive raw payloads in R2, persist to Postgres (AWS RDS), run scheduled ML scoring (Fargate) with alerts via webhooks.
