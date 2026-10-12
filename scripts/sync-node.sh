#!/usr/bin/env bash
# ==============================================================================
# Cluster Node Auto-Sync & Self-Reconciliation Worker
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"

check_root

INSTALL_DIR="/opt/cluster"

if [[ ! -d "${INSTALL_DIR}/.git" ]]; then
    info "Cluster repository not found at ${INSTALL_DIR}; checking current directory..."
    if [[ -d "${SCRIPT_DIR}/../.git" ]]; then
        INSTALL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
    else
        fatal "No git repository found for cluster synchronization."
    fi
fi

info "Checking for remote updates at ${INSTALL_DIR}..."

# Fetch remote git status
cd "${INSTALL_DIR}"
git fetch origin main --quiet

LOCAL_COMMIT="$(git rev-parse HEAD)"
REMOTE_COMMIT="$(git rev-parse origin/main)"

if [[ "${LOCAL_COMMIT}" == "${REMOTE_COMMIT}" ]]; then
    info "Node is already up to date with origin/main (${LOCAL_COMMIT:0:7}). No action required."
    exit 0
fi

info "New commit detected: updating from ${LOCAL_COMMIT:0:7} to ${REMOTE_COMMIT:0:7}..."
git pull origin main --quiet

# Load node configuration
load_env "/etc/cluster-node.env"
ROLE="${ROLE:-agent}"

info "Re-applying system hardening and firewall baseline..."
bash "${INSTALL_DIR}/scripts/01-system-prep.sh"
bash "${INSTALL_DIR}/scripts/02-firewall-hardening.sh"

# If server node, reconcile Kubernetes applications and manifests
if [[ "${ROLE}" == "server" ]] && command -v kubectl &>/dev/null; then
    info "Reconciling Kubernetes applications from apps/..."
    if [[ -d "${INSTALL_DIR}/apps" ]]; then
        kubectl apply -k "${INSTALL_DIR}/apps" || warn "Some app manifests failed to reconcile."
    fi

    info "Reconciling Headlamp dashboard..."
    if [[ -f "${INSTALL_DIR}/manifests/dashboard/headlamp.yaml" ]]; then
        kubectl apply -f "${INSTALL_DIR}/manifests/dashboard/headlamp.yaml" || true
    fi
fi

success "Node successfully synchronized and reconciled with commit ${REMOTE_COMMIT:0:7}!"
