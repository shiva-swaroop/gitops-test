#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# 04-deploy-infrastructure.sh
#
# Deploys infrastructure components via Flux reconciliation.
#
# The Flux Kustomization at clusters/virtuozzo/infrastructure-kustomization.yaml
# will automatically reconcile ./infrastructure/ which contains:
#   - MariaDB operator (HelmRepository + HelmRelease)
#
# This script optionally forces immediate reconciliation and monitors progress.
#
# Usage:
#   ./scripts/04-deploy-infrastructure.sh
# ---------------------------------------------------------------------------

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

check_prereqs() {
  if ! command -v flux &>/dev/null; then
    error "flux CLI not found. Run scripts/01-install-tools.sh first."
    exit 1
  fi

  if ! flux check &>/dev/null; then
    error "Flux is not running on the cluster. Run scripts/02-bootstrap-flux.sh first."
    exit 1
  fi
}

deploy_infrastructure() {
  info "Deploying infrastructure components..."

  # Apply the infrastructure Kustomization if it exists locally
  if [[ -f "clusters/virtuozzo/infrastructure-kustomization.yaml" ]]; then
    kubectl apply -f clusters/virtuozzo/infrastructure-kustomization.yaml
    info "Infrastructure Kustomization applied"
  else
    warn "infrastructure-kustomization.yaml not found."
    warn "Ensure it's committed to the repository so Flux picks it up."
  fi

  # Force reconciliation
  info "Triggering immediate reconciliation..."
  flux reconcile kustomization infrastructure -n flux-system 2>/dev/null || true
}

monitor_progress() {
  echo ""
  info "Monitoring MariaDB operator deployment..."
  echo ""

  # Wait for the HelmRelease to be ready
  if flux get helmrelease mariadb-operator -n flux-system &>/dev/null; then
    info "Waiting for MariaDB operator HelmRelease to be ready..."
    flux reconcile helmrelease mariadb-operator -n flux-system 2>/dev/null || true

    # Poll for readiness
    for i in $(seq 1 30); do
      local status
      status=$(flux get helmrelease mariadb-operator -n flux-system --no-header 2>/dev/null | awk '{print $2}' || echo "waiting")
      if [[ "${status}" == "Ready" ]]; then
        info "MariaDB operator is ready!"
        return 0
      fi
      sleep 10
    done

    warn "Timed out waiting for MariaDB operator. Check with:"
    warn "  flux get helmrelease mariadb-operator -n flux-system"
    warn "  kubectl get pods -n mariadb-operator-system"
  else
    warn "HelmRelease mariadb-operator not found yet."
    warn "It may take a moment for Flux to pick up the changes."
  fi
}

verify_installation() {
  echo ""
  info "Verifying infrastructure deployment..."
  echo ""

  echo "--- Flux Kustomizations ---"
  flux get kustomizations -n flux-system 2>/dev/null || echo "(waiting for Flux sync)"

  echo ""
  echo "--- Helm Releases ---"
  flux get helmreleases -n flux-system 2>/dev/null || echo "(none yet)"

  echo ""
  echo "--- MariaDB operator pods ---"
  kubectl get pods -n mariadb-operator-system 2>/dev/null \
    || kubectl get pods --all-namespaces 2>/dev/null \
      | grep -i mariadb \
      || echo "(no mariadb pods yet, operator may still be deploying)"
}

# --- Main ---

echo "=========================================="
echo "  Infrastructure Deployment"
echo "=========================================="
echo ""

check_prereqs
deploy_infrastructure
monitor_progress
verify_installation

echo ""
info "Infrastructure deployment complete!"
echo ""
echo "Next step: ./scripts/05-deploy-app.sh"
