# Addi Platform - Payments Service Deploy Override
# spec/examples/payments/deploy/dev-us-east-1.star
#
# Dev environment overrides for us-east-1.
# - 1 replica (cost savings, no HA required in dev)
# - Rolling update (fast iteration)
# - git_sha() version (built from current commit, auto-promoted by Kargo)
# - Reduced resources (dev cluster is smaller)

# load("//:service.star", "payments_api", "payments_worker", "payments_reconciliation")
# load("@addi//lib:patterns.star", "deployment", "rolling", "git_sha")

# Dev: 1 replica, rolling, git_sha version, minimal resources
payments_api_dev = {
    "component": "payments-api",
    "type": "api",
    "env": "dev",
    "cluster": "addi-dev-ue1",
    "version": {"source": "git-sha"},
    "replicas": 1,
    "resources": {"cpu": "100m", "memory": "128Mi"},
    "rollout": {
        "strategy": "rolling",
        "max_surge": "1",
        "max_unavailable": "0",
    },
    "env_override": {
        "LOG_LEVEL": "debug",
    },
}

payments_worker_dev = {
    "component": "payments-worker",
    "type": "worker",
    "env": "dev",
    "cluster": "addi-dev-ue1",
    "version": {"source": "git-sha"},
    "replicas": 1,
    "resources": {"cpu": "100m", "memory": "128Mi"},
    "rollout": {
        "strategy": "rolling",
        "max_surge": "1",
        "max_unavailable": "0",
    },
    "spot": True,
}

payments_reconciliation_dev = {
    "component": "payments-reconciliation",
    "type": "cronjob",
    "env": "dev",
    "cluster": "addi-dev-ue1",
    "version": {"source": "git-sha"},
    "resources": {"cpu": "200m", "memory": "256Mi"},
}

DEPLOYMENTS = [payments_api_dev, payments_worker_dev, payments_reconciliation_dev]
