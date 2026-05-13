#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# 02-bootstrap-flux.sh
#
# Bootstraps FluxCD on the Virtuozzo Kubernetes cluster.
#
# Prerequisites:
#   - kubectl configured with cluster access
#   - A GitHub/GitLab personal access token exported as GIT_TOKEN
#   - Tools from 01-install-tools.sh installed
#
# Usage:
#   export GIT_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx
#   ./scripts/02-bootstrap-flux.sh
#
# After bootstrap, Flux creates:
#   - clusters/virtuozzo/flux-system/  (local directory via --path)
#   - All Flux controllers in the cluster
#   - A GitRepository source pointing to this repo
# ---------------------------------------------------------------------------

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

# --- Configuration ---
# Change these to match your repository
GIT_REPO="gitops-test"
GIT_OWNER="${GIT_OWNER:-shiva-swaroop}"
GIT_BRANCH="${GIT_BRANCH:-main}"
CLUSTER_PATH="clusters/virtuozzo"

# --- Preflight checks ---

check_prereqs() {
  local missing=0

  if ! command -v flux &>/dev/null; then
    error "flux CLI not found. Run scripts/01-install-tools.sh first."
    missing=1
  fi

  if ! command -v kubectl &>/dev/null; then
    error "kubectl not found. Run scripts/01-install-tools.sh first."
    missing=1
  fi

  if ! kubectl cluster-info &>/dev/null; then
    error "Cannot reach Kubernetes cluster. Check your kubeconfig."
    missing=1
  fi

  if [[ -z "${GIT_TOKEN:-}" ]]; then
    error "GIT_TOKEN is not set."
    echo "  Export your GitHub/GitLab personal access token:"
    echo "  export GIT_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx"
    missing=1
  fi

  if [[ "$missing" -ne 0 ]]; then
    exit 1
  fi
}

# --- Bootstrap ---

bootstrap_flux() {
  info "Preparing cluster path: ${CLUSTER_PATH}"
  mkdir -p "${CLUSTER_PATH}"

  info "Bootstrapping Flux on Virtuozzo cluster..."
  info "Repository: ${GIT_OWNER}/${GIT_REPO} branch: ${GIT_BRANCH}"

  flux bootstrap git \
    --url="https://github.com/${GIT_OWNER}/${GIT_REPO}" \
    --branch="${GIT_BRANCH}" \
    --path="${CLUSTER_PATH}" \
    --token-auth \
    --password="${GIT_TOKEN}" \
    --components-extra=image-reflector-controller,image-automation-controller
}

post_bootstrap() {
  info "Waiting for Flux controllers to be ready..."
  flux check --pre 2>/dev/null || true

  echo ""
  info "Flux bootstrap complete!"
  echo ""
  echo "What was created:"
  echo "  - ${CLUSTER_PATH}/flux-system/  (Flux manifests)"
  echo "  - Flux controllers running in cluster"
  echo ""
  echo "Next steps:"
  echo "  1. Commit and push the generated flux-system/ directory:"
  echo "     git add ${CLUSTER_PATH}/flux-system/"
  echo "     git commit -m \"Add flux-system manifests\""
  echo "     git push"
  echo ""
  echo "  2. Run scripts/03-configure-sops.sh to set up SOPS"
  echo "  3. Run scripts/04-deploy-infrastructure.sh"
  echo "  4. Run scripts/05-deploy-app.sh"
}

# --- Main ---

echo "=========================================="
echo "  Flux Bootstrap Script"
echo "=========================================="
echo ""

check_prereqs
bootstrap_flux
post_bootstrap
