# Secret Management & NAS-Backed Private App Deployments

This guide details how production applications containing sensitive credentials (database passwords, API keys, certificates) are securely deployed to the cluster **without ever writing unencrypted secrets to the VPS filesystem**, and how to restore them instantly during disaster recovery.

---

## 1. Where Do Secrets Actually Live in Kubernetes?

When you run `kubectl apply -f secret.yaml`:
1. Kubernetes does **not** save the `.yaml` file to the node's disk.
2. The YAML is parsed **in memory (RAM)**.
3. The secret payload is written directly to the cluster control plane datastore.
4. In our architecture, the datastore is your **Managed DigitalOcean PostgreSQL 18** database over an encrypted TLS connection (`sslmode=require`).

Therefore, if we avoid copying `.yaml` files onto the VPS disk in the first place, **zero plain-text secrets ever touch the VPS storage**.

---

## 2. The In-Memory Streaming Pattern (`deploy-from-nas.sh`)

Instead of the insecure pattern:
> ❌ *SCP files to VPS disk ➔ `kubectl apply` ➔ `rm -f file` (Leaves unlinked inode traces and risk of exposure)*

We use an **in-memory standard input pipe over SSH**:
> ✅ *Read from encrypted NAS ➔ Pipe over encrypted SSH ➔ Stream straight into `kubectl apply -f -` in RAM*

```
  [ Your Workstation / NAS ]
  Encrypted Local Disk (/Volumes/NAS/apps)
             │
             │ (Encrypted SSH Tunnel - Port 22)
             ▼
  [ OVH Debian 13 VPS ]
  stdin (RAM) ───► /usr/local/bin/kubectl apply -f -
                          │
                          │ (Encrypted TLS Outbound)
                          ▼
            [ DigitalOcean PostgreSQL 18 ]
              (Stored Securely in Database)
```

### How to Deploy from your NAS:

From your Mac / dev workstation (inside the `nix develop` shell or terminal):

```bash
# Stream an entire directory of apps and secrets from your NAS:
./scripts/deploy-from-nas.sh \
  --source /Volumes/NAS/ClusterApps \
  --server <YOUR_SERVER_VPS_IP>

# Or if you have kubectl configured locally:
./scripts/deploy-from-nas.sh \
  --source /Volumes/NAS/ClusterApps \
  --local
```

### What Happens:
- The script packages the manifests into an in-memory stream.
- The stream pipes directly into the remote `kubectl` process stdin.
- **Zero plain-text files or secrets are created on the VPS filesystem.**
- No cleanup is required because nothing was ever written to disk!

---

## 3. Disaster Recovery Flow with NAS Apps

If your cluster is completely destroyed or wiped:

```bash
# Step 1: Provision the clean control plane node (2 minutes)
curl -fsSL https://install.cluster.lyttle.dev | sudo bash -s -- \
  --role server \
  --datastore-endpoint "postgres://k3s_user:SECRET@your-do-db:25060/k3s_cluster?sslmode=require" \
  --cf-token "YOUR_CLOUDFLARE_TUNNEL_TOKEN"

# Step 2: Restore your NAS-backed private apps & secrets (10 seconds)
./scripts/deploy-from-nas.sh --source /Volumes/NAS/ClusterApps --server <NEW_VPS_IP>
```

Within seconds, all production containers, environment variables, and private credentials are back online.

---

## 4. Alternative: Mozilla SOPS + Age (GitOps Encrypted Secrets)

If you eventually want your private secrets stored directly in this Git repository alongside your code without relying on a manual NAS step, you can use **Mozilla SOPS with Age** (already included in this repository's `flake.nix`):

### How SOPS Works:
1. You generate an `age` keypair once:
   ```bash
   age-keygen -o ~/.config/sops/age/keys.txt
   ```
2. Your **Public Key** is stored in `.sops.yaml` in the repo (safe to commit to GitHub).
3. Secrets in `apps/<name>/secret.enc.yaml` have their values encrypted:
   ```yaml
   apiVersion: v1
   kind: Secret
   metadata:
     name: db-credentials
   data:
     PASSWORD: ENC[AES256_GCM,data:wS8a1qZ...,iv:...]
   ```
4. Even if your GitHub repository is public or compromised, the secrets cannot be decrypted without your private Age key stored securely on your NAS.
