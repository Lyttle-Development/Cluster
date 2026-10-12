# Cluster Architecture & Security Blueprint

This document details the architectural decisions, threat model, security posture, and disaster recovery strategy for the Kubernetes cluster running on OVH Debian 13 VPS nodes.

---

## 1. Architectural Philosophy: The Stateless Cattle Model

### Why the Previous Setup (Docker Swarm + Portainer) Was Vulnerable
1. **Exposed Attack Surfaces**:
   - Docker daemon ports (`2375`/`2376`) or the Portainer management web UI exposed to the public internet.
   - Docker by default bypasses the host firewall (`UFW`) by injecting `iptables` rules directly into the `PREROUTING` chain. Services bound to `0.0.0.0` become reachable even if UFW blocks them.
2. **State Coupled to Compromised Nodes**:
   - Workloads writing state (databases, config files, volumes) directly to local node disks. Once an attacker obtains persistence or ransomware hits a node, the data and control plane are hostage.
3. **No Centralized Ephemeral Lifecycle**:
   - Recovering from an intrusion required manual forensics and rebuilds of individual containers and databases.

### The New Architecture: Zero-Trust & Decoupled State
```
               [ Public Internet ]
                        │
                        ▼
            [ Cloudflare Edge / WAF ]
          (DDoS protection, Edge TLS)
                        │
                        │  (Secure Outbound Tunnel - QUIC/HTTP2)
                        │  [Zero Inbound Ports on VPS]
                        ▼
      ┌──────────────────────────────────────────────┐
      │  OVH Debian 13 VPS Fleet                     │
      │                                              │
      │   ┌──────────────────────────────────────┐   │
      │   │ K3s Server Node (Stateless)          │   │
      │   │  ├── cloudflared (Tunnel Agent)      │   │
      │   │  ├── Traefik Ingress Controller       │   │
      │   │  └── K3s Control Plane (via Kine)    │   │
      │   └──────────────────┬───────────────────┘   │
      │                      │ Encrypted WireGuard   │
      │   ┌──────────────────┴───────────────────┐   │
      │   │ K3s Agent / Worker Node(s)           │   │
      │   │  ├── Workload Pods (Stateless)       │   │
      │   │  └── Local Cache / Scratch (Ephemeral) │
      │   └──────────────────────────────────────┘   │
      └──────────────────────┬───────────────────────┘
                             │
            TLS Encrypted    │ (Outbound to DB)
                             ▼
             ┌────────────────────────────────┐
             │ Managed DigitalOcean PG 18     │
             │  ├── Kine Datastore (K3s state)│
             │  └── Application Databases     │
             └────────────────────────────────┘
                             │
                             ▼
             ┌────────────────────────────────┐
             │ Object Storage (S3 / R2)       │
             │  ├── Media & Persistent Files  │
             │  └── Cluster Backup Snapshots  │
             └────────────────────────────────┘
```

---

## 2. Core Decisions & Rationale

### A. Control Plane Datastore: External PostgreSQL 18 via Kine
- **Decision**: Run K3s with `--datastore-endpoint` pointing to the external managed DigitalOcean PostgreSQL 18 instance.
- **Why**:
  - Traditional Kubernetes relies on an internal `etcd` cluster requiring quorum (3+ nodes) and low disk latency. If a VPS crashes or gets wiped, recovering etcd quorum can be complex.
  - K3s includes **Kine** (Kine is not etcd), an etcd-to-SQL translation layer.
  - **Total node decoupling**: All Kubernetes API resources, secrets, deployments, and cluster definitions reside safely in DO Managed PostgreSQL.
  - **Disaster Recovery**: If any or all VPSs are compromised, wipe them immediately. Booting a new K3s server pointing to the same database restores the entire cluster state within seconds.

### B. Ingress & Perimeter Defense: Cloudflare Tunnels (`cloudflared`)
- **Decision**: Inbound web traffic is routed strictly through Cloudflare Tunnels into the internal Ingress controller.
- **Why**:
  - **Zero Open Inbound Ports**: The host firewall (`UFW`) completely blocks inbound ports `80`, `443`, and `6443` on the public IP.
  - Outbound connection only: `cloudflared` initiates outbound connections over QUIC/HTTP2 to the nearest Cloudflare edge.
  - The public internet has **zero direct TCP access** to the VPS IP addresses.
  - Immunity to port scanners (Shodan, Censys), direct-to-IP DDoS, and zero-day HTTP exploits hitting the raw host kernel.
  - SSH access is restricted to a dedicated VPN / allowlisted management IP.

### C. Persistent Storage: External-First Architecture
- **Decision**: Workloads do not store critical durable data on VPS disks.
  - **Relational Data**: DigitalOcean Managed PostgreSQL 18.
  - **File / Blob Data**: S3-compatible Object Storage (e.g. Cloudflare R2, Backblaze B2, DigitalOcean Spaces).
  - **Local PVs**: Utilizes K3s's built-in `local-path-provisioner` exclusively for ephemeral workloads (Redis caches, Prometheus metrics ring buffers, temporary build artifacts).
- **Why**:
  - Eliminates the operational complexity, CPU overhead, and split-brain risks of distributed storage engines (Longhorn, Ceph/Rook).
  - Nodes remain 100% disposable "cattle".

### D. East-West Networking: In-Kernel WireGuard Overlay
- **Decision**: Configure K3s Flannel backend with `wireguard-native`.
- **Why**:
  - Debian 13 includes Linux 6.x with WireGuard built directly into the kernel.
  - All pod-to-pod and node-to-node traffic across VPS instances is encrypted end-to-end automatically with negligible CPU overhead.

### E. Node OS & Nix Integration: Pragmatic Separation
- **Decision**:
  - **VPS OS**: Clean, minimal Debian 13 (Trixie). Rock-solid, native OVH kernel and network support.
  - **Nix**: Used on the administrator/developer machine via a Nix Flake (`flake.nix`) to provide a fully reproducible devshell containing all operational tools (`kubectl`, `helm`, `sops`, `age`, `cloudflared`, `jq`, `yq`).
- **Why**:
  - Avoids brittle in-place OS conversions (`nixos-infect`) on cloud VPSs where network boot and cloud-init can fail during provider updates.
  - Gives complete reproducibility where it matters most: the deployment toolchain.

---

## 3. Defense-in-Depth Checklist on Debian 13

1. **Firewall (UFW / nftables)**:
   - Default Incoming: `DROP`
   - Default Outgoing: `ALLOW`
   - Allowed Inbound: Only SSH on a custom port or allowlisted IP.
   - Ports `80`, `443`, `6443` are **blocked** from public interfaces.
2. **SSH Hardening**:
   - `PasswordAuthentication no`
   - `PermitRootLogin prohibit-password` (ed25519 keys only)
   - MaxAuthTries 3
3. **Kernel Hardening (`/etc/sysctl.d/99-kubernetes-security.conf`)**:
   - Disable IP packet forwarding across untrusted interfaces.
   - Enable SYN cookies to prevent SYN flood DoS.
   - Disable ICMP redirect acceptance.
   - Ignore bogus ICMP responses.
4. **Automated Security Updates**:
   - `unattended-upgrades` enabled for Debian security channels.
5. **User Management & Default Provider Account Hardening**:
   - Cloud providers (OVH) provision images with predictable default accounts (e.g. `debian`). Automated bots continuously target these known names.
   - The provisioning scripts automatically establish a custom administrative account (default: `server`), migrate authorized SSH keys, and grant passwordless `sudo`.
   - The default `debian` account password is locked (`passwd -l debian`), eliminating credential brute-forcing against standard provider usernames.

