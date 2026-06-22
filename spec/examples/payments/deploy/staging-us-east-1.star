# Addi Platform - Payments Service Deploy Override
# spec/examples/payments/deploy/staging-us-east-1.star
#
# Staging environment overrides for us-east-1.
# - 2 replicas (basic HA, mirrors min-prod)
# - Rolling update (staging validation - not canary)
# - kargo_freight() version (promoted from dev after 4h soak)
# - Mid-range resources (validates resource sizing before prod)

# load("//:service.star", "payments_api", "payments_worker", "payments_reconciliation")
# load("@addi//lib:patterns.star", "deployment", "rolling", "kargo_freight")

payments_api_staging = {
    "component": "payments-api",
    "type": "api",
    "env": "staging",
    "cluster": "addi-staging-ue1",
    "version": {"source": "kargo-freight"},
    "replicas": 2,
    "resources": {"cpu": "200m", "memory": "256Mi"},
    "rollout": {
        "strategy": "rolling",
        "max_surge": "25%",
        "max_unavailable": "0",
    },
    "env_override": {
        "LOG_LEVEL": "info",
    },
}

payments_worker_staging = {
    "component": "payments-worker",
    "type": "worker",
    "env": "staging",
    "cluster": "addi-staging-ue1",
    "version": {"source": "kargo-freight"},
    "replicas": 2,
    "resources": {"cpu": "200m", "memory": "256Mi"},
    "rollout": {
        "strategy": "rolling",
        "max_surge": "25%",
        "max_unavailable": "0",
    },
    "spot": True,
}

payments_reconciliation_staging = {
    "component": "payments-reconciliation",
    "type": "cronjob",
    "env": "staging",
    "cluster": "addi-staging-ue1",
    "version": {"source": "kargo-freight"},
    "resources": {"cpu": "500m", "memory": "512Mi"},
}

DEPLOYMENTS = [payments_api_staging, payments_worker_staging, payments_reconciliation_staging]
