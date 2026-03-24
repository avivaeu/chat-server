# Aviva ESS Test Setup

Element Server Suite (Community) is deployed on a single Hetzner Ubuntu VM using K3s.

## Current deployment

- Server: `91.98.33.147` (Hetzner `cx33`, Ubuntu 24.04)
- Kubernetes: K3s single-node (`v1.34.4+k3s1`)
- Ingress: Traefik (K3s default)
- cert-manager: `v1.19.4` (installed separately via Helm OCI)
- ESS chart: `oci://ghcr.io/element-hq/ess-helm/matrix-stack` (release `26.2.3`)
- Namespace: `ess`

## DNS used

All records point to `91.98.33.147`:

- `chat.avivaeu.org`
- `web.chat.avivaeu.org`
- `matrix.chat.avivaeu.org`
- `admin.chat.avivaeu.org`
- `account.chat.avivaeu.org`
- `mrtc.chat.avivaeu.org`
- `push.chat.avivaeu.org`

## Public endpoints

- Element Web: `https://chat.avivaeu.org`
- Element Web direct host: `https://web.chat.avivaeu.org`
- Element Admin: `https://admin.chat.avivaeu.org`
- Account (MAS): `https://account.chat.avivaeu.org`
- Synapse ingress host: `https://matrix.chat.avivaeu.org`
- RTC ingress host: `https://mrtc.chat.avivaeu.org`
- Sygnal push ingress host: `https://push.chat.avivaeu.org/_matrix/push/v1/notify`

## Repo automation

Scripts and values are under `infra/ess`:

- Deploy: `infra/ess/deploy.sh`
- Teardown: `infra/ess/teardown.sh`
- ESS values: `infra/ess/values/ess.yaml`
- ClusterIssuer manifest: `infra/ess/manifests/clusterissuer.yaml`
- VM migration runbook: `infra/ess/MIGRATION_RUNBOOK.md`

Run deploy:

```bash
./infra/ess/deploy.sh
```

Run teardown:

```bash
./infra/ess/teardown.sh
```

## SSH access shortcut

`~/.ssh/config` includes:

```sshconfig
Host aviva-chat
  HostName 91.98.33.147
  User root
  IdentityFile ~/.ssh/id_aviva
  IdentitiesOnly yes
```

Connect with:

```bash
ssh aviva-chat
```

## Local kubectl over SSH tunnel

Goal: run local commands like `kubectl get pods` without wrapping with `ssh ... "kubectl ..."`.

### 1) Start tunnel

```bash
ssh -f -N -L 6443:127.0.0.1:6443 aviva-chat
```

### 2) Use kubeconfig/context

Local kubeconfig file created: `~/.kube/aviva-chat.yaml`.

Default server in this file is tunnel endpoint:

- `https://127.0.0.1:6443`

Context name:

- `aviva-chat`

Use it explicitly:

```bash
KUBECONFIG=~/.kube/aviva-chat.yaml kubectl --context aviva-chat get pods -A
```

Or set once in shell:

```bash
export KUBECONFIG=~/.kube/aviva-chat.yaml
kubectl config use-context aviva-chat
kubectl get pods
```

### 3) Handy zsh functions

Added to `~/.zshrc`:

- `proxy-aviva-chat-on`
- `proxy-aviva-chat-off`

Usage:

```bash
source ~/.zshrc
proxy-aviva-chat-on
kubectl get pods
proxy-aviva-chat-off
```

## Create first/super admin user

Non-interactive command:

```bash
kubectl exec -n ess deployment/ess-matrix-authentication-service -- \
  mas-cli manage register-user --yes <username> --password '<strong-password>' --admin --email '<email>'
```

Example:

```bash
kubectl exec -n ess deployment/ess-matrix-authentication-service -- \
  mas-cli manage register-user --yes avivaadmin --password 'ChangeMeToAVeryStrongPassword' --admin --email 'admin@avivaeu.org'
```

## Notes

- cert-manager is required separately; ESS uses it but does not install it.
- Let’s Encrypt is configured via `ClusterIssuer` `letsencrypt-prod` with HTTP-01 solver on Traefik.
- The kubeconfig copied from K3s grants admin-level cluster access; keep it private.
