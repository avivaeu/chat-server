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
