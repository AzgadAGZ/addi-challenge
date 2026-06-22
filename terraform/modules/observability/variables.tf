variable "environment" {
  description = "Environment name"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for RDS"
  type        = list(string)
}

variable "cluster_name" {
  description = "EKS cluster name (for Pod Identity associations)"
  type        = string
}

variable "dr_region" {
  description = "DR region for S3 cross-region replication"
  type        = string
  default     = "us-east-2"
}

variable "grafana_db_instance_class" {
  description = "RDS instance class for Grafana database"
  type        = string
  default     = "db.t4g.medium"
}

variable "grafana_db_multi_az" {
  description = "Enable Multi-AZ for Grafana RDS"
  type        = bool
  default     = false
}

variable "audit_trail_retention_years" {
  description = "Audit trail Object Lock retention in years (SFC requirement: 7)"
  type        = number
  default     = 7
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "kms_key_arn" {
  description = "KMS key ARN for S3 bucket encryption"
  type        = string
  default     = ""
}
