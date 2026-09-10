# Lantern

**Portless LAN names for local apps.**  
Menu bar app for macOS that advertises `http://name.local` on your Wi‑Fi — the missing piece when OrbStack’s `*.orb.local` only works on the host.

[![CI](https://github.com/niskan516/lantern/actions/workflows/ci.yml/badge.svg)](https://github.com/niskan516/lantern/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

> Replace the badge repo path with yours after pushing to GitHub.

## Why

| Without Lantern | With Lantern |
|-----------------|--------------|
| `http://192.168.x.x:5173` | `http://probus.local` |
| OrbStack `*.orb.local` (this Mac only) | Real LAN Bonjour name |
| Every phone must remember ports | Default HTTP port via local reverse proxy |

```text
Phone  →  http://probus.local
              ↓  mDNS (Bonjour)
         Mac LAN IP :80
              ↓  Lantern proxy (rewrites Host)
         127.0.0.1:5173  (Vite / Docker / anything)
```

No changes required in the target project — Lantern rewrites `Host` to localhost so Vite and friends accept the request.

## Features

- Menu bar only (no Dock icon)
- Pick listening ports from a live list
- Edit / remove services
- Portless URLs via reverse proxy (port 80, or backup 8787)
- Host-header rewrite for picky dev servers
- Loopback Control API for scripts
- Settings sidebar (“Easy URLs”)

## Requirements

- macOS 14+ (developed on macOS 26/27)
- Xcode 16+ (Swift 6)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## Install (from source)

```bash
git clone https://github.com/<you>/lantern.git
cd lantern
chmod +x scripts/build.sh
./scripts/build.sh
open build/DerivedData/Build/Products/Debug/Lantern.app
```

Or:

```bash
xcodegen generate
open Lantern.xcodeproj
```

Run the **Lantern** scheme.

## Usage

1. Click the antenna icon in the menu bar  
2. Turn on the master **Broadcast** toggle  
3. **Add Service** — pick a listening port (or type one)  
4. On another device on the same Wi‑Fi, open the URL (e.g. `http://probus.local`)

**Easy URLs** (Settings):

- **No port (recommended)** → `http://name.local` (needs bind on :80)  
- **Backup :8787** → `http://name.local:8787` if port 80 is blocked  

## Control API

Loopback only: `http://127.0.0.1:19247`

```bash
curl -s http://127.0.0.1:19247/status | jq
curl -s http://127.0.0.1:19247/aliases | jq
curl -s -X POST http://127.0.0.1:19247/broadcast \
  -H 'Content-Type: application/json' \
  -d '{"enabled":true}'
curl -s -X POST http://127.0.0.1:19247/aliases \
  -H 'Content-Type: application/json' \
  -d '{"name":"web","localPort":8080}'
```

## Architecture

```text
MenuBarExtra UI
  ├── AliasStore          persisted JSON in Application Support
  ├── BroadcastEngine     DNS-SD / dns-sd -P  → name.local → LAN IP
  ├── LocalProxy          :80/:8787  Host-based reverse proxy
  ├── PortDiscovery       lsof listening TCP ports
  └── ControlServer       127.0.0.1:19247 JSON API
```

## Project layout

```text
Lantern/                 Swift sources
project.yml              XcodeGen spec
scripts/build.sh         generate + xcodebuild
docs/plans/              design notes
.github/                 CI + issue templates
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).  
Security reports: [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE)
