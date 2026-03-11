#!/usr/bin/env python3
"""Simple async bridge between two OpenCode sessions.

Usage example:
python infra/ess/scripts/agent_chat_bridge.py \
  --source-url http://localhost:5000 \
  --source-session ses_xxx \
  --target-url http://localhost:5001 \
  --target-session ses_yyy \
  --request-id req-123
"""

from __future__ import annotations

import argparse
import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from typing import Any, cast


def http_json(
    url: str, method: str = "GET", payload: dict[str, Any] | None = None
) -> tuple[int, Any]:
    body = None
    headers = {}
    if payload is not None:
        body = json.dumps(payload).encode("utf-8")
        headers["content-type"] = "application/json"
    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    with urllib.request.urlopen(req, timeout=30) as resp:
        data = resp.read().decode("utf-8")
        return resp.status, (json.loads(data) if data else {})


def latest_assistant_text(messages: list[dict[str, Any]]) -> tuple[str, str]:
    for msg in reversed(messages):
        info = msg.get("info", {})
        if info.get("role") != "assistant":
            continue
        parts = msg.get("parts", [])
        text = "\n".join(
            p.get("text", "") for p in parts if p.get("type") == "text"
        ).strip()
        if text:
            return info.get("id", ""), text
    return "", ""


def relay_to_target(
    target_url: str,
    target_session: str,
    source_url: str,
    source_session: str,
    request_id: str,
    message: str,
) -> None:
    envelope = (
        "### APP-AGENT->PRIMARY\n"
        f"agent-url: {urllib.parse.urlparse(source_url).netloc}\n"
        f"agent-session-id: {source_session}\n"
        f"request-id: {request_id}\n"
        "status: ok\n"
        "message:\n"
        f"{message}"
    )
    payload = {"parts": [{"type": "text", "text": envelope}]}
    status, _ = http_json(
        f"{target_url}/session/{target_session}/prompt_async",
        method="POST",
        payload=payload,
    )
    if status != 204:
        raise RuntimeError(f"Target relay failed with status {status}")


def wait_for_source_idle_and_reply(
    source_url: str, source_session: str, timeout_s: int
) -> str:
    start = time.time()
    while time.time() - start < timeout_s:
        # lightweight check: once the source session is idle, fetch latest assistant message
        _, status_data = http_json(f"{source_url}/session/status")
        status_data = cast(dict[str, Any], status_data)
        state = status_data.get(source_session, {}).get("type")
        if state == "idle" or state is None:
            _, messages = http_json(f"{source_url}/session/{source_session}/message")
            messages = cast(list[dict[str, Any]], messages)
            _, text = latest_assistant_text(messages)
            if text:
                return text
        time.sleep(1.0)
    raise TimeoutError("Timed out waiting for source assistant reply")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Bridge async response between OpenCode sessions"
    )
    parser.add_argument("--source-url", required=True)
    parser.add_argument("--source-session", required=True)
    parser.add_argument("--target-url", required=True)
    parser.add_argument("--target-session", required=True)
    parser.add_argument("--request-id", required=True)
    parser.add_argument("--timeout", type=int, default=60)
    args = parser.parse_args()

    try:
        reply = wait_for_source_idle_and_reply(
            args.source_url, args.source_session, args.timeout
        )
        relay_to_target(
            target_url=args.target_url,
            target_session=args.target_session,
            source_url=args.source_url,
            source_session=args.source_session,
            request_id=args.request_id,
            message=reply,
        )
        print("relay=ok")
        return 0
    except (
        TimeoutError,
        urllib.error.URLError,
        RuntimeError,
        json.JSONDecodeError,
    ) as exc:
        print(f"relay=error error={exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
