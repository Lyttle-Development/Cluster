#!/usr/bin/env bash
# ==============================================================================
# Step 02: Host Firewall Hardening (UFW)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common.sh
source "${SCRIPT_DIR}/common.sh"

check_root

SSH_PORT="${SSH_PORT:-22}"
ALLOW_K8S_API="${ALLOW_K8S_API:-true}"

info "Starting Step 02: Configuring UFW firewall rules..."

# 1. Install UFW
apt-get install -y --no-install-recommends ufw

# 2. Reset existing rules to a known clean state
info "Resetting existing UFW rules..."
ufw --force reset > /dev/null

# 3. Configure default policies
info "Setting default policies (Inbound: DROP, Outbound: ALLOW, Routed: ACCEPT)..."
ufw default deny incoming
ufw default allow outgoing

# Enable packet routing in UFW for container networking
if grep -q "DEFAULT_FORWARD_POLICY=" /etc/default/ufw; then
    sed -i 's/DEFAULT_FORWARD_POLICY=.*/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw
fi

# 4. Allow SSH (Rate-limited to prevent brute force)
info "Allowing rate-limited SSH on port ${SSH_PORT}..."
ufw limit "${SSH_PORT}/tcp" comment "SSH rate-limited"

# 5. Allow K3s WireGuard Flannel Overlay Port
info "Allowing Flannel WireGuard encrypted overlay traffic (51820/udp)..."
ufw allow 51820/udp comment "K3s WireGuard overlay"

# 6. Allow K3s API Server Port (6443)
if [[ "${ALLOW_K8S_API}" == "true" ]]; then
    info "Allowing K3s control-plane communication (6443/tcp)..."
    ufw allow 6443/tcp comment "K3s API server"
fi

# 7. Allow internal loopback and container interfaces
info "Allowing local and container virtual interfaces..."
ufw allow in on lo comment "Local loopback"
ufw allow in on cni0 comment "CNI bridge" || true
ufw allow in on flannel.1 comment "Flannel overlay" || true
ufw allow in on flannel-wg comment "Flannel WireGuard interface" || true

# 8. Note: HTTP (80) and HTTPS (443) are deliberately NOT opened
info "Notice: Ports 80 and 443 are deliberately NOT exposed to public traffic."
info "All incoming web traffic is routed securely via outbound Cloudflare Tunnels."

# 9. Enable UFW
info "Enabling UFW..."
ufw --force enable

success "Step 02 completed: UFW configured and active. Direct public attack surface eliminated."
