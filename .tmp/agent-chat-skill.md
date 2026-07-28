# Agent Chat Skill (OpenCode local API)

This document defines a simple, reusable protocol for async agent-to-agent coordination between two local OpenCode servers.

- Primary agent API: `http://localhost:5001`
- App agent API: `http://localhost:5000`

## Message Protocol

Use explicit Markdown headers to distinguish message origin.

```md
### USER->PRIMARY
agent-url: localhost:5001
agent-session-id: <primary-session-id>
request-id: <request-id>
topic: <topic>
message:
<user request>

### PRIMARY->APP-AGENT
agent-url: localhost:5000
agent-session-id: <app-agent-session-id>
reply-to-agent-url: localhost:5001
reply-to-agent-session-id: <primary-session-id>
request-id: <same-request-id>
message:
<task for app agent>

### APP-AGENT->PRIMARY
agent-url: localhost:5000
agent-session-id: <app-agent-session-id>
request-id: <same-request-id>
status: ok|needs-input|error
message:
<response>
```

## How to get current session id

### Primary agent (`:5001`)

```bash
curl -sS http://localhost:5001/session/status
curl -sS http://localhost:5001/session
```

`/session/status` returns busy sessions. `/session` returns full session records.

### App agent (`:5000`)

```bash
curl -sS http://localhost:5000/session/status
curl -sS http://localhost:5000/session
```

## Async workflow

1. Create new app-agent conversation (new session):

```bash
curl -sS -X POST http://localhost:5000/session -H "content-type: application/json" -d '{}'
```

2. Send async message (non-blocking):

```bash
curl -sS -X POST "http://localhost:5000/session/<SESSION_ID>/prompt_async" \
  -H "content-type: application/json" \
  -d '{"parts":[{"type":"text","text":"<PROTOCOL_MESSAGE>"}]}'
```

3. Poll for assistant reply:

```bash
curl -sS "http://localhost:5000/session/<SESSION_ID>/message"
```

## How primary session detects arrival

Use `request-id` correlation and one of these modes:

- Passive: primary polls `GET /session/<app-session-id>/message` and looks for the first assistant text that contains the same `request-id`.
- Active relay: once found, primary forwards a normalized `### APP-AGENT->PRIMARY` envelope into the primary session via `POST /session/<primary-session-id>/prompt_async`.

Relay payload example:

```json
{
  "parts": [
    {
      "type": "text",
      "text": "### APP-AGENT->PRIMARY\nagent-url: localhost:5000\nagent-session-id: <app-session-id>\nrequest-id: <request-id>\nstatus: ok\nmessage:\n<assistant reply>"
    }
  ]
}
```

This is how a response that arrives in another session becomes identifiable "here": the same `request-id` is echoed back into the primary session.

## Trigger model (chicken-and-egg)

There is no magic cross-session wake-up by default. One process must be listening.

- Recommended trigger: run a small bridge/listener process that watches source status/events and relays replies.
- API support for listeners exists (`GET /event` and `GET /global/event` as SSE streams).
- Fallback if SSE is not used: poll `GET /session/status` and `GET /session/<id>/message`.

Reference implementation in this repo:

- `infra/ess/scripts/agent_chat_bridge.py`

Example:

```bash
python infra/ess/scripts/agent_chat_bridge.py \
  --source-url http://localhost:5000 \
  --source-session <app-session-id> \
  --target-url http://localhost:5001 \
  --target-session <primary-session-id> \
  --request-id req-123
```

## SQLite correlation fallback

OpenCode persists sessions/messages in:

- `~/.local/share/opencode/opencode.db`

Useful checks:

```bash
sqlite3 ~/.local/share/opencode/opencode.db ".tables"
sqlite3 ~/.local/share/opencode/opencode.db "SELECT id,title,directory,time_updated FROM session ORDER BY time_updated DESC LIMIT 10;"
sqlite3 ~/.local/share/opencode/opencode.db "PRAGMA table_info(session);"
sqlite3 ~/.local/share/opencode/opencode.db "PRAGMA table_info(message);"
```

This can recover session ids and correlate remote/primary sessions when env vars are missing.

## Model verification (must be GPT-5.3 Codex)

Verify the latest assistant message metadata includes:

- `providerID: openai`
- `modelID: gpt-5.3-codex`

Example check:

```bash
python - <<'PY'
import json, urllib.request
sid = "<SESSION_ID>"
data = json.loads(urllib.request.urlopen(f"http://localhost:5000/session/{sid}/message").read().decode())
assist = [m for m in data if m.get("info", {}).get("role") == "assistant"]
info = assist[-1]["info"]
print(info.get("providerID"), info.get("modelID"))
PY
```

## Tested Result

A live test was executed:

- New remote session created on `:5000`
- Async prompt sent via `/prompt_async`
- Reply received: `ACK /Users/fa2gq58/code/aviva/aviva-chat-ios`
- Remote assistant metadata confirmed: `openai gpt-5.3-codex`
