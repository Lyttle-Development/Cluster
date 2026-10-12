# Application Management, Web Dashboard & HTTP Routing

This guide details how containerized applications are deployed, managed, and monitored on the Lyttle Cluster. It covers dynamic HTTP routing via Traefik and Cloudflare, deploying ready-to-use private application fleets from an encrypted local NAS, inspecting containers with the stateless Headlamp dashboard, and instant fleet rebuilds during disaster recovery.

---

## 1. How Dynamic HTTP Routing Works

In this cluster, you **never** need to manually configure DNS records or create new Cloudflare tunnel routes when launching a container.

### The Wildcard Tunnel Flow:
```
User visits: https://myapp.cluster.lyttle.dev
                    │
                    ▼
          [ Cloudflare Edge ]
         (Matches *.cluster.lyttle.dev)
                    │
                    ▼ (Single Outbound Tunnel Connection)
          [ cloudflared Pod ]
                    │
                    ▼ (Internal Forward to Ingress Controller)
          [ Traefik Ingress Controller ]
          (Matches Ingress rule: host == myapp.cluster.lyttle.dev)
                    │
                    ▼
          [ Service: myapp-service:8080 ]
                    │
                    ▼
          [ Pod: myapp-pod ]
```

### The Cloudflare Wildcard Rule (Configured Once):
In your Cloudflare Zero Trust Tunnel configuration:
- **Public Hostname**: `*.cluster.lyttle.dev` (or `*.lyttle.dev`)
- **Service Type**: `HTTP`
- **URL**: `traefik.kube-system.svc.cluster.local:80`

Whenever an application manifest defines a standard Ingress rule matching `host: <subdomain>.cluster.lyttle.dev`, Traefik automatically discovers and serves it with TLS termination handled seamlessly at Cloudflare's edge.

---

## 2. Managing Containers: Three Integrated Workflows

We provide three complementary workflows to manage applications with maximum speed, zero-trust security, and rapid recovery:

```
┌─────────────────────────────────────────────────────────────────────────┐
│ Application Management Workflows                                        │
│                                                                         │
│   Workflow A: Encrypted NAS Deployer (Primary / Production Fleet)       │
│   ./scripts/deploy-from-nas.sh                                          │
│    ├── Source: /Volumes/NAS/cluster-apps/<app-name>/app.yaml            │
│    ├── Streams manifests & secrets directly into Kubernetes RAM over SSH│
│    ├── Zero disk footprint: no plain-text secrets ever touch VPS disk   │
│    └── Instant restore: redeploy the entire fleet in 10 seconds         │
│                                                                         │
│   Workflow B: Visual Web Dashboard (Headlamp)                           │
│   https://dashboard.cluster.lyttle.dev                                  │
│    ├── Replaces Portainer with a 100% stateless Kubernetes dashboard   │
│    ├── Real-time pod logs, live container terminal (exec)               │
│    ├── Visual CPU/Memory metrics per container                          │
│    └── Zero local database (direct Kubernetes API client)               │
│                                                                         │
│   Workflow C: Local CLI Scaffolder (Quick Prototyping)                  │
│   ./scripts/deploy-app.sh                                               │
│    ├── Fast helper to scaffold standard Kubernetes manifests            │
│    └── Generates declarative bundle in apps/<name>/app.yaml             │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Workflow A: Deploying from your Encrypted NAS (Primary Workflow)

The golden standard for running production applications in this cluster is **NAS-backed in-memory streaming**.

Your production application definitions, private environment variables, and database credentials reside securely on your local encrypted NAS (e.g. `/Volumes/NAS/cluster-apps/`).

Manifests are authored as self-contained bundles following the [AI Agent Application Specification](APP_SPEC_FOR_AGENTS.md).

### NAS Application Directory Layout:
```
/Volumes/NAS/cluster-apps/
├── ghost-blog/
│   └── app.yaml          # Deployment, Service, Ingress, Secrets for Ghost
├── analytics/
│   └── app.yaml          # Plausible / Umami analytics suite
├── home-assistant/
│   └── app.yaml          # Smart home bridge
└── personal-api/
    └── app.yaml          # Custom backend services
```

### Deploy a Single Application from NAS:
> 📍 **Run on: Developer PC** (where your NAS is mounted)
```bash
./scripts/deploy-from-nas.sh \
  --source /Volumes/NAS/cluster-apps/ghost-blog \
  --server <YOUR_SERVER_IP>
```

### Deploy / Sync All Applications Across your Fleet:
> 📍 **Run on: Developer PC** (where your NAS is mounted)
```bash
./scripts/deploy-from-nas.sh \
  --source /Volumes/NAS/cluster-apps \
  --server <YOUR_SERVER_IP>
```

*(If you have `kubectl` configured locally with the cluster's kubeconfig, you can pass `--local` instead of `--server <IP>`).*

### Under the Hood: Zero VPS Disk Footprint
1. `deploy-from-nas.sh` reads your `.yaml` manifests from the encrypted local volume.
2. It concatenates the manifests into an in-memory stream piped across an encrypted SSH tunnel.
3. The stream feeds directly into `/usr/local/bin/kubectl apply -f -` executing in RAM on the server.
4. Kubernetes parses the objects in RAM and writes secrets over TLS to **Managed DigitalOcean PostgreSQL 18**.
5. **No plain-text credentials, environment files, or YAML manifests are ever written to the VPS disk.** Even if a VPS host is forensically inspected, zero secrets exist on its drive.

---

## 4. Workflow B: Visual Web Dashboard (Headlamp)

[Headlamp](https://headlamp-k8s.github.io/headlamp/) provides an intuitive web interface for managing containers, replacing Portainer.

### Why Headlamp Over Portainer?
- **100% Stateless**: Portainer requires persistent disk volumes and internal SQLite/Bolt databases that corrupt or get lost when VPSes are wiped. Headlamp stores **zero state**; it queries the Kubernetes API directly.
- **Hardened & Lightweight**: Headlamp runs in an unprivileged container with read-only root filesystems and minimal resource overhead.
- **Protected by Cloudflare**: Exposed securely at `https://dashboard.cluster.lyttle.dev` via Cloudflare Tunnel.

### Accessing the Dashboard:
1. Retrieve your admin authentication token:
   > 📍 **Run on: Developer PC or Server VPS** (requires cluster access)
   ```bash
   ./scripts/get-dashboard-token.sh
   ```
2. Navigate to **`https://dashboard.cluster.lyttle.dev`**.
3. Paste the generated token into the login prompt.

### Daily Operations in Headlamp:
- **Stream Live Logs**: Click any pod or deployment to view colorized, real-time stdout/stderr streams.
- **Interactive Container Terminal**: Click the **Terminal** icon on any running container to execute a bash/sh shell directly in the browser (like `docker exec`).
- **Real-Time Resource Metrics**: Monitor CPU and Memory usage graphs per pod.
- **Restart or Scale**: Restart problematic pods or scale replicas up/down with one click.
- **Inspect Configuration**: View running environment variables, ingress hostnames, and secrets.

---

## 5. Workflow C: Fast CLI Application Scaffolder (`deploy-app.sh`)

When you want to quickly test a new Docker image, experiment with a tool, or commit an open-source public service into this Git repository, use `./scripts/deploy-app.sh`.

### CLI Usage:
> 📍 **Run on: Developer PC or Server VPS** (inside the `Cluster` repository)
```bash
# Non-interactive one-liner:
./scripts/deploy-app.sh \
  --name my-service \
  --image nginx:alpine \
  --domain my-service.cluster.lyttle.dev \
  --port 80 \
  --env NODE_ENV=production

# Or run interactively (prompts for missing parameters):
./scripts/deploy-app.sh
```

### What this does:
1. Scaffolds a Kubernetes bundle in `apps/my-service/app.yaml`.
2. Creates the **Deployment** (with unprivileged security context and resource limits).
3. Creates the **Service** (`ClusterIP`) on the specified internal port.
4. Creates the **Ingress** configured for Traefik and your domain.
5. Applies the manifest directly to the cluster.
6. Prints the public URL ready for access.

---

## 6. Instant Fleet Rebuild Guarantee (Disaster Recovery in 10 Seconds)

Because all state is externalized to Managed PostgreSQL and application definitions are stored declaratively on your encrypted NAS, restoring the entire cluster after a total wipe is trivial:

### Step 1: Bootstrap a Fresh Server VPS (2 Minutes)
> 📍 **Run on: Fresh Server VPS** (via SSH or OVH console as `root`)
```bash
curl -fsSL https://raw.githubusercontent.com/Lyttle-Development/Cluster/main/scripts/bootstrap.sh | sudo bash -s -- \
  --role server \
  --datastore-endpoint "<DO_POSTGRESQL_CONNECTION_STRING>" \
  --cf-token "<CLOUDFLARE_TUNNEL_TOKEN>"
```

### Step 2: Restore All Production Applications from NAS (10 Seconds)
> 📍 **Run on: Developer PC** (where your NAS is mounted)
```bash
./scripts/deploy-from-nas.sh \
  --source /Volumes/NAS/cluster-apps \
  --server <NEW_SERVER_IP>
```

### Step 3 (Optional): Restore Public Git Workloads
> 📍 **Run on: Developer PC or Server VPS** (inside the `Cluster` repository)
```bash
kubectl apply -k apps/
```

**Every container, environment variable, database connection, Traefik ingress route, and dashboard is immediately back online.**
