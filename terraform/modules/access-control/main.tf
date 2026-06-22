terraform {
  required_version = ">= 1.11.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.51"
    }
  }
}

# =============================================================================
# IAM Identity Center Permission Sets
# =============================================================================
# Break-Glass Access Strategy:
#
# Option 1 (Recommended - zero vendor risk): AWS TEAM (Temporary Elevated Access Management)
#   - Open-source, serverless (Step Functions + SNS + Slack)
#   - Manages time-boxed IAM Identity Center assignments
#   - Auto-revocation via Step Functions TTL
#   - CloudTrail audit trail included
#   - Repo: https://github.com/awslabs/aws-iam-identity-center-team
#
# Option 2 (Richer audit): Teleport Enterprise
#   - Native K8s exec recording, DB session recording, SSH
#   - Slack/PagerDuty approval workflows
#   - Additional vendor SFC CE 020/2022 notification required
#   - ~$15-25/user/mo
#
# Both tools integrate with these IAM Identity Center permission sets.
# =============================================================================

resource "aws_ssoadmin_permission_set" "read_only" {
  name             = "AddiReadOnly-${var.environment}"
  description      = "Read-only access for developers - standard day-to-day access"
  instance_arn     = var.sso_instance_arn
  session_duration = "PT8H"
  tags             = var.tags
}

resource "aws_ssoadmin_managed_policy_attachment" "read_only_view" {
  instance_arn       = var.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.read_only.arn
  managed_policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_ssoadmin_permission_set" "break_glass" {
  name             = "AddiBreakGlass-${var.environment}"
  description      = "JIT break-glass access - max 1 hour, requires 2 approvals via AWS TEAM or Teleport"
  instance_arn     = var.sso_instance_arn
  session_duration = var.break_glass_session_duration
  tags             = var.tags
}

resource "aws_ssoadmin_permission_set_inline_policy" "break_glass" {
  instance_arn       = var.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.break_glass.arn

  inline_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EKSReadAndAccess"
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters",
          "eks:AccessKubernetesApi",
          "eks:DescribeNodegroup",
          "eks:ListNodegroups",
          "eks:DescribeAddon",
          "eks:ListAddons"
        ]
        Resource = "*"
      },
      {
        Sid    = "DenyDestructiveEKSActions"
        Effect = "Deny"
        Action = [
          "eks:DeleteCluster",
          "eks:DeleteNodegroup",
          "eks:DeleteAddon"
        ]
        Resource = "*"
      },
      {
        Sid    = "CloudWatchLogsAccess"
        Effect = "Allow"
        Action = [
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:GetLogEvents",
          "logs:FilterLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}
