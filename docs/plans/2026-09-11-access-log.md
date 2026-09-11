# Access Log Implementation Plan

> **For Claude:** Implement in this session. SwiftUI / write-swift. No new third-party packages.

**Goal:** Session access log for the LAN proxy — menu row, Settings, Console.app, Control API.

**Architecture:** `LocalProxy` emits `AccessEvent` on a `@Sendable` callback. `AccessLogStore` is `@MainActor` `@Observable`, ring of 300, dual-writes to `os.Logger`. UI reads the store; nothing hits disk.

**Tech Stack:** Swift 6, SwiftUI, Network, `os.Logger`.

---

### Task 1: Model + store

**Files:**
- Create: `Lantern/Models/AccessEvent.swift`
- Create: `Lantern/Services/AccessLogStore.swift`

Pure request-line parser on `AccessEvent`. Store appends, filters by alias host, records last-hit date, logs to Console.

### Task 2: Proxy instrumentation

**Files:**
- Modify: `Lantern/Services/LocalProxy.swift`
- Modify: `Lantern/AppModel.swift`

Four emit points. Keep-alive subsequent request lines emit via the rewriter. WebSocket upgrade → one event then passthrough. Wire `proxy.onAccess` in `AppModel.start()`.

### Task 3: Menu row + Settings + API

**Files:**
- Modify: `Lantern/Views/ServiceRowView.swift`
- Create: `Lantern/Views/LogsSettingsView.swift`
- Modify: `Lantern/Views/SettingsView.swift`
- Modify: `Lantern/AppModel.swift` (`GET`/`DELETE /logs`)
- Modify: `README.md`

### Task 4: Build

Run: `make build`  
Expected: compile succeeds.
