output "r2_bucket_name" {
  value = cloudflare_r2_bucket.raw.name
}

output "queue_name" {
  value = cloudflare_queue.ingest.name
}

output "rds_endpoint" {
  value = aws_db_instance.postgres.address
}

output "ecr_repository_url" {
  value = aws_ecr_repository.ml.repository_url
}
