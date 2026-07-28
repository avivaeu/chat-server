# Aviva ESS Test Setup

Element Server Suite (Community) is deployed on a single Hetzner Ubuntu VM using K3s.

## Current deployment

- Server: `91.98.33.147` (Hetzner `cx33`, Ubuntu 24.04)
- Kubernetes: K3s single-node (`v1.34.4+k3s1`)
- Ingress: Traefik (K3s default)
- cert-manager: `v1.19.4` (installed separately via Helm OCI)
- ESS chart: `oci://ghcr.io/element-hq/ess-helm/matrix-stack` (release `26.5.1`)
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

Guest DNS records:

- `guest-chat.avivaeu.org`
- `matrix.guest-chat.avivaeu.org`

## Public endpoints

- Element Web: `https://chat.avivaeu.org`
- Element Web direct host: `https://web.chat.avivaeu.org`
- Element Admin: `https://admin.chat.avivaeu.org`
- Account (MAS): `https://account.chat.avivaeu.org`
- Synapse ingress host: `https://matrix.chat.avivaeu.org`
- RTC ingress host: `https://mrtc.chat.avivaeu.org`
- Sygnal push ingress host: `https://push.chat.avivaeu.org/_matrix/push/v1/notify`

Guest instance:

- Guest Element Call host: `https://guest-chat.avivaeu.org`
- Guest Synapse host: `https://matrix.guest-chat.avivaeu.org`

## Repo automation

Main ESS scripts and values are under `infra/ess`:

- Deploy: `infra/ess/deploy.sh`
- Teardown: `infra/ess/teardown.sh`
- ESS values: `infra/ess/values/ess.yaml`
- ClusterIssuer manifest: `infra/ess/manifests/clusterissuer.yaml`
- VM migration runbook: `infra/ess/MIGRATION_RUNBOOK.md`

Guest-only resources are under `guest/`:

- Deploy: `guest/deploy.sh`
- Guest values: `guest/values/guest.yaml`
- DNS helper: `guest/scripts/create-dns.sh`

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

## Enable registration with token

This applies to MAS password registration. If users only log in via Zitadel/OIDC, this does not create a separate self-service signup flow.

In `infra/ess/values/auth-media-retention.yaml`, enable password registration and require a token:

```yaml
matrixAuthenticationService:
  additional:
    auth.yaml:
      config: |
        account:
          password_registration_enabled: true
          password_registration_token_required: true
```

Generate a token with MAS CLI:

```bash
kubectl exec -n ess deployment/ess-matrix-authentication-service -- \
  mas-cli manage issue-user-registration-token --usage-limit 1 --expires-in 24h
```

If you want the token to be reusable, increase `--usage-limit` or use `--unlimited`.

Notes:

- `registration_token_required` is the deprecated name; prefer `password_registration_token_required`.
- This only works if `password_registration_enabled: true`.
- If you want email mandatory during registration, keep `password_registration_email_required: true`.

## Delete a user

Use exact identifiers only. First resolve the exact MAS username and Synapse MXID for the target email, then clean that one account.

1. Issue an admin compatibility token from `avivaadmin`:

```bash
kubectl exec -n ess deployment/ess-matrix-authentication-service -- \
  mas-cli manage issue-compatibility-token avivaadmin AIAgentAdminToken --yes-i-want-to-grant-synapse-admin-privileges
```

2. Use that token for the Synapse admin APIs:

```bash
curl -X POST -H "Authorization: Bearer <token>" -H 'Content-Type: application/json' \
  -d '{"rooms":[]}' \
  'https://matrix.chat.avivaeu.org/_synapse/admin/v1/user/%40<mxid>%3Achat.avivaeu.org/redact'

curl -X DELETE -H "Authorization: Bearer <token>" \
  'https://matrix.chat.avivaeu.org/_synapse/admin/v1/users/%40<mxid>%3Achat.avivaeu.org/media'

curl -X POST -H "Authorization: Bearer <token>" -H 'Content-Type: application/json' \
  -d '{"erase":true}' \
  'https://matrix.chat.avivaeu.org/_synapse/admin/v1/deactivate/%40<mxid>%3Achat.avivaeu.org'
```

3. Remove the MAS-side account access:

```bash
kubectl exec -n ess deployment/ess-matrix-authentication-service -- \
  mas-cli manage kill-sessions <username>

kubectl exec -n ess deployment/ess-matrix-authentication-service -- \
  mas-cli manage lock-user <username> --deactivate
```

4. Remove the email binding for the exact user/email pair.

Preferred path: use the MAS Admin API `DELETE /api/admin/v1/user-emails/{id}` with a `urn:mas:admin` personal session.

Fallback for this deployment: delete the exact `user_emails` row in Postgres by `user_id` and `lower(email)`.

5. Verify:

- Synapse `joined_rooms` is `0`
- MAS sessions are finished
- The exact email no longer exists in `matrixauthenticationservice.user_emails`

## Notes

- cert-manager is required separately; ESS uses it but does not install it.
- Let’s Encrypt is configured via `ClusterIssuer` `letsencrypt-prod` with HTTP-01 solver on Traefik.
- The kubeconfig copied from K3s grants admin-level cluster access; keep it private.
