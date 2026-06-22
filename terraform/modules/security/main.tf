terraform {
  required_version = ">= 1.11.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.51"
    }
  }
}

# ---------------------------------------------------------------------------
# Data Sources
# ---------------------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# CloudFront managed prefix list - used to restrict ALB ingress to CF only
data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

# ---------------------------------------------------------------------------
# WAF WebACL
# NOTE: WAF scope CLOUDFRONT requires the aws provider to be aliased to
#       us-east-1. The calling root module must configure a provider alias
#       (e.g. provider "aws" { alias = "us_east_1" region = "us-east-1" })
#       and pass it to this module via `providers = { aws = aws.us_east_1 }`.
# ---------------------------------------------------------------------------

resource "aws_wafv2_web_acl" "main" {
  name  = "${var.environment}-addi-waf"
  scope = "CLOUDFRONT"

  default_action {
    block {}
  }

  # Rule 1 - Host header validation: label matching hosts, then allow in rule 7
  rule {
    name     = "HostHeaderValidation"
    priority = 10

    action {
      count {}
    }

    rule_label {
      name = "valid-host"
    }

    dynamic "statement" {
      for_each = length(var.alb_allowed_hosts) == 1 ? [1] : []
      content {
        byte_match_statement {
          positional_constraint = "EXACTLY"
          search_string         = var.alb_allowed_hosts[0]
          field_to_match {
            single_header {
              name = "host"
            }
          }
          text_transformation {
            priority = 0
            type     = "LOWERCASE"
          }
        }
      }
    }

    dynamic "statement" {
      for_each = length(var.alb_allowed_hosts) > 1 ? [1] : []
      content {
        or_statement {
          dynamic "statement" {
            for_each = var.alb_allowed_hosts
            content {
              byte_match_statement {
                positional_constraint = "EXACTLY"
                search_string         = statement.value
                field_to_match {
                  single_header {
                    name = "host"
                  }
                }
                text_transformation {
                  priority = 0
                  type     = "LOWERCASE"
                }
              }
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.environment}-addi-waf-host-validation"
      sampled_requests_enabled   = true
    }
  }

  # Rule 2 - AWS Managed Common Rule Set
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 20

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesCommonRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.environment}-addi-waf-common-rules"
      sampled_requests_enabled   = true
    }
  }

  # Rule 3 - SQL Injection managed rule
  rule {
    name     = "AWSManagedRulesSQLiRuleSet"
    priority = 30

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesSQLiRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.environment}-addi-waf-sqli"
      sampled_requests_enabled   = true
    }
  }

  # Rule 4 - Known bad inputs managed rule
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 40

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.environment}-addi-waf-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  # Rule 5 - Bot Control managed rule
  rule {
    name     = "AWSManagedRulesBotControlRuleSet"
    priority = 50

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesBotControlRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.environment}-addi-waf-bot-control"
      sampled_requests_enabled   = true
    }
  }

  # Rule 6 - IP-based rate limiting
  rule {
    name     = "RateLimitPerIP"
    priority = 70

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.waf_rate_limit
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.environment}-addi-waf-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  # Rule 7 - Allow requests that were labelled as valid-host in rule 1
  rule {
    name     = "AllowValidHosts"
    priority = 99

    action {
      allow {}
    }

    statement {
      label_match_statement {
        scope = "LABEL"
        key   = "awswaf:${data.aws_caller_identity.current.account_id}:webacl:${var.environment}-addi-waf:valid-host"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.environment}-addi-waf-allow-valid-hosts"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.environment}-addi-waf"
    sampled_requests_enabled   = true
  }

  tags = merge(var.tags, {
    Name        = "${var.environment}-addi-waf"
    Environment = var.environment
  })
}

# ---------------------------------------------------------------------------
# KMS Key
# ---------------------------------------------------------------------------

resource "aws_kms_key" "main" {
  description             = "Addi ${var.environment} main encryption key"
  enable_key_rotation     = true
  deletion_window_in_days = var.kms_deletion_window

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableRootAccountPermissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowKeyRotation"
        Effect = "Allow"
        Principal = {
          Service = "kms.amazonaws.com"
        }
        Action = [
          "kms:CreateGrant",
          "kms:ListGrants",
          "kms:RevokeGrant"
        ]
        Resource = "*"
        Condition = {
          Bool = {
            "kms:GrantIsForAWSResource" = "true"
          }
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name        = "addi-${var.environment}-main"
    Environment = var.environment
  })
}

resource "aws_kms_alias" "main" {
  name          = "alias/addi-${var.environment}-main"
  target_key_id = aws_kms_key.main.key_id
}

# ---------------------------------------------------------------------------
# Security Groups
# ---------------------------------------------------------------------------

# ALB - only accepts traffic originating from CloudFront edge nodes
resource "aws_security_group" "alb" {
  name        = "${var.environment}-addi-alb-sg"
  description = "Security group for the internal ALB; restricts ingress to CloudFront prefix list"
  vpc_id      = var.vpc_id

  ingress {
    description     = "HTTPS from CloudFront"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    prefix_list_ids = [data.aws_ec2_managed_prefix_list.cloudfront.id]
  }

  ingress {
    description     = "HTTP from CloudFront (redirect only)"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    prefix_list_ids = [data.aws_ec2_managed_prefix_list.cloudfront.id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name        = "${var.environment}-addi-alb-sg"
    Environment = var.environment
  })
}

# EKS Nodes - accept traffic from ALB and peer nodes
resource "aws_security_group" "eks_nodes" {
  name        = "${var.environment}-addi-eks-nodes-sg"
  description = "Security group for EKS worker nodes"
  vpc_id      = var.vpc_id

  ingress {
    description     = "HTTP from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "HTTPS from ALB"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description = "Node-to-node communication"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name        = "${var.environment}-addi-eks-nodes-sg"
    Environment = var.environment
  })
}

# VPC Endpoints - accept HTTPS from within the VPC
resource "aws_security_group" "vpc_endpoints" {
  name        = "${var.environment}-addi-vpc-endpoints-sg"
  description = "Security group for VPC interface endpoints"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name        = "${var.environment}-addi-vpc-endpoints-sg"
    Environment = var.environment
  })
}
