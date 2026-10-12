# Application Management, Dashboard & HTTP Routing

This guide explains how to deploy and manage containers with coupled domains and environment variables, how HTTP traffic is dynamically routed, and how to rebuild the entire application fleet in seconds.

---

## 1. How Dynamic HTTP Routing Works

In this cluster, you **never** need to manually add DNS records or update Cloudflare tunnel configurations every time you launch a new container.

### The Wildcard Tunnel Flow:
```
User visits: https://myapp.cluster.lyttle.dev
                    │
                    ▼
          [ Cloudflare Edge ]
         (Matches *.cluster.lyttle.dev)
                    │
                    ▼ (Single Outbound Tunnel)
          [ cloudflared Pod ]
                    │
                    ▼ (Forward to Ingress Controller)
          [ Traefik Ingress Controller ]
          (Reads Ingress rule: host == myapp.cluster.lyttle.dev)
                    │
                    ▼
          [ Service: myapp-service:8080 ]
                    │
                    ▼
          [ Pod: myapp-pod ]
```

### The Cloudflare Wildcard Rule (Set Once):
In your Cloudflare Zero Trust Tunnel configuration:
- **Public Hostname**: `*.cluster.lyttle.dev` (or `*.lyttle.dev`)
- **Service Type**: `HTTP`
- **URL**: `traefik.kube-system.svc.cluster.local:80`

Now, whenever an application defines an Ingress rule with `host: something.cluster.lyttle.dev`, Traefik handles it automatically in real time!

---

## 2. Managing Containers: Two Complementary Workflows

We provide two workflows designed to maximize deployment speed while guaranteeing rapid disaster recovery:

```
┌─────────────────────────────────────────────────────────────┐
│ Fast & Safe Deploy Flows                                    │
│                                                             │
│   Workflow A: Fast CLI Deployer                             │
│   ./scripts/deploy-app.sh                                   │
│    ├── Prompts/flags: Name, Image, Domain, Port, Envs       │
│    ├── Generates declarative manifest in apps/<name>/       │
│    └── Immediately applies to cluster & commits to Git      │
│                                                             │
│   Workflow B: Visual Web Dashboard (Headlamp)               │
│   https://dashboard.cluster.lyttle.dev                      │
│    ├── Real-time pod logs, live container terminal (exec)   │
│    ├── Visual CPU/Memory metrics per container              │
│    ├── One-click edits, scale replicas up/down              │
│    └── Zero-state (backed by Kubernetes API directly)       │
└─────────────────────────────────────────────────────────────┘
```

---

## 3. Workflow A: The Fast CLI Deployer (`deploy-app.sh`)

To deploy a new container in seconds, run:

> 📍 **Run on: Developer PC or Server VPS** (inside the `Cluster` repository)
```bash
# Non-interactive one-liner:
./scripts/deploy-app.sh \
  --name ghost-blog \
  --image ghost:5-alpine \
  --domain blog.cluster.lyttle.dev \
  --port 2368 \
  --env NODE_ENV=production \
  --env url=https://blog.cluster.lyttle.dev

# Or run interactively (it will prompt for inputs):
./scripts/deploy-app.sh
```

### What this does:
1. Generates a clean Kubernetes manifest bundle in `apps/ghost-blog/`.
2. Creates the **Deployment** (with unprivileged security context and resource limits).
3. Creates the **Service** (cluster-internal networking).
4. Creates the **Ingress** (configured for Traefik and your domain).
5. Applies the manifest directly via `kubectl apply -k apps/ghost-blog/`.
6. Prints the public URL ready to access.

---

## 4. Workflow B: Visual Web Dashboard (Headlamp)

[Headlamp](https://headlamp-k8s.github.io/headlamp/) is a modern, CNCF Kubernetes dashboard that replaces Portainer without Portainer's security vulnerabilities and database baggage.

### Key Benefits over Portainer:
1. **Completely Stateless**: Headlamp stores **zero local database**. It speaks directly to the Kubernetes API. If you rebuild your VPS cluster, Headlamp is immediately ready with zero database restores.
2. **Secure Access**: Deployed behind Cloudflare Tunnel at `https://dashboard.cluster.lyttle.dev` with an authenticated ServiceAccount token.
3. **Full Visibility**:
   - Stream container logs in real time.
   - Open interactive shell/terminal inside running containers.
   - Inspect environment variables, ingress routes, and resource usage.
   - Restart pods or edit deployments on the fly.

### Deploying the Dashboard:
> 📍 **Run on: Developer PC or Server VPS** (requires cluster access)
```bash
kubectl apply -f manifests/dashboard/headlamp.yaml

# Generate an admin access token:
./scripts/get-dashboard-token.sh
```

---

## 5. Instant Cluster Rebuild Guarantee

Because every application deployed via `deploy-app.sh` creates declarative files in `apps/`:

```
apps/
├── kustomization.yaml
├── ghost-blog/
│   └── app.yaml
├── whoami/
│   └── app.yaml
└── analytics/
    └── app.yaml
```

If your entire cluster is wiped, your disaster recovery command is:

1. **Bootstrap clean control plane node**:
   > 📍 **Run on: Fresh Server VPS** (via SSH or OVH console as `root`)
   ```bash
   curl -fsSL https://install.cluster.lyttle.dev | sudo bash -s -- --role server ...
   ```

2. **Re-apply all containers, environment variables & domains**:
   > 📍 **Run on: Developer PC or Server VPS** (inside the `Cluster` repository)
   ```bash
   kubectl apply -k apps/
   ```

**Every application, container, environment variable, ingress rule, and dashboard is immediately back online.**

