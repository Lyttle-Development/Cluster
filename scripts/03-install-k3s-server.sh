#!/usr/bin/env bash
# ==============================================================================
# Step 03: Install K3s Control-Plane Server (with External PostgreSQL via Kine)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"

check_root

# Load environment configuration if present
load_env "${1:-/etc/cluster-node.env}"

DATASTORE_ENDPOINT="${DATASTORE_ENDPOINT:-}"
K3S_TOKEN="${K3S_TOKEN:-}"
NODE_IP="${NODE_IP:-$(curl -s https://api.ipify.org || hostname -I | awk '{print $1}')}"

if [[ -z "${DATASTORE_ENDPOINT}" ]]; then
    fatal "DATASTORE_ENDPOINT is not set! Provide your DigitalOcean PostgreSQL connection string (e.g. postgres://user:pass@host:25060/k3s_cluster?sslmode=require)."
fi

# Generate token if not provided
if [[ -z "${K3S_TOKEN}" ]]; then
    info "No K3S_TOKEN provided; generating a cryptographically secure token..."
    K3S_TOKEN="$(openssl rand -hex 32)"
fi

info "Starting Step 03: Installing K3s Control-Plane Server..."
info "Node IP: ${NODE_IP}"
info "Datastore: PostgreSQL via Kine (External Managed DB)"

# 1. Create K3s configuration directory
mkdir -p /etc/rancher/k3s

# 2. Write K3s Server Configuration
cat <<EOF > /etc/rancher/k3s/config.yaml
datastore-endpoint: "${DATASTORE_ENDPOINT}"
token: "${K3S_TOKEN}"
flannel-backend: "wireguard-native"
disable:
  - "servicelb"
write-kubeconfig-mode: "0644"
tls-san:
  - "127.0.0.1"
  - "${NODE_IP}"
EOF

info "Created /etc/rancher/k3s/config.yaml"

# 3. Run K3s official installer
info "Executing K3s installer..."
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server" sh -s -

# 4. Wait for K3s systemd service
info "Waiting for K3s service to reach active state..."
for i in {1..30}; do
    if systemctl is-active --quiet k3s; then
        break
    fi
    sleep 2
done

if ! systemctl is-active --quiet k3s; then
    fatal "K3s failed to start. Check 'journalctl -u k3s -n 50' for details."
fi

# 5. Set up kubeconfig for root, sudo user, and admin user
mkdir -p /root/.kube
cp /etc/rancher/k3s/k3s.yaml /root/.kube/config
chmod 600 /root/.kube/config

ADMIN_USER="${ADMIN_USER:-server}"
for target_user in "${SUDO_USER:-}" "${ADMIN_USER}"; do
    if [[ -n "${target_user}" && "${target_user}" != "root" ]] && id "${target_user}" &>/dev/null; then
        USER_HOME="$(getent passwd "${target_user}" | cut -d: -f6)"
        mkdir -p "${USER_HOME}/.kube"
        cp /etc/rancher/k3s/k3s.yaml "${USER_HOME}/.kube/config"
        chown -R "${target_user}:${target_user}" "${USER_HOME}/.kube"
        chmod 600 "${USER_HOME}/.kube/config"
        info "Kubeconfig configured for user '${target_user}' at ${USER_HOME}/.kube/config"
    fi
done


# 6. Wait for node to be Ready
info "Waiting for node to report Ready state..."
for i in {1..30}; do
    if kubectl get nodes | grep -q "Ready"; then
        break
    fi
    sleep 2
done

# Save cluster credentials for subsequent scripts
cat <<EOF > /etc/cluster-node.env
ROLE=server
NODE_IP=${NODE_IP}
K3S_TOKEN=${K3S_TOKEN}
DATASTORE_ENDPOINT=${DATASTORE_ENDPOINT}
EOF
chmod 600 /etc/cluster-node.env

success "Step 03 completed: K3s Control Plane is running and connected to PostgreSQL!"
echo "=========================================================================="
echo "Cluster Node Token: ${K3S_TOKEN}"
echo "Server URL:         https://${NODE_IP}:6443"
echo "Kubeconfig path:    /etc/rancher/k3s/k3s.yaml"
echo "=========================================================================="
