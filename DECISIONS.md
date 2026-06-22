# Architectural Decisions

Every decision in this repository is documented here with context, alternatives considered, and rationale. Decisions are grouped by domain and ordered from foundational to specific.

---

## Networking

### D-01: CloudFront as sole public entry point (no public ALBs)

**Context:** Addi's current architecture uses a single shared ALB as the public entry point for 1000+ services. This is a single point of failure with no WAF protection, no DDoS mitigation, and no caching layer.

**Decision:** All public traffic routes through CloudFront. ALBs are always private (internal scheme). CloudFront connects to ALBs via VPC Origin - traffic never traverses the public internet between CloudFront and the ALB.

**Alternatives considered:**
- Public ALB with WAF attached directly - simpler, but ALB is still reachable directly (bypassing WAF) if the DNS is misconfigured or the ALB hostname leaks
- API Gateway - adds latency for pass-through APIs, introduces another service to manage, throttling semantics don't fit all workload types
- NLB + Istio Gateway - requires sidecar mesh, adds complexity without CloudFront's caching and geo-restriction

**Why CloudFront:** CloudFront provides TLS termination, DDoS protection (Shield Standard included), geo-restriction (relevant for SFC data residency), static content caching (reduces ALB load), and VPC Origin ensures the ALB is never exposed. The WAF attaches to CloudFront, not the ALB - any request that bypasses CloudFront never reaches the infrastructure.

### D-02: Cilium eBPF service mesh (not Istio, not Linkerd)

**Context:** 1000+ microservices need service-to-service encryption (mTLS), network policy enforcement, and observability. Traditional service meshes add sidecar proxies to every pod.

**Decision:** Cilium with eBPF in kernel space. No sidecars. mTLS via Cilium's built-in PKI with 30-day auto-rotation. Default-deny network policies enforced at the kernel level.

**Alternatives considered:**
- Istio + Envoy sidecars - industry standard, but each sidecar adds 50-100MB RAM and 5-10ms latency per hop. A typical request chain (3-5 hops deep) accumulates 15-50ms of sidecar overhead per end-to-end request. Memory overhead: 50-100GB of RAM cluster-wide just for sidecars (1000 pods x 50-100MB each)
- Linkerd - lighter than Istio (~10MB per sidecar, ~1-2ms latency), but still user-space proxies with measurable overhead
- No mesh (just NetworkPolicies) - loses mTLS, loses L7 observability, loses traffic splitting for canary

**Why Cilium:** eBPF operates in kernel space - zero sidecar overhead, sub-millisecond latency, and the networking stack (CNI + service mesh + network policies + observability) is unified in one component. Hubble provides pod-to-pod flow visibility at L3/L4/L7 without additional tooling. At 1000+ services, the operational simplicity of one agent vs. 1000+ sidecar proxies is significant.

### D-03: Internal traffic via Cilium ClusterIP (never through ALB)

**Context:** Service-to-service calls could route through the ALB (external path) or directly pod-to-pod via Kubernetes ClusterIP.

**Decision:** All internal communication uses ClusterIP DNS resolved by CoreDNS, routed by Cilium eBPF in kernel space. ALBs handle only external ingress traffic.

**Why:** Internal traffic through ALBs adds cost ($0.008/LCU-hour + $0.01/GB processed), latency (5-10ms per hop), and breaks the mTLS chain (ALB terminates TLS, re-encrypts to pod). With 1000 services making ~5 internal calls each at 100 req/s, routing through ALBs would cost $2,000-4,000/month and add 25-50ms per request chain. Cilium ClusterIP costs $0 and adds less than 1ms.

### D-04: VPC Endpoints to eliminate NAT Gateway traffic

**Context:** NAT Gateways charge $0.045/hr + $0.045/GB processed. Pods making AWS API calls (ECR image pulls, STS credential exchanges, SSM parameter lookups, CloudWatch log pushes, KMS encryption) all route through NAT.

**Decision:** Deploy VPC Gateway Endpoints for S3 and DynamoDB (free), VPC Interface Endpoints for ECR, STS, SSM, CloudWatch Logs, and KMS ($0.01/GB vs $0.045/GB). NAT Gateways remain only for genuine external traffic (third-party APIs, webhooks).

**Impact:** NAT Gateway cost drops from ~$966/month to ~$300/month (69% savings). In dev/staging, a single NAT Gateway per VPC (instead of 3 per AZ) further reduces costs.

### D-05: Route53 weighted DNS for migration cutover (not CloudFront origin failover)

**Context:** Migrating 1000 services from legacy ALB to CloudFront+WAF+private ALB requires a gradual, per-service cutover mechanism.

**Decision:** Route53 weighted records per service. Legacy ALB stays untouched. Each service gets two weighted records (legacy CNAME + CloudFront alias). Traffic shifts gradually: 100/0 -> 90/10 -> 50/50 -> 0/100.

**Alternatives considered:**
- CloudFront origin failover - would require putting the legacy ALB behind CloudFront first, which adds complexity to a system we are trying to migrate away from
- DNS CNAME swap (instant cutover) - binary, no gradual rollout, higher risk
- Istio/Envoy traffic splitting - requires service mesh on the legacy namespace, which defeats the migration purpose

**Why Route53 weighted:** Per-service granularity, reversible in ~60s (revert weight), observable (compare error rates at each weight), no changes to legacy infrastructure. The legacy ALB continues operating exactly as-is until a service is fully migrated.

---

## Security

### D-06: WAF rule chain - COUNT+label, not direct ALLOW

**Context:** WAF needs to validate that incoming requests have a valid Host header, then pass them through OWASP managed rules, then allow valid traffic.

**Decision:** Host validation rules use COUNT action with a label (`valid-host`). The default action is BLOCK. Managed rules (SQLi, XSS, Bot Control) evaluate all requests regardless of host. A final rule at priority 99 ALLOWs traffic only if it has the `valid-host` label.

**Why not direct ALLOW on host match:** An ALLOW action at host validation priority would short-circuit evaluation - valid-host requests would skip SQLi/XSS/Bot checks entirely. COUNT+label is non-terminating: the request continues through all security rules. Only if it survives every check AND has a valid host does the final ALLOW rule pass it through.

### D-07: Pod Identity (not IRSA) for service-to-AWS access

**Context:** Kubernetes pods need to assume AWS IAM roles to access services like Secrets Manager, S3, STS.

**Decision:** EKS Pod Identity via the `eks-pod-identity-agent` addon.

**Alternatives considered:**
- IRSA (IAM Roles for Service Accounts) - requires creating and managing an OIDC provider per cluster, trust policies reference the OIDC provider ARN (long, cluster-specific, error-prone), credential injection via mutating webhook (if webhook is down, pods can't assume roles)
- Instance profiles - all pods on a node share the same IAM role, violates least privilege
- Long-lived IAM access keys - prohibited by SFC CE 007/2018 and our own SCPs

**Why Pod Identity:**
1. No OIDC provider to manage per cluster
2. Trust policy uses `pods.eks.amazonaws.com` - same principal across all clusters, all accounts
3. DaemonSet agent (not webhook) - survives control plane outages
4. Association is external to the ServiceAccount - platform team manages bindings without touching service manifests
5. CloudTrail shows `eks:PodIdentityAssociation` events - cleaner audit trail for SFC

### D-08: AWS TEAM for break-glass (with Teleport as alternative)

**Context:** SFC Decreto 2555 requires segregation of duties and auditable access to production. Engineers need emergency access for incident response, but standing access violates compliance.

**Decision:** Recommend AWS TEAM (Temporary Elevated Access Management) as the primary break-glass mechanism. Document Teleport as an alternative for organizations that need session recording for database access.

**Why TEAM over Teleport for a new deployment:** TEAM is serverless (API Gateway + Lambda + Step Functions + DynamoDB), zero operational cost, auto-revocation guaranteed by Step Functions TTL, no additional vendor dependency. Teleport adds infrastructure (dedicated proxy servers, certificate authority) and a vendor relationship that requires SFC notification under CE 020/2022.

**When Teleport wins:** If Addi already uses Teleport, or if SFC auditors require session recording (video-like replay of terminal sessions) for database access - something TEAM does not provide.

### D-09: CODEOWNERS + Kyverno - dual-layer governance

**Context:** Developer autonomy must be balanced with security controls. Service teams should deploy independently, but certain changes (public exposure, network policy, production config) need review.

**Decision:** Two enforcement layers:
1. CODEOWNERS in GitHub - PR-level gate. Exposure changes require security team approval. Production overlays require platform team approval.
2. Kyverno admission control - cluster-level gate. Even if someone bypasses the PR process (admin merge, force push), Kyverno blocks public-facing ingress without the `addi.com/security-approved: "true"` label.

**Why both:** CODEOWNERS alone is a process control - it can be overridden. Kyverno alone operates at admission time - it can't review intent. Together they enforce at both the review layer and the runtime layer. SFC Decreto 2555 requires demonstrable segregation of duties - this dual-layer approach provides audit evidence at both stages.

### D-10: Immutable audit trail - S3 Object Lock COMPLIANCE mode, 7 years

**Context:** SFC CE 007/2018 requires immutable audit trails. CloudTrail logs and observability data must be tamper-proof.

**Decision:** S3 buckets for CloudTrail and audit data use Object Lock in COMPLIANCE mode with 7-year retention. COMPLIANCE mode cannot be overridden even by the root account - objects are immutable for the full retention period.

**Why COMPLIANCE over GOVERNANCE mode:** GOVERNANCE mode allows users with specific IAM permissions to override the lock. For a regulated bank, the regulator needs assurance that not even the account owner can delete audit records. COMPLIANCE mode provides that guarantee.

**Why 7 years:** SFC requires minimum 5 years for financial records. 7 years provides a 2-year margin and aligns with international banking standards (Basel III recommends 7 years).

### D-11: KMS customer-managed keys (not AWS-managed SSE-S3)

**Context:** S3 encryption can use SSE-S3 (AWS manages keys) or SSE-KMS (customer-managed keys).

**Decision:** All production S3 buckets (observability data, audit trails, OCI artifacts) use SSE-KMS with a customer-managed KMS key. Annual key rotation enabled.

**Why CMK over SSE-S3:** CMK provides centralized key governance (who accessed what, when), CloudTrail audit of every key usage, and the ability to revoke access by disabling the key. SSE-S3 keys are invisible to the customer - no audit trail, no revocation capability. For SFC CE 007/2018, demonstrating key management control is a stronger compliance posture.

---

## Deployment & Delivery

### D-12: ArgoCD + Kargo + Argo Rollouts (not ArgoCD alone, not FluxCD)

**Context:** 1000+ services need GitOps delivery with progressive rollout, environment promotion gates, and automated rollback.

**Decision:** Three-tool stack:
- ArgoCD - reconciles Git state to cluster state (the "how" of deployment)
- Kargo - orchestrates promotion across environments (the "when" of deployment)
- Argo Rollouts - executes canary/blue-green rollouts with metric gates (the "safety" of deployment)

**Why not ArgoCD alone:** ArgoCD syncs manifests but has no native concept of promotion pipelines (dev -> staging -> prod) or metric-gated canary rollouts. Teams would need custom workflows for promotion and manual rollback procedures.

**Why not FluxCD:** Flux is excellent for GitOps but lacks Kargo's promotion orchestration and Argo Rollouts' traffic-splitting canary analysis. Flux + Flagger is a comparable combination, but the Argo ecosystem (ArgoCD + Kargo + Rollouts) provides tighter integration - Kargo was built by Akuity (the ArgoCD company) specifically to complement ArgoCD.

### D-13: OCI config artifacts for atomic promotion (not direct gitops commits)

**Context:** ArgoCD auto-sync is enabled (`selfHeal: true`). Writing compiled config (Helm values from Starlark) directly to the gitops repo triggers immediate deployment before Kargo can gate the promotion. Config and image tag must land in one atomic commit.

**Decision:** Compiled Helm values are stored as versioned, immutable OCI artifacts in the container registry. CI compiles Starlark -> pushes OCI artifact via ORAS. During Kargo promotion, `oci-download` pulls the artifact, `copy` replaces the values.yaml, `yaml-update` sets the image tag, and `git-commit` creates one atomic commit. ArgoCD only sees the final state - never a partial write.

**Why OCI over direct git commit from CI:**
- No race condition between config write and image promotion
- Config artifact is immutable and content-addressable (same guarantees as container images)
- One commit per promotion (not N commits for N config fields)
- Config-only changes to production use the same pipeline (git tag -> OCI artifact -> Kargo promote)
- Scales to 3000+ services: 1 OCI repo with many tags, ~1.9GB/year storage

**Industry precedent:** Google Config Sync, Flux CD, Netflix Managed Delivery all use OCI as the configuration delivery mechanism. KubeCon 2025 "Gitless GitOps" talk explicitly advocates this pattern.

### D-14: Canary rollout with Prometheus-gated analysis (not time-based)

**Context:** Production deployments need safety gates. Options range from "wait 5 minutes and hope" to metric-driven automated analysis.

**Decision:** Argo Rollouts executes canary steps (10% -> 50% -> 100%) with AnalysisRun checks at each stage. Analysis queries Prometheus for error rate (< 5%) and p99 latency (< 500ms). If either metric fails, the rollout auto-rolls back to the previous ReplicaSet.

**Why metric-gated over time-based:** A time-based pause (e.g., 5 minutes) doesn't tell you if the canary is healthy - it just waits. A metric-gated analysis measures the actual impact: is the error rate within SLO? Is latency acceptable? A bad version that increases error rate from 0.1% to 10% would pass a time-based gate but fail the metric gate immediately. For a payments platform, detecting a bad deployment in seconds (not minutes) is the difference between 10 failed transactions and 10,000.

### D-15: Staging soak of 4 hours with health-check gates

**Context:** How long should a version soak in staging before being eligible for production?

**Decision:** 4-hour soak with continuous health-check analysis (error rate + latency p99, evaluated every 5 minutes for 48 intervals).

**Why 4 hours:** Short enough for daily deploy cadence (deploy in morning, 4hr soak, promote to prod in afternoon). Long enough to catch: database connection pool exhaustion (typically manifests after 1-2 hours under load), memory leaks (GC pressure builds over hours, not minutes), cache warming effects (cold cache performance vs warm), and time-sensitive business logic (e.g., a payment processor that handles differently during Colombian banking hours vs. off-hours).

### D-16: Manual approval for production (auto-promote dev/staging)

**Context:** Should production promotion be automatic (if SLOs are met) or require human approval?

**Decision:** Dev and staging auto-promote. Production requires manual approval via Kargo. Documented in the Kargo Project resource with `autoPromotionEnabled: false` for the prod stage.

**Why manual for a bank:** SFC Decreto 2555 requires change management controls for production systems. An automatic promotion - even one gated by metrics - removes the human accountability that regulators expect. The human approver is recorded in the Kargo audit trail as evidence of the change management process. Auto-promotion can be evaluated once SFC audit practices are established and the team has confidence in the SLO gates.

---

## Infrastructure as Code

### D-17: Terraform with community modules (not OpenTofu, not Terragrunt, not Pulumi)

**Context:** The challenge specifies "Terraform/IaC." The IaC tool choice affects evaluator familiarity and maintenance burden.

**Decision:** Vanilla Terraform with `terraform-aws-modules/*` community modules where available. Custom modules only when no community module exists.

**Alternatives considered:**
- OpenTofu - truly open-source fork, identical HCL syntax. Better long-term choice but may confuse evaluators unfamiliar with the fork
- Terragrunt - DRY layer on top of Terraform. Adds operational complexity (Terragrunt config + Terraform config) without proportional benefit for a take-home
- Pulumi - general-purpose languages (Go, Python). More flexible but evaluators expect HCL for a DevOps role
- CDK for Terraform - TypeScript/Python generating Terraform. Additional build step, debugging is harder

**Why community modules first:** `terraform-aws-modules/vpc`, `terraform-aws-modules/eks` are battle-tested by thousands of organizations. They handle edge cases (multi-AZ NAT, endpoint routing, addon management) that custom modules would need to re-implement and maintain. Custom code is technical debt - community modules are shared maintenance.

### D-18: Starlark DSL for service specs (not raw YAML, not HCL, not CUE)

**Context:** Service teams need to define their workload configuration. The format must be safe, type-checkable, and resistant to common errors.

**Decision:** Starlark (Python-like, deterministic, sandboxed) as the input language. Each service has `service.star` (component definitions) and `deploy/<env>-<region>.star` (environment overrides). A CLI compiles Starlark to Helm values.yaml.

**Alternatives considered:**
- Raw YAML - fragile. A single indentation error silently produces wrong config. No type checking, no cross-field validation, no composability
- HCL - Terraform-native but mixing HCL for service specs with YAML for K8s manifests feels inconsistent. Also, HCL is less familiar to application developers than Python
- CUE - type-safe, constraint validation. Excellent language but unfamiliar to most developers. Learning curve higher than Starlark
- JSON Schema + YAML - validation catches errors but doesn't prevent them. Developers still write fragile YAML

**Why Starlark:**
1. Python-like syntax - familiar to most developers, near-zero learning curve
2. Real parser - syntax errors are caught at parse time, not at deploy time. No "bad indentation = wrong config" class of bugs
3. Sandboxed - no file I/O, no network access, no arbitrary imports. Safe for CI execution
4. Functions as guardrails - `api()`, `worker()`, `canary()` validate arguments at definition time
5. Cross-field validation - `exposure = "cloudfront"` can automatically require `slo.availability >= 99.9`
6. Composable - `load("@addi//lib:patterns.star", "standard_api")` for golden-path presets

### D-19: Shared Helm chart (not duplicated manifests per service)

**Context:** 1000+ services need the same K8s resource patterns: Rollout/Deployment, Service, CiliumNetworkPolicy, ExternalSecret, SLO, HPA, PDB. Duplicating these manifests per service means N copies of the same templates with slight variations.

**Decision:** A single `addi-workload` Helm chart in `charts/addi-workload/`. Each service provides only a `values.yaml` per environment. ArgoCD uses multi-source: Source 1 = OCI Helm chart from GHCR, Source 2 = values.yaml from the gitops repo.

**Why shared chart over per-service manifests:**
- DRY: security context hardening (runAsNonRoot, readOnlyRootFilesystem, drop ALL, seccomp) defined once in the chart, applied to every service automatically
- Consistency: a change to probe configuration, resource defaults, or network policy patterns propagates to all services via chart version bump
- Less generator output: the Starlark compiler produces one values.yaml (20-50 lines) instead of 8+ YAML files (200+ lines)
- Easier upgrades: when Argo Rollouts or CiliumNetworkPolicy APIs evolve, update the chart - not 1000 separate manifests

**Why multi-source over Kustomize:** Kustomize helmCharts has security restrictions on file access - each overlay needs a self-contained values.yaml and cannot reference files outside its directory. Multi-source Applications separate the chart (versioned OCI artifact) from the values (Git), allowing Kargo to manage the chart version independently of the values.

---

## Observability

### D-20: Self-hosted LGTM stack (not Grafana Cloud)

**Context:** 1000 services generate ~250K metric series, ~30TB logs/month, and traces at 10% sampling. The observability stack must be reliable, cost-predictable, and compliant with SFC data sovereignty requirements.

**Decision:** Self-hosted Mimir (metrics), Loki (logs), Tempo (traces), Grafana (dashboards) on EKS with S3 backend.

**TCO comparison at 1000 services:**
- Grafana Cloud: ~$17,250/month (usage-based, dominated by log ingestion at ~$15,000/month)
- Self-hosted single-region: ~$13,100/month (fixed compute + S3 storage + 0.5 FTE SRE)
- Self-hosted multi-region DR: ~$18,700/month

**Why self-hosted for a bank:**
1. Data sovereignty - SFC can inspect Addi's infrastructure directly. With Grafana Cloud, audit evidence lives in Grafana Labs' infrastructure, requiring contractual arrangements for SFC inspection rights
2. Cost predictability - log volume at 1000 services makes usage-based pricing volatile. A traffic spike doubles the Grafana Cloud bill. Self-hosted cost is fixed compute
3. CE 020/2022 vendor management - each cloud provider requires SFC notification. Self-hosted on existing AWS avoids adding Grafana Labs as an additional vendor
4. Data residency - LGTM data stays in the same AWS region as the workloads. No cross-border data transfer

**When to reconsider:** If the operational burden of self-hosted observability exceeds 1 FTE, or if Addi's service count drops below 200 (where Grafana Cloud pricing becomes competitive).

### D-21: Alloy as unified collector (not Prometheus agent + Fluentd + OTel Collector)

**Context:** Observability requires collecting metrics, logs, and traces from every pod. Traditionally this means three separate agents.

**Decision:** Grafana Alloy deployed as a DaemonSet. One agent collects all three signal types and includes a PII redaction pipeline.

**Why one agent over three:**
- One DaemonSet to manage, monitor, and debug instead of three
- One configuration language (Alloy config) instead of three (Prometheus config, Fluentd config, OTel Collector YAML)
- PII redaction applied at the collection layer before data reaches storage - redaction logic defined once, applied to all signals

### D-22: PII redaction at collection layer (not at application or query layer)

**Context:** SFC Ley 1581/2012 requires personal data protection. Financial logs inevitably contain PII: Colombian cedula numbers, NIT (tax IDs), card numbers, email addresses.

**Decision:** Alloy's pipeline includes regex-based redaction stages that replace PII patterns with `[REDACTED_*]` tokens before data is written to Mimir/Loki/Tempo. Redaction happens at collection, not at application emission or query time.

**Why collection layer:**
- Application-layer redaction requires every team to implement it correctly - at 1000 services, someone will miss it
- Query-layer redaction (e.g., Grafana data source transformations) means PII is stored unredacted - if the storage is compromised, PII is exposed
- Collection-layer redaction is centralized (one Alloy config), applied before storage (PII never hits S3), and transparent to application developers

**PII patterns redacted:** Colombian cedula (contextual field-prefix matching to avoid false positives on transaction IDs), NIT (formatted `NNN.NNN.NNN-D`), payment card numbers (13-19 digit sequences), email addresses.

### D-23: Sloth SLOs with burn-rate alerts (not raw Prometheus alerts)

**Context:** Service teams need to define SLI/SLO targets. Alerting must be noise-free and actionable.

**Decision:** Sloth generates PrometheusRules from a simple SLO spec. Multi-window burn-rate alerts fire based on error budget consumption rate, not raw error counts.

**Why burn-rate over threshold alerts:**
- A threshold alert ("error rate > 1%") fires on a 1-minute spike and pages the on-call. The spike resolves in 2 minutes. The page was noise
- A burn-rate alert ("error budget burning at 14x rate") fires only when the rate of error budget consumption threatens the monthly SLO target. Brief spikes don't trigger it. Sustained degradation does
- Multi-window (fast: 5m/1h + slow: 30m/6h) prevents flapping: fast window catches acute incidents, slow window catches chronic degradation

### D-24: SLO-to-deployment feedback loop

**Context:** SLOs exist as monitoring constructs. Deployment exists as a delivery construct. They should be connected.

**Decision:** The same Prometheus metrics that drive SLO burn-rate alerts also feed Argo Rollouts AnalysisTemplates. A canary deployment that degrades the SLO is automatically rolled back. A Kargo promotion to the next stage is blocked if the current stage's SLO is unhealthy.

**Why this matters:** Without this loop, a team can define a 99.95% availability SLO and simultaneously deploy a version that drops availability to 99.5%. The SLO alert fires after deployment is complete. With the feedback loop, the deployment itself is the first line of defense - the canary fails before full rollout.

---

## Supply Chain Security

### D-25: Golden base images with 7-scanner pipeline

**Context:** Every service builds on a base image. The base image's security posture affects every service that inherits from it.

**Decision:** Three hardened golden base images (Go distroless, Python Alpine, Node Alpine) maintained by platform engineering. Each image passes a 7-scanner zero-tolerance gate before being published:
1. Hadolint - Dockerfile best practices
2. Trivy - CVE scanning (images + dependencies)
3. Grype - CVE scanning (second opinion, different vulnerability database)
4. Dockle - CIS Docker benchmark
5. Gitleaks - secret detection in build context
6. Syft - SBOM generation (CycloneDX)
7. Checkov - Dockerfile security policies

**Why 7 scanners (not just Trivy):** Each scanner has a different vulnerability database, different detection heuristics, and different coverage. Trivy and Grype both scan for CVEs but use different data sources - a CVE missed by one is often caught by the other. Hadolint catches Dockerfile anti-patterns that vulnerability scanners ignore. Dockle validates CIS benchmark compliance that static analysis tools miss. Defense in depth at the scanner level.

### D-26: CVE exceptions as OCI labels - propagation to consumer builds

**Context:** Golden base images have known vulnerabilities that are not exploitable in our context (e.g., a libexpat CVE in a distroless image that never parses XML). These exceptions must travel with the image - consumer CI pipelines need to know which CVEs are already accepted.

**Decision:** A central `cve-exceptions.json` registry defines accepted CVEs with justification, expiry date, and scoped applicability (`applies_to: ["go", "python"]`). At build time, the exception registry is:
1. Filtered per image by `applies_to`
2. Compressed into compact JSON
3. Injected as the `security.cve-exceptions` OCI label on the golden image

Consumer CI pipelines:
1. Read the `FROM` image in the Dockerfile
2. Pull the golden image and extract the `security.cve-exceptions` label
3. Merge with the repo's local `.trivyignore` (service-specific exceptions)
4. Pass the merged exception list to Trivy

**Why OCI labels over a shared file:** The exception list is bound to the specific image version. If the golden image is rebuilt with a new exception, only consumer builds that use the new image version get the new exception. There's no global file that silently suppresses CVEs for images that were built before the exception was added. The exception travels with the artifact - it's part of the supply chain, not a side-channel.

### D-27: Cosign keyless signing via GitHub OIDC (not keypair-based)

**Context:** Container images must be signed to prove they were built by authorized CI pipelines. SFC CE 007/2018 requires supply chain integrity controls.

**Decision:** Cosign keyless signing using GitHub OIDC. No keypair to generate, store, rotate, or protect. GitHub's OIDC issuer provides a short-lived certificate (5 minutes) scoped to the specific workflow run. The signature and certificate are recorded in the Sigstore transparency log (Rekor).

**Why keyless over keypair:** Keypair-based signing requires secure key storage (Vault, KMS, HSM), rotation ceremonies, and key compromise procedures. Keyless signing delegates trust to the CI identity system (GitHub OIDC) - the question changes from "who has the key?" to "did this workflow run on this repo on this branch?" The transparency log provides immutable proof.

### D-28: SBOM in Dependency-Track (not just attached to images)

**Context:** SBOMs attached to images via Cosign are useful for per-image verification, but answering "which of our 1000 services use libexpat?" requires querying across all SBOMs.

**Decision:** CycloneDX SBOMs are generated by Trivy, attached to images (Cosign), and also uploaded to OWASP Dependency-Track. Dependency-Track indexes all components across all services and provides:
- Proactive CVE alerts: new CVE published -> Dependency-Track matches against all indexed SBOMs -> Slack alert with affected service list
- License compliance: detect GPL/AGPL in production dependencies (legal risk for banking)
- SFC audit evidence: complete component inventory per service, timestamped, versioned

**Why Dependency-Track over manual queries:** When a critical CVE drops (Log4Shell, xz backdoor), the incident response question is "which of our 1000 services are affected?" Without Dependency-Track, the answer requires pulling and parsing 1000 SBOM files. With it, it's a single API query that returns results in seconds.

### D-29: CBOM strategy for cryptographic inventory

**Context:** SFC CE 007/2018 mandates documented encryption mechanisms. PCI DSS 4.0 requires cryptographic inventory. NIST post-quantum migration timeline (2030-2035) requires knowing what algorithms to migrate.

**Decision:** A Cryptographic Bill of Materials (CBOM) strategy document catalogs every cryptographic algorithm, protocol, key length, and certificate in the platform. Currently maintained as a manual document with a 14-row inventory table. Phase 2 plans automated detection via `cryptobom-forge` in CI.

**Why document it now (even manually):** If SFC asks "what encryption protects customer financial data?" the answer is this table - not "we think it's AES-256 somewhere." The manual catalog is also the starting point for post-quantum migration planning: every RSA/ECDH instance in the inventory is a future migration target for ML-KEM/ML-DSA.

---

## Registry & Artifact Management

### D-30: GHCR for bootstrap, Harbor for production (SFC data residency)

**Context:** Container images, OCI config artifacts, Helm charts, and SBOMs need a registry. The registry choice affects compliance, scalability, and operational burden.

**Decision:** GHCR for the bootstrap phase and this take-home. Harbor recommended as the production registry for SFC-regulated operations.

**Why Harbor for production:**
- Data residency - GHCR is US-hosted with no regional control. SFC CE 020/2022 requires the bank to control where deployment artifacts are stored. Harbor runs in Addi's AWS region
- Tag immutability - GHCR has no immutability toggle. Harbor provides per-project immutability, ensuring a released artifact cannot be overwritten
- Multi-region replication - Harbor replicates artifacts to DR region automatically. No cross-border pull at promotion time
- Audit - Harbor logs every push/pull with user identity. GHCR provides GitHub audit logs but with less granularity

**Migration path:** Change one variable per service in the Kargo PromotionTask (`configArtifact` URL). The OCI convention, tag scheme, signing, and promotion flow are identical. Registry is a pluggable backend, not an architecture decision.

---

## Cost Optimization

### D-31: Karpenter with mixed instance types and spot strategy

**Context:** EKS compute is the largest cost driver. 1000+ services over-provisioned on fixed instance types waste money.

**Decision:** Karpenter replaces static node groups. Two NodePools:
- General: mixed instance types (m6i, m7i, c6i, r6i - large and xlarge), spot + on-demand, consolidation enabled
- Critical: on-demand only, tainted for payment/auth workloads that cannot tolerate spot interruption

Spot strategy by environment:
- Dev/staging: 100% spot
- Prod non-critical (workers, batch): 70% spot, 30% on-demand
- Prod critical (API, auth, payments): 100% on-demand

**Impact:** Compute cost drops from ~$35,000/month (naive on-demand) to ~$9,100/month (Karpenter + spot + VPA right-sizing). 74% savings.

### D-32: Cilium topology-aware routing (prefer same-AZ)

**Context:** Cross-AZ data transfer costs $0.01/GB in each direction. With 1000 services making internal calls, cross-AZ traffic is a significant hidden cost.

**Decision:** Cilium's topology-aware routing prefers same-AZ backends when available, falling back to cross-AZ when same-AZ is unhealthy.

**Why:** If payments-api in AZ-a calls fraud-engine, and fraud-engine has replicas in all 3 AZs, Cilium routes to the AZ-a replica ($0 intra-AZ) instead of the AZ-b replica ($0.01/GB cross-AZ). At scale, this is 30-50% reduction in cross-AZ data transfer costs.

---

## SFC Compliance

### D-33: Multi-region DR with S3 Cross-Region Replication

**Context:** SFC SARO requires business continuity planning with defined RPO/RTO. As a licensed bank, Addi must demonstrate the ability to continue operations if the primary region fails.

**Decision:** Primary region (us-east-1) with DR region (us-east-2). Self-hosted LGTM stack deployed in both regions. S3 Cross-Region Replication for metrics, logs, and traces. RDS read replica in DR region for Grafana state. Route53 health check triggers DNS failover.

**RPO:** ~15 minutes (S3 CRR replication lag). **RTO:** ~30 minutes (DNS failover + RDS promotion).

### D-34: GuardDuty + AWS Config + Security Hub (defense in depth)

**Context:** SFC CE 007/2018 requires anomaly detection, configuration compliance monitoring, and centralized security findings.

**Decision:** All three enabled at the organization level:
- GuardDuty - runtime threat detection (EKS audit log analysis, S3 protection, malware scanning)
- AWS Config - continuous configuration compliance (detect drift: public S3 buckets, permissive security groups, unencrypted volumes)
- Security Hub - aggregates findings from all security services into a unified compliance score

**Why all three (not just GuardDuty):** Each service detects different threat classes. GuardDuty finds active threats (credential compromise, cryptocurrency mining). AWS Config finds misconfigurations that could become threats (an S3 bucket accidentally made public). Security Hub correlates findings across services and benchmarks against CIS/AWS best practices. For a bank, the SFC expects all three.

### D-35: EKS control plane audit logs enabled

**Context:** SFC CE 007/2018 requires the ability to reconstruct "who did what, when" for all infrastructure interactions.

**Decision:** All five EKS control plane log types enabled: API, audit, authenticator, controllerManager, scheduler. Logs shipped to CloudWatch Logs (encrypted with CMK).

**Why all five:** The `audit` log is the most critical (records every kubectl command and API call with user identity). The `authenticator` log records failed authentication attempts (security events). The `api` log records API server errors (operational debugging). `controllerManager` and `scheduler` help diagnose node scheduling and controller reconciliation issues during incidents.

### D-36: Exit strategy document (CE 020/2022 Article 4)

**Context:** SFC CE 020/2022 requires banks using cloud services to maintain an exit strategy: a documented plan for migrating off the cloud provider.

**Decision:** `docs/sfc/exit-strategy.md` documents: multi-cloud portability (Terraform modules, Kubernetes workloads), data export procedures (S3 sync, pg_dump, OCI registry copy), registry migration path (GHCR -> Harbor -> any OCI registry), and a 90-day exit timeline.

**Why 90 days:** The exit strategy estimates 13 weeks for a full migration (2 weeks planning, 4 weeks data migration, 4 weeks workload migration, 1 week DNS cutover, 2 weeks decommission). This is conservative - parallel-team execution can compress to 60 days. The timeline includes infrastructure provisioning in the target provider, which is the longest-lead item.
