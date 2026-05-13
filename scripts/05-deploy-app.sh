#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# 05-deploy-app.sh
#
# Builds and deploys the sample application along with all MariaDB resources.
#
# Steps:
#   1. Optionally build and push the application Docker image
#   2. Ensure the SOPS-encrypted db-secret exists
#   3. Apply the apps Kustomization to trigger Flux reconciliation
#   4. Monitor deployment progress
#
# Prerequisites:
#   - Tools from 01-install-tools.sh installed
#   - Cluster bootstrapped (02-bootstrap-flux.sh)
#   - SOPS configured (03-configure-sops.sh)
#   - Infrastructure deployed (04-deploy-infrastructure.sh)
#
# Usage:
#   ./scripts/05-deploy-app.sh
#   IMAGE_REGISTRY=myregistry.io ./scripts/05-deploy-app.sh
# ---------------------------------------------------------------------------

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE_REGISTRY="${IMAGE_REGISTRY:-}"
IMAGE_NAME="${IMAGE_NAME:-my-app}"
IMAGE_TAG="${IMAGE_TAG:-latest}"

check_prereqs() {
  if ! command -v flux &>/dev/null; then
    error "flux CLI not found. Run scripts/01-install-tools.sh first."
    exit 1
  fi

  if ! flux check &>/dev/null; then
    error "Flux is not running. Run scripts/02-bootstrap-flux.sh first."
    exit 1
  fi

  # Check if MariaDB operator HelmRelease is ready
  local operator_status
  operator_status=$(flux get helmrelease mariadb-operator -n flux-system --no-header 2>/dev/null | awk '{print $2}' || echo "not-found")
  if [[ "${operator_status}" != "Ready" ]]; then
    warn "MariaDB operator is not ready yet. Run scripts/04-deploy-infrastructure.sh first."
    warn "Continuing anyway — the app will deploy once the operator is available."
  fi
}

ensure_encrypted_secret() {
  local encrypted_file="${REPO_ROOT}/apps/my-app/secrets/db-secret.enc.yaml"

  if [[ ! -f "${encrypted_file}" ]]; then
    info "Encrypted db-secret not found. Running SOPS encryption..."

    if [[ ! -f "${REPO_ROOT}/apps/my-app/secrets/password.txt" ]]; then
      warn "password.txt not found. Creating a default one..."
      echo "CHANGE-ME-$(openssl rand -base64 12)" > "${REPO_ROOT}/apps/my-app/secrets/password.txt"
      warn "Default password created. Change it before production!"
    fi

    # Run SOPS encryption
    pushd "${REPO_ROOT}" >/dev/null
    kubectl create secret generic db-secret \
      --namespace=my-app \
      --from-file=password="${REPO_ROOT}/apps/my-app/secrets/password.txt" \
      --dry-run=client \
      -o yaml \
      | sops --encrypt --input-type=yaml --output-type=yaml \
        --encrypted-regex='^(data|stringData)$' \
        - > "${encrypted_file}"
    popd >/dev/null

    info "Encrypted secret created at ${encrypted_file}"
  else
    info "Encrypted secret already exists: ${encrypted_file}"
  fi
}

build_and_push_image() {
  if [[ -z "${IMAGE_REGISTRY}" ]]; then
    warn "IMAGE_REGISTRY not set. Skipping image build."
    warn "The deployment will use the image specified in apps/my-app/deployment.yaml."
    warn "Update the image field manually or set IMAGE_REGISTRY to auto-build."
    return
  fi

  if ! command -v docker &>/dev/null; then
    warn "Docker not found. Skipping image build."
    return
  fi

  local full_image="${IMAGE_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

  info "Building application image: ${full_image}"
  docker build -t "${full_image}" "${REPO_ROOT}/sample-app"

  info "Pushing image to registry..."
  docker push "${full_image}"

  # Update the deployment YAML with the new image
  local deployment_file="${REPO_ROOT}/apps/my-app/deployment.yaml"
  if [[ -f "${deployment_file}" ]]; then
    info "Updating deployment image to ${full_image}..."
    if [[ "$(uname)" == "darwin" ]]; then
      sed -i '' "s|image: my-app:latest|image: ${full_image}|" "${deployment_file}"
    else
      sed -i "s|image: my-app:latest|image: ${full_image}|" "${deployment_file}"
    fi
    info "Deployment updated. Commit and push the change."
  fi
}

deploy_app() {
  info "Deploying application via Flux..."

  # Ensure the target namespace exists
  kubectl create namespace my-app --dry-run=client -o yaml | kubectl apply -f -

  # Apply the encrypted secret directly (Flux will manage it via Kustomization)
  local encrypted_file="${REPO_ROOT}/apps/my-app/secrets/db-secret.enc.yaml"
  if [[ -f "${encrypted_file}" ]]; then
    sops --decrypt "${encrypted_file}" | kubectl apply -f -
    info "Decrypted and applied db-secret"
  fi

  # Apply the apps Kustomization
  if [[ -f "${REPO_ROOT}/clusters/virtuozzo/apps-kustomization.yaml" ]]; then
    kubectl apply -f "${REPO_ROOT}/clusters/virtuozzo/apps-kustomization.yaml"
    info "Apps Kustomization applied"
  fi

  # Force reconciliation
  info "Triggering immediate reconciliation..."
  flux reconcile kustomization apps -n flux-system 2>/dev/null || true
}

monitor_deployment() {
  echo ""
  info "Monitoring application deployment..."
  echo ""

  # Watch pods in the my-app namespace
  for i in $(seq 1 36); do
    echo "--- $(date +%H:%M:%S) ---"
    kubectl get pods -n my-app 2>/dev/null || echo "(namespace not ready yet)"
    echo ""

    local ready
    ready=$(kubectl get pods -n my-app -l app.kubernetes.io/name=my-app \
      -o jsonpath='{.items[*].status.containerStatuses[0].ready}' 2>/dev/null \
      | tr ' ' '\n' | grep -c "true" || echo "0")

    local total
    total=$(kubectl get pods -n my-app -l app.kubernetes.io/name=my-app \
      --no-headers 2>/dev/null | wc -l || echo "0")

    if [[ "${total}" -gt 0 ]] && [[ "${ready}" -eq "${total}" ]]; then
      info "All application pods are ready!"
      return 0
    fi

    sleep 10
  done

  warn "Timed out waiting for application pods."
  warn "Check with: kubectl get pods -n my-app"
  warn "           kubectl describe pods -n my-app"
}

verify() {
  echo ""
  info "Verifying application deployment..."
  echo ""

  echo "--- Flux Kustomizations ---"
  flux get kustomizations -n flux-system 2>/dev/null

  echo ""
  echo "--- Pods in my-app namespace ---"
  kubectl get pods -n my-app -o wide 2>/dev/null || echo "(none)"

  echo ""
  echo "--- Services ---"
  kubectl get svc -n my-app 2>/dev/null || echo "(none)"

  echo ""
  echo "--- MariaDB resources ---"
  kubectl get mariadb -n my-app 2>/dev/null || echo "(none)"
  kubectl get database -n my-app 2>/dev/null || echo "(none)"
  kubectl get user -n my-app 2>/dev/null || echo "(none)"
  kubectl get grant -n my-app 2>/dev/null || echo "(none)"
}

# --- Main ---

echo "=========================================="
echo "  Application Deployment"
echo "=========================================="
echo ""

check_prereqs
ensure_encrypted_secret
build_and_push_image
deploy_app
monitor_deployment
verify

echo ""
info "Application deployment complete!"
echo ""
echo "Useful commands:"
echo "  kubectl get pods -n my-app"
echo "  kubectl logs -n my-app -l app.kubernetes.io/name=my-app"
echo "  kubectl port-forward -n my-app svc/my-app 8080:8080"
echo "  curl http://localhost:8080/health"
echo "  curl http://localhost:8080/api/items"
