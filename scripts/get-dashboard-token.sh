#!/usr/bin/env bash
# ==============================================================================
# Helper: Get Headlamp Dashboard Admin Authentication Token
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common.sh
source "${SCRIPT_DIR}/common.sh"

if ! command -v kubectl &>/dev/null; then
    fatal "kubectl is required to run this script."
fi

info "Fetching Headlamp Dashboard Admin Token..."

# Attempt fetching token from secret first (if static token secret exists)
TOKEN=""
if kubectl get secret headlamp-admin-token -n headlamp &>/dev/null; then
    TOKEN="$(kubectl get secret headlamp-admin-token -n headlamp -o jsonpath='{.data.token}' | base64 -d || true)"
fi

# Fallback to creating a long-lived token via kubectl create token
if [[ -z "${TOKEN}" ]]; then
    TOKEN="$(kubectl create token headlamp-admin -n headlamp --duration=87600h)"
fi

if [[ -z "${TOKEN}" ]]; then
    fatal "Could not retrieve or generate a token for headlamp-admin."
fi

echo "=========================================================================="
echo " 🌟 Headlamp Dashboard Authentication Token"
echo " Dashboard URL: https://dashboard.cluster.lyttle.dev"
echo "=========================================================================="
echo "${TOKEN}"
echo "=========================================================================="
echo "Copy and paste the token above into the login prompt at the dashboard URL."
