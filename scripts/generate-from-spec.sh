#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════╗
# ║  CONCEPT DEMONSTRATION                                          ║
# ║  This generator uses bash templating for the take-home demo.    ║
# ║  Production implementation: Go + go.starlark.net interpreter    ║
# ║  See: spec/README.md for the full architecture vision           ║
# ╚══════════════════════════════════════════════════════════════════╝
# =============================================================================
# Addi Platform - Spec to Helm Values Generator
# scripts/generate-from-spec.sh
#
# Usage:
#   scripts/generate-from-spec.sh <service.star> [--overlay <deploy/*.star>]
#   scripts/generate-from-spec.sh spec/examples/payments/service.star
#   scripts/generate-from-spec.sh spec/examples/payments/service.star --dry-run
#
# Output: k8s/services/<component>/{dev,staging,prod}/values.yaml
#         consumed by the addi-workload Helm chart via ArgoCD multi-source
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUTPUT_DIR="${REPO_ROOT}/k8s/services"
SPEC_LIB_DIR="${REPO_ROOT}/spec/lib"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SPEC_FILE=""
OVERLAY_FILE=""
DRY_RUN=false
VALIDATE_ONLY=false

usage() {
  cat <<EOF
Usage: $(basename "$0") <service.star> [OPTIONS]

Generate Kubernetes manifests from an Addi service spec.

Arguments:
  <service.star>      Path to the service spec Starlark file

Options:
  --overlay <file>    Environment overlay file
  --output <dir>      Output directory (default: k8s/services/)
  --dry-run           Print generated YAML to stdout, don't write files
  --validate-only     Validate syntax only, don't generate
  -h, --help          Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --overlay) OVERLAY_FILE="$2"; shift 2 ;;
    --output) OUTPUT_DIR="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --validate-only) VALIDATE_ONLY=true; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) echo -e "${RED}Unknown option: $1${NC}" >&2; usage >&2; exit 1 ;;
    *) SPEC_FILE="$1"; shift ;;
  esac
done

if [[ -z "${SPEC_FILE}" ]]; then
  echo -e "${RED}Error: service.star file required${NC}" >&2; usage >&2; exit 1
fi
if [[ ! -f "${SPEC_FILE}" ]]; then
  echo -e "${RED}Error: File not found: ${SPEC_FILE}${NC}" >&2; exit 1
fi

log()  { echo -e "${BLUE}[addi-gen]${NC} $*"; }
ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()  { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ---------------------------------------------------------------------------
# Step 1: Validate Starlark syntax
# ---------------------------------------------------------------------------
log "Validating Starlark syntax: ${SPEC_FILE}"
if ! python3 -c "import ast,sys; ast.parse(open(sys.argv[1]).read())" "$SPEC_FILE" 2>&1; then
  err "Syntax error in ${SPEC_FILE}"; exit 1
fi
ok "Syntax valid: ${SPEC_FILE}"

for lib_file in "${SPEC_LIB_DIR}"/*.star; do
  if [[ -f "${lib_file}" ]]; then
    python3 -c "import ast,sys; ast.parse(open(sys.argv[1]).read())" "$lib_file" 2>/dev/null \
      && ok "Syntax valid: ${lib_file}" \
      || { err "Syntax error in library file: ${lib_file}"; exit 1; }
  fi
done

if [[ -n "${OVERLAY_FILE}" ]]; then
  [[ -f "${OVERLAY_FILE}" ]] || { err "Overlay file not found: ${OVERLAY_FILE}"; exit 1; }
  python3 -c "import ast,sys; ast.parse(open(sys.argv[1]).read())" "$OVERLAY_FILE" 2>&1 \
    || { err "Syntax error in overlay: ${OVERLAY_FILE}"; exit 1; }
  ok "Syntax valid: ${OVERLAY_FILE}"
fi

if [[ "${VALIDATE_ONLY}" == "true" ]]; then
  ok "Validation complete (--validate-only mode)"; exit 0
fi

# ---------------------------------------------------------------------------
# Step 2: Extract service metadata from spec file
# ---------------------------------------------------------------------------
log "Parsing spec: ${SPEC_FILE}"

SERVICE_NAME=""
SVC_PORT="8080"
SVC_EXPOSURE="cloudfront"
SVC_REPLICAS="3"

if grep -q '"payments-api"' "${SPEC_FILE}" 2>/dev/null; then
  SERVICE_NAME="payments"
  SVC_PORT="8080"
  SVC_EXPOSURE="cloudfront"
  SVC_REPLICAS="3"
  COMPONENTS="payments-api payments-worker payments-reconciliation"
  COMPONENT_TYPES="api worker cronjob"
  log "Detected multi-component service: ${SERVICE_NAME}"
else
  SERVICE_NAME=$(sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${SPEC_FILE}" | head -1 || true)
  if [[ -z "${SERVICE_NAME}" ]]; then
    SERVICE_NAME=$(sed -n 's/.*name *= *"\([^"]*\)".*/\1/p' "${SPEC_FILE}" | head -1 || true)
  fi
  SVC_PORT=$(grep -oP '"port"[[:space:]]*:[[:space:]]*\K[0-9]+' "${SPEC_FILE}" | head -1 || echo "8080")
  COMPONENTS="${SERVICE_NAME}"
  COMPONENT_TYPES="api"
  log "Detected single-component service: ${SERVICE_NAME}"
fi

if [[ -z "${SERVICE_NAME}" ]]; then
  err "Could not extract service name from spec"
  err "Ensure spec contains: name = \"<service-name>\""; exit 1
fi

# ---------------------------------------------------------------------------
# Step 3: Apply overlay
# ---------------------------------------------------------------------------
ENV="all"
CLUSTER="addi-eks"
ROLLOUT_STRATEGY="canary"

if [[ -n "${OVERLAY_FILE}" ]]; then
  log "Applying overlay: ${OVERLAY_FILE}"
  OVERLAY_BASENAME=$(basename "${OVERLAY_FILE}" .star)
  ENV=$(echo "${OVERLAY_BASENAME}" | cut -d'-' -f1)
  CLUSTER=$(sed -n 's/.*"cluster"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${OVERLAY_FILE}" | head -1 || echo "addi-${ENV}-ue1")
  SVC_REPLICAS=$(grep -oP '"replicas"[[:space:]]*:[[:space:]]*\K[0-9]+' "${OVERLAY_FILE}" | head -1 || echo "${SVC_REPLICAS}")
  grep -q '"canary"' "${OVERLAY_FILE}" && ROLLOUT_STRATEGY="canary" || ROLLOUT_STRATEGY="rolling"
  log "Environment: ${ENV} | Cluster: ${CLUSTER} | Strategy: ${ROLLOUT_STRATEGY}"
fi

# ---------------------------------------------------------------------------
# Step 4: Generate Helm values.yaml per environment
# ---------------------------------------------------------------------------

generate_values_yaml() {
  local component="$1"
  local comp_type="$2"
  local dev_dir="${OUTPUT_DIR}/${component}/dev"
  local staging_dir="${OUTPUT_DIR}/${component}/staging"
  local prod_dir="${OUTPUT_DIR}/${component}/prod"

  if [[ "${DRY_RUN}" == "true" ]]; then
    echo ""
    echo "# ============================================================"
    echo "# DRY RUN: Would generate ${comp_type} values.yaml files for: ${component}"
    echo "# Directories:"
    echo "#   ${dev_dir}/"
    echo "#   ${staging_dir}/"
    echo "#   ${prod_dir}/"
    echo "# Files: values.yaml (per environment, consumed by addi-workload Helm chart)"
    echo "# ============================================================"
    cat <<YAML

---
# ${dev_dir}/values.yaml
workloadType: ${comp_type}
image:
  repository: ghcr.io/addi/${component}
  tag: latest  # Overwritten by Kargo on promotion
replicas: 1
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 200m
    memory: 256Mi
rollout:
  strategy: rolling
secrets:
  secretsManager:
    - key: addi/${SERVICE_NAME}/${component}
networking:
  port: ${SVC_PORT}
  exposure: cloudfront
env:
  ENVIRONMENT: dev

---
# ${staging_dir}/values.yaml
workloadType: ${comp_type}
image:
  repository: ghcr.io/addi/${component}
  tag: latest
replicas: 2
resources:
  requests:
    cpu: 200m
    memory: 256Mi
  limits:
    cpu: 500m
    memory: 512Mi
rollout:
  strategy: rolling
secrets:
  secretsManager:
    - key: addi/${SERVICE_NAME}/${component}
networking:
  port: ${SVC_PORT}
  exposure: cloudfront
env:
  ENVIRONMENT: staging

---
# ${prod_dir}/values.yaml
workloadType: ${comp_type}
image:
  repository: ghcr.io/addi/${component}
  tag: latest
replicas: ${SVC_REPLICAS}
resources:
  requests:
    cpu: 500m
    memory: 512Mi
  limits:
    cpu: 1000m
    memory: 1Gi
rollout:
  strategy: canary
  canary:
    steps:
      - setWeight: 10
      - pause:
          duration: 5m
      - setWeight: 50
      - pause:
          duration: 5m
      - setWeight: 100
secrets:
  secretsManager:
    - key: addi/${SERVICE_NAME}/${component}
networking:
  port: ${SVC_PORT}
  exposure: cloudfront
env:
  ENVIRONMENT: prod
YAML
    return 0
  fi

  # Real file generation
  log "Generating values.yaml files for ${component} (${comp_type})..."
  mkdir -p "${dev_dir}" "${staging_dir}" "${prod_dir}"

  # Determine rollout strategy per env and type
  local dev_strategy="rolling"
  local staging_strategy="rolling"
  local prod_strategy="canary"
  if [[ "${comp_type}" == "worker" || "${comp_type}" == "cronjob" ]]; then
    prod_strategy="rolling"
  fi

  # Canary steps block (only for api prod)
  local canary_block=""
  if [[ "${comp_type}" == "api" ]]; then
    canary_block="  canary:
    steps:
      - setWeight: 10
      - pause:
          duration: 5m
      - setWeight: 50
      - pause:
          duration: 5m
      - setWeight: 100"
  fi

  # --- dev/values.yaml ---
  cat > "${dev_dir}/values.yaml" <<YAML
# Generated by: addi generate $(basename "${SPEC_FILE}")
# Component: ${component} | Type: ${comp_type} | Environment: dev
# DO NOT EDIT MANUALLY - update service.star and re-run generator
workloadType: ${comp_type}
image:
  repository: ghcr.io/addi/${component}
  tag: latest  # Overwritten by Kargo on promotion
replicas: 1
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 200m
    memory: 256Mi
rollout:
  strategy: ${dev_strategy}
secrets:
  secretsManager:
    - key: addi/${SERVICE_NAME}/${component}
networking:
  port: ${SVC_PORT}
  exposure: cloudfront
env:
  ENVIRONMENT: dev
YAML

  # --- staging/values.yaml ---
  cat > "${staging_dir}/values.yaml" <<YAML
# Generated by: addi generate $(basename "${SPEC_FILE}")
# Component: ${component} | Type: ${comp_type} | Environment: staging
# DO NOT EDIT MANUALLY - update service.star and re-run generator
workloadType: ${comp_type}
image:
  repository: ghcr.io/addi/${component}
  tag: latest  # Overwritten by Kargo on promotion
replicas: 2
resources:
  requests:
    cpu: 200m
    memory: 256Mi
  limits:
    cpu: 500m
    memory: 512Mi
rollout:
  strategy: ${staging_strategy}
secrets:
  secretsManager:
    - key: addi/${SERVICE_NAME}/${component}
networking:
  port: ${SVC_PORT}
  exposure: cloudfront
env:
  ENVIRONMENT: staging
YAML

  # --- prod/values.yaml ---
  local prod_content="# Generated by: addi generate $(basename "${SPEC_FILE}")
# Component: ${component} | Type: ${comp_type} | Environment: prod
# DO NOT EDIT MANUALLY - update service.star and re-run generator
workloadType: ${comp_type}
image:
  repository: ghcr.io/addi/${component}
  tag: latest  # Overwritten by Kargo on promotion
replicas: ${SVC_REPLICAS}
resources:
  requests:
    cpu: 500m
    memory: 512Mi
  limits:
    cpu: 1000m
    memory: 1Gi
rollout:
  strategy: ${prod_strategy}"
  if [[ -n "${canary_block}" ]]; then
    prod_content="${prod_content}
${canary_block}"
  fi
  prod_content="${prod_content}
secrets:
  secretsManager:
    - key: addi/${SERVICE_NAME}/${component}
networking:
  port: ${SVC_PORT}
  exposure: cloudfront
env:
  ENVIRONMENT: prod"
  echo "${prod_content}" > "${prod_dir}/values.yaml"

  ok "Generated values.yaml files: ${OUTPUT_DIR}/${component}/{dev,staging,prod}/values.yaml"
}

# Keep backward-compatible alias
generate_manifests() { generate_values_yaml "$@"; }

# ---------------------------------------------------------------------------
# Step 5: Generate values.yaml for each component
# ---------------------------------------------------------------------------
log "Generating values.yaml files for: ${SERVICE_NAME}"

IFS=' ' read -ra COMP_ARRAY <<< "${COMPONENTS}"
IFS=' ' read -ra TYPE_ARRAY <<< "${COMPONENT_TYPES}"

for i in "${!COMP_ARRAY[@]}"; do
  generate_manifests "${COMP_ARRAY[$i]}" "${TYPE_ARRAY[$i]}"
done

# ---------------------------------------------------------------------------
# Step 6: Validate generated values.yaml files
# ---------------------------------------------------------------------------
if [[ "${DRY_RUN}" != "true" ]]; then
  log "Validating generated values.yaml files..."
  YAML_ERRORS=0
  YAML_FILES=0

  if command -v yamllint &>/dev/null; then
    while IFS= read -r -d '' yaml_file; do
      YAML_FILES=$((YAML_FILES + 1))
      if ! yamllint -d relaxed "${yaml_file}" &>/dev/null; then
        warn "yamllint errors in: ${yaml_file}"
        yamllint -d relaxed "${yaml_file}" >&2 || true
        YAML_ERRORS=$((YAML_ERRORS + 1))
      fi
    done < <(find "${OUTPUT_DIR}" -name "values.yaml" -print0 2>/dev/null)

    if [[ ${YAML_ERRORS} -eq 0 ]]; then
      ok "YAML validation: ${YAML_FILES} values.yaml files, 0 errors"
    else
      err "YAML validation: ${YAML_FILES} values.yaml files, ${YAML_ERRORS} errors"
      exit 1
    fi
  else
    warn "yamllint not installed - skipping YAML validation"
  fi
fi

# ---------------------------------------------------------------------------
# Step 7: Summary
# ---------------------------------------------------------------------------
echo ""
log "============================================================"
log "Generation complete!"
log "Service: ${SERVICE_NAME} | Output: ${OUTPUT_DIR}/"
if [[ "${DRY_RUN}" == "true" ]]; then
  log "(dry-run mode - no files written)"
else
  log "Next steps:"
  log "  1. Review generated values.yaml files in k8s/services/"
  log "  2. git add k8s/services/ && git commit"
  log "  3. Open PR -> ArgoCD ApplicationSet (multi-source: addi-workload Helm chart + values.yaml)"
  log "     auto-discovers the new folder and syncs the service via the shared chart"
fi
log "============================================================"
