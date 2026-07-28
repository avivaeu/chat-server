# Guest ESS

This folder contains the guest-only ESS deployment for public call access.

Chart version:

- `26.7.2`

Default release / namespace:

- release: `guest-ess`
- namespace: `guest-ess`

## Goal

- reuse the existing cluster Traefik ingress
- reuse the existing cert-manager and ClusterIssuer
- keep the guest stack minimal
- run guest Synapse via ESS Helm
- run Element Call as a separate standalone web deployment
- only allow joining main-instance calls through federation and the main LiveKit backend

## DNS

Create these Cloudflare A records to the VM public IP:

- `guest-chat.avivaeu.org`
- `matrix.guest-chat.avivaeu.org`

## Files

- `guest/deploy.sh`
- `guest/values/guest.yaml`
- `guest/scripts/create-dns.sh`
- `guest/manifests/element-call.yaml`

## Deploy

```bash
./guest/deploy.sh
```

Defaults to `~/.kube/aviva-netcup.yaml` with context `aviva-netcup`.

## Cloudflare DNS

The DNS helper only creates or updates the two guest A records above and does not touch any other record.

## Deployment model

- `guest/values/guest.yaml` keeps the guest ESS release on Synapse only
- `guest/manifests/element-call.yaml` deploys the standalone `ghcr.io/element-hq/element-call:v0.20.0` SPA outside Helm
