variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "cluster_version" {
  description = "EKS Kubernetes version"
  type        = string
  default     = "1.32"
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for EKS nodes"
  type        = list(string)
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "node_instance_types" {
  description = "EC2 instance types for general node group"
  type        = list(string)
  default     = ["m5.xlarge", "m5a.xlarge", "m6i.xlarge"]
}

variable "critical_instance_types" {
  description = "EC2 instance types for critical node group (on-demand)"
  type        = list(string)
  default     = ["m5.xlarge", "m6i.xlarge"]
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "allowed_cidrs" {
  description = "CIDR blocks allowed to access the EKS API server endpoint. Empty list means private-only access (recommended for prod)."
  type        = list(string)
  default     = []
}

variable "kms_key_arn" {
  description = "ARN of the KMS key to use for encrypting Kubernetes secrets at rest. Empty string disables CMK encryption."
  type        = string
  default     = ""
}
