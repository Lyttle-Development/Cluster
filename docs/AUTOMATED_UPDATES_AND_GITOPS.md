# Automated Updates, GitOps & Fleet Self-Reconciliation

This document explains the automated update loop, pull-based GitOps architecture, and CI pipeline that keeps the cluster secure, up-to-date, and self-healing.

---

## 1. The Pull-Based GitOps Loop

Traditional CI/CD pipelines use "push-based" deployment: GitHub Actions connects directly into a Kubernetes cluster via `kubectl`.

### Why Push-Based Deployment is Dangerous for Hardened Clusters:
1. **Firewall Holes**: The cluster would have to expose its Kubernetes API server (`6443`) to the public internet so GitHub Actions runners can reach it.
2. **Credential Risk**: A long-lived, high-privilege cluster admin credential (`kubeconfig`) must be stored in GitHub Secrets. If GitHub or an action is breached, the entire cluster is compromised.

### The Pull-Based Solution:
```
  Developer / CI
        │
        ▼ (git push main)
 [ GitHub Repository ]
        ▲
        │  (Outbound HTTPS git fetch every 30 mins)
        │  [Zero Inbound Ports on VPS]
 ┌──────┴──────────────────────────────────────┐
 │ Each Cluster Node                           │
 │                                             │
 │  [ cluster-sync.timer (systemd) ]           │
 │       │                                     │
 │       ▼                                     │
 │  [ scripts/sync-node.sh ]                   │
 │       ├── git pull origin main              │
 │       ├── Re-apply sysctl & firewall rules  │
 │       └── (Server node) kubectl apply apps/ │
 └─────────────────────────────────────────────┘
```

---

## 2. What Happens During Auto-Sync (`sync-node.sh`)

Every 30 minutes (configurable via `SYNC_INTERVAL`), the systemd service on each node runs:

1. **Remote Drift Check**:
   Fetches `origin/main` without changing local files. If commit hashes match, the script exits immediately with zero overhead.
2. **Repository Update**:
   Pulls the latest code and scripts from `origin/main`.
3. **Host Security Re-enforcement**:
   Re-runs `01-system-prep.sh` and `02-firewall-hardening.sh`. This ensures:
   - Any manual changes to firewall rules are reverted.
   - Any new sysctl security parameters added in Git are immediately applied across all nodes.
4. **Kubernetes Fleet Reconciliation (Server Nodes)**:
   Runs `kubectl apply -k apps/`.
   - New applications added to `apps/` are automatically scheduled.
   - Domain updates, environment variable edits, or image tag bumps are rolled out automatically with zero downtime.

---

## 3. GitHub Actions CI & Quality Gates

Before any change reaches the cluster, GitHub Actions validates the codebase:

- **Lint Shell Scripts** (`.github/workflows/ci.yml`):
  - Checks syntax (`bash -n`) across all scripts.
  - Runs `shellcheck -x` to prevent shell scripting errors, unbound variables, or unsafe expansions.
- **Validate Kubernetes Manifests**:
  - Validates `kustomize build apps/` to ensure no broken YAML or invalid kustomization configurations are merged.

---

## 4. Automated Dependency Bumping (Dependabot)

Configured via `.github/dependabot.yml`:
- Scans GitHub Actions workflow actions weekly and opens PRs for version upgrades.
- Can be paired with [Renovate Bot](https://docs.renovatebot.com/) to automatically scan container image tags (e.g. `headlamp`, `traefik`, `cloudflared`) and open PRs whenever upstream releases security patches.
