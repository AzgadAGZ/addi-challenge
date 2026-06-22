output "alb_arn" {
  description = "Private ALB ARN"
  value       = aws_lb.main.arn
}

output "alb_dns_name" {
  description = "Private ALB DNS name"
  value       = aws_lb.main.dns_name
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID"
  value       = aws_cloudfront_distribution.main.id
}

output "cloudfront_domain_name" {
  description = "CloudFront domain name"
  value       = aws_cloudfront_distribution.main.domain_name
}
