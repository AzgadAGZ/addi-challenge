# Addi Platform - Starlark Standard Library
# spec/lib/observability.star
#
# Observability definitions: SLOs and alert rules.
# SLOs are rendered to Sloth PrometheusServiceLevel CRDs.
# Alerts are rendered to PrometheusRule resources.
#
# Usage:
#   load("@addi//lib:observability.star", "slo", "alert")

# Registry of SLOs and alerts (populated during spec evaluation)
_SLOS = []
_ALERTS = []


def slo(
    service,
    availability=99.9,
    latency_p99_ms=500,
    latency_bucket="0.5",
    team=None,
    tier="standard",
    runbook=None,
):
    """Register a Service Level Objective for a service.

    Generates a Sloth PrometheusServiceLevel CRD that auto-creates:
    - Multi-window burn rate alerts (page + ticket + info)
    - Error budget recording rules
    - Grafana dashboard annotations

    SFC requirement: exposure=cloudfront services must have availability >= 99.9

    Args:
        service: service name matching the component name, e.g. "payments-api"
        availability: availability SLO percentage, e.g. 99.95
        latency_p99_ms: p99 latency SLO in milliseconds, e.g. 500
        latency_bucket: Prometheus histogram bucket for latency
        team: owning team (defaults to domain owner)
        tier: "critical" | "standard" | "best-effort" (affects alert routing)
        runbook: runbook URL for availability alerts

    Returns:
        dict representing the SLO definition (also appended to global registry)

    Example:
        slo(service="payments-api", availability=99.95, latency_p99_ms=500)
    """
    if runbook == None:
        runbook = "https://wiki.addi.com/runbooks/" + service + "-availability"
    if team == None:
        team = "platform"

    definition = {
        "type": "slo",
        "service": service,
        "availability": availability,
        "latency_p99_ms": latency_p99_ms,
        "latency_bucket": latency_bucket,
        "team": team,
        "tier": tier,
        "runbook": runbook,
    }

    _SLOS.append(definition)
    return definition


def alert(
    name,
    expr,
    window="5m",
    severity="warning",
    runbook=None,
    summary=None,
    labels=None,
):
    """Register a Prometheus alert rule.

    Generates a PrometheusRule resource. Every alert MUST have a runbook
    (enforced by platform policy - no runbook = Kyverno blocks it).

    Alert routing by severity:
      critical -> PagerDuty page -> oncall primary
      warning  -> Slack #incidents -> oncall notify
      info     -> Slack #observability -> awareness

    Args:
        name: alert rule name, e.g. "PaymentsWorkerConsumerLag"
        expr: PromQL expression that triggers the alert
        window: evaluation window, e.g. "5m"
        severity: "critical" | "warning" | "info"
        runbook: runbook URL (REQUIRED - platform enforces this)
        summary: human-readable alert summary
        labels: additional label dict

    Returns:
        dict representing the alert definition (also appended to global registry)

    Example:
        alert(
            name = "payments-worker-lag",
            expr = 'nats_consumer_pending{stream="payments-events"} > 10000',
            window = "5m",
            severity = "warning",
            runbook = "https://wiki.addi.com/runbooks/payments-worker-lag",
        )
    """
    if runbook == None:
        runbook = "https://wiki.addi.com/runbooks/" + name
    if summary == None:
        summary = "Alert: " + name
    if labels == None:
        labels = {}

    definition = {
        "type": "alert",
        "name": name,
        "expr": expr,
        "window": window,
        "severity": severity,
        "runbook": runbook,
        "summary": summary,
        "labels": labels,
    }

    _ALERTS.append(definition)
    return definition


def get_slos():
    """Return all registered SLOs (used by generator).

    Returns:
        list of SLO definition dicts
    """
    return _SLOS


def get_alerts():
    """Return all registered alerts (used by generator).

    Returns:
        list of alert definition dicts
    """
    return _ALERTS
