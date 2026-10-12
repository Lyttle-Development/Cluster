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

## 📚 Documentation Directory & Navigation Hub

Use this index to quickly locate documentation, understand which approach is **(Recommended)**, and find what you need based on what you are trying to do:

| Document | Recommendation Status | What You Will Find There | When to Use |
| :--- | :--- | :--- | :--- |
| [**`docs/APP_SPEC_FOR_AGENTS.md`**](docs/APP_SPEC_FOR_AGENTS.md) | ⭐ **Recommended (Golden Standard)** | AI agent system prompt & rules to generate single-file `app.yaml` bundles (Traefik Ingress, non-root security context, Managed PostgreSQL TLS, resource limits). | Feed to Claude, ChatGPT, or coding agents when generating new application deployments for your NAS. |
| [**`docs/SECRET_MANAGEMENT_AND_NAS.md`**](docs/SECRET_MANAGEMENT_AND_NAS.md) | ⭐ **Recommended (Primary Fleet Flow)** | Explains in-memory SSH streaming (`deploy-from-nas.sh`), keeping secrets off the VPS filesystem, and the Mozilla SOPS + Age GitOps alternative. | Setting up or updating private production credentials and understanding the zero-disk footprint architecture. |
| [**`docs/APP_MANAGEMENT_AND_DASHBOARD.md`**](docs/APP_MANAGEMENT_AND_DASHBOARD.md) | ⭐ **Recommended (App Lifecycle)** | Comprehensive guide for the 3 deployment workflows: NAS Deployer (Primary), Headlamp Web Dashboard (Portainer replacement), and CLI scaffolder. Details dynamic wildcard HTTP routing. | Deploying apps, streaming logs, opening live container terminals, and managing routes. |
| [**`docs/DISASTER_RECOVERY.md`**](docs/DISASTER_RECOVERY.md) | ⭐ **Recommended (Incident Runbook)** | Rapid step-by-step recovery playbooks (<5 min rebuild): individual worker node compromise, server control-plane rebuild, and total fleet loss. | An active security breach, node failure, or scheduled cluster wipe and re-provisioning. |
| [**`docs/STORAGE_STRATEGY.md`**](docs/STORAGE_STRATEGY.md) | ⭐ **Recommended (Storage Pattern)** | Explains the stateless cattle architecture: Managed PostgreSQL 18 for databases, Cloudflare R2 / S3 for files/blobs, and ephemeral local caching. | Planning application state, avoiding stateful database pods on VPS disks, or configuring S3 uploads. |
| [**`docs/ARCHITECTURE.md`**](docs/ARCHITECTURE.md) | 📖 **Architecture Blueprint** | Detailed threat modeling, defense-in-depth principles, Swarm vs K3s comparison, and external Kine PostgreSQL datastore architecture. | Understanding why the cluster is designed this way and evaluating security guarantees. |
| [**`docs/NETWORKING_AND_INGRESS.md`**](docs/NETWORKING_AND_INGRESS.md) | 📖 **Network Reference** | Zero-open-port ingress architecture with Cloudflare Tunnel (`cloudflared`), Traefik ingress controller, WireGuard-native overlay mesh, and UFW firewall rules. | Network debugging, configuring DNS/tunnels, or auditing open ports. |
| [**`docs/AUTOMATED_UPDATES_AND_GITOPS.md`**](docs/AUTOMATED_UPDATES_AND_GITOPS.md) | ⚙️ **Automation & GitOps** | Pull-based self-healing via `cluster-sync.timer` (systemd periodic pull every 30m), GitHub Actions CI linting, and automated Dependabot updates. | Configuring automated updates, maintaining cluster parity, or customizing the sync timer. |

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

The primary workflow for this cluster is **NAS-Backed Private Applications**: your production apps, secrets, and environment configurations live safely on your encrypted local NAS. You stream them in-memory to the cluster with zero disk footprint on the VPS.

### 1. Deploying Apps from your Encrypted NAS (Primary Workflow)
Your apps are stored on your local NAS (e.g. `/Volumes/NAS/cluster-apps/<app-name>/app.yaml`), formatted using the [AI Agent Application Specification](docs/APP_SPEC_FOR_AGENTS.md).

#### Deploy a Single Application from NAS:
> 📍 **Run on: Developer PC** (where your NAS is mounted)
```bash
./scripts/deploy-from-nas.sh \
  --source /Volumes/NAS/cluster-apps/ghost-blog \
  --server <YOUR_SERVER_IP>
```

#### Deploy / Sync All Applications Across your NAS Fleet:
> 📍 **Run on: Developer PC** (where your NAS is mounted)
```bash
./scripts/deploy-from-nas.sh \
  --source /Volumes/NAS/cluster-apps \
  --server <YOUR_SERVER_IP>
```
- **Zero Disk Footprint**: Streams manifests directly into Kubernetes RAM over SSH. No plain-text files or secrets ever touch the VPS disk.
- **Dynamic Routing**: Traefik automatically routes each app's domain (e.g. `blog.cluster.lyttle.dev`) through your Cloudflare wildcard tunnel.
- **Database Integrated**: Apps connect to your Managed DigitalOcean PostgreSQL 18 via TLS.

---

### 2. Instant Fleet Rebuild (Disaster Recovery in 10 Seconds)
If you wipe or rebuild your cluster, restore your entire production application fleet with a single command from your workstation:
> 📍 **Run on: Developer PC** (where your NAS is mounted)
```bash
./scripts/deploy-from-nas.sh --source /Volumes/NAS/cluster-apps --server <NEW_SERVER_IP>
```
*(Or for public repo apps: `kubectl apply -k apps/`).*

---

### 3. Visual Web Dashboard (Headlamp)
Replace Portainer with a **stateless, secure Kubernetes dashboard** pre-installed during server bootstrap:
> 📍 **Run on: Developer PC or Server VPS** (requires cluster access)
```bash
# Get your admin login token
./scripts/get-dashboard-token.sh
```
- Open **`https://dashboard.cluster.lyttle.dev`** and log in with your token.
- Inspect container metrics, stream logs, open in-container interactive terminals, and restart pods.

---

### 4. Fast CLI Manifest Scaffolder (`./scripts/deploy-app.sh`)
Helper script to quickly scaffold a new application bundle or test deployments:
> 📍 **Run on: Developer PC or Server VPS** (inside the `Cluster` repository)
```bash
./scripts/deploy-app.sh \
  --name my-service \
  --image nginx:alpine \
  --domain my-service.cluster.lyttle.dev \
  --port 80 \
  --env NODE_ENV=production
```
- Generates `apps/<name>/app.yaml` following the standard bundle format.

---

## 🧩 KISS Modular Scripts

Instead of a monolithic black-box, each step is an independent script inside [`scripts/`](scripts):

| Script | Purpose |
| :--- | :--- |
| [`scripts/01-system-prep.sh`](scripts/01-system-prep.sh) | Base packages, disable swap, kernel modules (`overlay`, `br_netfilter`, `wireguard`), sysctl hardening, `unattended-upgrades`, `fail2ban`. |
| [`scripts/02-firewall-hardening.sh`](scripts/02-firewall-hardening.sh) | UFW setup: default drop inbound, rate-limited SSH, allows WireGuard 51820/udp & K3s 6443/tcp. **Keeps 80 & 443 closed to public**. |
| [`scripts/03-install-k3s-server.sh`](scripts/03-install-k3s-server.sh) | K3s control-plane with external PostgreSQL datastore (Kine), native WireGuard flannel, and generated credentials. |
| [`scripts/04-install-k3s-agent.sh`](scripts/04-install-k3s-agent.sh) | Joins worker node to the K3s cluster. |
| [`scripts/05-deploy-cloudflared.sh`](scripts/05-deploy-cloudflared.sh) | Deploys Cloudflare Tunnel agent inside cluster (least-privilege non-root container with read-only rootfs). |
| [`scripts/06-deploy-dashboard.sh`](scripts/06-deploy-dashboard.sh) | Deploys Headlamp web dashboard, generates token, and saves it to `/etc/headlamp-admin-token.txt`. |
| [`scripts/07-setup-auto-sync.sh`](scripts/07-setup-auto-sync.sh) | Installs systemd timer and service to run `sync-node.sh` periodically (default: 30 min). |
| [`scripts/sync-node.sh`](scripts/sync-node.sh) | Pulls Git updates, reconciles applications, and reapplies firewall/sysctl baseline. |
| [`scripts/deploy-app.sh`](scripts/deploy-app.sh) | Fast interactive/CLI container deployer: configures image, envs, domain, and Traefik ingress in `apps/`. |
| [`scripts/deploy-from-nas.sh`](scripts/deploy-from-nas.sh) | Streams private NAS manifests/secrets directly into Kubernetes RAM (zero disk trace on VPS). |
| [`scripts/get-dashboard-token.sh`](scripts/get-dashboard-token.sh) | Generates admin authentication token for the Headlamp web dashboard. |
| [`scripts/99-reset-node.sh`](scripts/99-reset-node.sh) | Complete node wipe: uninstalls K3s, unmounts container storage, removes virtual interfaces, resets firewall safely. |
| [`scripts/provision-node.sh`](scripts/provision-node.sh) | Orchestrates remote VPS setup from Developer PC over SSH: handles reboots, user migration, and kubeconfig sync. |
| [`scripts/bootstrap.sh`](scripts/bootstrap.sh) | Unified master orchestrator supporting both local host runs and `--target <vps-ip>` remote runs. |

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

## 📖 Documentation Deep Dives & Topic Guides

For detailed architectural justifications, complete configurations, and operational workflows, explore each topic guide:

### Application & Deployment Guides
- [**`docs/APP_SPEC_FOR_AGENTS.md`**](docs/APP_SPEC_FOR_AGENTS.md) — **AI Agent Application Specification (Recommended)**  
  The golden standard system prompt and reference manifest for AI coding agents to create clean, single-file `app.yaml` bundles ready to save onto your encrypted NAS and stream to the cluster.
- [**`docs/SECRET_MANAGEMENT_AND_NAS.md`**](docs/SECRET_MANAGEMENT_AND_NAS.md) — **Secret Management & NAS Workflows (Recommended)**  
  In-depth explanation of zero-disk-footprint secrets, in-memory SSH streaming (`deploy-from-nas.sh`), direct PostgreSQL TLS storage, and the Mozilla SOPS + Age encrypted GitOps alternative.
- [**`docs/APP_MANAGEMENT_AND_DASHBOARD.md`**](docs/APP_MANAGEMENT_AND_DASHBOARD.md) — **Application Lifecycle & Dashboard (Recommended)**  
  Details the 3 application workflows (NAS deployment, Headlamp UI, CLI scaffolder), dynamic wildcard HTTP routing via Cloudflare Tunnels, and instant fleet rebuilds.

### Reliability & Infrastructure Guides
- [**`docs/DISASTER_RECOVERY.md`**](docs/DISASTER_RECOVERY.md) — **Disaster Recovery & Node Rebuilds (Recommended Runbook)**  
  Step-by-step incident response runbooks to wipe and rebuild compromised worker nodes, recover from control-plane losses, or re-provision the entire cluster in under 5 minutes.
- [**`docs/STORAGE_STRATEGY.md`**](docs/STORAGE_STRATEGY.md) — **Storage Strategy & Stateless Cattle (Recommended Pattern)**  
  Detailed rationale for the 3-tier storage architecture: Managed DigitalOcean PostgreSQL 18 for relational data, Cloudflare R2 / S3 for media and files, and ephemeral local caching.
- [**`docs/ARCHITECTURE.md`**](docs/ARCHITECTURE.md) — **Architecture & Security Blueprint (Reference)**  
  Complete threat modeling, defense-in-depth principles, Swarm vs K3s comparison, breach isolation, and external Kine PostgreSQL datastore mechanics.
- [**`docs/NETWORKING_AND_INGRESS.md`**](docs/NETWORKING_AND_INGRESS.md) — **Networking & Ingress Guide (Reference)**  
  Comprehensive network blueprint: zero inbound open ports on host VPS, Cloudflare Tunnel wildcard ingress, Traefik routing, WireGuard mesh, and strict UFW policies.
- [**`docs/AUTOMATED_UPDATES_AND_GITOPS.md`**](docs/AUTOMATED_UPDATES_AND_GITOPS.md) — **Automated Updates & GitOps Loop (Reference)**  
  Pull-based self-healing systemd timer (`cluster-sync.timer`), automatic repository reconciliation every 30 minutes, GitHub Actions CI validation, and Dependabot security updates.

---

## 📄 License

MIT © [Lyttle Development](https://github.com/Lyttle-Development)
