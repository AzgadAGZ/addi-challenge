variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
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
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "Availability zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "private_subnets" {
  description = "Private subnet CIDRs"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "public_subnets" {
  description = "Public subnet CIDRs"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
}

variable "single_nat_gateway" {
  description = "Use single NAT gateway (cost saving for dev)"
  type        = bool
  default     = true
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "addi-dev"
}

variable "cluster_version" {
  description = "EKS Kubernetes version"
  type        = string
  default     = "1.32"
}

variable "node_instance_types" {
  description = "Instance types for general node group"
  type        = list(string)
  default     = ["m5.large", "m5a.large", "m6i.large"]
}

variable "critical_instance_types" {
  description = "Instance types for critical node group"
  type        = list(string)
  default     = ["m5.large", "m6i.large"]
}

variable "waf_rate_limit" {
  description = "WAF rate limit per 5 minutes"
  type        = number
  default     = 2000
}

variable "alb_allowed_hosts" {
  description = "Valid hostnames for WAF host validation"
  type        = list(string)
  default     = ["dev.addi.com", "api-dev.addi.com"]
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
  default     = false
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
