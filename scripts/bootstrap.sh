#!/usr/bin/env bash
# ==============================================================================
# Cluster Bootstrap Orchestrator (One-Liner Entrypoint)
# Repository: https://github.com/Lyttle-Development/Cluster
# ==============================================================================

set -euo pipefail

REPO_URL="https://github.com/Lyttle-Development/Cluster.git"
INSTALL_DIR="/opt/cluster"

# Check root
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "[ERROR] This script must be run as root (use sudo)." >&2
    exit 1
fi

# Ensure git and curl are available if piped
if ! command -v git &> /dev/null || ! command -v curl &> /dev/null; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y > /dev/null
    apt-get install -y --no-install-recommends git curl ca-certificates > /dev/null
fi

# Determine script location or clone if running from pipe
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"

if [[ ! -f "${SCRIPT_DIR}/common.sh" ]]; then
    echo "[INFO] Running via remote pipe. Cloning repository to ${INSTALL_DIR}..."
    if [[ -d "${INSTALL_DIR}/.git" ]]; then
        git -C "${INSTALL_DIR}" pull --quiet || true
    else
        mkdir -p "${INSTALL_DIR}"
        git clone --quiet "${REPO_URL}" "${INSTALL_DIR}"
    fi
    SCRIPT_DIR="${INSTALL_DIR}/scripts"
fi

# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"

# Default variables
ROLE=""
DATASTORE_ENDPOINT="${DATASTORE_ENDPOINT:-}"
SERVER_URL="${SERVER_URL:-}"
TOKEN="${K3S_TOKEN:-${TOKEN:-}}"
CF_TOKEN="${CLOUDFLARE_TUNNEL_TOKEN:-${CF_TOKEN:-}}"
ADMIN_USER="${ADMIN_USER:-server}"
LOCK_DEFAULT_USER="${LOCK_DEFAULT_USER:-true}"
INSTALL_DASHBOARD="${INSTALL_DASHBOARD:-true}"
SSH_PORT="${SSH_PORT:-22}"
DO_RESET=false

usage() {
    cat <<EOF
Usage: $0 [options]

Options:
  --role [server|agent]            Node role (server = control plane, agent = worker)
  --datastore-endpoint <url>       PostgreSQL 18 connection string (required for server)
  --server-url <url>               Control-plane URL e.g. https://1.2.3.4:6443 (required for agent)
  --token <token>                  Cluster join token (auto-generated if omitted on server)
  --cf-token <token>               Cloudflare Tunnel token (optional for server)
  --dashboard <bool>               Deploy Headlamp web dashboard (default: true)
  --admin-user <name>              Admin user to create/configure with SSH keys (default: server)
  --lock-default-user <bool>       Lock password on default 'debian' user (default: true)
  --ssh-port <port>                SSH port to allow in UFW (default: 22)
  --reset                          Reset and uninstall cluster software on this node
  -h, --help                       Show this help message



Examples:
  # One-Liner Install Server Node:
  curl -fsSL https://install.cluster.lyttle.dev | sudo bash -s -- \\
    --role server --datastore-endpoint "postgres://user:pass@host:25060/db?sslmode=require"

  # One-Liner Install Agent Node:
  curl -fsSL https://install.cluster.lyttle.dev | sudo bash -s -- \\
    --role agent --server-url "https://10.0.0.1:6443" --token "mysecrettoken"

  # One-Liner Reset Node:
  curl -fsSL https://install.cluster.lyttle.dev | sudo bash -s -- --reset
EOF
    exit 0

}

# Parse CLI arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --role)
            ROLE="$2"
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
        --dashboard)
            INSTALL_DASHBOARD="$2"
            shift 2
            ;;
        --admin-user)
            ADMIN_USER="$2"
            shift 2
            ;;

        --lock-default-user)
            LOCK_DEFAULT_USER="$2"
            shift 2
            ;;
        --ssh-port)
            SSH_PORT="$2"
            shift 2
            ;;
        --reset)
            DO_RESET=true
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

# Handle reset command
if [[ "${DO_RESET}" == "true" ]]; then
    exec "${SCRIPT_DIR}/99-reset-node.sh"
fi

# Interactive mode if role is not specified
if [[ -z "${ROLE}" ]]; then
    echo -e "${CYAN}=== Lyttle Cluster Setup Assistant ===${NC}"
    echo "1) Server (Control-plane connected to PostgreSQL)"
    echo "2) Agent  (Worker node joining existing cluster)"
    read -r -p "Select role [1 or 2]: " role_choice
    case "${role_choice}" in
        1) ROLE="server" ;;
        2) ROLE="agent" ;;
        *) fatal "Invalid selection." ;;
    esac
fi

# Validate and prompt for Server requirements
if [[ "${ROLE}" == "server" ]]; then
    if [[ -z "${DATASTORE_ENDPOINT}" ]]; then
        echo -e "${YELLOW}Please enter your DigitalOcean PostgreSQL 18 connection string:${NC}"
        echo "Example: postgres://k3s_user:secret@db-do-123.b.db.ondigitalocean.com:25060/k3s_cluster?sslmode=require"
        read -r -p "Datastore URL: " DATASTORE_ENDPOINT
    fi
    if [[ -z "${DATASTORE_ENDPOINT}" ]]; then
        fatal "Datastore endpoint is mandatory for server role."
    fi
    export DATASTORE_ENDPOINT
    export K3S_TOKEN="${TOKEN}"
    export CLOUDFLARE_TUNNEL_TOKEN="${CF_TOKEN}"
fi

# Validate and prompt for Agent requirements
if [[ "${ROLE}" == "agent" ]]; then
    if [[ -z "${SERVER_URL}" ]]; then
        read -r -p "Enter Server URL (e.g. https://1.2.3.4:6443): " SERVER_URL
    fi
    if [[ -z "${TOKEN}" ]]; then
        read -r -p "Enter Cluster Token: " TOKEN
    fi
    if [[ -z "${SERVER_URL}" || -z "${TOKEN}" ]]; then
        fatal "Both Server URL and Token are mandatory for agent role."
    fi
    export K3S_SERVER_URL="${SERVER_URL}"
    export K3S_TOKEN="${TOKEN}"
fi

export SSH_PORT="${SSH_PORT}"
export ADMIN_USER="${ADMIN_USER}"
export LOCK_DEFAULT_USER="${LOCK_DEFAULT_USER}"


# ==============================================================================
# Execution Pipeline
# ==============================================================================
info "=========================================================================="
info " Starting Cluster Node Bootstrap: Role [${ROLE}]"
info "=========================================================================="

# Step 01: System Prep
bash "${SCRIPT_DIR}/01-system-prep.sh"

# Step 02: Firewall Hardening
bash "${SCRIPT_DIR}/02-firewall-hardening.sh"

# Step 03 or 04: K3s Installation
if [[ "${ROLE}" == "server" ]]; then
    bash "${SCRIPT_DIR}/03-install-k3s-server.sh"
    # Step 05: Cloudflare Tunnel (if token supplied)
    if [[ -n "${CF_TOKEN}" ]]; then
        bash "${SCRIPT_DIR}/05-deploy-cloudflared.sh"
    fi
    # Step 06: Headlamp Web Dashboard (if enabled)
    if [[ "${INSTALL_DASHBOARD}" == "true" ]]; then
        bash "${SCRIPT_DIR}/06-deploy-dashboard.sh"
    fi
elif [[ "${ROLE}" == "agent" ]]; then
    bash "${SCRIPT_DIR}/04-install-k3s-agent.sh"
fi

# Step 07: Automated Node Sync & Reconciliation (runs on all nodes)
bash "${SCRIPT_DIR}/07-setup-auto-sync.sh"

success "=========================================================================="
success " Bootstrap complete! Node is secure, hardened, and active."
success "=========================================================================="

