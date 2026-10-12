# Disaster Recovery & Node Rebuild Runbook

This runbook outlines the rapid recovery procedures if a node, control plane, or the entire VPS fleet is compromised or corrupted.

---

## The Recovery Guarantee

Because cluster state is decoupled from host storage:
- **K3s Control Plane State** is stored securely in Managed DigitalOcean PostgreSQL 18.
- **Application Databases** reside in Managed DigitalOcean PostgreSQL 18.
- **Persistent Files / Blobs** reside in S3 / R2 Object Storage.
- **Cluster Deployment Manifests** reside in this Git repository.

A complete rebuild of a compromised node or the entire cluster takes **under 5 minutes**.

---

## Scenario 1: A Worker Node is Suspect or Compromised

### Step 1: Drain and Delete from Cluster
> 📍 **Run on: Developer PC / Workstation** (using local `kubectl` inside `nix develop`)
```bash
# Mark node unschedulable and evict running pods
kubectl drain <node-name> --delete-emptydir-data --ignore-daemonsets --force

# Remove node from the cluster
kubectl delete node <node-name>
```

### Step 2: Nuke the Node
> 📍 **Run on: Compromised Worker VPS** (via SSH or OVH web console as `root`)
```bash
# Option A: Soft reset (Uninstall K3s, purge firewall, remove network interfaces)
sudo ./scripts/99-reset-node.sh --force

# Option B: Hard reset (Recommended during an active breach)
# Re-image the VPS from the OVH control panel to a clean Debian 13 installation.
```

### Step 3: Re-provision as a Worker Node
> 📍 **Run on: Clean Worker VPS** (via SSH or OVH console as `root`)
```bash
curl -fsSL https://raw.githubusercontent.com/Lyttle-Development/Cluster/main/scripts/bootstrap.sh | sudo bash -s -- \
  --role agent \
  --server-url https://<SERVER_IP>:6443 \
  --token <K3S_NODE_TOKEN>
```
The node automatically rejoins the WireGuard overlay network and begins receiving workloads.

---

## Scenario 2: The Control Plane (K3s Server) is Compromised

### Step 1: Nuke the Server VPS
Do not attempt forensic cleanup on a live compromised control-plane host.
Reinstall Debian 13 immediately via the OVH dashboard or re-image script.

### Step 2: Rotate the Database Password (Precautionary)
In the DigitalOcean console:
1. Rotate the PostgreSQL user password used for the Kine datastore connection string.
2. Ensure SSL mode is set to `require` (`sslmode=require`).

### Step 3: Bootstrap a Fresh Server Node
> 📍 **Run on: Fresh Server VPS** (via SSH or OVH console as `root`)
```bash
curl -fsSL https://raw.githubusercontent.com/Lyttle-Development/Cluster/main/scripts/bootstrap.sh | sudo bash -s -- \
  --role server \
  --datastore-endpoint "postgres://k3s_user:NEW_PASSWORD@db-postgresql-nyc1-do-user-123.b.db.ondigitalocean.com:25060/k3s_cluster?sslmode=require" \
  --token <NEW_OR_EXISTING_K3S_NODE_TOKEN> \
  --cf-token <CLOUDFLARE_TUNNEL_TOKEN>
```

### Result:
- K3s boots up and attaches to the existing PostgreSQL table.
- All deployments, services, namespaces, secrets, and configs are immediately recognized.
- Cloudflare Tunnel reconnects to the Cloudflare edge; public traffic resumes immediately.
- Worker nodes reconnect to the control plane. Total downtime: the time it took to reinstall Debian and run the script (~3-5 minutes).

---

## Scenario 3: Complete Fleet Loss (All VPSs Compromised)

1. Re-image all VPS instances in OVH to fresh Debian 13.
2. In DigitalOcean, create a point-in-time restore of the PostgreSQL database if data tampering is suspected.
3. Boot Server Node 1:
   > 📍 **Run on: Fresh Server VPS** (via SSH or OVH console as `root`)
   ```bash
   curl -fsSL https://raw.githubusercontent.com/Lyttle-Development/Cluster/main/scripts/bootstrap.sh | sudo bash -s -- \
     --role server \
     --datastore-endpoint "<DO_PG_URL>" \
     --token "<CLUSTER_TOKEN>" \
     --cf-token "<CLOUDFLARE_TUNNEL_TOKEN>"
   ```
4. Boot Agent Nodes:
   > 📍 **Run on: Each Fresh Agent VPS** (via SSH or OVH console as `root`)
   ```bash
   curl -fsSL https://raw.githubusercontent.com/Lyttle-Development/Cluster/main/scripts/bootstrap.sh | sudo bash -s -- \
     --role agent \
     --server-url "https://<SERVER_IP>:6443" \
     --token "<CLUSTER_TOKEN>"
   ```
5. Apply cluster workloads from this Git repository:
   > 📍 **Run on: Developer PC or Server VPS** (inside the `Cluster` repository)
   ```bash
   kubectl apply -k apps/
   ```
6. Restore NAS-backed private apps and secrets (if applicable):
   > 📍 **Run on: Developer PC** (where your encrypted NAS is mounted)
   ```bash
   ./scripts/deploy-from-nas.sh --source /Volumes/NAS/cluster-apps --server <SERVER_IP>
   ```

