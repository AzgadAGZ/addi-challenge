terraform {
  required_version = ">= 1.11.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.51"
    }
  }
}

data "aws_region" "current" {}

locals {
  common_tags = merge(
    {
      Environment = var.environment
      ManagedBy   = "addi-platform"
      Project     = "addi"
    },
    var.tags,
  )

  endpoint_sg_ids = var.endpoint_security_group_ids
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.6"

  name = "${var.environment}-addi-vpc"
  cidr = var.vpc_cidr

  azs             = var.azs
  private_subnets = var.private_subnets
  public_subnets  = var.public_subnets

  enable_dns_hostnames = true
  enable_dns_support   = true

  enable_nat_gateway     = true
  single_nat_gateway     = var.single_nat_gateway
  one_nat_gateway_per_az = !var.single_nat_gateway

  tags = local.common_tags

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }

  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }

  enable_flow_log                      = true
  create_flow_log_cloudwatch_log_group = true
  create_flow_log_cloudwatch_iam_role  = true
  flow_log_max_aggregation_interval    = 60
  flow_log_destination_type            = "cloud-watch-logs"
}

# =============================================================================
# VPC Gateway Endpoints - free, traffic stays in VPC
# =============================================================================

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = module.vpc.private_route_table_ids

  tags = merge(local.common_tags, { Name = "${var.environment}-addi-vpce-s3" })
}

resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = module.vpc.private_route_table_ids

  tags = merge(local.common_tags, { Name = "${var.environment}-addi-vpce-dynamodb" })
}

# =============================================================================
# VPC Interface Endpoints - reduce NAT traffic for AWS API calls
# =============================================================================

resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = local.endpoint_sg_ids
  private_dns_enabled = true

  tags = merge(local.common_tags, { Name = "${var.environment}-addi-vpce-ecr-api" })
}

resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = local.endpoint_sg_ids
  private_dns_enabled = true

  tags = merge(local.common_tags, { Name = "${var.environment}-addi-vpce-ecr-dkr" })
}

resource "aws_vpc_endpoint" "sts" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.sts"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = local.endpoint_sg_ids
  private_dns_enabled = true

  tags = merge(local.common_tags, { Name = "${var.environment}-addi-vpce-sts" })
}

resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = local.endpoint_sg_ids
  private_dns_enabled = true

  tags = merge(local.common_tags, { Name = "${var.environment}-addi-vpce-ssm" })
}

resource "aws_vpc_endpoint" "logs" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = local.endpoint_sg_ids
  private_dns_enabled = true

  tags = merge(local.common_tags, { Name = "${var.environment}-addi-vpce-logs" })
}

resource "aws_vpc_endpoint" "kms" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.kms"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = local.endpoint_sg_ids
  private_dns_enabled = true

  tags = merge(local.common_tags, { Name = "${var.environment}-addi-vpce-kms" })
}
