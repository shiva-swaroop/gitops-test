#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# 03-configure-sops.sh
#
# Sets up SOPS with age encryption for Flux-managed secrets.
#
# This script:
#   1. Generates an age key pair (if none exists)
#   2. Creates the sops-age Kubernetes secret in flux-system namespace
#   3. Updates .sops.yaml with the public key
#   4. Encrypts the sample db-secret
#
# Prerequisites:
#   - Tools from 01-install-tools.sh (sops, age, kubectl)
#   - Flux bootstrapped (02-bootstrap-flux.sh)
#   - kubectl configured with cluster access
#
# Usage:
#   ./scripts/03-configure-sops.sh
# ---------------------------------------------------------------------------

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }
step()  { echo -e "\n${CYAN}[STEP]${NC} $*"; }

SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-${HOME}/.config/sops/age/keys.txt}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# --- Step 1: Generate age key ---

step "1/4  Generating age key pair"

mkdir -p "$(dirname "${SOPS_AGE_KEY_FILE}")"

if [[ -f "${SOPS_AGE_KEY_FILE}" ]]; then
  warn "Age key already exists at ${SOPS_AGE_KEY_FILE}"
  warn "Using existing key. To regenerate, delete the file and re-run."
else
  age-keygen -o "${SOPS_AGE_KEY_FILE}"
  info "Age key generated at ${SOPS_AGE_KEY_FILE}"
fi

AGE_PUBLIC_KEY=$(age-keygen -y "${SOPS_AGE_KEY_FILE}")
info "Public key: ${AGE_PUBLIC_KEY}"

# --- Step 2: Create Kubernetes secret ---

step "2/4  Creating sops-age Kubernetes secret in flux-system namespace"

if kubectl get secret sops-age -n flux-system &>/dev/null; then
  warn "Secret sops-age already exists in flux-system namespace"
else
  kubectl create secret generic sops-age \
    --namespace=flux-system \
    --from-file=age.agekey="${SOPS_AGE_KEY_FILE}"
  info "Secret sops-age created in flux-system namespace"
fi

# --- Step 3: Update .sops.yaml root config ---

step "3/4  Updating root .sops.yaml with age public key"

ROOT_SOPS="${REPO_ROOT}/.sops.yaml"

if grep -q "age1\.\.\." "${ROOT_SOPS}" 2>/dev/null; then
  # Replace the placeholder with the actual public key
  if [[ "$(uname)" == "darwin" ]]; then
    sed -i '' "s|age: age1\.\.\.|age: ${AGE_PUBLIC_KEY}|" "${ROOT_SOPS}"
  else
    sed -i "s|age: age1\.\.\.|age: ${AGE_PUBLIC_KEY}|" "${ROOT_SOPS}"
  fi
  info "Updated ${ROOT_SOPS} with age public key"
else
  # .sops.yaml was already configured or had a different placeholder
  warn "Root .sops.yaml does not contain the placeholder 'age: age1...'."
  warn "Please manually set the age key in ${ROOT_SOPS} to:"
  echo "  age: ${AGE_PUBLIC_KEY}"
fi

# Also update the app-level .sops.yaml
APP_SOPS="${REPO_ROOT}/apps/my-app/secrets/.sops.yaml"
if [[ -f "${APP_SOPS}" ]] && grep -q "age: age1\.\.\." "${APP_SOPS}" 2>/dev/null; then
  if [[ "$(uname)" == "darwin" ]]; then
    sed -i '' "s|age: age1\.\.\.|age: ${AGE_PUBLIC_KEY}|" "${APP_SOPS}"
  else
    sed -i "s|age: age1\.\.\.|age: ${AGE_PUBLIC_KEY}|" "${APP_SOPS}"
  fi
  info "Updated ${APP_SOPS} with age public key"
fi

# --- Step 4: Encrypt sample secret ---

step "4/4  Encrypting sample db-secret with SOPS"

SECRETS_DIR="${REPO_ROOT}/apps/my-app/secrets"
PASSWORD_FILE="${SECRETS_DIR}/password.txt"
ENCRYPTED_FILE="${SECRETS_DIR}/db-secret.enc.yaml"

if [[ -f "${PASSWORD_FILE}" ]]; then
  # Create a plain Kubernetes Secret, pipe through sops to encrypt
  kubectl create secret generic db-secret \
    --namespace=my-app \
    --from-file=password="${PASSWORD_FILE}" \
    --dry-run=client \
    -o yaml \
    | sops --encrypt --input-type=yaml --output-type=yaml \
      --encrypted-regex='^(data|stringData)$' \
      - > "${ENCRYPTED_FILE}"

  info "Encrypted secret written to ${ENCRYPTED_FILE}"
  echo ""
  echo "You can now safely commit the encrypted secret:"
  echo "  git add ${ENCRYPTED_FILE}"
  echo ""
  warn "IMPORTANT: Add password.txt to .gitignore to avoid leaking the plaintext:"
  echo "  echo 'apps/my-app/secrets/password.txt' >> .gitignore"
else
  warn "password.txt not found at ${PASSWORD_FILE}. Skipping encryption."
  warn "Create a password.txt file in ${SECRETS_DIR} and re-run this script."
fi

echo ""
info "SOPS configuration complete!"
echo ""
echo "Summary:"
echo "  Private key: ${SOPS_AGE_KEY_FILE}"
echo "  Public key:  ${AGE_PUBLIC_KEY}"
echo "  K8s secret:  sops-age (namespace: flux-system)"
echo "  Root config: ${REPO_ROOT}/.sops.yaml"
echo ""
echo "Next step: ./scripts/04-deploy-infrastructure.sh"
