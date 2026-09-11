# Access Log — Design

**Date:** 2026-09-11  
**Approach:** In-memory ring buffer + `os.Logger`. Session debugging only.

## Goals

Prove a LAN client reached this Mac, and watch live traffic to `name.local` while developing. No persistence across launches.

## Scope (v1)

| Area | Change |
|------|--------|
| Model | `AccessEvent` + `AccessLogStore` (newest first, cap 300) |
| Proxy | Emit on missing host / unknown host / upstream down / each forwarded request line |
| Menu row | Last 3 hits when expanded; collapsed subtitle `just now` for 10s after a hit |
| Settings | Logs pane: Access / Activity / All, search, filter, clear, copy |
| Console.app | `subsystem:app.lantern` — `proxy` for hits, `app` for activity |
| Control API | `GET /logs`, `DELETE /logs` |

## Event

`time`, `method`, `path` (query kept, truncated to 200), `host`, `client` (LAN IP if known), `localPort`, `outcome` (`forwarded` / `unknownHost` / `missingHost` / `upstreamDown`).

No bodies, no headers. WebSocket upgrade: one event, then passthrough. No upstream status code in v1 (raw TCP pipe).

Activity (same ring): broadcast on/off, proxy bound/stopped/bind failed, service add/update/remove/toggle. Console category `app`.

## Out of scope

Disk/JSONL persistence, status-code peek, pause, per-row jump-to-Settings.
