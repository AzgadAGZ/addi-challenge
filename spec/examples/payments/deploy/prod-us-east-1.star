# Addi Platform - Payments Service Deploy Override
# spec/examples/payments/deploy/prod-us-east-1.star
#
# Production primary (us-east-1) overrides.
# - 3 replicas baseline (min for PDB minAvailable: 2)
# - Canary rollout: 10% -> 5m pause -> 50% -> 5m pause -> 100%
#   Analysis gates: error rate < 5%, p99 latency < 500ms
# - kargo_freight() version (promoted from staging after dual-approval)
# - HPA: 3-10 replicas at 70% CPU
# - Full resources: production-grade CPU/memory
# SFC Decreto 2555: production deploys require dual approval (enforced by Kargo)

# load("//:service.star", "payments_api", "payments_worker", "payments_reconciliation")
# load("@addi//lib:patterns.star",
#      "deployment", "canary", "rolling", "kargo_freight", "hpa")

payments_api_prod = {
    "component": "payments-api",
    "type": "api",
    "env": "prod",
    "cluster": "addi-prod-ue1",
    "version": {"source": "kargo-freight"},
    "replicas": 3,
    "resources": {"cpu": "500m", "memory": "512Mi"},
    "rollout": {
        "strategy": "canary",
        "steps": [10, 50, 100],
        "pause": "5m",
        "analysis": "canary-health",
    },
    "autoscaling": {
        "enabled": True,
        "min_replicas": 3,
        "max_replicas": 10,
        "cpu_target": 70,
    },
    "env_override": {
        "LOG_LEVEL": "warn",
    },
}

payments_worker_prod = {
    "component": "payments-worker",
    "type": "worker",
    "env": "prod",
    "cluster": "addi-prod-ue1",
    "version": {"source": "kargo-freight"},
    "replicas": 2,
    "resources": {"cpu": "250m", "memory": "256Mi"},
    "rollout": {
        "strategy": "rolling",
        "max_surge": "25%",
        "max_unavailable": "0",
    },
    "spot": True,
}

payments_reconciliation_prod = {
    "component": "payments-reconciliation",
    "type": "cronjob",
    "env": "prod",
    "cluster": "addi-prod-ue1",
    "version": {"source": "kargo-freight"},
    "resources": {"cpu": "1000m", "memory": "1Gi"},
}

DEPLOYMENTS = [payments_api_prod, payments_worker_prod, payments_reconciliation_prod]
