# 🚀 Lyttle Cluster Toolchain

> **Hardened, Stateless, Zero-Trust Kubernetes Cluster on Debian 13 VPSes**  
> Powered by K3s, Managed PostgreSQL 18 (Kine), Cloudflare Tunnels, and Nix.

[![Debian 13](https://img.shields.io/badge/OS-Debian%2013%20(Trixie)-red.svg)](https://www.debian.org/)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-K3s-blue.svg)](https://k3s.io/)
[![Datastore](https://img.shields.io/badge/Datastore-PostgreSQL%2018%20(DigitalOcean)-336791.svg)](https://www.digitalocean.com/products/managed-databases-postgresql)
[![Ingress](https://img.shields.io/badge/Ingress-Cloudflare%20Tunnels-orange.svg)](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

---

## 💡 Overview & Threat Model

This repository is built to replace fragile Docker Swarm / Portainer setups with a **hardened, disposable Kubernetes cluster** that can be rapidly wiped and rebuilt in under 5 minutes in case of an incident.

### Why this design is resilient:
1. **Decoupled Cluster State**: The K3s control plane state is stored in an **external DigitalOcean Managed PostgreSQL 18** instance via **Kine**. If every VPS in the fleet gets deleted or compromised, the cluster state is completely safe.
2. **Zero Inbound Public Attack Surface**: Inbound web traffic arrives strictly through **Cloudflare Tunnels (`cloudflared`)**. Public ports `80`, `443`, and `6443` are **blocked on the host firewall (`UFW`)**. Direct IP scans, port probing, and raw network exploits cannot reach the VPS.
3. **Stateless Cattle**: VPS disks store no critical business data. Application data lives in PostgreSQL, media/blobs live in S3/R2 object storage, and node disks are purely ephemeral caches.
4. **Encrypted East-West Mesh**: Pod-to-pod and node-to-node overlay traffic uses in-kernel **WireGuard** (`wireguard-native`).
5. **KISS Modular Scripts**: Every provisioning step is broken down into simple, standalone bash scripts following the Unix philosophy.
6. **Local Nix Flake**: The administrator's toolchain (`kubectl`, `helm`, `cloudflared`, `sops`) is declared reproducibly via `flake.nix`.

---

## ⚡ Quickstart: One-Liner Commands

> [!TIP]
> The primary installation commands below use **`https://install.cluster.lyttle.dev`**.  
> To set up this domain on your Cloudflare account, see the [Cloudflare Configuration Guide](file:///Users/kiliandebock/Documents/GitHub/Cluster/docs/CLOUDFLARE_SETUP.md).  
> *(The direct GitHub URL `raw.githubusercontent.com/Lyttle-Development/Cluster/main/scripts/bootstrap.sh` also works as a direct fallback).*

### 1. Provision a Server Node (Control Plane)
Run on a fresh Debian 13 VPS:
```bash
curl -fsSL https://install.cluster.lyttle.dev | sudo bash -s -- \
  --role server \
  --datastore-endpoint "postgres://k3s_user:SECRET_PASSWORD@db-do-host:25060/k3s_cluster?sslmode=require" \
  --cf-token "YOUR_CLOUDFLARE_TUNNEL_TOKEN"
```

### 2. Provision an Agent Node (Worker)
Run on any additional Debian 13 VPS to expand compute capacity:
```bash
curl -fsSL https://install.cluster.lyttle.dev | sudo bash -s -- \
  --role agent \
  --server-url "https://<SERVER_IP>:6443" \
  --token "<CLUSTER_NODE_TOKEN>"
```

### 3. Reset / Decontaminate a Node
To cleanly remove K3s, container storage, and network interfaces back to baseline:
```bash
curl -fsSL https://install.cluster.lyttle.dev | sudo bash -s -- --reset
```


---

## 🧩 KISS Modular Scripts

Instead of a monolithic black-box, each step is an independent script inside [`scripts/`](file:///Users/kiliandebock/Documents/GitHub/Cluster/scripts):

| Script | Purpose |
| :--- | :--- |
| [`scripts/01-system-prep.sh`](file:///Users/kiliandebock/Documents/GitHub/Cluster/scripts/01-system-prep.sh) | Base packages, disable swap, kernel modules (`overlay`, `br_netfilter`, `wireguard`), sysctl hardening, `unattended-upgrades`, `fail2ban`. |
| [`scripts/02-firewall-hardening.sh`](file:///Users/kiliandebock/Documents/GitHub/Cluster/scripts/02-firewall-hardening.sh) | UFW setup: default drop inbound, rate-limited SSH, allows WireGuard 51820/udp & K3s 6443/tcp. **Keeps 80 & 443 closed to public**. |
| [`scripts/03-install-k3s-server.sh`](file:///Users/kiliandebock/Documents/GitHub/Cluster/scripts/03-install-k3s-server.sh) | K3s control-plane with external PostgreSQL datastore (Kine), native WireGuard flannel, and generated credentials. |
| [`scripts/04-install-k3s-agent.sh`](file:///Users/kiliandebock/Documents/GitHub/Cluster/scripts/04-install-k3s-agent.sh) | Joins worker node to the K3s cluster. |
| [`scripts/05-deploy-cloudflared.sh`](file:///Users/kiliandebock/Documents/GitHub/Cluster/scripts/05-deploy-cloudflared.sh) | Deploys Cloudflare Tunnel agent inside cluster (least-privilege non-root container with read-only rootfs). |
| [`scripts/99-reset-node.sh`](file:///Users/kiliandebock/Documents/GitHub/Cluster/scripts/99-reset-node.sh) | Complete node wipe: uninstalls K3s, unmounts container storage, removes virtual interfaces, resets firewall safely. |
| [`scripts/bootstrap.sh`](file:///Users/kiliandebock/Documents/GitHub/Cluster/scripts/bootstrap.sh) | Unified master orchestrator supporting both CLI flags and interactive prompts. |

---

## 🛠️ Local Administrator Environment (Nix Flake)

To manage the cluster from your Mac or workstation without polluting system packages:

```bash
# Clone the repository
git clone https://github.com/Lyttle-Development/Cluster.git
cd Cluster

# Enter the isolated Nix environment
nix develop
```

This immediately loads:
- `kubectl`
- `helm`
- `k3sup`
- `cloudflared`
- `sops` & `age`
- `jq` & `yq`

---

## 📚 Documentation Deep Dives

- [**Architecture & Security Blueprint**](file:///Users/kiliandebock/Documents/GitHub/Cluster/docs/ARCHITECTURE.md): Threat model, defense-in-depth, and control plane decoupling.
- [**Disaster Recovery Runbook**](file:///Users/kiliandebock/Documents/GitHub/Cluster/docs/DISASTER_RECOVERY.md): Rapid response guides for node compromise, server rebuilds, and total fleet recovery.
- [**Networking & Ingress Guide**](file:///Users/kiliandebock/Documents/GitHub/Cluster/docs/NETWORKING_AND_INGRESS.md): Cloudflare Tunnel integration, WireGuard overlay, and firewall policies.
- [**Storage Strategy**](file:///Users/kiliandebock/Documents/GitHub/Cluster/docs/STORAGE_STRATEGY.md): PostgreSQL 18 database partitioning, S3 object storage, and ephemeral local paths.
- [**Cloudflare DNS & Routing Setup**](file:///Users/kiliandebock/Documents/GitHub/Cluster/docs/CLOUDFLARE_SETUP.md): DNS records, redirect rules, and Worker code for `install.cluster.lyttle.dev`.


---

## 📄 License

MIT © [Lyttle Development](https://github.com/Lyttle-Development)
