#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

ENV_FILE="${ENV_FILE:-${REPO_ROOT}/.env}"
TEMPLATE_FILE="${TEMPLATE_FILE:-${REPO_ROOT}/infra/ess/values/templates/local-secrets.yaml.template}"
OUTPUT_DIR="${OUTPUT_DIR:-${REPO_ROOT}/infra/ess/values/generated}"
OUTPUT_FILE="${OUTPUT_FILE:-${OUTPUT_DIR}/local-secrets.yaml}"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing env file: ${ENV_FILE}"
  echo "Copy ${REPO_ROOT}/.env.example to ${REPO_ROOT}/.env and fill values."
  exit 1
fi

if [[ ! -f "${TEMPLATE_FILE}" ]]; then
  echo "Missing template file: ${TEMPLATE_FILE}"
  exit 1
fi

set -a
source "${ENV_FILE}"
set +a

required_vars=(
  ZITADEL_CLIENT_ID
  ZITADEL_CLIENT_SECRET
  SMTP_PASSWORD
)

for var_name in "${required_vars[@]}"; do
  if [[ -z "${!var_name:-}" ]]; then
    echo "Missing required env var: ${var_name}"
    exit 1
  fi
done

mkdir -p "${OUTPUT_DIR}"
envsubst < "${TEMPLATE_FILE}" > "${OUTPUT_FILE}"

if grep -q '\${[A-Za-z_][A-Za-z0-9_]*}' "${OUTPUT_FILE}"; then
  echo "Unresolved placeholders remain in ${OUTPUT_FILE}"
  exit 1
fi

echo "Rendered ${OUTPUT_FILE}"
