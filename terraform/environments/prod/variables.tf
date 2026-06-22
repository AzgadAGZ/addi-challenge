variable "environment" {
  description = "Environment name"
  type        = string
  default     = "prod"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "dr_region" {
  description = "DR region for cross-region replication"
  type        = string
  default     = "us-east-2"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.1.0.0/16"
}

variable "azs" {
  description = "Availability zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "private_subnets" {
  description = "Private subnet CIDRs"
  type        = list(string)
  default     = ["10.1.1.0/24", "10.1.2.0/24", "10.1.3.0/24"]
}

variable "public_subnets" {
  description = "Public subnet CIDRs"
  type        = list(string)
  default     = ["10.1.101.0/24", "10.1.102.0/24", "10.1.103.0/24"]
}

variable "single_nat_gateway" {
  description = "Use single NAT gateway (cost saving for dev)"
  type        = bool
  default     = false
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "addi-prod"
}

variable "cluster_version" {
  description = "EKS Kubernetes version"
  type        = string
  default     = "1.32"
}

variable "node_instance_types" {
  description = "Instance types for general node group"
  type        = list(string)
  default     = ["m5.xlarge", "m5a.xlarge", "m6i.xlarge"]
}

variable "critical_instance_types" {
  description = "Instance types for critical node group"
  type        = list(string)
  default     = ["m5.xlarge", "m6i.xlarge"]
}

variable "waf_rate_limit" {
  description = "WAF rate limit per 5 minutes"
  type        = number
  default     = 2000
}

variable "alb_allowed_hosts" {
  description = "Valid hostnames for WAF host validation"
  type        = list(string)
  default     = ["addi.com", "api.addi.com", "app.addi.com"]
}

variable "domain_name" {
  description = "Primary domain name"
  type        = string
  default     = "addi.com"
}

variable "github_org" {
  description = "GitHub organization"
  type        = string
  default     = "addi"
}

variable "allowed_repos" {
  description = "GitHub repos allowed for CI"
  type        = list(string)
  default     = ["addi-platform"]
}

variable "approved_regions" {
  description = "Approved AWS regions for data services"
  type        = list(string)
  default     = ["us-east-1", "us-east-2"]
}

variable "grafana_db_instance_class" {
  description = "RDS instance class for Grafana"
  type        = string
  default     = "db.t4g.medium"
}

variable "grafana_db_multi_az" {
  description = "Grafana RDS Multi-AZ"
  type        = bool
  default     = true
}

variable "identity_store_id" {
  description = "IAM Identity Center identity store ID"
  type        = string
  default     = ""
}

variable "sso_instance_arn" {
  description = "IAM Identity Center instance ARN"
  type        = string
  default     = ""
}
