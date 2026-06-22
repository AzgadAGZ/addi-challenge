# Addi Platform - Starlark Standard Library
# spec/lib/patterns.star
#
# Constructor functions for service workload types.
# Each returns a dict representing a validated service component.
# Usage:
#   load("@addi//lib:patterns.star", "api", "worker", "cronjob", "job",
#        "canary", "rolling", "blue_green", "hpa", "deployment",
#        "kargo_freight", "git_sha", "static_version")

# ---------------------------------------------------------------------------
# Rollout Strategy Helpers
# ---------------------------------------------------------------------------

def canary(steps=None, pause="5m", analysis="canary-health"):
    """Canary rollout strategy.

    Args:
        steps: list of integer percentages, e.g. [10, 50, 100]
        pause: pause duration between steps, e.g. "5m"
        analysis: AnalysisTemplate name for canary gates

    Returns:
        dict with rollout strategy configuration
    """
    if steps == None:
        steps = [10, 50, 100]
    return {
        "strategy": "canary",
        "steps": steps,
        "pause": pause,
        "analysis": analysis,
    }


def rolling(max_surge="25%", max_unavailable="0"):
    """Rolling update strategy.

    Args:
        max_surge: max pods above desired during rollout
        max_unavailable: max pods unavailable during rollout

    Returns:
        dict with rollout strategy configuration
    """
    return {
        "strategy": "rolling",
        "max_surge": max_surge,
        "max_unavailable": max_unavailable,
    }


def blue_green(auto_promotion_seconds=300, preview_service=None):
    """Blue-green rollout strategy.

    Args:
        auto_promotion_seconds: seconds before auto-promoting (0 = manual)
        preview_service: name of the preview service (defaults to <name>-preview)

    Returns:
        dict with rollout strategy configuration
    """
    return {
        "strategy": "blue-green",
        "auto_promotion_seconds": auto_promotion_seconds,
        "preview_service": preview_service,
        "analysis": "canary-health",
    }


# ---------------------------------------------------------------------------
# Autoscaling Helpers
# ---------------------------------------------------------------------------

def hpa(min_replicas=2, max_replicas=10, cpu_target=70, memory_target=None):
    """Horizontal Pod Autoscaler configuration.

    Args:
        min_replicas: minimum pod count
        max_replicas: maximum pod count
        cpu_target: CPU utilization target percentage
        memory_target: memory utilization target percentage (optional)

    Returns:
        dict with HPA configuration
    """
    config = {
        "enabled": True,
        "min_replicas": min_replicas,
        "max_replicas": max_replicas,
        "cpu_target": cpu_target,
    }
    if memory_target != None:
        config["memory_target"] = memory_target
    return config


# ---------------------------------------------------------------------------
# Version Helpers
# ---------------------------------------------------------------------------

def kargo_freight():
    """Version sourced from Kargo freight promotion pipeline.

    Returns:
        dict indicating Kargo-managed version
    """
    return {"source": "kargo-freight"}


def git_sha():
    """Version sourced from current Git commit SHA (dev/CI usage).

    Returns:
        dict indicating git-sha version
    """
    return {"source": "git-sha"}


def static_version(v):
    """Pinned static version string.

    Args:
        v: version string, e.g. "1.2.3" or "sha-abc1234"

    Returns:
        dict with pinned version
    """
    return {"source": "static", "value": v}


# ---------------------------------------------------------------------------
# Workload Constructor: api()
# ---------------------------------------------------------------------------

def api(
    name,
    domain,
    owner,
    language,
    exposure="cloudfront",
    port=8080,
    protocol="http",
    health_check="/healthz",
    data_classification="confidential",
    depends_on=None,
    secrets=None,
    env=None,
    resources=None,
):
    """Define an HTTP/gRPC API service component.

    Exposure options: cloudfront | private | public
    Traffic is routed through CloudFront -> WAF -> Private ALB -> EKS pod.
    Generated output: Rollout (canary/blue-green), Service, CiliumNetworkPolicy,
    ExternalSecret, Sloth SLO, HPA, PDB.

    Args:
        name: service name, e.g. "payments-api"
        domain: bounded context domain, e.g. "financial-services"
        owner: owning team, e.g. "team-payments"
        language: runtime language, e.g. "go", "python", "node"
        exposure: traffic exposure ("cloudfront", "private", "public")
        port: container port
        protocol: "http" or "grpc"
        health_check: health check path
        data_classification: "public" | "internal" | "confidential" | "restricted"
        depends_on: list of dependency refs, e.g. ["//data:postgres"]
        secrets: list of secret dicts from secrets.star
        env: dict of static environment variables
        resources: dict with cpu/memory requests, e.g. {"cpu": "200m", "memory": "256Mi"}

    Returns:
        dict representing the api component spec
    """
    if depends_on == None:
        depends_on = []
    if secrets == None:
        secrets = []
    if env == None:
        env = {}
    if resources == None:
        resources = {"cpu": "200m", "memory": "256Mi"}

    return {
        "type": "api",
        "name": name,
        "domain": domain,
        "owner": owner,
        "language": language,
        "exposure": exposure,
        "port": port,
        "protocol": protocol,
        "health_check": health_check,
        "data_classification": data_classification,
        "depends_on": depends_on,
        "secrets": secrets,
        "env": env,
        "resources": resources,
    }


# ---------------------------------------------------------------------------
# Workload Constructor: worker()
# ---------------------------------------------------------------------------

def worker(
    name,
    domain,
    owner,
    language,
    command=None,
    args=None,
    exposure="private",
    spot=False,
    depends_on=None,
    secrets=None,
    env=None,
    resources=None,
    data_classification="internal",
):
    """Define an async event worker component.

    Workers process async events (queues, streams). Deployed as Deployment
    (not Rollout - no traffic split needed). Always private.
    Generated output: Deployment, Service (headless), CiliumNetworkPolicy,
    ExternalSecret.

    Args:
        name: service name, e.g. "payments-worker"
        domain: bounded context domain
        owner: owning team
        language: runtime language
        command: container command list
        args: container args list
        exposure: must be "private" for workers
        spot: whether to use Spot instances (cost optimization)
        depends_on: list of dependency refs
        secrets: list of secret dicts from secrets.star
        env: dict of static environment variables
        resources: dict with cpu/memory requests

    Returns:
        dict representing the worker component spec
    """
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
        "type": "worker",
        "name": name,
        "domain": domain,
        "owner": owner,
        "language": language,
        "command": command,
        "args": args,
        "exposure": "private",
        "spot": spot,
        "depends_on": depends_on,
        "secrets": secrets,
        "env": env,
        "resources": resources,
        "data_classification": data_classification,
    }


# ---------------------------------------------------------------------------
# Workload Constructor: cronjob()
# ---------------------------------------------------------------------------

def cronjob(
    name,
    domain,
    owner,
    language,
    command=None,
    schedule="0 * * * *",
    active_deadline_seconds=3600,
    concurrency_policy="Forbid",
    data_classification="internal",
    depends_on=None,
    secrets=None,
    env=None,
    resources=None,
):
    """Define a scheduled CronJob component.

    CronJobs run on a schedule (e.g. reconciliation, batch processing).
    Generated output: CronJob, CiliumNetworkPolicy, ExternalSecret.

    Args:
        name: job name, e.g. "payments-reconciliation"
        domain: bounded context domain
        owner: owning team
        language: runtime language
        command: container command list
        schedule: cron schedule string, e.g. "0 */4 * * *"
        active_deadline_seconds: job timeout in seconds
        concurrency_policy: "Forbid" | "Allow" | "Replace"
        data_classification: "public" | "internal" | "confidential" | "restricted"
        depends_on: list of dependency refs
        secrets: list of secret dicts from secrets.star
        env: dict of static environment variables
        resources: dict with cpu/memory requests

    Returns:
        dict representing the cronjob component spec
    """
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
        "type": "cronjob",
        "name": name,
        "domain": domain,
        "owner": owner,
        "language": language,
        "command": command,
        "schedule": schedule,
        "active_deadline_seconds": active_deadline_seconds,
        "concurrency_policy": concurrency_policy,
        "data_classification": data_classification,
        "depends_on": depends_on,
        "secrets": secrets,
        "env": env,
        "resources": resources,
    }


# ---------------------------------------------------------------------------
# Workload Constructor: job()
# ---------------------------------------------------------------------------

def job(
    name,
    domain,
    owner,
    language,
    command=None,
    active_deadline_seconds=3600,
    data_classification="internal",
    depends_on=None,
    secrets=None,
    env=None,
    resources=None,
):
    """Define a one-off Job component.

    One-off jobs run once (e.g. DB migrations, data backfill).
    Generated output: Job, CiliumNetworkPolicy, ExternalSecret.

    Args:
        name: job name, e.g. "db-migration"
        domain: bounded context domain
        owner: owning team
        language: runtime language
        command: container command list
        active_deadline_seconds: job timeout in seconds
        data_classification: data classification level
        depends_on: list of dependency refs
        secrets: list of secret dicts
        env: dict of environment variables
        resources: dict with cpu/memory requests

    Returns:
        dict representing the job component spec
    """
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
        "type": "job",
        "name": name,
        "domain": domain,
        "owner": owner,
        "language": language,
        "command": command,
        "active_deadline_seconds": active_deadline_seconds,
        "data_classification": data_classification,
        "depends_on": depends_on,
        "secrets": secrets,
        "env": env,
        "resources": resources,
    }


# ---------------------------------------------------------------------------
# Golden Path Presets
# ---------------------------------------------------------------------------

def standard_api(name, domain, owner, language="go", port=8080):
    """Golden-path preset for a standard HTTP API.

    Opinionated defaults: cloudfront exposure, confidential data,
    /healthz health check, HTTP protocol.

    Args:
        name: service name
        domain: bounded context
        owner: owning team
        language: runtime language (default: "go")
        port: container port (default: 8080)

    Returns:
        dict representing a standard api component
    """
    return api(
        name=name,
        domain=domain,
        owner=owner,
        language=language,
        exposure="cloudfront",
        port=port,
        protocol="http",
        health_check="/healthz",
        data_classification="confidential",
    )


def standard_worker(name, domain, owner, language="go"):
    """Golden-path preset for a standard async event worker.

    Opinionated defaults: private exposure, spot instances enabled,
    internal data classification.

    Args:
        name: service name
        domain: bounded context
        owner: owning team
        language: runtime language (default: "go")

    Returns:
        dict representing a standard worker component
    """
    return worker(
        name=name,
        domain=domain,
        owner=owner,
        language=language,
        exposure="private",
        spot=True,
        data_classification="internal",
    )


# ---------------------------------------------------------------------------
# Deployment Override
# ---------------------------------------------------------------------------

def deployment(
    component,
    env,
    cluster,
    version=None,
    replicas=None,
    resources=None,
    rollout=None,
    autoscaling=None,
    env_override=None,
    spot=None,
):
    """Declare a per-environment deployment override for a component.

    Called in deploy/<env>-<region>.star files to override defaults
    defined in service.star.

    Args:
        component: the component dict (from api(), worker(), etc.)
        env: environment name, e.g. "prod", "dev", "staging"
        cluster: cluster name, e.g. "addi-prod-ue1"
        version: version dict from kargo_freight(), git_sha(), or static_version()
        replicas: desired replica count
        resources: resource overrides dict
        rollout: rollout strategy dict from canary(), rolling(), blue_green()
        autoscaling: HPA config dict from hpa()
        env_override: dict of environment variable overrides
        spot: override spot instance preference

    Returns:
        dict representing a deployment override
    """
    if version == None:
        version = kargo_freight()
    if env_override == None:
        env_override = {}

    override = {
        "component": component["name"],
        "type": component["type"],
        "env": env,
        "cluster": cluster,
        "version": version,
    }

    if replicas != None:
        override["replicas"] = replicas
    if resources != None:
        override["resources"] = resources
    if rollout != None:
        override["rollout"] = rollout
    if autoscaling != None:
        override["autoscaling"] = autoscaling
    if env_override:
        override["env_override"] = env_override
    if spot != None:
        override["spot"] = spot

    return override
