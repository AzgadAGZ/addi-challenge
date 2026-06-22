# Addi Platform - AI Agent Instructions

## Repository Purpose

This repository defines Addi's EKS platform infrastructure: multi-layered security (CloudFront -> WAF -> private ALB -> Cilium mesh), progressive delivery (ArgoCD + Kargo + Argo Rollouts), and self-hosted observability (LGTM stack). Compliant with Colombian banking regulation (SFC).

## Repository Structure

```
terraform/          Terraform modules (VPC, EKS, security, networking, IAM, observability)
k8s/platform/       Platform-team K8s manifests (Cilium, ArgoCD, Kargo, Kyverno, LGTM)
k8s/services/       Service values.yaml files (consumed by addi-workload Helm chart via ArgoCD multi-source)
spec/               Starlark DSL library, examples, JSON Schema
scripts/            Generator script (spec -> K8s manifests)
docs/               Architecture diagrams and strategic documentation
.github/workflows/  CI/CD pipelines
```

## Onboarding a New Service

1. Create `service.star` in the service repo root using constructors from `spec/lib/`:
   - `api()` for HTTP/gRPC services
   - `worker()` for async event processors
   - `cronjob()` for scheduled batch jobs
   - One service can have multiple components (e.g., API + Worker + CronJob)

2. Create `deploy/<env>-<region>.star` files with per-environment `deployment()` overrides

3. Run the generator: `./scripts/generate-from-spec.sh spec/examples/<service>/`
   (Generator produces `values.yaml` per environment - not base + overlays)

4. Generated output lands in `k8s/services/<service-name>/{dev,staging,prod}/values.yaml`

5. Open PR - CODEOWNERS enforces required approvals:
   - `k8s/services/*/prod/` -> Platform team (production gating)
   - `values.yaml` with `dataClassification: restricted` -> Security team
   - Everything else -> Service team only
   (Network policies and rollout strategy are now rendered by the `addi-workload` chart - no standalone files to review)

6. On merge, ApplicationSet auto-discovers the new folder -> ArgoCD syncs via multi-source
   (addi-workload OCI chart from `ghcr.io/addi/charts` + per-service `values.yaml` from Git)

## Validation

- Terraform: `cd terraform/modules/<module> && terraform init -backend=false && terraform validate`
- K8s YAML: `yamllint -d relaxed k8s/`
- Starlark: files are valid Python 3 syntax (Starlark is a subset)
- JSON Schema: `spec/schemas/service-spec.schema.json` validates service definitions

## Key Patterns

- **Exposure modes**: `private` (internal ALB), `cloudfront` (CloudFront -> VPC Origin -> private ALB), `public` (internet-facing, requires security approval)
- **Rollout strategies**: `canary(steps=[10,50,100])`, `blue_green()`, `rolling()` - rendered by the shared `addi-workload` Helm chart (no per-service Kustomize overlays)
- **Dependencies**: `":local-component"` or `"//domain:service"` -> generates CiliumNetworkPolicy
- **Secrets**: `secrets_manager("KEY")` -> generates ExternalSecret (ESO -> AWS Secrets Manager)
- **SLOs**: `slo(service, availability, latency_p99_ms)` -> generates Sloth PrometheusServiceLevel
- **Infrastructure**: `infrastructure()` declarations are DESIRABLE (not yet implemented)

## Constraints

- Never commit real AWS credentials or secrets
- Use ExternalSecrets pattern for all secrets
- Community Terraform modules (`terraform-aws-modules/*`) preferred over custom
- All public-facing services require `exposure: "cloudfront"` (never direct ALB)
- Production requires: min 2 replicas, immutable image tags, trusted registry, canary rollout
- SFC compliance: immutable audit trail (S3 Object Lock), PII redaction in logs, encryption at rest/transit
