# ESS Community on Hetzner (single-node K3s)

This folder contains a reproducible setup for Element Server Suite Community on a single Hetzner Ubuntu node.

## What gets installed

- K3s (includes Traefik ingress)
- Helm
- cert-manager (OCI chart)
- ClusterIssuer `letsencrypt-prod` (HTTP-01 via Traefik)
- ESS Community (`oci://ghcr.io/element-hq/ess-helm/matrix-stack`)

## Required DNS

All records must point to your server public IP:

- `chat.avivaeu.org`
- `matrix.chat.avivaeu.org`
- `admin.chat.avivaeu.org`
- `account.chat.avivaeu.org`
- `mrtc.chat.avivaeu.org`
- `push.chat.avivaeu.org`

## Deploy

```bash
./infra/ess/deploy.sh
```

Useful overrides:

```bash
SERVER_IP=49.13.16.88 SSH_KEY=~/.ssh/id_aviva LETSENCRYPT_EMAIL=admin@avivaeu.org ./infra/ess/deploy.sh
```

## Teardown

```bash
./infra/ess/teardown.sh
```

## Sygnal push gateway (iOS APNs)

Sygnal is deployed separately from the ESS Helm release and exposed at:

- `https://push.chat.avivaeu.org/_matrix/push/v1/notify`

### 1) Prepare APNs secret

Create the secret from your local APNs `.p8` key file (do not commit real keys):

```bash
kubectl -n ess create secret generic sygnal-apns \
  --from-file=AuthKey.p8=/path/to/AuthKey_XXXXXXX.p8
```

If the secret already exists and you need to rotate the key:

```bash
kubectl -n ess delete secret sygnal-apns
kubectl -n ess create secret generic sygnal-apns \
  --from-file=AuthKey.p8=/path/to/AuthKey_XXXXXXX.p8
```

### 2) Configure Sygnal app mapping

Edit `infra/ess/manifests/sygnal-configmap.yaml` and set:

- `key_id` to your Apple Push Key ID
- keep `team_id: ZR769W56HB`
- keep `topic: org.avivaeu.chat`
- keep both app IDs during migration:
  - `org.avivaeu.chat.ios.prod` (new)
  - `org.avivaeu.chat` (legacy fallback)

### 3) Apply Sygnal manifests

```bash
kubectl apply -f infra/ess/manifests/sygnal-configmap.yaml
kubectl apply -f infra/ess/manifests/sygnal-deployment.yaml
kubectl apply -f infra/ess/manifests/sygnal-service.yaml
kubectl apply -f infra/ess/manifests/sygnal-ingress.yaml
```

### 4) Verify deployment

```bash
kubectl -n ess get pods -l app=sygnal
kubectl -n ess logs deployment/sygnal --tail=200
curl -i https://push.chat.avivaeu.org/_matrix/push/v1/notify
```

Expected: `curl` returns `405` for GET (endpoint is POST-only), confirming ingress routing.

### 5) Verify end-to-end from Matrix side

After the iOS app registers its pusher, confirm:

- `app_id` is `org.avivaeu.chat.ios.prod` (or legacy `org.avivaeu.chat` during migration)
- pusher `url` is `https://push.chat.avivaeu.org/_matrix/push/v1/notify`

You can inspect pushers using Matrix Client-Server API `/_matrix/client/v3/pushers`.

## kubectl access from local machine

K3s official way is to copy `/etc/rancher/k3s/k3s.yaml` and update `server:`.

Example:

```bash
mkdir -p ~/.kube
ssh -i ~/.ssh/id_aviva root@49.13.16.88 "cat /etc/rancher/k3s/k3s.yaml" > ~/.kube/config-aviva-ess
perl -i -pe 's#https://127.0.0.1:6443#https://49.13.16.88:6443#g' ~/.kube/config-aviva-ess
KUBECONFIG=~/.kube/config-aviva-ess kubectl get nodes
```

Alternative via SSH tunnel:

```bash
ssh -i ~/.ssh/id_aviva -L 6443:127.0.0.1:6443 root@49.13.16.88
```

Then use kubeconfig with `server: https://127.0.0.1:6443` while the tunnel is open.
