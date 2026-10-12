#!/usr/bin/env bash
# ==============================================================================
# Step 99: Clean Reset & Node Teardown (Disaster Recovery & Decommissioning)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common.sh
source "${SCRIPT_DIR}/common.sh"

check_root

FORCE="${1:-}"

if [[ "${FORCE}" != "--force" && "${FORCE}" != "-y" ]]; then
    echo -e "${RED}WARNING: This script will completely remove K3s, container storage, and network interfaces on this node.${NC}"
    read -r -p "Are you sure you want to completely reset this node? [y/N]: " confirm
    if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then
        info "Node reset cancelled."
        exit 0
    fi
fi

info "Initiating full node reset and decontamination..."

# 1. Execute official K3s uninstallers if present
if [[ -f /usr/local/bin/k3s-uninstall.sh ]]; then
    info "Running K3s server uninstaller..."
    /usr/local/bin/k3s-uninstall.sh || true
fi

if [[ -f /usr/local/bin/k3s-agent-uninstall.sh ]]; then
    info "Running K3s agent uninstaller..."
    /usr/local/bin/k3s-agent-uninstall.sh || true
fi

# 2. Kill any stray containerd / k3s processes
info "Terminating residual container processes..."
pkill -9 -f "k3s" || true
pkill -9 -f "containerd-shim" || true

# 3. Unmount leftover Kubernetes / Containerd filesystems
info "Unmounting leftover container mounts..."
awk '$2 ~ /^\/(var\/lib\/rancher|var\/lib\/kubelet|run\/k3s|run\/netns)/ {print $2}' /proc/mounts | sort -r | while read -r mountpoint; do
    umount -f "${mountpoint}" || true
done

# 4. Remove directories and data
info "Purging cluster directories and services..."
systemctl disable --now cluster-sync.timer cluster-sync.service 2>/dev/null || true
rm -f /etc/systemd/system/cluster-sync.* || true
systemctl daemon-reload || true

rm -rf /etc/rancher \

       /var/lib/rancher \
       /var/lib/kubelet \
       /run/k3s \
       /run/flannel \
       /var/lib/cni \
       /etc/cni \
       /etc/cluster-node.env \
       /etc/headlamp-admin-token.txt \
       /root/.kube
rm -f /home/*/headlamp-token.txt || true


# 5. Clean up virtual network interfaces
info "Removing container virtual network interfaces..."
ip link delete cni0 || true
ip link delete flannel.1 || true
ip link delete flannel-wg || true

# 6. Reset UFW firewall safely
info "Resetting UFW firewall rules..."
if command -v ufw &> /dev/null; then
    ufw --force reset > /dev/null
    ufw default deny incoming
    ufw default allow outgoing
    ufw limit 22/tcp comment "SSH rate-limited"
    ufw --force enable
fi

success "Step 99 completed: Node has been reset to a clean baseline state."
info "This node is now ready for a clean re-bootstrap or redeployment."
