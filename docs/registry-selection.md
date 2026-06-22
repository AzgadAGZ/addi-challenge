# Registry Selection for OCI Config Artifacts

## Decision Framework

Addi stores per-service configuration as OCI artifacts. Two candidates exist for the artifact registry: GitHub Container Registry (GHCR) and Harbor. This document explains when to use each and why production must target Harbor.

## Current State

This repository uses GHCR as the interim registry for both container images and OCI config artifacts. This is appropriate for the bootstrap phase and take-home demonstration. For production deployment under SFC regulation, Harbor should be deployed as described below. The migration is a registry URL swap - no architectural changes required.

## Comparison

| Concern | GHCR | Harbor |
|---|---|---|
| Hosting | GitHub-managed (US) | Self-hosted (your infra) |
| Data residency control | None | Full |
| Tag immutability | Not supported natively | Native, per-repository |
| Audit log access | Limited | Complete |
| Compliance posture | Consumer-grade | Enterprise / regulated |
| Setup cost | Zero | Moderate |

## Why Harbor for Production

Addi operates under SFC CE 020/2022 (Colombia's financial regulator). That circular requires firms to maintain control over infrastructure hosting regulated data. GHCR stores artifacts on GitHub's US-based infrastructure - you cannot audit where objects land, you cannot enforce tag immutability, and you cannot demonstrate to regulators that artifact state is tamper-proof.

Harbor, deployed within Addi's own Kubernetes cluster, satisfies all three:

- **Data residency**: artifacts never leave Addi-controlled infrastructure.
- **Tag immutability**: enabled per repository; once a config tag is pushed, it cannot be overwritten or deleted without an explicit policy exception.
- **Audit trail**: every push, pull, and deletion is logged and exportable for regulatory review.

GHCR is acceptable for non-production environments where compliance obligations do not apply.

## Migration Path

The registry URL is a single variable - `configArtifact` - declared once per service. Switching from GHCR to Harbor requires changing that one value. No application code changes, no schema migrations, no pipeline rewrites. Services pull whatever URL is configured at deploy time.

## Scalability

At 1000 services, config artifacts grow at approximately 1.9 GB per year. Storage cost is negligible. Neither GHCR nor Harbor presents a scaling concern for this workload.

## Tag Convention

```
{service}-{version}-{region}
```

Example: `payments-api-v1.4.2-prod-us-east-1`

Region is included because the same service version may carry different config per region.

## Tag Cleanup Policy

- **Deployed tags**: never delete. A deployed tag is an immutable audit record.
- **All tags**: retain for a minimum of 13 months to satisfy regulatory audit windows.
- **Undeployed tags** (pushed but never deployed to any environment): eligible for deletion after 90 days.

Cleanup jobs must check deployment state before deleting any tag.
