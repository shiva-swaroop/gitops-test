#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# 01-install-tools.sh
#
# Installs the CLI tools required for Flux + SOPS + MariaDB operator workflow.
# Supports Linux (apt) and macOS (brew). Run once per workstation.
#
# Tools installed:
#   - kubectl          Kubernetes CLI
#   - helm             Helm package manager
#   - flux             FluxCD CLI
#   - sops             Secrets encryption/decryption
#   - age              Modern file encryption tool (SOPS backend)
# ---------------------------------------------------------------------------

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }

detect_os() {
  if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    echo "linux"
  elif [[ "$OSTYPE" == "darwin"* ]]; then
    echo "macos"
  else
    echo "unsupported"
  fi
}

install_kubectl() {
  if command -v kubectl &>/dev/null; then
    info "kubectl already installed: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
    return
  fi
  info "Installing kubectl..."
  case "$(detect_os)" in
    linux)
      curl -LO "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
      chmod +x kubectl
      sudo mv kubectl /usr/local/bin/
      ;;
    macos)
      brew install kubectl
      ;;
  esac
  info "kubectl installed: $(kubectl version --client --short)"
}

install_helm() {
  if command -v helm &>/dev/null; then
    info "helm already installed: $(helm version --short)"
    return
  fi
  info "Installing helm..."
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  info "helm installed: $(helm version --short)"
}

install_flux() {
  if command -v flux &>/dev/null; then
    info "flux already installed: $(flux --version 2>/dev/null || flux version)"
    return
  fi
  info "Installing flux CLI..."
  case "$(detect_os)" in
    linux)
      curl -s https://fluxcd.io/install.sh | sudo bash
      ;;
    macos)
      brew install fluxcd/tap/flux
      ;;
  esac
  info "flux installed: $(flux --version 2>/dev/null || flux version)"
}

install_sops() {
  if command -v sops &>/dev/null; then
    info "sops already installed: $(sops --version)"
    return
  fi
  info "Installing sops..."
  local version="v3.9.1"
  case "$(detect_os)" in
    linux)
      curl -LO "https://github.com/getsops/sops/releases/download/${version}/sops-${version}.linux.amd64"
      chmod +x "sops-${version}.linux.amd64"
      sudo mv "sops-${version}.linux.amd64" /usr/local/bin/sops
      ;;
    macos)
      brew install sops
      ;;
  esac
  info "sops installed: $(sops --version)"
}

install_age() {
  if command -v age &>/dev/null; then
    info "age already installed: $(age --version)"
    return
  fi
  info "Installing age..."
  case "$(detect_os)" in
    linux)
      local version="v1.2.0"
      curl -LO "https://github.com/FiloSottile/age/releases/download/${version}/age-${version}-linux-amd64.tar.gz"
      tar -xzf "age-${version}-linux-amd64.tar.gz"
      sudo mv age/age /usr/local/bin/
      sudo mv age/age-keygen /usr/local/bin/
      rm -rf "age-${version}-linux-amd64.tar.gz" age/
      ;;
    macos)
      brew install age
      ;;
  esac
  info "age installed: $(age --version)"
}

# --- Main ---

echo "=========================================="
echo "  Tool Installation Script"
echo "=========================================="
echo ""

install_kubectl
install_helm
install_flux
install_sops
install_age

echo ""
info "All tools installed successfully!"
echo ""
echo "Verify with:"
echo "  kubectl version --client"
echo "  helm version --short"
echo "  flux --version"
echo "  sops --version"
echo "  age --version"
