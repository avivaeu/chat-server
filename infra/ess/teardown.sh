#!/usr/bin/env bash
set -euo pipefail

SERVER_IP="${SERVER_IP:-91.98.33.147}"
SSH_USER="${SSH_USER:-root}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_aviva}"
ESS_NAMESPACE="${ESS_NAMESPACE:-ess}"

SSH_OPTS=(
  -i "${SSH_KEY}"
  -o UserKnownHostsFile=/dev/null
  -o StrictHostKeyChecking=no
)

run_remote() {
  ssh "${SSH_OPTS[@]}" "${SSH_USER}@${SERVER_IP}" "$@"
}

run_remote "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml; helm uninstall ess -n ${ESS_NAMESPACE} || true; kubectl delete namespace ${ESS_NAMESPACE} --ignore-not-found=true"
run_remote "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml; helm uninstall cert-manager -n cert-manager || true; kubectl delete namespace cert-manager --ignore-not-found=true; kubectl delete clusterissuer letsencrypt-prod --ignore-not-found=true"

echo "Teardown finished for server ${SERVER_IP}"
