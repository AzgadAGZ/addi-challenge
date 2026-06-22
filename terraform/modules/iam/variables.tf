variable "environment" {
  description = "Environment name"
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "cluster_oidc_issuer_url" {
  description = "EKS cluster OIDC issuer URL"
  type        = string
}

variable "github_org" {
  description = "GitHub organization name"
  type        = string
  default     = "addi"
}

variable "allowed_repos" {
  description = "GitHub repos allowed to assume the CI role"
  type        = list(string)
  default     = ["addi-platform"]
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
