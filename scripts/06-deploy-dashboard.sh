#!/usr/bin/env bash
# ==============================================================================
# Step 06: Deploy Headlamp Web Dashboard (Stateless Container Management UI)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"

check_root

if ! command -v kubectl &> /dev/null; then
    fatal "kubectl command not found. Ensure K3s control-plane is installed before running this script."
fi

info "Starting Step 06: Deploying Headlamp Web Dashboard..."

MANIFEST_FILE="${SCRIPT_DIR}/../manifests/dashboard/headlamp.yaml"

if [[ -f "${MANIFEST_FILE}" ]]; then
    info "Applying Headlamp manifest from ${MANIFEST_FILE}..."
    kubectl apply -f "${MANIFEST_FILE}"
else
    info "Applying embedded Headlamp manifest..."
    cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: headlamp
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: headlamp-admin
  namespace: headlamp
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: headlamp-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: headlamp-admin
  namespace: headlamp
---
apiVersion: v1
kind: Secret
metadata:
  name: headlamp-admin-token
  namespace: headlamp
  annotations:
    kubernetes.io/service-account.name: headlamp-admin
type: kubernetes.io/service-account-token
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: headlamp
  namespace: headlamp
  labels:
    app: headlamp
spec:
  replicas: 1
  selector:
    matchLabels:
      app: headlamp
  template:
    metadata:
      labels:
        app: headlamp
    spec:
      serviceAccountName: headlamp-admin
      containers:
      - name: headlamp
        image: ghcr.io/headlamp-k8s/headlamp:latest
        args:
        - "-in-cluster"
        ports:
        - containerPort: 4466
          name: http
        resources:
          limits:
            cpu: 500m
            memory: 512Mi
          requests:
            cpu: 100m
            memory: 128Mi
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: false
---
apiVersion: v1
kind: Service
metadata:
  name: headlamp
  namespace: headlamp
spec:
  selector:
    app: headlamp
  ports:
  - port: 80
    targetPort: 4466
    name: http
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: headlamp
  namespace: headlamp
  annotations:
    kubernetes.io/ingress.class: "traefik"
spec:
  rules:
  - host: dashboard.cluster.lyttle.dev
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: headlamp
            port:
              number: 80
EOF
fi

info "Waiting for Headlamp deployment rollout..."
kubectl rollout status deployment/headlamp -n headlamp --timeout=60s || true

# Fetch or generate the authentication token
info "Retrieving Headlamp admin token..."
TOKEN=""
for i in {1..10}; do
    if kubectl get secret headlamp-admin-token -n headlamp &>/dev/null; then
        TOKEN="$(kubectl get secret headlamp-admin-token -n headlamp -o jsonpath='{.data.token}' | base64 -d 2>/dev/null || true)"
        if [[ -n "${TOKEN}" ]]; then
            break
        fi
    fi
    sleep 1
done

if [[ -z "${TOKEN}" ]]; then
    TOKEN="$(kubectl create token headlamp-admin -n headlamp --duration=87600h)"
fi

# Save token locally for convenience
echo "${TOKEN}" > /etc/headlamp-admin-token.txt
chmod 600 /etc/headlamp-admin-token.txt

ADMIN_USER="${ADMIN_USER:-server}"
if [[ -n "${ADMIN_USER}" && "${ADMIN_USER}" != "root" ]] && id "${ADMIN_USER}" &>/dev/null; then
    USER_HOME="$(getent passwd "${ADMIN_USER}" | cut -d: -f6)"
    echo "${TOKEN}" > "${USER_HOME}/headlamp-token.txt"
    chown "${ADMIN_USER}:${ADMIN_USER}" "${USER_HOME}/headlamp-token.txt"
    chmod 600 "${USER_HOME}/headlamp-token.txt"
fi

success "Step 06 completed: Headlamp Web Dashboard is live!"
echo "=========================================================================="
echo " 🌟 Headlamp Web Dashboard Deployed"
echo " URL:   https://dashboard.cluster.lyttle.dev"
echo " Token: Saved to /etc/headlamp-admin-token.txt"
if [[ -n "${ADMIN_USER}" && "${ADMIN_USER}" != "root" ]] && id "${ADMIN_USER}" &>/dev/null; then
    echo "        Saved to ${USER_HOME}/headlamp-token.txt"
fi
echo "=========================================================================="
