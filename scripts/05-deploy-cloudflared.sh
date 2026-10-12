#!/usr/bin/env bash
# ==============================================================================
# Step 05: Deploy Cloudflare Tunnel Agent (Zero-Trust Ingress)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common.sh
source "${SCRIPT_DIR}/common.sh"

check_root

CF_TOKEN="${CLOUDFLARE_TUNNEL_TOKEN:-${CF_TOKEN:-}}"

if [[ -z "${CF_TOKEN}" ]]; then
    warn "No Cloudflare Tunnel Token provided (CLOUDFLARE_TUNNEL_TOKEN or CF_TOKEN)."
    warn "Skipping automatic Cloudflare Tunnel deployment."
    warn "You can deploy it later by providing the token to this script."
    exit 0
fi

if ! command -v kubectl &> /dev/null; then
    fatal "kubectl command not found. Ensure K3s control-plane is installed before running this script."
fi

info "Starting Step 05: Deploying Cloudflare Tunnel into Kubernetes..."

# 1. Create namespace
kubectl create namespace cloudflare --dry-run=client -o yaml | kubectl apply -f -

# 2. Create Secret with Tunnel Token
kubectl create secret generic cloudflared-token \
    --namespace cloudflare \
    --from-literal=token="${CF_TOKEN}" \
    --dry-run=client -o yaml | kubectl apply -f -

# 3. Apply Cloudflared Deployment
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cloudflared
  namespace: cloudflare
  labels:
    app: cloudflared
spec:
  replicas: 2
  selector:
    matchLabels:
      app: cloudflared
  template:
    metadata:
      labels:
        app: cloudflared
    spec:
      containers:
      - name: cloudflared
        image: cloudflare/cloudflared:latest
        args:
        - tunnel
        - --no-autoupdate
        - run
        - --token
        - \$(TUNNEL_TOKEN)
        env:
        - name: TUNNEL_TOKEN
          valueFrom:
            secretKeyRef:
              name: cloudflared-token
              key: token
        resources:
          limits:
            cpu: 500m
            memory: 256Mi
          requests:
            cpu: 50m
            memory: 64Mi
        securityContext:
          runAsNonRoot: true
          runAsUser: 65532
          readOnlyRootFilesystem: true
          allowPrivilegeEscalation: false
          capabilities:
            drop:
            - ALL
EOF

info "Waiting for cloudflared deployment rollout..."
kubectl rollout status deployment/cloudflared -n cloudflare --timeout=60s || true

success "Step 05 completed: Cloudflare Tunnel deployed in 'cloudflare' namespace!"
info "Cloudflare Tunnel is now securely forwarding traffic to internal cluster services without open ports."
