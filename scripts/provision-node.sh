#!/usr/bin/env bash
# ==============================================================================
# Remote Node Provisioner (Runs on Developer PC -> Orchestrates Target VPS)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"

TARGET_HOST=""
ROLE=""
SSH_USER=""
SSH_PORT="22"
ADMIN_USER="server"
DATASTORE_ENDPOINT=""
SERVER_URL=""
TOKEN=""
CF_TOKEN=""
DO_REBOOT=false

usage() {
    cat <<EOF
Usage: $0 --target <vps-ip> [options]

Run this script on your Developer PC. It securely connects to the target VPS,
orchestrates hardening, user migration, reboots, and cluster setup, then downloads
your kubeconfig and dashboard token locally.

Options:
  --target <host/ip>           Target VPS IP or hostname (required)
  --role [server|agent]        Cluster role (server or agent)
  --ssh-user <user>            Initial SSH user (auto-detects: server, debian, root)
  --ssh-port <port>            SSH port (default: 22)
  --admin-user <user>          New admin user to configure (default: server)
  --datastore-endpoint <url>   PostgreSQL connection string (for server)
  --server-url <url>           Control-plane URL e.g. https://1.2.3.4:6443 (for agent)
  --token <token>              Cluster join token (for agent or server)
  --cf-token <token>           Cloudflare Tunnel token (for server)
  --reboot                     Perform a clean reboot after OS updates and reconnect
  -h, --help                   Show this help message

Examples:
  # Provision Server VPS remotely from your Mac:
  $0 --target 51.68.123.45 --role server \\
     --datastore-endpoint "postgres://k3s_user:pass@host:25060/db?sslmode=require" \\
     --cf-token "YOUR_CLOUDFLARE_TOKEN" --reboot

  # Provision Worker VPS remotely from your Mac:
  $0 --target 51.68.123.46 --role agent \\
     --server-url "https://51.68.123.45:6443" --token "CLUSTER_TOKEN"
EOF
    exit 0
}

# Parse CLI arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --target)
            TARGET_HOST="$2"
            shift 2
            ;;
        --role)
            ROLE="$2"
            shift 2
            ;;
        --ssh-user)
            SSH_USER="$2"
            shift 2
            ;;
        --ssh-port)
            SSH_PORT="$2"
            shift 2
            ;;
        --admin-user)
            ADMIN_USER="$2"
            shift 2
            ;;
        --datastore-endpoint)
            DATASTORE_ENDPOINT="$2"
            shift 2
            ;;
        --server-url)
            SERVER_URL="$2"
            shift 2
            ;;
        --token)
            TOKEN="$2"
            shift 2
            ;;
        --cf-token)
            CF_TOKEN="$2"
            shift 2
            ;;
        --reboot)
            DO_REBOOT=true
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

if [[ -z "${TARGET_HOST}" ]]; then
    echo -e "${CYAN}=== Remote Node Provisioner ===${NC}"
    read -r -p "Target VPS IP or hostname: " TARGET_HOST
fi

if [[ -z "${TARGET_HOST}" ]]; then
    fatal "Target host is required."
fi

# 1. Detect active SSH user on target
detect_ssh_user() {
    local host="$1"
    local port="$2"
    local candidates=("${SSH_USER}" "server" "debian" "root")

    for user in "${candidates[@]}"; do
        [[ -z "${user}" ]] && continue
        info "Checking SSH connection as '${user}' on ${host}:${port}..."
        if ssh -p "${port}" -o BatchMode=yes -o ConnectTimeout=4 -o StrictHostKeyChecking=accept-new "${user}@${host}" "true" 2>/dev/null; then
            echo "${user}"
            return 0
        fi
    done
    return 1
}

info "Discovering initial SSH access to ${TARGET_HOST}..."
CURRENT_SSH_USER="$(detect_ssh_user "${TARGET_HOST}" "${SSH_PORT}" || true)"

if [[ -z "${CURRENT_SSH_USER}" ]]; then
    fatal "Could not connect to ${TARGET_HOST}:${SSH_PORT} using SSH keys for users [${SSH_USER:-server, debian, root}]. Check your SSH key agent."
fi

success "Connected to ${TARGET_HOST} as initial user: '${CURRENT_SSH_USER}'"

# Helper for executing commands on remote target
remote_exec() {
    local user="$1"
    local cmd="$2"
    ssh -p "${SSH_PORT}" -o BatchMode=yes -o StrictHostKeyChecking=accept-new "${user}@${TARGET_HOST}" "${cmd}"
}

# Wait for server to reboot and resume SSH connectivity
wait_for_reboot() {
    local user="$1"
    info "Waiting for ${TARGET_HOST} to reboot and restore SSH connectivity..."
    sleep 8
    local attempts=0
    local max_attempts=45

    while ! ssh -p "${SSH_PORT}" -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=accept-new "${user}@${TARGET_HOST}" "true" 2>/dev/null; do
        attempts=$((attempts + 1))
        if [[ ${attempts} -ge ${max_attempts} ]]; then
            fatal "Timeout waiting for ${TARGET_HOST} to reconnect after reboot."
        fi
        sleep 2
    done
    success "${TARGET_HOST} is back online!"
}

# Prompt role if not specified
if [[ -z "${ROLE}" ]]; then
    echo -e "${CYAN}Select Node Role for ${TARGET_HOST}:${NC}"
    echo "1) Server (Control Plane connected to PostgreSQL)"
    echo "2) Agent  (Worker Node joining cluster)"
    read -r -p "Role [1 or 2]: " role_opt
    case "${role_opt}" in
        1) ROLE="server" ;;
        2) ROLE="agent" ;;
        *) fatal "Invalid selection." ;;
    esac
fi

# Build arguments for bootstrap on the remote node
BOOTSTRAP_FLAGS="--role ${ROLE} --admin-user ${ADMIN_USER} --ssh-port ${SSH_PORT}"

if [[ "${ROLE}" == "server" ]]; then
    if [[ -z "${DATASTORE_ENDPOINT}" ]]; then
        read -r -p "PostgreSQL Datastore Endpoint: " DATASTORE_ENDPOINT
    fi
    BOOTSTRAP_FLAGS="${BOOTSTRAP_FLAGS} --datastore-endpoint '${DATASTORE_ENDPOINT}'"
    [[ -n "${TOKEN}" ]] && BOOTSTRAP_FLAGS="${BOOTSTRAP_FLAGS} --token '${TOKEN}'"
    [[ -n "${CF_TOKEN}" ]] && BOOTSTRAP_FLAGS="${BOOTSTRAP_FLAGS} --cf-token '${CF_TOKEN}'"
elif [[ "${ROLE}" == "agent" ]]; then
    if [[ -z "${SERVER_URL}" ]]; then
        read -r -p "Server URL (https://<server-ip>:6443): " SERVER_URL
    fi
    if [[ -z "${TOKEN}" ]]; then
        read -r -p "Cluster Join Token: " TOKEN
    fi
    BOOTSTRAP_FLAGS="${BOOTSTRAP_FLAGS} --server-url '${SERVER_URL}' --token '${TOKEN}'"
fi

# 2. Trigger Bootstrap remotely
info "Streaming bootstrap orchestrator to ${TARGET_HOST}..."
REMOTE_BOOTSTRAP_CMD="curl -fsSL https://raw.githubusercontent.com/Lyttle-Development/Cluster/main/scripts/bootstrap.sh | sudo bash -s -- ${BOOTSTRAP_FLAGS}"

remote_exec "${CURRENT_SSH_USER}" "${REMOTE_BOOTSTRAP_CMD}"

# 3. Handle reboot if requested
if [[ "${DO_REBOOT}" == "true" ]]; then
    info "Reboot requested: issuing reboot to ${TARGET_HOST}..."
    remote_exec "${CURRENT_SSH_USER}" "sudo reboot" || true
    wait_for_reboot "${ADMIN_USER}"
fi

# 4. Verify new admin user and safely lock default provider user
info "Verifying SSH authentication with new admin user '${ADMIN_USER}'..."
if ssh -p "${SSH_PORT}" -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new "${ADMIN_USER}@${TARGET_HOST}" "true" 2>/dev/null; then
    success "New admin user '${ADMIN_USER}' authenticated successfully via SSH key!"
    if [[ "${CURRENT_SSH_USER}" != "${ADMIN_USER}" && "${CURRENT_SSH_USER}" == "debian" ]]; then
        info "Safely locking default 'debian' account on ${TARGET_HOST}..."
        remote_exec "${ADMIN_USER}" "sudo passwd -l debian || true"
        success "Default 'debian' account password locked."
    fi
else
    warn "Could not authenticate as '${ADMIN_USER}'. Keeping '${CURRENT_SSH_USER}' unlocked to prevent lockout."
fi

# 5. Fetch Kubeconfig and Headlamp Token (if server node)
if [[ "${ROLE}" == "server" ]]; then
    info "Downloading cluster kubeconfig to your Developer PC..."
    LOCAL_KUBE_DIR="${HOME}/.kube"
    mkdir -p "${LOCAL_KUBE_DIR}"
    LOCAL_CONFIG="${LOCAL_KUBE_DIR}/config-cluster-${TARGET_HOST}"

    remote_exec "${ADMIN_USER}" "sudo cat /etc/rancher/k3s/k3s.yaml" | \
        sed "s/127.0.0.1/${TARGET_HOST}/g" > "${LOCAL_CONFIG}"
    chmod 600 "${LOCAL_CONFIG}"

    # Fetch Headlamp Dashboard Token
    info "Fetching Headlamp Dashboard admin token..."
    DASHBOARD_TOKEN="$(remote_exec "${ADMIN_USER}" "sudo cat /etc/headlamp-admin-token.txt 2>/dev/null || true")"

    echo "=========================================================================="
    echo " 🚀 Remote Provisioning Complete!"
    echo " Host:             ${TARGET_HOST}"
    echo " SSH Access:       ssh -p ${SSH_PORT} ${ADMIN_USER}@${TARGET_HOST}"
    echo " Kubeconfig Saved: ${LOCAL_CONFIG}"
    echo " Use Kubeconfig:   export KUBECONFIG=${LOCAL_CONFIG}"
    if [[ -n "${DASHBOARD_TOKEN}" ]]; then
        echo " Headlamp URL:     https://dashboard.cluster.lyttle.dev"
        echo " Dashboard Token:  ${DASHBOARD_TOKEN}"
    fi
    echo "=========================================================================="
fi
