# Exit Strategy - SFC CE 020/2022 Article 4

## Overview

This document describes Addi's exit strategy from its current cloud infrastructure, satisfying CE 020/2022 Article 4 requirements for cloud service provider dependency management and portability.

## Multi-Cloud Portability

**Infrastructure (Terraform):** All Terraform modules follow cloud-agnostic patterns where possible. EKS-specific resources (NodeClass, Pod Identity) have documented equivalents for GKE (Workload Identity) and AKS (Managed Identity). The VPC, IAM, and S3 patterns map directly to GCP VPC/GCS and Azure VNET/Blob.

**Workloads (Kubernetes):** All application workloads run on standard Kubernetes APIs. No proprietary AWS controllers are required in the workload data path. Migration is a cluster endpoint swap.

## Data Export Procedures

- **Object storage (S3):** Data exportable via `aws s3 sync` or S3 Batch Operations to any S3-compatible target (GCS, Azure Blob, MinIO).
- **Relational databases (RDS):** Standard PostgreSQL snapshots (`pg_dump`) are portable to any PostgreSQL-compatible engine.
- **Container images and OCI artifacts:** Stored in GHCR (bootstrap) or Harbor (production). OCI artifacts are registry-agnostic - migrate via `oras copy` or `skopeo copy`.

## Registry Migration

GHCR -> Harbor -> any OCI-compliant registry (ECR, GCR, ACR, Quay).

Migration procedure:
1. Update `configArtifact` registry URL in service specs (single variable per service)
2. Run `oras copy` or `skopeo sync` to replicate all tags to the new registry
3. Update CI pipeline registry target (one GitHub Actions variable)
4. No application code changes required

## Exit Timeline

| Phase | Duration | Activities |
|-------|----------|------------|
| Planning | Weeks 1–2 | Identify target provider, provision new infrastructure |
| Data migration | Weeks 3–6 | Replicate S3, snapshot RDS, sync OCI artifacts |
| Workload migration | Weeks 7–10 | Roll workloads to new cluster via Kargo |
| DNS cutover | Week 11 | Update Route53 -> new LB, validate SLOs |
| Decommission | Week 12–13 | Verify no traffic to old infra, destroy |

**Total exit window: 90 days** (conservative; parallel-team execution can compress to 60 days).

## AWS-Specific Dependencies and Alternatives

| AWS Service | Usage | Alternative |
|-------------|-------|-------------|
| EKS | Kubernetes control plane | GKE, AKS, self-managed k8s |
| RDS PostgreSQL | Grafana backend | Cloud SQL, Azure Database, self-managed |
| S3 | LGTM stack storage, artifacts | GCS, Azure Blob, MinIO |
| Secrets Manager | Application secrets | GCP Secret Manager, Azure Key Vault, Vault |
| CloudTrail | Audit logs | GCP Audit Logs, Azure Monitor |
| Route53 | DNS | Cloud DNS, Azure DNS, Cloudflare |
| WAF | Edge security | Cloud Armor, Azure Front Door WAF, Cloudflare |
| KMS | Encryption keys | Cloud KMS, Azure Key Vault, HashiCorp Vault |
