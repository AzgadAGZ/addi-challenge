terraform {
  required_version = ">= 1.11.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.51"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.2"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.2"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = local.common_tags
  }
}

# DR region provider (for observability S3 cross-region replication)
provider "aws" {
  alias  = "dr"
  region = var.dr_region
  default_tags {
    tags = local.common_tags
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    }
  }
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

locals {
  common_tags = {
    Environment = var.environment
    ManagedBy   = "addi-platform"
    Project     = "addi"
  }
}

module "vpc" {
  source = "../../modules/vpc"

  environment        = var.environment
  vpc_cidr           = var.vpc_cidr
  azs                = var.azs
  private_subnets    = var.private_subnets
  public_subnets     = var.public_subnets
  single_nat_gateway = var.single_nat_gateway
  tags               = local.common_tags

  endpoint_security_group_ids = [module.security.vpc_endpoints_security_group_id]
}

module "security" {
  source = "../../modules/security"

  environment       = var.environment
  vpc_id            = module.vpc.vpc_id
  vpc_cidr          = var.vpc_cidr
  waf_rate_limit    = var.waf_rate_limit
  alb_allowed_hosts = var.alb_allowed_hosts
  tags              = local.common_tags
}

module "eks" {
  source = "../../modules/eks"

  cluster_name            = var.cluster_name
  cluster_version         = var.cluster_version
  vpc_id                  = module.vpc.vpc_id
  subnet_ids              = module.vpc.private_subnet_ids
  environment             = var.environment
  node_instance_types     = var.node_instance_types
  critical_instance_types = var.critical_instance_types
  kms_key_arn             = module.security.kms_key_arn
  tags                    = local.common_tags
}

module "networking" {
  source = "../../modules/networking"

  environment           = var.environment
  vpc_id                = module.vpc.vpc_id
  private_subnet_ids    = module.vpc.private_subnet_ids
  alb_security_group_id = module.security.alb_security_group_id
  waf_web_acl_arn       = module.security.waf_web_acl_arn
  domain_name           = var.domain_name
  tags                  = local.common_tags
}

module "iam" {
  source = "../../modules/iam"

  environment             = var.environment
  cluster_name            = module.eks.cluster_name
  cluster_oidc_issuer_url = module.eks.cluster_oidc_issuer_url
  github_org              = var.github_org
  allowed_repos           = var.allowed_repos
  tags                    = local.common_tags
}

module "observability" {
  source = "../../modules/observability"

  providers = {
    aws    = aws
    aws.dr = aws.dr
  }

  environment               = var.environment
  vpc_id                    = module.vpc.vpc_id
  subnet_ids                = module.vpc.private_subnet_ids
  cluster_name              = module.eks.cluster_name
  dr_region                 = var.dr_region
  grafana_db_instance_class = var.grafana_db_instance_class
  grafana_db_multi_az       = var.grafana_db_multi_az
  kms_key_arn               = module.security.kms_key_arn
  tags                      = local.common_tags
}

module "access_control" {
  source = "../../modules/access-control"

  environment                  = var.environment
  identity_store_id            = var.identity_store_id
  sso_instance_arn             = var.sso_instance_arn
  break_glass_session_duration = "PT1H"
  tags                         = local.common_tags
}
