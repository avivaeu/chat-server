#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

ENV_FILE="${ENV_FILE:-${REPO_ROOT}/.env}"
RENDER_SCRIPT="${RENDER_SCRIPT:-${SCRIPT_DIR}/render-values.sh}"

ESS_RELEASE="${ESS_RELEASE:-ess}"
ESS_NAMESPACE="${ESS_NAMESPACE:-ess}"
ESS_CHART="${ESS_CHART:-oci://ghcr.io/element-hq/ess-helm/matrix-stack}"

VALUES_BASE="${REPO_ROOT}/infra/ess/values/ess.yaml"
VALUES_AUTH="${REPO_ROOT}/infra/ess/values/auth-media-retention.yaml"
VALUES_SMTP="${REPO_ROOT}/infra/ess/values/smtp.yaml"
VALUES_LOCAL="${REPO_ROOT}/infra/ess/values/generated/local-secrets.yaml"

if [[ ! -x "${RENDER_SCRIPT}" ]]; then
  echo "Render script is not executable: ${RENDER_SCRIPT}"
  exit 1
fi

ENV_FILE="${ENV_FILE}" "${RENDER_SCRIPT}"

for file in "${VALUES_BASE}" "${VALUES_AUTH}" "${VALUES_SMTP}" "${VALUES_LOCAL}"; do
  if [[ ! -f "${file}" ]]; then
    echo "Missing values file: ${file}"
    exit 1
  fi
done

helm upgrade --install "${ESS_RELEASE}" "${ESS_CHART}" \
  --namespace "${ESS_NAMESPACE}" \
  --create-namespace \
  -f "${VALUES_BASE}" \
  -f "${VALUES_AUTH}" \
  -f "${VALUES_SMTP}" \
  -f "${VALUES_LOCAL}" \
  --wait --timeout 25m

echo "Deployed ${ESS_RELEASE} in namespace ${ESS_NAMESPACE}"
