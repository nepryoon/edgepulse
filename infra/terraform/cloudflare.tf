# R2 bucket (raw archive)
resource "cloudflare_r2_bucket" "raw" {
  account_id = var.cloudflare_account_id
  name       = "${var.project_name}-raw"
}

# Queue (ingest)
resource "cloudflare_queue" "ingest" {
  account_id = var.cloudflare_account_id
  name       = "${var.project_name}-ingest-q"
}
