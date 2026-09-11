#!/usr/bin/env bash
# Control API + proxy e2e for access/activity logs.
# Relaunches the Debug menu bar app (same as make run).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

API="${API:-http://127.0.0.1:19247}"
TOKEN_FILE="${HOME}/Library/Application Support/Lantern/control-token"

if [[ "${SKIP_BUILD:-}" != "1" ]]; then
  make build
fi
make relaunch

wait_for_api() {
  local i
  for i in $(seq 1 40); do
    if curl -sf "$API/status" >/dev/null; then
      return 0
    fi
    sleep 0.25
  done
  echo "Control API did not come up at $API" >&2
  return 1
}

wait_for_api

for i in $(seq 1 20); do
  if [[ -s "$TOKEN_FILE" ]]; then
    break
  fi
  sleep 0.2
done
TOKEN=$(tr -d '[:space:]' < "$TOKEN_FILE")
AUTH=(-H "X-Lantern-Token: $TOKEN" -H "Content-Type: application/json")

curl -sf -X POST "$API/broadcast" "${AUTH[@]}" \
  -d '{"enabled":false}' >/dev/null
sleep 0.4
curl -sf -X DELETE "$API/logs" "${AUTH[@]}" >/dev/null

NAME="e2e$(date +%s)"
ADD_JSON=$(curl -sf -X POST "$API/aliases" "${AUTH[@]}" \
  -d "{\"name\":\"$NAME\",\"localPort\":59999}")
ALIAS_ID=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["alias"]["id"])' <<<"$ADD_JSON")

curl -sf -X POST "$API/broadcast" "${AUTH[@]}" \
  -d '{"enabled":true}' >/dev/null

STATUS=""
for _ in $(seq 1 20); do
  STATUS=$(curl -sf "$API/status")
  python3 -c 'import json,sys; s=json.loads(sys.argv[1]); sys.exit(0 if s.get("proxyRunning") or s.get("error") else 1)' "$STATUS" && break
  sleep 0.25
done
LOGS=$(curl -sf "$API/logs")

python3 - "$STATUS" "$LOGS" "$API" "$ALIAS_ID" "$TOKEN" "$NAME" <<'PY'
import json, sys, urllib.request

status = json.loads(sys.argv[1])
logs = json.loads(sys.argv[2])
api = sys.argv[3]
alias_id = sys.argv[4]
token = sys.argv[5]
name = sys.argv[6]
events = logs.get("events") or []
kinds = {e.get("activity") for e in events if e.get("kind") == "activity"}

assert logs.get("ok") is True, logs
assert logs.get("file"), logs
assert "serviceAdded" in kinds, f"missing serviceAdded in {kinds}"
assert "broadcastOn" in kinds, f"missing broadcastOn in {kinds}"
assert "proxyBound" in kinds or "proxyBindFailed" in kinds, f"missing proxy result in {kinds}"

proxy_running = bool(status.get("proxyRunning"))
port = int(status.get("proxyPort") or 8787)
print(f"proxyRunning={proxy_running} port={port} file={logs.get('file')} activity={sorted(k for k in kinds if k)}")

def authed(url, method="GET"):
    return urllib.request.Request(url, method=method, headers={"X-Lantern-Token": token})

if proxy_running:
    req = urllib.request.Request(
        f"http://127.0.0.1:{port}/missing",
        headers={"Host": f"{name}.local"},
        method="GET",
    )
    try:
        urllib.request.urlopen(req, timeout=3)
    except Exception as exc:
        print(f"probe error (expected): {type(exc).__name__}: {exc}")

    hit = None
    after = {}
    for _ in range(16):
        with urllib.request.urlopen(f"{api}/logs") as resp:
            after = json.loads(resp.read().decode())
        access = [e for e in after.get("events") or [] if e.get("kind") == "access"]
        hit = next((e for e in access if name in (e.get("host") or "")), None)
        if hit:
            break
        import time
        time.sleep(0.15)
    assert hit is not None, after
    assert hit.get("outcome") in {"upstreamDown", "forwarded", "unknownHost"}, hit
    print(f"access outcome={hit.get('outcome')} path={hit.get('path')}")
else:
    print("skip access hit: proxy not bound")

urllib.request.urlopen(authed(f"{api}/aliases/{alias_id}", "DELETE"))
print("e2e-logs ok")
PY
