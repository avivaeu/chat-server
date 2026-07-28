#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

KUBECONFIG_FILE="${KUBECONFIG_FILE:-$HOME/.kube/aviva-netcup.yaml}"
KUBE_CONTEXT="${KUBE_CONTEXT:-aviva-netcup}"
ESS_NAMESPACE="${ESS_NAMESPACE:-guest-ess}"
ESS_RELEASE="${ESS_RELEASE:-guest-ess}"
ESS_CHART="${ESS_CHART:-oci://ghcr.io/element-hq/ess-helm/matrix-stack}"
ESS_CHART_VERSION="${ESS_CHART_VERSION:-26.7.2}"

export KUBECONFIG="${KUBECONFIG_FILE}"

echo "[1/4] Checking DNS records"
for host in guest-chat.avivaeu.org matrix.guest-chat.avivaeu.org; do
  resolved_ip="$(nslookup "${host}" | awk '/^Address: / {print $2}' | tail -n1 || true)"
  if [[ -z "${resolved_ip}" ]]; then
    echo "DNS lookup failed for ${host}"
    exit 1
  fi
done

echo "[2/4] Ensuring namespace exists"
kubectl --context "${KUBE_CONTEXT}" get ns "${ESS_NAMESPACE}" >/dev/null 2>&1 || kubectl --context "${KUBE_CONTEXT}" create namespace "${ESS_NAMESPACE}"

echo "[3/4] Deploying guest ESS"
helm --kube-context "${KUBE_CONTEXT}" upgrade --install "${ESS_RELEASE}" "${ESS_CHART}" \
  --version "${ESS_CHART_VERSION}" \
  --namespace "${ESS_NAMESPACE}" \
  --create-namespace \
  -f "${SCRIPT_DIR}/values/guest.yaml" \
  --wait --timeout 25m

kubectl --context "${KUBE_CONTEXT}" delete ingress guest-ess-room -n "${ESS_NAMESPACE}" --ignore-not-found
kubectl --context "${KUBE_CONTEXT}" delete middleware guest-ess-room-strip room-strip -n "${ESS_NAMESPACE}" --ignore-not-found

echo "[4/4] Deploying Element Call SPA"
kubectl --context "${KUBE_CONTEXT}" apply -f "${SCRIPT_DIR}/manifests/element-call.yaml"
kubectl --context "${KUBE_CONTEXT}" rollout status deployment/guest-element-call -n "${ESS_NAMESPACE}" --timeout 10m
