---
name: aviva-chat-user-deletion
description: Use when deleting Aviva chat users in ESS, especially by email, Synapse MXID, MAS username, media, or room history.
---

# Aviva Chat User Deletion

Use only for this ESS deployment.

Always resolve the exact target first.

## Target resolution

- Find the exact MAS user from `matrixauthenticationservice.user_emails` using `lower(email)=lower('<email>')`.
- Find the exact Synapse MXID from `synapse.user_threepids` or the known localpart.
- Never use wildcard deletes.

## Safe order

1. Issue an admin compatibility token from `avivaadmin`:

```bash
kubectl exec -n ess deployment/ess-matrix-authentication-service -- \
  mas-cli manage issue-compatibility-token avivaadmin AIAgentAdminToken --yes-i-want-to-grant-synapse-admin-privileges
```

2. Use the token on the Synapse admin API for the exact MXID:

- Redact events: `POST /_synapse/admin/v1/user/<mxid>/redact` with `{"rooms":[]}`
- Delete media: `DELETE /_synapse/admin/v1/users/<mxid>/media`
- Deactivate and erase: `POST /_synapse/admin/v1/deactivate/<mxid>` with `{"erase":true}`

3. Use MAS CLI for the exact username:

- `mas-cli manage kill-sessions <username>`
- `mas-cli manage lock-user <username> --deactivate`

4. Remove the exact email binding.

- Preferred: MAS Admin API `DELETE /api/admin/v1/user-emails/{id}` if a `urn:mas:admin` token is available.
- Fallback in this deployment: delete the exact `matrixauthenticationservice.user_emails` row by `user_id` and `lower(email)`.

5. Verify only the target changed.

- Synapse `joined_rooms` is `0` for the target.
- No active MAS sessions remain for the target.
- The email is gone from `matrixauthenticationservice.user_emails`.
- Upstream Zitadel cleanup is still manual.
