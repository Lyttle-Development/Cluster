#!/usr/bin/env bash
# ==============================================================================
# Common Helper Utilities for Cluster Scripts
# ==============================================================================

set -euo pipefail

# Colors for terminal output
# shellcheck disable=SC2034
RED='\033[0;31m'
# shellcheck disable=SC2034
GREEN='\033[0;32m'
# shellcheck disable=SC2034
YELLOW='\033[1;33m'
# shellcheck disable=SC2034
BLUE='\033[0;34m'
# shellcheck disable=SC2034
CYAN='\033[0;36m'
# shellcheck disable=SC2034
NC='\033[0m' # No Color

info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

fatal() {
    echo -e "${RED}[FATAL]${NC} $*" >&2
    exit 1
}

# Ensure script is run as root
check_root() {
    if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
        fatal "This script must be run as root (use sudo)."
    fi
}

# Verify OS compatibility
check_os() {
    if [[ ! -f /etc/os-release ]]; then
        fatal "Cannot determine OS: /etc/os-release not found."
    fi

    # shellcheck source=/dev/null
    source /etc/os-release

    info "Detected Operating System: ${NAME:-Unknown} ${VERSION_ID:-Unknown} (${ID:-unknown})"

    if [[ "${ID:-}" != "debian" && "${ID:-}" != "ubuntu" ]]; then
        warn "This cluster toolchain is primarily tuned for Debian 13/Ubuntu. Proceeding with caution..."
    fi
}

# Load environment configuration if available
load_env() {
    local env_file="${1:-/etc/cluster-node.env}"
    if [[ -f "${env_file}" ]]; then
        info "Loading configuration from ${env_file}..."
        set -a
        # shellcheck source=/dev/null
        source "${env_file}"
        set +a
    fi
}
