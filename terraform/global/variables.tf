variable "aws_region" {
  description = "Primary AWS region"
  type        = string
  default     = "us-east-1"
}

variable "domain_name" {
  description = "Root domain name for Route53"
  type        = string
  default     = "addi.com"
}

variable "organization_master_email" {
  description = "AWS Organizations master account email"
  type        = string
  default     = ""
}

variable "cloudtrail_s3_bucket_name" {
  description = "S3 bucket name for CloudTrail logs"
  type        = string
  default     = "addi-cloudtrail-logs"
}

variable "approved_regions" {
  description = "Approved AWS regions for data services (SFC compliance)"
  type        = list(string)
  default     = ["us-east-1", "us-east-2"]
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    ManagedBy = "addi-platform"
    Project   = "addi"
    Layer     = "global"
  }
}

variable "config_bucket_name" {
  description = "S3 bucket name for AWS Config delivery channel"
  type        = string
  default     = "addi-config-logs"
}

variable "enable_organization_resources" {
  description = "Set to false in standalone accounts without AWS Organizations"
  type        = bool
  default     = true
}
