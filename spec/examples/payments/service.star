# Addi Platform - Payments Service Spec
# spec/examples/payments/service.star
#
# Multi-component payments service definition.
# This file defines WHAT the service is - components, dependencies,
# secrets references, and observability requirements.
# HOW it is deployed (replicas, resources, rollout strategy) lives in
# deploy/<env>-<region>.star files.
#
# Usage:
#   addi generate spec/examples/payments/service.star
#   addi generate spec/examples/payments/service.star \
#     --overlay deploy/prod-us-east-1.star

# load("@addi//lib:patterns.star", "api", "worker", "cronjob")
# load("@addi//lib:secrets.star", "secrets_manager")
# load("@addi//lib:observability.star", "slo", "alert")

# Inline definitions (in production, these come from the loaded library)
# The generator resolves load() statements before processing.

def _secrets_manager(key, field=None, version="AWSCURRENT"):
    ref = {"provider": "aws-secrets-manager", "key": key, "version": version}
    if field != None:
        ref["field"] = field
    return ref

def _api(name, domain, owner, language, exposure="cloudfront", port=8080,
         protocol="http", health_check="/healthz", data_classification="confidential",
         depends_on=None, secrets=None, env=None, resources=None):
    if depends_on == None:
        depends_on = []
    if secrets == None:
        secrets = []
    if env == None:
        env = {}
    if resources == None:
        resources = {"cpu": "200m", "memory": "256Mi"}
    return {
        "type": "api", "name": name, "domain": domain, "owner": owner,
        "language": language, "exposure": exposure, "port": port,
        "protocol": protocol, "health_check": health_check,
        "data_classification": data_classification, "depends_on": depends_on,
        "secrets": secrets, "env": env, "resources": resources,
    }

def _worker(name, domain, owner, language, command=None, args=None,
            exposure="private", spot=False, depends_on=None, secrets=None,
            env=None, resources=None, data_classification="internal"):
    if command == None:
        command = []
    if args == None:
        args = []
    if depends_on == None:
        depends_on = []
    if secrets == None:
        secrets = []
    if env == None:
        env = {}
    if resources == None:
        resources = {"cpu": "250m", "memory": "256Mi"}
    return {
        "type": "worker", "name": name, "domain": domain, "owner": owner,
        "language": language, "command": command, "args": args,
        "exposure": "private", "spot": spot, "depends_on": depends_on,
        "secrets": secrets, "env": env, "resources": resources,
        "data_classification": data_classification,
    }

def _cronjob(name, domain, owner, language, command=None,
             schedule="0 * * * *", active_deadline_seconds=3600,
             concurrency_policy="Forbid", data_classification="internal",
             depends_on=None, secrets=None, env=None, resources=None):
    if command == None:
        command = []
    if depends_on == None:
        depends_on = []
    if secrets == None:
        secrets = []
    if env == None:
        env = {}
    if resources == None:
        resources = {"cpu": "500m", "memory": "512Mi"}
    return {
        "type": "cronjob", "name": name, "domain": domain, "owner": owner,
        "language": language, "command": command, "schedule": schedule,
        "active_deadline_seconds": active_deadline_seconds,
        "concurrency_policy": concurrency_policy,
        "data_classification": data_classification,
        "depends_on": depends_on, "secrets": secrets, "env": env,
        "resources": resources,
    }

# ---------------------------------------------------------------------------
# Component 1: API - receives HTTP traffic from CloudFront
# ---------------------------------------------------------------------------

payments_api = _api(
    name = "payments-api",
    domain = "financial-services",
    owner = "team-payments",
    language = "go",
    exposure = "cloudfront",
    port = 8080,
    protocol = "http",
    health_check = "/healthz",
    data_classification = "confidential",
    depends_on = [
        ":payments-worker",
        "//financial-services:fraud-engine",
        "//data:postgres",
        "//data:redis",
    ],
    secrets = [
        _secrets_manager("DB_PASSWORD"),
        _secrets_manager("STRIPE_API_KEY"),
        _secrets_manager("FRAUD_ENGINE_TOKEN"),
    ],
    env = {
        "LOG_LEVEL": "info",
        "PAYMENT_GATEWAY": "stripe",
        "OTEL_EXPORTER_OTLP_ENDPOINT": "http://alloy.observability.svc.cluster.local:4317",
    },
    resources = {"cpu": "200m", "memory": "256Mi"},
)

# ---------------------------------------------------------------------------
# Component 2: Worker - processes async payment events from NATS
# ---------------------------------------------------------------------------

payments_worker = _worker(
    name = "payments-worker",
    domain = "financial-services",
    owner = "team-payments",
    language = "go",
    command = ["/app/worker"],
    args = ["--queue", "payments-events", "--concurrency", "10"],
    exposure = "private",
    spot = True,
    depends_on = [
        "//messaging:nats",
        "//data:postgres",
    ],
    secrets = [
        _secrets_manager("DB_PASSWORD"),
        _secrets_manager("NATS_CREDENTIALS"),
    ],
    env = {
        "LOG_LEVEL": "info",
        "OTEL_EXPORTER_OTLP_ENDPOINT": "http://alloy.observability.svc.cluster.local:4317",
    },
    resources = {"cpu": "250m", "memory": "256Mi"},
    data_classification = "confidential",
)

# ---------------------------------------------------------------------------
# Component 3: CronJob - reconciles payments with banking core every 4h
# SFC Decreto 2555: reconciliation is a regulated financial control
# ---------------------------------------------------------------------------

payments_reconciliation = _cronjob(
    name = "payments-reconciliation",
    domain = "financial-services",
    owner = "team-payments",
    language = "go",
    command = ["/app/reconcile", "--full", "--notify-on-discrepancy"],
    schedule = "0 */4 * * *",
    active_deadline_seconds = 3600,
    concurrency_policy = "Forbid",
    data_classification = "restricted",
    depends_on = [
        "//data:postgres",
    ],
    secrets = [
        _secrets_manager("DB_PASSWORD"),
        _secrets_manager("BANKING_CORE_API_KEY"),
    ],
    env = {
        "LOG_LEVEL": "warn",
        "OTEL_EXPORTER_OTLP_ENDPOINT": "http://alloy.observability.svc.cluster.local:4317",
    },
    resources = {"cpu": "500m", "memory": "512Mi"},
)

# ---------------------------------------------------------------------------
# Observability - SLOs and alerts
# SFC CE 007/2018: financial services must have SLOs and incident response
# ---------------------------------------------------------------------------

# Availability SLO: 99.95% (< 4.38 hrs downtime/year)
# Latency SLO: p99 < 500ms
# exposure=cloudfront requires availability >= 99.9 (platform validates)
_payments_api_slo = {
    "type": "slo",
    "service": "payments-api",
    "availability": 99.95,
    "latency_p99_ms": 500,
    "team": "team-payments",
    "tier": "critical",
    "runbook": "https://wiki.addi.com/runbooks/payments-api-availability",
}

# Alert: worker consumer lag indicates processing backlog
_payments_worker_lag_alert = {
    "type": "alert",
    "name": "payments-worker-lag",
    "expr": 'nats_consumer_pending{stream="payments-events"} > 10000',
    "window": "5m",
    "severity": "warning",
    "runbook": "https://wiki.addi.com/runbooks/payments-worker-lag",
    "summary": "Payments worker consumer lag exceeds 10k messages",
}

# Alert: reconciliation job failure (critical - SFC regulated control)
_payments_reconciliation_failure_alert = {
    "type": "alert",
    "name": "payments-reconciliation-failed",
    "expr": 'kube_job_status_failed{job_name=~"payments-reconciliation-.*"} > 0',
    "window": "1m",
    "severity": "critical",
    "runbook": "https://wiki.addi.com/runbooks/payments-reconciliation-failed",
    "summary": "Payments reconciliation job failed - SFC audit control at risk",
}

# Service manifest registry (consumed by generator)
SERVICE_COMPONENTS = [payments_api, payments_worker, payments_reconciliation]
SERVICE_SLOS = [_payments_api_slo]
SERVICE_ALERTS = [_payments_worker_lag_alert, _payments_reconciliation_failure_alert]
