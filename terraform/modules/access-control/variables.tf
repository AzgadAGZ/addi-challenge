variable "environment" {
  description = "Environment name"
  type        = string
}

variable "identity_store_id" {
  description = "IAM Identity Center identity store ID"
  type        = string
}

variable "sso_instance_arn" {
  description = "IAM Identity Center instance ARN"
  type        = string
}

variable "break_glass_session_duration" {
  description = "Break-glass session duration"
  type        = string
  default     = "PT1H"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
