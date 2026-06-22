terraform {
  required_version = ">= 1.11.0"
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.51"
      configuration_aliases = [aws.dr]
    }
  }
}

# Provider alias for standalone validation; callers override this via provider blocks.
provider "aws" {
  alias  = "dr"
  region = "us-east-2"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_vpc" "main" {
  id = var.vpc_id
}

# =============================================================================
# S3 Buckets - LGTM Stack (Mimir, Loki, Tempo)
# =============================================================================

locals {
  account_id = data.aws_caller_identity.current.account_id

  lgtm_components = {
    mimir = "mimir"
    loki  = "loki"
    tempo = "tempo"
  }
}

# --- Mimir ---

resource "aws_s3_bucket" "mimir" {
  bucket = "addi-${var.environment}-mimir-${local.account_id}"
  tags   = var.tags
}

resource "aws_s3_bucket_versioning" "mimir" {
  bucket = aws_s3_bucket.mimir.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "mimir" {
  bucket = aws_s3_bucket.mimir.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
  }
}

resource "aws_s3_bucket_intelligent_tiering_configuration" "mimir" {
  bucket = aws_s3_bucket.mimir.id
  name   = "mimir-tiering"

  tiering {
    access_tier = "ARCHIVE_ACCESS"
    days        = 90
  }

  tiering {
    access_tier = "DEEP_ARCHIVE_ACCESS"
    days        = 180
  }
}

resource "aws_s3_bucket_public_access_block" "mimir" {
  bucket                  = aws_s3_bucket.mimir.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- Loki ---

resource "aws_s3_bucket" "loki" {
  bucket = "addi-${var.environment}-loki-${local.account_id}"
  tags   = var.tags
}

resource "aws_s3_bucket_versioning" "loki" {
  bucket = aws_s3_bucket.loki.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "loki" {
  bucket = aws_s3_bucket.loki.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
  }
}

resource "aws_s3_bucket_intelligent_tiering_configuration" "loki" {
  bucket = aws_s3_bucket.loki.id
  name   = "loki-tiering"

  tiering {
    access_tier = "ARCHIVE_ACCESS"
    days        = 90
  }

  tiering {
    access_tier = "DEEP_ARCHIVE_ACCESS"
    days        = 180
  }
}

resource "aws_s3_bucket_public_access_block" "loki" {
  bucket                  = aws_s3_bucket.loki.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- Tempo ---

resource "aws_s3_bucket" "tempo" {
  bucket = "addi-${var.environment}-tempo-${local.account_id}"
  tags   = var.tags
}

resource "aws_s3_bucket_versioning" "tempo" {
  bucket = aws_s3_bucket.tempo.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tempo" {
  bucket = aws_s3_bucket.tempo.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
  }
}

resource "aws_s3_bucket_intelligent_tiering_configuration" "tempo" {
  bucket = aws_s3_bucket.tempo.id
  name   = "tempo-tiering"

  tiering {
    access_tier = "ARCHIVE_ACCESS"
    days        = 90
  }

  tiering {
    access_tier = "DEEP_ARCHIVE_ACCESS"
    days        = 180
  }
}

resource "aws_s3_bucket_public_access_block" "tempo" {
  bucket                  = aws_s3_bucket.tempo.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# =============================================================================
# S3 Audit Trail Bucket - Object Lock (SFC requirement: 7-year immutable retention)
# =============================================================================

resource "aws_s3_bucket" "audit_trail" {
  bucket              = "addi-${var.environment}-audit-trail-${local.account_id}"
  object_lock_enabled = true
  tags                = var.tags
}

resource "aws_s3_bucket_versioning" "audit_trail" {
  bucket = aws_s3_bucket.audit_trail.id
  versioning_configuration {
    # Required for Object Lock
    status = "Enabled"
  }
}

resource "aws_s3_bucket_object_lock_configuration" "audit_trail" {
  bucket = aws_s3_bucket.audit_trail.id

  rule {
    default_retention {
      mode = "COMPLIANCE"
      days = var.audit_trail_retention_years * 365
    }
  }
}

resource "aws_s3_bucket_public_access_block" "audit_trail" {
  bucket                  = aws_s3_bucket.audit_trail.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# =============================================================================
# S3 Cross-Region Replication - DR (mimir, loki, tempo -> dr_region)
# =============================================================================

# DR destination buckets (created with provider alias aws.dr)

resource "aws_s3_bucket" "mimir_dr" {
  provider = aws.dr
  bucket   = "addi-${var.environment}-mimir-dr-${local.account_id}"
  tags     = var.tags
}

resource "aws_s3_bucket_versioning" "mimir_dr" {
  provider = aws.dr
  bucket   = aws_s3_bucket.mimir_dr.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "mimir_dr" {
  provider                = aws.dr
  bucket                  = aws_s3_bucket.mimir_dr.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket" "loki_dr" {
  provider = aws.dr
  bucket   = "addi-${var.environment}-loki-dr-${local.account_id}"
  tags     = var.tags
}

resource "aws_s3_bucket_versioning" "loki_dr" {
  provider = aws.dr
  bucket   = aws_s3_bucket.loki_dr.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "loki_dr" {
  provider                = aws.dr
  bucket                  = aws_s3_bucket.loki_dr.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket" "tempo_dr" {
  provider = aws.dr
  bucket   = "addi-${var.environment}-tempo-dr-${local.account_id}"
  tags     = var.tags
}

resource "aws_s3_bucket_versioning" "tempo_dr" {
  provider = aws.dr
  bucket   = aws_s3_bucket.tempo_dr.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "tempo_dr" {
  provider                = aws.dr
  bucket                  = aws_s3_bucket.tempo_dr.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# IAM role for S3 replication

resource "aws_iam_role" "s3_replication" {
  name = "addi-${var.environment}-observability-s3-replication"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "s3.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "s3_replication" {
  name = "s3-replication-policy"
  role = aws_iam_role.s3_replication.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetReplicationConfiguration",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.mimir.arn,
          aws_s3_bucket.loki.arn,
          aws_s3_bucket.tempo.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectVersionAcl",
          "s3:GetObjectVersionTagging"
        ]
        Resource = [
          "${aws_s3_bucket.mimir.arn}/*",
          "${aws_s3_bucket.loki.arn}/*",
          "${aws_s3_bucket.tempo.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags"
        ]
        Resource = [
          "${aws_s3_bucket.mimir_dr.arn}/*",
          "${aws_s3_bucket.loki_dr.arn}/*",
          "${aws_s3_bucket.tempo_dr.arn}/*"
        ]
      }
    ]
  })
}

# Replication configurations on source buckets

resource "aws_s3_bucket_replication_configuration" "mimir" {
  bucket = aws_s3_bucket.mimir.id
  role   = aws_iam_role.s3_replication.arn

  rule {
    id     = "mimir-dr-replication"
    status = "Enabled"

    destination {
      bucket        = aws_s3_bucket.mimir_dr.arn
      storage_class = "STANDARD_IA"
    }
  }

  depends_on = [aws_s3_bucket_versioning.mimir]
}

resource "aws_s3_bucket_replication_configuration" "loki" {
  bucket = aws_s3_bucket.loki.id
  role   = aws_iam_role.s3_replication.arn

  rule {
    id     = "loki-dr-replication"
    status = "Enabled"

    destination {
      bucket        = aws_s3_bucket.loki_dr.arn
      storage_class = "STANDARD_IA"
    }
  }

  depends_on = [aws_s3_bucket_versioning.loki]
}

resource "aws_s3_bucket_replication_configuration" "tempo" {
  bucket = aws_s3_bucket.tempo.id
  role   = aws_iam_role.s3_replication.arn

  rule {
    id     = "tempo-dr-replication"
    status = "Enabled"

    destination {
      bucket        = aws_s3_bucket.tempo_dr.arn
      storage_class = "STANDARD_IA"
    }
  }

  depends_on = [aws_s3_bucket_versioning.tempo]
}

# =============================================================================
# RDS PostgreSQL - Grafana backend database
# =============================================================================

resource "aws_db_subnet_group" "grafana" {
  name       = "grafana-${var.environment}"
  subnet_ids = var.subnet_ids
  tags       = var.tags
}

resource "aws_security_group" "grafana_rds" {
  name        = "grafana-rds-${var.environment}"
  description = "Allow PostgreSQL from VPC"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.main.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = var.tags
}

resource "aws_db_instance" "grafana" {
  identifier                  = "grafana-${var.environment}"
  engine                      = "postgres"
  engine_version              = "16.6"
  instance_class              = var.grafana_db_instance_class
  allocated_storage           = 20
  max_allocated_storage       = 100
  db_name                     = "grafana"
  username                    = "grafana"
  manage_master_user_password = true
  db_subnet_group_name        = aws_db_subnet_group.grafana.name
  vpc_security_group_ids      = [aws_security_group.grafana_rds.id]
  multi_az                    = var.grafana_db_multi_az
  storage_encrypted           = true
  backup_retention_period     = 7
  deletion_protection         = true
  skip_final_snapshot         = false
  final_snapshot_identifier   = "grafana-${var.environment}-final"
  tags                        = var.tags
}

# =============================================================================
# IAM roles - LGTM S3 access via Pod Identity
# =============================================================================

# --- Mimir ---

resource "aws_iam_role" "mimir" {
  name = "${var.cluster_name}-mimir"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = local.account_id
          "aws:SourceCluster" = var.cluster_name
        }
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "mimir_s3" {
  name = "mimir-s3-access"
  role = aws_iam_role.mimir.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ]
      Resource = [
        aws_s3_bucket.mimir.arn,
        "${aws_s3_bucket.mimir.arn}/*"
      ]
    }]
  })
}

resource "aws_eks_pod_identity_association" "mimir" {
  cluster_name    = var.cluster_name
  namespace       = "monitoring"
  service_account = "mimir"
  role_arn        = aws_iam_role.mimir.arn
}

# --- Loki ---

resource "aws_iam_role" "loki" {
  name = "${var.cluster_name}-loki"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = local.account_id
          "aws:SourceCluster" = var.cluster_name
        }
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "loki_s3" {
  name = "loki-s3-access"
  role = aws_iam_role.loki.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ]
      Resource = [
        aws_s3_bucket.loki.arn,
        "${aws_s3_bucket.loki.arn}/*"
      ]
    }]
  })
}

resource "aws_eks_pod_identity_association" "loki" {
  cluster_name    = var.cluster_name
  namespace       = "monitoring"
  service_account = "loki"
  role_arn        = aws_iam_role.loki.arn
}

# --- Tempo ---

resource "aws_iam_role" "tempo" {
  name = "${var.cluster_name}-tempo"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = local.account_id
          "aws:SourceCluster" = var.cluster_name
        }
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "tempo_s3" {
  name = "tempo-s3-access"
  role = aws_iam_role.tempo.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ]
      Resource = [
        aws_s3_bucket.tempo.arn,
        "${aws_s3_bucket.tempo.arn}/*"
      ]
    }]
  })
}

resource "aws_eks_pod_identity_association" "tempo" {
  cluster_name    = var.cluster_name
  namespace       = "monitoring"
  service_account = "tempo"
  role_arn        = aws_iam_role.tempo.arn
}
