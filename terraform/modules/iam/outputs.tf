output "payments_api_role_arn" {
  description = "payments-api Pod Identity role ARN"
  value       = aws_iam_role.payments_api.arn
}

output "github_ci_role_arn" {
  description = "GitHub CI role ARN"
  value       = aws_iam_role.github_ci.arn
}

output "github_oidc_provider_arn" {
  description = "GitHub OIDC provider ARN"
  value       = aws_iam_openid_connect_provider.github.arn
}
