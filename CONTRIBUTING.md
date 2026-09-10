# Contributing to Lantern

Thanks for helping improve Lantern.

## Development setup

1. macOS 26+ and Xcode 26+
2. [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
3. Clone and generate the project:

```bash
git clone https://github.com/<you>/lantern.git
cd lantern
xcodegen generate
open Lantern.xcodeproj
```

Or build from the CLI:

```bash
./scripts/build.sh
```

## Guidelines

- Keep the menu-bar UX dense and native (BetterDisplay-style sections/rows).
- Prefer fixing behavior in Lantern (e.g. Host rewrite) over asking users to patch their apps.
- Swift 6 strict concurrency — avoid silencing isolation issues without reason.
- Don’t commit secrets, personal DerivedData, or local signing identities.
- Match existing code style; keep diffs focused.

## Pull requests

1. Branch from `main`
2. Describe the problem and how you tested (Broadcast on/off, portless URL, Vite/Node app)
3. Include screenshots for UI changes
4. Keep PRs small when possible

## Reporting bugs

Use GitHub Issues and include:

- macOS / Xcode version
- Whether Broadcast + Easy URLs are enabled
- `curl -s http://127.0.0.1:19247/status`
- Whether `http://name.local` fails to resolve, connect, or returns an app error
