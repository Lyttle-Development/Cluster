#!/usr/bin/env bash
# ==============================================================================
# Step 01: System Preparation & Base Hardening
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"

check_root
check_os

info "Starting Step 01: System preparation and kernel hardening..."

export DEBIAN_FRONTEND=noninteractive

# 1. Update package repositories and upgrade
info "Updating apt packages..."
apt-get update -y
apt-get upgrade -y -o Dpkg::Options::="--force-confold"

# 2. Install core packages
info "Installing required base packages..."
apt-get install -y --no-install-recommends \
    curl \
    wget \
    sudo \
    ca-certificates \
    gnupg \
    lsb-release \
    apparmor \
    apparmor-utils \
    wireguard-tools \
    fail2ban \
    unattended-upgrades \
    iptables \
    tar \
    jq

# 3. Disable Swap (Required for Kubernetes memory management)
info "Disabling swap..."
swapoff -a || true
if grep -q "swap" /etc/fstab; then
    sed -i '/swap/d' /etc/fstab
    info "Removed swap entries from /etc/fstab"
fi

# 4. Load required kernel modules for Kubernetes & WireGuard overlay
info "Configuring kernel modules..."
cat <<EOF > /etc/modules-load.d/k3s-kernel.conf
overlay
br_netfilter
wireguard
EOF

modprobe overlay || true
modprobe br_netfilter || true
modprobe wireguard || true

# 5. Apply sysctl security & network parameters
info "Applying kernel sysctl hardening..."
cat <<EOF > /etc/sysctl.d/99-k3s-hardened.conf
# Enable packet forwarding for container networking
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1

# TCP SYN flood protection
net.ipv4.tcp_syncookies = 1

# Disable ICMP redirect acceptance (Mitigate Man-in-the-Middle)
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

# Disable IP source routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0

# Enable reverse path filtering (Anti-spoofing)
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Ignore bogus ICMP error messages
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
EOF

sysctl --system > /dev/null

# 6. Configure unattended security updates
info "Configuring unattended security updates..."
cat <<EOF > /etc/apt/apt.conf.d/20auto-upgrades
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
systemctl enable --now unattended-upgrades || true

# 7. Configure Fail2ban for SSH
info "Configuring fail2ban for SSH protection..."
cat <<EOF > /etc/fail2ban/jail.local
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true
port = ssh
EOF
systemctl enable --now fail2ban || true

success "Step 01 completed: System prepared, kernel hardened, and security services active."
