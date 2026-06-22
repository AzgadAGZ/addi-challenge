# Prod environment - HA, multi-AZ, on-demand critical, strict WAF

environment        = "prod"
aws_region         = "us-east-1"
dr_region          = "us-east-2"
vpc_cidr           = "10.1.0.0/16"
azs                = ["us-east-1a", "us-east-1b", "us-east-1c"]
private_subnets    = ["10.1.1.0/24", "10.1.2.0/24", "10.1.3.0/24"]
public_subnets     = ["10.1.101.0/24", "10.1.102.0/24", "10.1.103.0/24"]
single_nat_gateway = false # 3 NAT GWs for HA - $0.045/hr each AZ

cluster_name    = "addi-prod"
cluster_version = "1.31"

# Larger instance types for prod
node_instance_types     = ["m5.xlarge", "m5a.xlarge", "m6i.xlarge"]
critical_instance_types = ["m5.xlarge", "m6i.xlarge"]

# Strict WAF - tighter rate limiting for prod
waf_rate_limit    = 2000
alb_allowed_hosts = ["addi.com", "api.addi.com", "app.addi.com"]

domain_name      = "addi.com"
github_org       = "addi"
allowed_repos    = ["addi-platform"]
approved_regions = ["us-east-1", "us-east-2"]

# Prod: Multi-AZ Grafana DB (required for SFC BCP/DRP compliance)
grafana_db_instance_class = "db.t4g.medium"
grafana_db_multi_az       = true

# IAM Identity Center - fill in after SSO setup
# identity_store_id = "d-xxxxxxxxxx"
# sso_instance_arn  = "arn:aws:sso:::instance/ssoins-xxxxxxxxxx"
identity_store_id = ""
sso_instance_arn  = ""
