output "read_only_permission_set_arn" {
  description = "ReadOnly permission set ARN"
  value       = aws_ssoadmin_permission_set.read_only.arn
}

output "break_glass_permission_set_arn" {
  description = "BreakGlass permission set ARN"
  value       = aws_ssoadmin_permission_set.break_glass.arn
}
