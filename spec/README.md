# Addi Platform - Spec Layer

The spec layer is the **AI-native interface** to the Addi platform. Instead of writing YAML directly, service teams write a `service.star` file in the Starlark DSL, run the generator, and get production-ready Kubernetes manifests, SLOs, alerts, and Kargo pipelines.

## Why Starlark?

| Problem with YAML | Starlark Solution |
|---|---|
| No functions - copy-paste proliferates | Constructor functions: `api()`, `worker()`, `cronjob()` |
| No type safety | JSON Schema validates before generation |
| No DRY - 200-line rollout duplicated per service | Library patterns in `spec/lib/` |
| Indentation errors at 2am | Valid Python syntax, ast.parse catches it |
| AI agents produce hallucinated YAML | Agents write Starlark -> schema validates -> generator produces correct YAML |

## Directory Structure

```
spec/
├── lib/                        # Platform-team owned (CODEOWNERS: @addi/platform-engineering)
│   ├── patterns.star           # api(), worker(), cronjob(), job(), hpa(), canary(), rolling()
│   ├── secrets.star            # secrets_manager(), ssm()
│   └── observability.star      # slo(), alert()
├── schemas/
│   └── service-spec.schema.json  # JSON Schema for AI agent validation
├── examples/
│   └── payments/               # Full multi-component example
│       ├── service.star        # Component definitions
│       └── deploy/             # Per-environment overrides
│           ├── dev-us-east-1.star
│           ├── staging-us-east-1.star
│           ├── prod-us-east-1.star
│           └── prod-us-east-2.star
└── README.md                   # This file
```

## For Developers - Writing Your First Service

### Step 1: Create `service.star`

```python
load("@addi//lib:patterns.star", "api", "worker")
load("@addi//lib:secrets.star", "secrets_manager")
load("@addi//lib:observability.star", "slo", "alert")

# Define your API component
my_api = api(
    name = "my-service",
    domain = "my-domain",
    owner = "team-my-team",
    language = "go",
    exposure = "cloudfront",
    port = 8080,
    health_check = "/healthz",
    data_classification = "confidential",
    depends_on = [
        "//data:postgres",
        "//data:redis",
    ],
    secrets = [
        secrets_manager("DB_PASSWORD"),
    ],
    env = {
        "LOG_LEVEL": "info",
    },
)

# Define your SLO
slo(service = "my-service", availability = 99.9, latency_p99_ms = 500)
```

### Step 2: Create per-environment overrides

```python
# deploy/prod-us-east-1.star
load("//:service.star", "my_api")
load("@addi//lib:patterns.star", "deployment", "canary", "kargo_freight", "hpa")

deployment(my_api, "prod",
    cluster = "addi-prod-ue1",
    version = kargo_freight(),
    replicas = 3,
    resources = {"cpu": "500m", "memory": "512Mi"},
    rollout = canary(steps = [10, 50, 100], pause = "5m"),
    autoscaling = hpa(min_replicas = 3, max_replicas = 10, cpu_target = 70),
)
```

### Step 3: Generate manifests

```bash
# Generate K8s manifests from spec
scripts/generate-from-spec.sh spec/examples/my-service/service.star

# With environment overlay
scripts/generate-from-spec.sh spec/examples/my-service/service.star \
  --overlay spec/examples/my-service/deploy/prod-us-east-1.star

# Validate Starlark syntax before running
python3 -c "import ast; ast.parse(open('service.star').read())"
```

### Step 4: PR -> ArgoCD syncs automatically

```
service.star (write) ->
  generate-from-spec.sh ->
    k8s/services/my-service/{dev,staging,prod}/values.yaml ->
      git commit + PR ->
        ArgoCD ApplicationSet (auto-discovers k8s/services/*/dev|staging|prod,
          multi-source: addi-workload chart + values.yaml) ->
          ArgoCD syncs -> service is live
```

No manual kubectl. No kubectl apply. Git is the source of truth.

## Workload Types

| Constructor | Use Case | Generated Resources | Default Rollout |
|---|---|---|---|
| `api()` | HTTP/gRPC services receiving traffic | Rollout, 2x Services, NetworkPolicy, ExternalSecret, SLO, HPA, PDB | canary |
| `worker()` | Async event processors | Deployment, headless Service, NetworkPolicy, ExternalSecret | rolling |
| `cronjob()` | Scheduled batch jobs | CronJob, NetworkPolicy, ExternalSecret | N/A |
| `job()` | One-off tasks (DB migrations) | Job, NetworkPolicy, ExternalSecret | N/A |

## Environment-Aware Validation Rules

| Rule | Dev | Staging | Prod |
|---|---|---|---|
| Trusted registry required | warn | warn | **error** (block) |
| Min replicas for api | 1 | 2 | 2 (enforced) |
| Immutable image tags | skip | warn | **error** |
| Plaintext secrets in env | **error** | **error** | **error** |
| Canary steps end at 100% | skip | warn | **error** |
| `exposure=cloudfront` requires SLO >= 99.9 | skip | warn | **error** |
| `data_classification=restricted` requires encryption | **error** | **error** | **error** |

## Rollout Strategy Helpers

```python
# Canary (default for api())
canary(
    steps = [10, 50, 100],   # traffic weights
    pause = "5m",            # pause between steps
    analysis = "canary-health",  # AnalysisTemplate
)

# Rolling (default for worker())
rolling(max_surge = "25%", max_unavailable = "0")

# Blue-Green (payment processing, auth - instant rollback)
blue_green(auto_promotion_seconds = 300)
```

## HPA Configuration

```python
# Auto-scale based on CPU
hpa(
    min_replicas = 3,
    max_replicas = 10,
    cpu_target = 70,   # scale up when CPU > 70%
)
```

## Secret References (Never Store Values)

```python
load("@addi//lib:secrets.star", "secrets_manager", "ssm")

secrets = [
    # AWS Secrets Manager
    secrets_manager("DB_PASSWORD"),
    secrets_manager("payments/certs", field = "tls.crt"),

    # SSM Parameter Store
    ssm("/addi/payments/prod/feature-flags"),
]
```

Secrets are pulled at runtime via ESO + Pod Identity. No long-lived AWS credentials in cluster.

## SLO and Alert Definitions

```python
load("@addi//lib:observability.star", "slo", "alert")

# Availability + latency SLO
slo(
    service = "payments-api",
    availability = 99.95,      # < 4.38 hrs downtime/year
    latency_p99_ms = 500,
    tier = "critical",
    runbook = "https://wiki.addi.com/runbooks/payments-api-availability",
)

# Custom alert (must have runbook - Kyverno enforces this)
alert(
    name = "payments-worker-lag",
    expr = 'nats_consumer_pending{stream="payments-events"} > 10000',
    window = "5m",
    severity = "warning",
    runbook = "https://wiki.addi.com/runbooks/payments-worker-lag",
)
```

## For AI Agents - Using the JSON Schema

The `spec/schemas/service-spec.schema.json` is the machine-readable contract for AI agents.

### Workflow for AI-assisted service onboarding

The `CLAUDE.md` at the repo root instructs Claude Code how to onboard a new service:

1. **Read the schema**: `spec/schemas/service-spec.schema.json` - understand valid fields
2. **Read an example**: `spec/examples/payments/service.star` - see how fields are used
3. **Read the library**: `spec/lib/patterns.star` - understand constructor functions
4. **Generate a spec**: Write `service.star` for the new service
5. **Validate syntax**: `python3 -c "import ast; ast.parse(open('service.star').read())"`
6. **Validate schema**: Validate the spec dict against `service-spec.schema.json`
7. **Run generator**: `scripts/generate-from-spec.sh service.star`
8. **Open PR**: `gh pr create` - ArgoCD syncs automatically

### Schema-validated fields (key constraints)

- `name`: `^[a-z][a-z0-9-]{1,62}$` - lowercase, hyphens, K8s-compatible
- `owner`: `^team-[a-z][a-z0-9-]+$` - must match CODEOWNERS team
- `exposure=cloudfront` + `availability < 99.9` -> validation error in staging/prod
- `data_classification=restricted` -> platform enforces encryption via Kyverno
- Secrets: only `provider` + `key` references, never values

## Data Classification (SFC Circular Externa 020/2022)

| Level | Examples | Requirements |
|---|---|---|
| `public` | Marketing content, public docs | Standard controls |
| `internal` | Internal tools, metrics | TLS in transit |
| `confidential` | PII, financial data | mTLS + encryption at rest |
| `restricted` | Banking core API keys, card data | mTLS + KMS + additional audit logging + approval to modify |

## Full Payments Example

See `spec/examples/payments/` for a complete 3-component example:
- `payments-api` - HTTP API with canary rollout, 3 secrets, SLO 99.95%
- `payments-worker` - Async NATS worker, spot instances, 2 secrets
- `payments-reconciliation` - CronJob every 4hrs, data_classification=restricted

The generated values.yaml files are in `k8s/services/payments-*/{dev,staging,prod}/values.yaml`.

## Config Artifact Flow

1. Developer writes `service.star` + `deploy/<env>-<region>.star`
2. Generator (`scripts/generate-from-spec.sh`) produces `values.yaml` files directly into `k8s/services/<component>/{dev,staging,prod}/`; ArgoCD uses the `addi-workload` Helm chart multi-source - no separate CI compile step is needed for the GitOps flow
3. Each compiled values.yaml is also pushed as an OCI artifact for Kargo: `oras push ghcr.io/addi/addi-configs:{svc}-{version}-{region}`
4. Kargo Warehouse watches for new image tags
5. During promotion, Kargo:
   a. Downloads the config artifact matching the promoted version + target environment
   b. Copies it into the gitops repo overlay
   c. Sets image.tag from the Freight
   d. Commits atomically (config + image in one commit)
   e. Pushes -> ArgoCD auto-syncs
