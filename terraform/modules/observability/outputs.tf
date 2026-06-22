output "mimir_bucket_id" {
  description = "Mimir S3 bucket name"
  value       = aws_s3_bucket.mimir.id
}

output "loki_bucket_id" {
  description = "Loki S3 bucket name"
  value       = aws_s3_bucket.loki.id
}

output "tempo_bucket_id" {
  description = "Tempo S3 bucket name"
  value       = aws_s3_bucket.tempo.id
}

output "audit_trail_bucket_id" {
  description = "Audit trail bucket name"
  value       = aws_s3_bucket.audit_trail.id
}

output "grafana_db_endpoint" {
  description = "Grafana RDS endpoint"
  value       = aws_db_instance.grafana.endpoint
}

output "grafana_db_name" {
  description = "Grafana database name"
  value       = aws_db_instance.grafana.db_name
}

output "mimir_role_arn" {
  description = "Mimir Pod Identity role ARN"
  value       = aws_iam_role.mimir.arn
}

output "loki_role_arn" {
  description = "Loki Pod Identity role ARN"
  value       = aws_iam_role.loki.arn
}

output "tempo_role_arn" {
  description = "Tempo Pod Identity role ARN"
  value       = aws_iam_role.tempo.arn
}
