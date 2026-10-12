#!/usr/bin/env bash
# ==============================================================================
# Fast Application Deployer & Manifest Generator
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"

REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
APPS_DIR="${REPO_ROOT}/apps"

NAME=""
IMAGE=""
DOMAIN=""
PORT="80"
REPLICAS="1"
NAMESPACE="apps"
declare -a ENVS=()

usage() {
    cat <<EOF
Usage: $0 [options]

Options:
  --name <app-name>        Name of the application (e.g. ghost-blog, my-api)
  --image <image:tag>      Docker image (e.g. ghost:5-alpine, nginx:alpine)
  --domain <hostname>      Domain name (e.g. blog.cluster.lyttle.dev)
  --port <port>            Container port (default: 80)
  --env KEY=VALUE          Environment variable (can be repeated)
  --replicas <num>         Number of replicas (default: 1)
  --namespace <ns>         Kubernetes namespace (default: apps)
  -h, --help               Show this help message

Examples:
  # Deploy a blog:
  $0 --name blog --image ghost:5-alpine --domain blog.cluster.lyttle.dev --port 2368 --env NODE_ENV=production

  # Interactive mode:
  $0
EOF
    exit 0
}

# Parse CLI arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --name)
            NAME="$2"
            shift 2
            ;;
        --image)
            IMAGE="$2"
            shift 2
            ;;
        --domain)
            DOMAIN="$2"
            shift 2
            ;;
        --port)
            PORT="$2"
            shift 2
            ;;
        --replicas)
            REPLICAS="$2"
            shift 2
            ;;
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --env)
            ENVS+=("$2")
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            warn "Unknown argument: $1"
            shift
            ;;
    esac
done

# Interactive prompts if required arguments are missing
if [[ -z "${NAME}" ]]; then
    echo -e "${CYAN}=== Fast Application Deployer ===${NC}"
    read -r -p "Application Name (e.g. my-service): " NAME
fi

if [[ -z "${IMAGE}" ]]; then
    read -r -p "Docker Image (e.g. nginx:alpine): " IMAGE
fi

if [[ -z "${DOMAIN}" ]]; then
    read -r -p "Domain Name (e.g. my-service.cluster.lyttle.dev): " DOMAIN
fi

if [[ -z "${PORT}" ]]; then
    read -r -p "Container Port [80]: " input_port
    PORT="${input_port:-80}"
fi

# Sanitize application name (lowercase, alphanumeric, dashes)
NAME="$(echo "${NAME}" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')"

if [[ -z "${NAME}" || -z "${IMAGE}" || -z "${DOMAIN}" ]]; then
    fatal "Application name, image, and domain are required."
fi

APP_TARGET_DIR="${APPS_DIR}/${NAME}"
mkdir -p "${APP_TARGET_DIR}"

info "Generating Kubernetes manifests in ${APP_TARGET_DIR}/app.yaml..."

# Format environment variables into YAML
ENV_YAML=""
if [[ ${#ENVS[@]} -gt 0 ]]; then
    ENV_YAML="        env:"
    for env_pair in "${ENVS[@]}"; do
        key="${env_pair%%=*}"
        val="${env_pair#*=}"
        ENV_YAML+=$'\n'"        - name: ${key}"
        ENV_YAML+=$'\n'"          value: \"${val}\""
    done
fi

cat <<EOF > "${APP_TARGET_DIR}/app.yaml"
apiVersion: v1
kind: Namespace
metadata:
  name: ${NAMESPACE}
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${NAME}
  namespace: ${NAMESPACE}
  labels:
    app: ${NAME}
spec:
  replicas: ${REPLICAS}
  selector:
    matchLabels:
      app: ${NAME}
  template:
    metadata:
      labels:
        app: ${NAME}
    spec:
      containers:
      - name: ${NAME}
        image: ${IMAGE}
        ports:
        - containerPort: ${PORT}
          name: http
${ENV_YAML}
        resources:
          limits:
            cpu: 500m
            memory: 512Mi
          requests:
            cpu: 50m
            memory: 64Mi
---
apiVersion: v1
kind: Service
metadata:
  name: ${NAME}
  namespace: ${NAMESPACE}
spec:
  selector:
    app: ${NAME}
  ports:
  - port: 80
    targetPort: ${PORT}
    name: http
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ${NAME}
  namespace: ${NAMESPACE}
  annotations:
    kubernetes.io/ingress.class: "traefik"
spec:
  rules:
  - host: ${DOMAIN}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: ${NAME}
            port:
              number: 80
EOF

# Update root apps/kustomization.yaml
mkdir -p "${APPS_DIR}"
if [[ ! -f "${APPS_DIR}/kustomization.yaml" ]]; then
    cat <<EOF > "${APPS_DIR}/kustomization.yaml"
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources: []
EOF
fi

if ! grep -q "${NAME}/app.yaml" "${APPS_DIR}/kustomization.yaml"; then
    # Add resource to kustomization.yaml
    if grep -q "resources: \[\]" "${APPS_DIR}/kustomization.yaml"; then
        sed -i '' "s/resources: \[\]/resources:\n  - ${NAME}\/app.yaml/" "${APPS_DIR}/kustomization.yaml" 2>/dev/null || \
        sed -i "s/resources: \[\]/resources:\n  - ${NAME}\/app.yaml/" "${APPS_DIR}/kustomization.yaml"
    else
        echo "  - ${NAME}/app.yaml" >> "${APPS_DIR}/kustomization.yaml"
    fi
    info "Registered ${NAME} into apps/kustomization.yaml"
fi

# Apply to cluster if kubectl is present
if command -v kubectl &>/dev/null; then
    info "Applying ${NAME} to Kubernetes cluster..."
    kubectl apply -f "${APP_TARGET_DIR}/app.yaml"
    success "Application '${NAME}' successfully deployed!"
else
    warn "kubectl not detected. Manifest generated at ${APP_TARGET_DIR}/app.yaml"
fi

echo "=========================================================================="
echo " 🚀 Application Live URL: https://${DOMAIN}"
echo " Manifest Location:    apps/${NAME}/app.yaml"
echo " Fleet Rebuild Rule:   kubectl apply -k apps/"
echo "=========================================================================="
info "Remember to commit apps/${NAME} to Git to keep your fleet declarative!"
