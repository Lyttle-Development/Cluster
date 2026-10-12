#!/usr/bin/env bash
# ==============================================================================
# In-Memory NAS / Local Secret App Deployer (Zero Disk Footprint)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"

SOURCE_PATH=""
SERVER_HOST=""
SSH_USER="server"
SSH_PORT="22"

usage() {
    cat <<EOF
Usage: $0 --source <path-to-nas-apps> [options]

Options:
  --source <path>       Local/NAS directory containing app manifests or secrets
  --server <host>       Server IP or hostname (to pipe securely via SSH)
  --user <ssh-user>     SSH user on the server (default: server)
  --port <ssh-port>     SSH port (default: 22)
  --local               Apply directly using local kubectl (requires local kubeconfig)
  -h, --help            Show this help message

How it works:
  This script streams manifests directly from your NAS/encrypted disk into
  the Kubernetes API in-memory (stdin).
  ZERO plain-text files are ever written to the VPS disk.

Examples:
  # Stream manifests from NAS to server over encrypted SSH pipe:
  $0 --source /Volumes/NAS/cluster-apps --server 123.45.67.89

  # Apply directly using local workstation kubectl:
  $0 --source /Volumes/NAS/cluster-apps --local
EOF
    exit 0
}

USE_LOCAL=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --source)
            SOURCE_PATH="$2"
            shift 2
            ;;
        --server)
            SERVER_HOST="$2"
            shift 2
            ;;
        --user)
            SSH_USER="$2"
            shift 2
            ;;
        --port)
            SSH_PORT="$2"
            shift 2
            ;;
        --local)
            USE_LOCAL=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            warn "Unknown argument: $1"
            shift
            ;;
    esac
done

if [[ -z "${SOURCE_PATH}" ]]; then
    fatal "Missing required argument: --source <path-to-nas-apps>."
fi

if [[ ! -e "${SOURCE_PATH}" ]]; then
    fatal "Source path does not exist: ${SOURCE_PATH}"
fi

# ==============================================================================
# Method A: Local kubectl stream
# ==============================================================================
if [[ "${USE_LOCAL}" == "true" ]]; then
    if ! command -v kubectl &>/dev/null; then
        fatal "Local kubectl not found. Run inside 'nix develop' or install kubectl."
    fi

    info "Applying manifests directly from ${SOURCE_PATH} via local kubectl..."
    if [[ -d "${SOURCE_PATH}" ]]; then
        kubectl apply -R -f "${SOURCE_PATH}"
    else
        kubectl apply -f "${SOURCE_PATH}"
    fi
    success "All manifests applied directly into Kubernetes memory!"
    exit 0
fi

# ==============================================================================
# Method B: In-Memory Stream over SSH Pipe (Zero Disk Footprint on VPS)
# ==============================================================================
if [[ -z "${SERVER_HOST}" ]]; then
    echo -e "${YELLOW}Please enter the server IP or hostname to stream manifests to:${NC}"
    read -r -p "Server Host: " SERVER_HOST
fi

if [[ -z "${SERVER_HOST}" ]]; then
    fatal "Server host is required for remote SSH streaming."
fi

info "Connecting to ${SSH_USER}@${SERVER_HOST}:${SSH_PORT}..."

# Test SSH connectivity
if ! ssh -p "${SSH_PORT}" -o BatchMode=yes -o ConnectTimeout=5 "${SSH_USER}@${SERVER_HOST}" "true" 2>/dev/null; then
    fatal "Cannot connect to ${SSH_USER}@${SERVER_HOST}:${SSH_PORT}. Verify SSH key and user."
fi

info "Streaming manifests from ${SOURCE_PATH} directly into remote kubectl stdin..."

if [[ -d "${SOURCE_PATH}" ]]; then
    # Archive directory into tar stream and unpack directly into kubectl apply on server
    tar -czf - -C "${SOURCE_PATH}" . | \
        ssh -p "${SSH_PORT}" "${SSH_USER}@${SERVER_HOST}" \
        'tar -xzf - -O | sudo /usr/local/bin/kubectl apply -f -'
else
    # Stream single file directly
    cat "${SOURCE_PATH}" | \
        ssh -p "${SSH_PORT}" "${SSH_USER}@${SERVER_HOST}" \
        'sudo /usr/local/bin/kubectl apply -f -'
fi

success "=========================================================================="
success " Manifests and secrets successfully deployed to the cluster!"
success " In-memory streaming complete: ZERO secret files were written to VPS disk."
success "=========================================================================="
