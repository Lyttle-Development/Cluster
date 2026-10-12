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

## ⚡ Quickstart: Provisioning Workflows

You can provision nodes in two ways:
1. **From your Developer PC (Recommended)**: Automatically connects over SSH, orchestrates hardening, handles reboots smoothly, migrates users, and downloads `kubeconfig` to your workstation.
2. **Direct One-Liner on the VPS**: Paste directly into a VPS terminal.

---

### Method A: Remote Provisioning from Developer PC (Recommended)

#### Provision Server Node (Control Plane):
> 📍 **Run on: Developer PC / Workstation**
```bash
./scripts/bootstrap.sh --target <VPS_IP> --role server \
  --datastore-endpoint "postgres://k3s_user:SECRET@your-do-db:25060/k3s_cluster?sslmode=require" \
  --cf-token "YOUR_CLOUDFLARE_TUNNEL_TOKEN" \
  --reboot
```
*(Handles system reboots, verifies new `server` SSH user, locks `debian`, and downloads `~/.kube/config-cluster-<IP>` and Headlamp token to your Mac).*

#### Provision Worker / Agent Node:
> 📍 **Run on: Developer PC / Workstation**
```bash
./scripts/bootstrap.sh --target <WORKER_VPS_IP> --role agent \
  --server-url "https://<SERVER_IP>:6443" \
  --token "<CLUSTER_NODE_TOKEN>"
```

---

### Method B: Direct One-Liner on Target VPS

#### 1. Provision Server Node directly on host:
> 📍 **Run on: Fresh Server VPS** (via SSH or OVH console as `root` / `sudo`)
```bash
curl -fsSL https://raw.githubusercontent.com/Lyttle-Development/Cluster/main/scripts/bootstrap.sh | sudo bash -s -- \
  --role server \
  --datastore-endpoint "postgres://k3s_user:SECRET_PASSWORD@db-do-host:25060/k3s_cluster?sslmode=require" \
  --cf-token "YOUR_CLOUDFLARE_TUNNEL_TOKEN"
```

#### 2. Provision Worker Node directly on host:
> 📍 **Run on: Additional Worker VPS** (via SSH or OVH console as `root` / `sudo`)
```bash
curl -fsSL https://raw.githubusercontent.com/Lyttle-Development/Cluster/main/scripts/bootstrap.sh | sudo bash -s -- \
  --role agent \
  --server-url "https://<SERVER_IP>:6443" \
  --token "<CLUSTER_NODE_TOKEN>"
```

#### 3. Reset / Decontaminate a Node:
> 📍 **Run on: Target VPS Node to Wipe** (via SSH or OVH console as `root` / `sudo`)
```bash
curl -fsSL https://raw.githubusercontent.com/Lyttle-Development/Cluster/main/scripts/bootstrap.sh | sudo bash -s -- --reset
```



---

## 🚢 Application & Container Management

Deploying containers, mapping domains, and injecting environment variables is designed to be fast and safe.

### 1. Fast CLI Deployer (`./scripts/deploy-app.sh`)
> 📍 **Run on: Developer PC or Server VPS** (inside the `Cluster` repository)
```bash
./scripts/deploy-app.sh \
  --name my-service \
  --image nginx:alpine \
  --domain my-service.cluster.lyttle.dev \
  --port 80 \
  --env NODE_ENV=production
```
- Automatically generates declarative Kubernetes manifests in `apps/<name>/app.yaml`.
- Registers the application in `apps/kustomization.yaml`.
- Traefik automatically routes `https://my-service.cluster.lyttle.dev` through your Cloudflare wildcard tunnel.

### 2. Visual Web Dashboard (Headlamp)
> 📍 **Run on: Developer PC or Server VPS** (requires cluster access)
```bash
# Deploy Headlamp dashboard
kubectl apply -f manifests/dashboard/headlamp.yaml

# Get your admin login token
./scripts/get-dashboard-token.sh
```
- Open `https://dashboard.cluster.lyttle.dev` and log in with your token.
- Inspect container metrics, stream logs, open in-container terminals, and restart pods.

### 3. Instant Fleet Rebuild (All Containers & Routes in 10 Seconds)
> 📍 **Run on: Developer PC or Server VPS** (inside the `Cluster` repository)
```bash
kubectl apply -k apps/
```

### 4. Deploying Private / NAS-Backed Apps (Zero VPS Disk Footprint)
> 📍 **Run on: Developer PC** (where your NAS is mounted; streams directly to VPS over SSH)
```bash
./scripts/deploy-from-nas.sh \
  --source /Volumes/NAS/cluster-apps \
  --server <YOUR_SERVER_IP>
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
| [`scripts/06-deploy-dashboard.sh`](file:///Users/kiliandebock/Documents/GitHub/Cluster/scripts/06-deploy-dashboard.sh) | Deploys Headlamp web dashboard, generates token, and saves it to `/etc/headlamp-admin-token.txt`. |
| [`scripts/07-setup-auto-sync.sh`](file:///Users/kiliandebock/Documents/GitHub/Cluster/scripts/07-setup-auto-sync.sh) | Installs systemd timer and service to run `sync-node.sh` periodically (default: 30 min). |
| [`scripts/sync-node.sh`](file:///Users/kiliandebock/Documents/GitHub/Cluster/scripts/sync-node.sh) | Pulls Git updates, reconciles applications, and reapplies firewall/sysctl baseline. |
| [`scripts/deploy-app.sh`](file:///Users/kiliandebock/Documents/GitHub/Cluster/scripts/deploy-app.sh) | Fast interactive/CLI container deployer: configures image, envs, domain, and Traefik ingress in `apps/`. |
| [`scripts/deploy-from-nas.sh`](file:///Users/kiliandebock/Documents/GitHub/Cluster/scripts/deploy-from-nas.sh) | Streams private NAS manifests/secrets directly into Kubernetes RAM (zero disk trace on VPS). |
| [`scripts/get-dashboard-token.sh`](file:///Users/kiliandebock/Documents/GitHub/Cluster/scripts/get-dashboard-token.sh) | Generates admin authentication token for the Headlamp web dashboard. |
| [`scripts/99-reset-node.sh`](file:///Users/kiliandebock/Documents/GitHub/Cluster/scripts/99-reset-node.sh) | Complete node wipe: uninstalls K3s, unmounts container storage, removes virtual interfaces, resets firewall safely. |
| [`scripts/provision-node.sh`](file:///Users/kiliandebock/Documents/GitHub/Cluster/scripts/provision-node.sh) | Orchestrates remote VPS setup from Developer PC over SSH: handles reboots, user migration, and kubeconfig sync. |
| [`scripts/bootstrap.sh`](file:///Users/kiliandebock/Documents/GitHub/Cluster/scripts/bootstrap.sh) | Unified master orchestrator supporting both local host runs and `--target <vps-ip>` remote runs. |


---

## 🛠️ Local Administrator Environment (Nix Flake)

To manage the cluster from your Mac or workstation without polluting system packages:

> 📍 **Run on: Developer PC / Workstation** (Mac or Linux)
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

- [**Application Management & Dashboard**](file:///Users/kiliandebock/Documents/GitHub/Cluster/docs/APP_MANAGEMENT_AND_DASHBOARD.md): Rapid container deployment, wildcard HTTP routing, and Headlamp dashboard.
- [**Secret Management & NAS Deployments**](file:///Users/kiliandebock/Documents/GitHub/Cluster/docs/SECRET_MANAGEMENT_AND_NAS.md): In-memory streaming, zero-disk secrets, and Mozilla SOPS alternative.
- [**Architecture & Security Blueprint**](file:///Users/kiliandebock/Documents/GitHub/Cluster/docs/ARCHITECTURE.md): Threat model, defense-in-depth, and control plane decoupling.
- [**Disaster Recovery Runbook**](file:///Users/kiliandebock/Documents/GitHub/Cluster/docs/DISASTER_RECOVERY.md): Rapid response guides for node compromise, server rebuilds, and total fleet recovery.
- [**Networking & Ingress Guide**](file:///Users/kiliandebock/Documents/GitHub/Cluster/docs/NETWORKING_AND_INGRESS.md): Cloudflare Tunnel integration, WireGuard overlay, and firewall policies.
- [**Storage Strategy**](file:///Users/kiliandebock/Documents/GitHub/Cluster/docs/STORAGE_STRATEGY.md): PostgreSQL 18 database partitioning, S3 object storage, and ephemeral local paths.
- [**Automated Updates & GitOps**](file:///Users/kiliandebock/Documents/GitHub/Cluster/docs/AUTOMATED_UPDATES_AND_GITOPS.md): Pull-based self-reconciliation, systemd sync timer, and GitHub Actions CI.






---

## 📄 License

MIT © [Lyttle Development](https://github.com/Lyttle-Development)
