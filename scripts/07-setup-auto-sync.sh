#!/usr/bin/env bash
# ==============================================================================
# Step 07: Set Up Automated Node Sync & Reconciliation (systemd timer)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common.sh
source "${SCRIPT_DIR}/common.sh"

check_root

SYNC_INTERVAL="${SYNC_INTERVAL:-30min}"

info "Starting Step 07: Configuring cluster-sync systemd service and timer..."

# 1. Create systemd service unit
cat <<EOF > /etc/systemd/system/cluster-sync.service
[Unit]
Description=Cluster Node Auto-Sync and Self-Reconciliation
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
WorkingDirectory=/opt/cluster
ExecStart=/bin/bash /opt/cluster/scripts/sync-node.sh
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# 2. Create systemd timer unit
cat <<EOF > /etc/systemd/system/cluster-sync.timer
[Unit]
Description=Run Cluster Node Auto-Sync periodically (${SYNC_INTERVAL})

[Timer]
OnBootSec=5min
OnUnitActiveSec=${SYNC_INTERVAL}
Persistent=true

[Install]
WantedBy=timers.target
EOF

# 3. Reload systemd daemon and activate timer
info "Enabling and starting cluster-sync.timer..."
systemctl daemon-reload
systemctl enable --now cluster-sync.timer

success "Step 07 completed: cluster-sync.timer is active (Interval: ${SYNC_INTERVAL})."
info "Your cluster nodes will automatically pull updates and self-heal from GitHub!"
