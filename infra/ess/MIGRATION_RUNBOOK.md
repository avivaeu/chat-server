# ESS VM Migration Runbook (Hetzner + STRATO DynDNS)

This runbook captures the migration path used for Aviva ESS from a smaller VM to a larger VM while preserving data and minimizing downtime.

Scope:
- Hetzner Cloud VM hosting single-node K3s + ESS
- DNS managed via STRATO DynDNS
- Domain: `chat.avivaeu.org` and subdomains

## 1) Preconditions

- Existing server is healthy enough to snapshot.
- You have Hetzner CLI (`hcloud`) access to the right project/context.
- You have SSH access to both old and new VMs.
- You have STRATO DynDNS credentials available locally (do not commit secrets).

Recommended checks:

```bash
hcloud context list
hcloud server list
hcloud primary-ip list
```

## 2) Create snapshot (safety point)

```bash
hcloud server create-image --type snapshot \
  --description "pre-migration-$(date +%F)" \
  <old-server-name>
```

Wait until snapshot status is `available`.

## 3) Create new VM from snapshot

Use same location if you want easy IP/DNS continuity (`fsn1` in this case).

```bash
hcloud server create \
  --name <new-server-name> \
  --type cx33 \
  --image <snapshot-id> \
  --location fsn1
```

Example used:
- Snapshot: `365811499`
- New server: `ubuntu-8gb-fsn1-1`

## 4) Bring new VM online and validate baseline

```bash
hcloud server describe <new-server-name>
ssh <new-server> "hostname && systemctl is-active k3s"
ssh <new-server> "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml; kubectl get nodes -o wide; kubectl get pods -A"
```

If temporary primary IPs are detached, reassign them before testing:

```bash
hcloud primary-ip assign --server <new-server-name> <new-ipv4-id>
hcloud primary-ip assign --server <new-server-name> <new-ipv6-id>
hcloud server poweron <new-server-name>
```

## 5) Update DNS via STRATO DynDNS (no secret in repo)

Store password in a local file outside git tracking (example used: `.secrets/.dyndns`).

```bash
export DYNDNS_USER="<your-strato-dyndns-user>"
export DYNDNS_PASSWORD="$(tr -d '\r\n' < .secrets/.dyndns)"
export TARGET_IP="<new-server-ipv4>"

for host in \
  chat.avivaeu.org \
  web.chat.avivaeu.org \
  matrix.chat.avivaeu.org \
  admin.chat.avivaeu.org \
  account.chat.avivaeu.org \
  mrtc.chat.avivaeu.org \
  push.chat.avivaeu.org
do
  curl -sS -u "$DYNDNS_USER:$DYNDNS_PASSWORD" \
    "https://dyndns.strato.com/nic/update?hostname=$host&myip=$TARGET_IP"
  echo
done
```

Expected response values include `good <ip>` or `nochg <ip>`.

## 6) Validate DNS and service health

```bash
for host in chat.avivaeu.org web.chat.avivaeu.org matrix.chat.avivaeu.org admin.chat.avivaeu.org account.chat.avivaeu.org mrtc.chat.avivaeu.org push.chat.avivaeu.org; do
  printf "%s -> " "$host"
  dig +short A "$host" | tr '\n' ' '
  echo
done
```

```bash
for url in \
  https://chat.avivaeu.org \
  https://web.chat.avivaeu.org \
  https://matrix.chat.avivaeu.org/_matrix/client/versions \
  https://admin.chat.avivaeu.org \
  https://account.chat.avivaeu.org \
  https://mrtc.chat.avivaeu.org \
  https://push.chat.avivaeu.org/_matrix/push/v1/notify
do
  code=$(curl -s -o /dev/null -w "%{http_code}" "$url")
  echo "$url -> $code"
done
```

Expected codes:
- `chat` -> `301`
- `web` -> `200`
- `matrix` -> `200`
- `admin` -> `200`
- `account` -> `200`
- `mrtc` -> `200`
- `push` GET -> `405` (POST-only endpoint)

## 7) Cluster recovery checks (if some pods are not ready)

Use on new VM:

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl get nodes -o wide
kubectl -n ess get pods -o wide
kubectl -n ess get ingress -o wide
```

If a critical pod is stuck after migration, restart only affected pods and re-check:

```bash
kubectl -n ess delete pod ess-postgres-0 --force --grace-period=0
kubectl -n ess delete pod ess-synapse-main-0 --force --grace-period=0
kubectl -n ess get pods -w
```

Then confirm:
- `ess-postgres-0` ready
- `ess-synapse-main-0` ready
- `ess-haproxy` ready

## 8) Rollback DNS (if needed)

Rollback is DNS-based when keeping the old VM as fallback.

```bash
export DYNDNS_USER="<your-strato-dyndns-user>"
export DYNDNS_PASSWORD="$(tr -d '\r\n' < .secrets/.dyndns)"
export ROLLBACK_IP="<old-server-ipv4>"

for host in \
  chat.avivaeu.org \
  web.chat.avivaeu.org \
  matrix.chat.avivaeu.org \
  admin.chat.avivaeu.org \
  account.chat.avivaeu.org \
  mrtc.chat.avivaeu.org \
  push.chat.avivaeu.org
do
  curl -sS -u "$DYNDNS_USER:$DYNDNS_PASSWORD" \
    "https://dyndns.strato.com/nic/update?hostname=$host&myip=$ROLLBACK_IP"
  echo
done
```

Re-run DNS + endpoint checks after rollback.

## 9) Post-migration cleanup

- Update docs/default server IP and operator instructions.
- Keep old VM powered off for a safety window.
- Remove old VM/snapshots only after stable operation window.

## Notes from this migration

- `change-type` can get stuck in provider action queue; snapshot-to-new-VM is a valid fallback.
- If moving across different Hetzner locations, primary IP reassignment may be constrained by location; DNS cutover is the safer universal option.
- Keep DynDNS credentials local only; never commit to git.
