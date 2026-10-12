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

# 8. User Management & SSH Hardening
ADMIN_USER="${ADMIN_USER:-server}"
LOCK_DEFAULT_USER="${LOCK_DEFAULT_USER:-true}"

if [[ -n "${ADMIN_USER}" && "${ADMIN_USER}" != "root" ]]; then
    if ! id "${ADMIN_USER}" &>/dev/null; then
        info "Creating administrative user: ${ADMIN_USER}..."
        useradd -m -s /bin/bash -G sudo "${ADMIN_USER}"
    else
        info "Administrative user ${ADMIN_USER} already exists."
        usermod -aG sudo "${ADMIN_USER}" || true
    fi

    # Set up passwordless sudo for the admin user
    echo "${ADMIN_USER} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/99-${ADMIN_USER}"
    chmod 440 "/etc/sudoers.d/99-${ADMIN_USER}"

    # Migrate SSH keys from default debian or root account
    ADMIN_SSH_DIR="/home/${ADMIN_USER}/.ssh"
    mkdir -p "${ADMIN_SSH_DIR}"
    chmod 700 "${ADMIN_SSH_DIR}"

    SOURCE_KEYS=""
    if [[ -f /home/debian/.ssh/authorized_keys ]]; then
        SOURCE_KEYS="/home/debian/.ssh/authorized_keys"
    elif [[ -n "${SUDO_USER:-}" && -f "/home/${SUDO_USER}/.ssh/authorized_keys" ]]; then
        SOURCE_KEYS="/home/${SUDO_USER}/.ssh/authorized_keys"
    elif [[ -f /root/.ssh/authorized_keys ]]; then
        SOURCE_KEYS="/root/.ssh/authorized_keys"
    fi

    if [[ -n "${SOURCE_KEYS}" && -f "${SOURCE_KEYS}" ]]; then
        info "Migrating authorized SSH keys from ${SOURCE_KEYS} to ${ADMIN_USER}..."
        cp "${SOURCE_KEYS}" "${ADMIN_SSH_DIR}/authorized_keys"
        chmod 600 "${ADMIN_SSH_DIR}/authorized_keys"
        chown -R "${ADMIN_USER}:${ADMIN_USER}" "${ADMIN_SSH_DIR}"
        success "SSH key installed for user '${ADMIN_USER}'."
    else
        warn "No existing authorized_keys found to copy for user '${ADMIN_USER}'."
    fi

    # Lock password on default debian user if requested
    if [[ "${LOCK_DEFAULT_USER}" == "true" && "${ADMIN_USER}" != "debian" ]] && id debian &>/dev/null; then
        info "Locking password authentication on default 'debian' user..."
        passwd -l debian || true
    fi
fi

# Enforce SSH daemon security settings
info "Hardening SSH daemon configuration..."
mkdir -p /etc/ssh/sshd_config.d
cat <<EOF > /etc/ssh/sshd_config.d/99-hardened.conf
# Enforce public key authentication only
PasswordAuthentication no
PubkeyAuthentication yes
KbdInteractiveAuthentication no
PermitEmptyPasswords no
X11Forwarding no
MaxAuthTries 4
EOF

# Reload SSH service safely without dropping active sessions
systemctl reload ssh || systemctl reload sshd || systemctl restart ssh || systemctl restart sshd || true

success "Step 01 completed: System prepared, kernel hardened, user '${ADMIN_USER}' active, and SSH secured."

