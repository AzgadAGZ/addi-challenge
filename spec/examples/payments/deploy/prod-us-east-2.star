# Addi Platform - Payments Service Deploy Override
# spec/examples/payments/deploy/prod-us-east-2.star
#
# Production DR region (us-east-2) overrides.
# - 2 replicas (reduced capacity - warm DR standby)
# - Rolling update (DR doesn't need canary - same version as prod-ue1)
# - kargo_freight() version (same freight as prod-us-east-1)
# - SARO: RTO < 30m, RPO < 15m - DR cluster stays warm and current
# - Active-active: 20% of traffic routed here normally (Route53 weighted)
#   On failover: Route53 health check flips to 100% in < 60s

# load("//:service.star", "payments_api", "payments_worker", "payments_reconciliation")
# load("@addi//lib:patterns.star", "deployment", "rolling", "kargo_freight")

payments_api_prod_ue2 = {
    "component": "payments-api",
    "type": "api",
    "env": "prod",
    "cluster": "addi-prod-ue2",
    "version": {"source": "kargo-freight"},
    "replicas": 2,
    "resources": {"cpu": "500m", "memory": "512Mi"},
    "rollout": {
        "strategy": "rolling",
        "max_surge": "25%",
        "max_unavailable": "0",
    },
    "env_override": {
        "LOG_LEVEL": "warn",
    },
}

payments_worker_prod_ue2 = {
    "component": "payments-worker",
    "type": "worker",
    "env": "prod",
    "cluster": "addi-prod-ue2",
    "version": {"source": "kargo-freight"},
    "replicas": 1,
    "resources": {"cpu": "250m", "memory": "256Mi"},
    "rollout": {
        "strategy": "rolling",
        "max_surge": "1",
        "max_unavailable": "0",
    },
    "spot": True,
}

payments_reconciliation_prod_ue2 = {
    "component": "payments-reconciliation",
    "type": "cronjob",
    "env": "prod",
    "cluster": "addi-prod-ue2",
    "version": {"source": "kargo-freight"},
    "resources": {"cpu": "1000m", "memory": "1Gi"},
}

DEPLOYMENTS = [payments_api_prod_ue2, payments_worker_prod_ue2, payments_reconciliation_prod_ue2]
