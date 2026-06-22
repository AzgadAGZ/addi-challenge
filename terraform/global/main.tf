terraform {
  required_version = ">= 1.11.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.51"
    }
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = var.tags
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# =============================================================================
# Route53 - Global Hosted Zone
# =============================================================================

resource "aws_route53_zone" "main" {
  name    = var.domain_name
  comment = "Addi platform primary hosted zone - managed by Terraform"
  tags    = var.tags
}

# =============================================================================
# KMS - CloudTrail encryption key
# =============================================================================

resource "aws_kms_key" "cloudtrail" {
  description             = "KMS key for CloudTrail encryption - Addi global"
  enable_key_rotation     = true
  deletion_window_in_days = 30

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow CloudTrail to encrypt logs"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = ["kms:GenerateDataKey*", "kms:DescribeKey"]
        Resource = "*"
        Condition = {
          StringLike = {
            "kms:EncryptionContext:aws:cloudtrail:arn" = "arn:aws:cloudtrail:*:${data.aws_caller_identity.current.account_id}:trail/*"
          }
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_kms_alias" "cloudtrail" {
  name          = "alias/addi-cloudtrail"
  target_key_id = aws_kms_key.cloudtrail.key_id
}

# =============================================================================
# S3 - CloudTrail log bucket
# =============================================================================

resource "aws_s3_bucket" "cloudtrail" {
  bucket              = "${var.cloudtrail_s3_bucket_name}-${data.aws_caller_identity.current.account_id}"
  force_destroy       = false
  object_lock_enabled = true
  tags                = var.tags
}

resource "aws_s3_bucket_versioning" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_object_lock_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    default_retention {
      mode  = "COMPLIANCE"
      years = 7
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.cloudtrail.arn
    }
  }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket                  = aws_s3_bucket.cloudtrail.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail.arn
        Condition = {
          StringEquals = {
            "aws:SourceArn" = "arn:aws:cloudtrail:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:trail/addi-global-trail"
          }
        }
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"  = "bucket-owner-full-control"
            "aws:SourceArn" = "arn:aws:cloudtrail:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:trail/addi-global-trail"
          }
        }
      }
    ]
  })
}

# =============================================================================
# CloudTrail - Multi-region trail (SFC CE 007/2018 compliance)
# =============================================================================

resource "aws_cloudtrail" "global" {
  name                          = "addi-global-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true
  kms_key_id                    = aws_kms_key.cloudtrail.arn

  event_selector {
    read_write_type           = "All"
    include_management_events = true

    data_resource {
      type   = "AWS::S3::Object"
      values = ["arn:aws:s3:::"]
    }
  }

  tags = var.tags

  depends_on = [aws_s3_bucket_policy.cloudtrail]
}

# =============================================================================
# AWS Organizations SCPs - Data Residency + IAM Key Denial
# SFC CE 020/2022: data must remain in approved regions
# =============================================================================

# NOTE: These SCPs require the caller to be the AWS Organizations management
# account or a delegated administrator for SCP management.
# Set enable_organization_resources = false in standalone accounts without
# AWS Organizations to skip this data source and all dependent resources.

data "aws_organizations_organization" "current" {
  count = var.enable_organization_resources ? 1 : 0
}

resource "aws_organizations_policy" "deny_non_approved_regions" {
  count       = var.enable_organization_resources ? 1 : 0
  name        = "DenyNonApprovedRegionsForDataServices"
  description = "SFC CE 020/2022: Deny data service operations outside approved regions"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyDataServicesInNonApprovedRegions"
        Effect = "Deny"
        Action = [
          "rds:CreateDBInstance",
          "rds:RestoreDBInstanceFromDBSnapshot",
          "rds:CreateDBCluster",
          "dynamodb:CreateTable",
          "dynamodb:RestoreTableFromBackup",
          "s3:CreateBucket"
        ]
        Resource = "*"
        Condition = {
          StringNotEquals = {
            "aws:RequestedRegion" = var.approved_regions
          }
        }
      }
    ]
  })
}

resource "aws_organizations_policy_attachment" "deny_non_approved_regions" {
  count     = var.enable_organization_resources ? 1 : 0
  policy_id = aws_organizations_policy.deny_non_approved_regions[0].id
  target_id = data.aws_organizations_organization.current[0].roots[0].id
}

resource "aws_organizations_policy" "deny_iam_keys" {
  count       = var.enable_organization_resources ? 1 : 0
  name        = "DenyIAMKeyCreation"
  description = "Force OIDC and Pod Identity - deny long-lived IAM access keys (SFC CE 007/2018)"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "DenyIAMKeyCreation"
        Effect   = "Deny"
        Action   = ["iam:CreateAccessKey"]
        Resource = "*"
        Condition = {
          StringNotEquals = {
            "aws:PrincipalARN" = [
              "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/BreakGlassAdmin",
              "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
            ]
          }
        }
      }
    ]
  })
}

resource "aws_organizations_policy_attachment" "deny_iam_keys" {
  count     = var.enable_organization_resources ? 1 : 0
  policy_id = aws_organizations_policy.deny_iam_keys[0].id
  target_id = data.aws_organizations_organization.current[0].roots[0].id
}

# =============================================================================
# GuardDuty - Threat detection (SFC CE 007/2018)
# =============================================================================

resource "aws_guardduty_detector" "main" {
  count  = var.enable_organization_resources ? 1 : 0
  enable = true

  datasources {
    s3_logs {
      enable = true
    }
    kubernetes {
      audit_logs {
        enable = true
      }
    }
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes {
          enable = true
        }
      }
    }
  }

  tags = var.tags
}

# =============================================================================
# AWS Config - Continuous compliance recording
# =============================================================================

resource "aws_iam_role" "config" {
  count = var.enable_organization_resources ? 1 : 0
  name  = "addi-config-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "config.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "config" {
  count      = var.enable_organization_resources ? 1 : 0
  role       = aws_iam_role.config[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

resource "aws_config_configuration_recorder" "main" {
  count    = var.enable_organization_resources ? 1 : 0
  name     = "addi-config-recorder"
  role_arn = aws_iam_role.config[0].arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }
}

resource "aws_config_delivery_channel" "main" {
  count          = var.enable_organization_resources ? 1 : 0
  name           = "addi-config-channel"
  s3_bucket_name = var.config_bucket_name

  snapshot_delivery_properties {
    delivery_frequency = "TwentyFour_Hours"
  }

  depends_on = [aws_config_configuration_recorder.main]
}

resource "aws_config_configuration_recorder_status" "main" {
  count      = var.enable_organization_resources ? 1 : 0
  name       = aws_config_configuration_recorder.main[0].name
  is_enabled = true

  depends_on = [aws_config_delivery_channel.main]
}

# =============================================================================
# Security Hub - Centralized security findings (CIS + AWS best practices)
# =============================================================================

resource "aws_securityhub_account" "main" {
  count = var.enable_organization_resources ? 1 : 0
}

resource "aws_securityhub_standards_subscription" "cis" {
  count         = var.enable_organization_resources ? 1 : 0
  standards_arn = "arn:aws:securityhub:::ruleset/cis-aws-foundations-benchmark/v/1.4.0"
  depends_on    = [aws_securityhub_account.main]
}

resource "aws_securityhub_standards_subscription" "aws_best_practices" {
  count         = var.enable_organization_resources ? 1 : 0
  standards_arn = "arn:aws:securityhub:${data.aws_region.current.name}::standards/aws-foundational-security-best-practices/v/1.0.0"
  depends_on    = [aws_securityhub_account.main]
}
