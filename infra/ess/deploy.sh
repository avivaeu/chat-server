#!/usr/bin/env bash
set -euo pipefail

# ESS Community on single-node K3s (Hetzner VM)

SERVER_IP="${SERVER_IP:-91.98.33.147}"
SSH_USER="${SSH_USER:-root}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_aviva}"
DOMAIN="${DOMAIN:-chat.avivaeu.org}"
LETSENCRYPT_EMAIL="${LETSENCRYPT_EMAIL:-admin@avivaeu.org}"
ESS_NAMESPACE="${ESS_NAMESPACE:-ess}"
INGRESS_CLASS="${INGRESS_CLASS:-traefik}"
CERT_MANAGER_VERSION="${CERT_MANAGER_VERSION:-v1.19.4}"
ESS_CHART="${ESS_CHART:-oci://ghcr.io/element-hq/ess-helm/matrix-stack}"
ESS_CHART_VERSION="${ESS_CHART_VERSION:-26.5.1}"

MATRIX_HOST="${MATRIX_HOST:-matrix.${DOMAIN}}"
ADMIN_HOST="${ADMIN_HOST:-admin.${DOMAIN}}"
ACCOUNT_HOST="${ACCOUNT_HOST:-account.${DOMAIN}}"
MRTC_HOST="${MRTC_HOST:-mrtc.${DOMAIN}}"

REMOTE_CONFIG_DIR="/root/ess-config-values"
REMOTE_VALUES_FILE="${REMOTE_CONFIG_DIR}/ess.yaml"
REMOTE_ISSUER_FILE="/root/clusterissuer.yaml"

SSH_OPTS=(
  -i "${SSH_KEY}"
  -o UserKnownHostsFile=/dev/null
  -o StrictHostKeyChecking=no
)

run_remote() {
  ssh "${SSH_OPTS[@]}" "${SSH_USER}@${SERVER_IP}" "$@"
}

echo "[1/8] Checking DNS records"
for host in "${DOMAIN}" "${MATRIX_HOST}" "${ADMIN_HOST}" "${ACCOUNT_HOST}" "${MRTC_HOST}"; do
  resolved_ip="$(nslookup "${host}" | awk '/^Address: / {print $2}' | tail -n1 || true)"
  if [[ "${resolved_ip}" != "${SERVER_IP}" ]]; then
    echo "DNS check failed for ${host}: expected ${SERVER_IP}, got ${resolved_ip:-<none>}"
    exit 1
  fi
done
echo "DNS is ready"

echo "[2/8] Installing K3s"
run_remote "if ! command -v k3s >/dev/null 2>&1; then curl -sfL https://get.k3s.io | sh -; fi"

echo "[3/8] Waiting for node readiness"
run_remote "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml; kubectl wait --for=condition=Ready node --all --timeout=180s"

echo "[4/8] Installing Helm"
run_remote "if ! command -v helm >/dev/null 2>&1; then curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash; fi"

echo "[5/8] Installing cert-manager"
run_remote "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml; helm upgrade --install cert-manager oci://quay.io/jetstack/charts/cert-manager --version ${CERT_MANAGER_VERSION} --namespace cert-manager --create-namespace --set crds.enabled=true --wait --timeout 10m"

echo "[6/8] Applying ClusterIssuer"
run_remote "cat > ${REMOTE_ISSUER_FILE} <<'EOF'
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    email: ${LETSENCRYPT_EMAIL}
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-prod-account-key
    solvers:
      - http01:
          ingress:
            class: ${INGRESS_CLASS}
EOF
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl apply -f ${REMOTE_ISSUER_FILE}
"

echo "[7/8] Writing ESS values"
run_remote "mkdir -p ${REMOTE_CONFIG_DIR}; cat > ${REMOTE_VALUES_FILE} <<'EOF'
serverName: ${DOMAIN}

certManager:
  clusterIssuer: letsencrypt-prod

ingress:
  className: ${INGRESS_CLASS}

synapse:
  ingress:
    host: ${MATRIX_HOST}
  additional:
    guest-federation.yaml:
      config: |
        federation_domain_whitelist:
          - guest-chat.avivaeu.org

elementWeb:
  ingress:
    host: ${DOMAIN}
  additional:
    guest-access: |
      {
        "features": {
          "feature_ask_to_join": true
        },
        "element_call": {
          "guest_spa_url": "https://guest-chat.avivaeu.org"
        }
      }
    permalink-config: |
      {
        "permalink_prefix": "https://web.chat.avivaeu.org"
      }

elementAdmin:
  ingress:
    host: ${ADMIN_HOST}

matrixAuthenticationService:
  ingress:
    host: ${ACCOUNT_HOST}

matrixRTC:
  ingress:
    host: ${MRTC_HOST}
EOF"

echo "[8/8] Deploying ESS"
run_remote "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml; kubectl get ns ${ESS_NAMESPACE} >/dev/null 2>&1 || kubectl create namespace ${ESS_NAMESPACE}; helm upgrade --install ess ${ESS_CHART} --version ${ESS_CHART_VERSION} --namespace ${ESS_NAMESPACE} --create-namespace -f ${REMOTE_VALUES_FILE} --wait --timeout 25m"

echo
echo "Deployment complete"
echo "Server: ${SERVER_IP}"
echo "Element Web: https://${DOMAIN}"
echo "Element Admin: https://${ADMIN_HOST}"
echo "Account: https://${ACCOUNT_HOST}"
echo
echo "Create first user:"
echo "ssh -i ${SSH_KEY} ${SSH_USER}@${SERVER_IP} \"export KUBECONFIG=/etc/rancher/k3s/k3s.yaml; kubectl exec -n ${ESS_NAMESPACE} -it deployment/ess-matrix-authentication-service -- mas-cli manage register-user\""
