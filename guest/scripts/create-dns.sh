#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

TOKEN_FILE="${TOKEN_FILE:-${REPO_ROOT}/.secrets/cloudflare.token}"
ZONE_NAME="${ZONE_NAME:-avivaeu.org}"
CONTENT_IP="${CONTENT_IP:-152.53.156.144}"

if [[ ! -f "${TOKEN_FILE}" ]]; then
  echo "Missing Cloudflare token file: ${TOKEN_FILE}"
  exit 1
fi

token="$(<"${TOKEN_FILE}")"

cf_get() {
  curl -fsS \
    -H "Authorization: Bearer ${token}" \
    -H "Content-Type: application/json" \
    "$1"
}

zone_id="$(cf_get "https://api.cloudflare.com/client/v4/zones?name=${ZONE_NAME}&status=active&per_page=1" | jq -r '.result[0].id // empty')"

if [[ -z "${zone_id}" ]]; then
  echo "Could not find Cloudflare zone: ${ZONE_NAME}"
  exit 1
fi

ensure_record() {
  local name="$1"
  local existing record_id record_content payload

  existing="$(cf_get "https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records?type=A&name=${name}&per_page=1")"
  record_id="$(jq -r '.result[0].id // empty' <<<"${existing}")"
  record_content="$(jq -r '.result[0].content // empty' <<<"${existing}")"

  if [[ -z "${record_id}" ]]; then
    payload="$(jq -n --arg name "${name}" --arg content "${CONTENT_IP}" '{type:"A",name:$name,content:$content,ttl:1,proxied:false}')"
    curl -fsS -X POST \
      -H "Authorization: Bearer ${token}" \
      -H "Content-Type: application/json" \
      --data "${payload}" \
      "https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records" >/dev/null
    echo "created ${name} -> ${CONTENT_IP}"
    return
  fi

  if [[ "${record_content}" == "${CONTENT_IP}" ]]; then
    echo "unchanged ${name} -> ${CONTENT_IP}"
    return
  fi

  payload="$(jq -n --arg content "${CONTENT_IP}" '{content:$content,ttl:1,proxied:false}')"
  curl -fsS -X PATCH \
    -H "Authorization: Bearer ${token}" \
    -H "Content-Type: application/json" \
    --data "${payload}" \
    "https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records/${record_id}" >/dev/null
  echo "updated ${name} -> ${CONTENT_IP}"
}

ensure_record "guest-chat.avivaeu.org"
ensure_record "matrix.guest-chat.avivaeu.org"
