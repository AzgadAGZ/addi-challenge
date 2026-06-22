# Dev environment - cost-optimized configuration
# Single NAT GW (save ~$65/mo vs 3 NAT GWs), smaller instances, spot compute

environment        = "dev"
aws_region         = "us-east-1"
dr_region          = "us-east-2"
vpc_cidr           = "10.0.0.0/16"
azs                = ["us-east-1a", "us-east-1b", "us-east-1c"]
private_subnets    = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
public_subnets     = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
single_nat_gateway = true

cluster_name    = "addi-dev"
cluster_version = "1.31"

# Smaller instance types for dev - cost optimization
node_instance_types     = ["m5.large", "m5a.large", "m6i.large"]
critical_instance_types = ["m5.large", "m6i.large"]

# Relaxed WAF for dev (higher rate limit to avoid blocking developer testing)
waf_rate_limit    = 2000
alb_allowed_hosts = ["dev.addi.com", "api-dev.addi.com"]

domain_name      = "addi.com"
github_org       = "addi"
allowed_repos    = ["addi-platform"]
approved_regions = ["us-east-1", "us-east-2"]

# Dev: single-AZ Grafana DB (cheaper)
grafana_db_instance_class = "db.t4g.medium"
grafana_db_multi_az       = false

# IAM Identity Center - fill in after SSO setup
# identity_store_id = "d-xxxxxxxxxx"
# sso_instance_arn  = "arn:aws:sso:::instance/ssoins-xxxxxxxxxx"
identity_store_id = ""
sso_instance_arn  = ""
