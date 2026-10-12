# Storage Architecture & Persistence Strategy

This document outlines how persistent and ephemeral data are managed in this cluster according to the **External-First / Stateless Cattle** architecture.

---

## 1. Storage Taxonomy

| Data Category | Solution | Location | Persistence Guarantee |
| :--- | :--- | :--- | :--- |
| **K3s Control Plane** | Kine over PostgreSQL 18 | DigitalOcean Managed Database | High Availability, automatic backups |
| **Application Databases** | PostgreSQL 18 | DigitalOcean Managed Database | High Availability, automated daily snapshots |
| **Media, Files & Assets** | S3-Compatible Storage | Cloudflare R2 / DO Spaces / Backblaze B2 | Globally distributed, high durability |
| **Caches, Ephemeral Scratch** | K3s `local-path` PVs | Local Host VPS SSD | Ephemeral (wiped on node reset) |

---

## 2. DigitalOcean PostgreSQL 18 Configuration

### A. Kine Datastore Setup
Before bootstrapping the K3s server, create a dedicated database and user on your DigitalOcean PostgreSQL cluster:

1. **Database Name**: `k3s_cluster`
2. **User**: `k3s_admin` (or dedicated service account)
3. **Pool Mode**: Transaction or Session (direct connection to port `25060` with SSL enabled).

**Connection String Format**:
```
postgres://<username>:<password>@<do-cluster-host>.b.db.ondigitalocean.com:25060/k3s_cluster?sslmode=require
```

### B. Application Databases
For every app deployed on the cluster (e.g. Nextcloud, Ghost, custom web services):
- Create a dedicated database (e.g. `app_ghost`, `app_analytics`).
- Create dedicated least-privilege credentials.
- Store database credentials as Kubernetes Secrets in the application namespace:
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: app-db-credentials
type: Opaque
stringData:
  DATABASE_URL: "postgres://app_user:secret_pass@<do-host>:25060/app_ghost?sslmode=require"
```

---

## 3. Object Storage for Unstructured Files

Avoid mounting NFS or distributed file systems (Ceph/GlusterFS) over VPS block storage. Instead, configure applications to upload directly to S3-compatible object storage:
- **Cloudflare R2**: Zero egress fees, high performance, native integration with Cloudflare CDN.
- **DigitalOcean Spaces / Backblaze B2**: S3-compatible APIs for application backups and media storage.

---

## 4. Local Ephemeral Storage (`local-path`)

K3s includes the Rancher `local-path-provisioner` out-of-the-box.
Use this provisioner for:
- Redis / Memcached disk dumps (cache warm-up).
- Temporary build/transcoding directories.
- Prometheus time-series metrics buffers (configured with 7-14 day retention).

If a node crashes, Kubernetes automatically reschedules these stateless workloads on another healthy node with a fresh local volume.
