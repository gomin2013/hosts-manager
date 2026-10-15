# Hosts Manager

A native macOS app for editing **`/etc/hosts`** — toggle, add, edit and group entries without `sudo vim`.
Every change is validated, backed up, written atomically by a small privileged helper, and the DNS cache is
flushed for you. Opens from Launchpad / Applications like any other app. English and Thai UI.

> **Status: Phase 1 — static UI prototype.** The window shows mock data; nothing writes to `/etc/hosts` yet.
> Real reads/writes arrive in Phase 2 (Backend Implementation).

Same window layout as [Git Exclude Manager](https://github.com/gomin2013/git-exclude-manager) — if you use one,
you already know the other.

## Features (planned for 1.0)

- **Visual editor** — Add, edit, enable/disable (`# 127.0.0.1 api.test`), search and delete entries.
- **Sections** — a blank line + optional `# heading` is a draggable section; drag anything to reorder.
- **Safe by default** — IPv4/IPv6 and hostname (RFC 1123) validation, system entries (`localhost`,
  `broadcasthost`) are locked, your file's comments and spacing are written back byte-for-byte.
- **Restore Previous** — every save keeps a backup; one click undoes the last save.
- **Preview Raw** — see exactly what will be written to `/etc/hosts`.
- **Import / Export** — load a hosts file (merge or replace) or save the current one.
- **AI Agent (optional)** — ask about your entries with Apple Foundation Models, Ollama, OpenAI, Gemini or Claude.
- **Help panel**, English / Thai, light / dark — ⌘N add, ⌘F search, ⌘W / ⌘Q close and quit.

## Build from source

Requires macOS 14+ and Xcode 16+ (Swift 6).

```bash
git clone https://github.com/gomin2013/hosts-manager.git && cd hosts-manager
swift build && swift test
scripts/build-app.sh && open build/HostsManager.app
```

To launch it from Launchpad, copy it to Applications: `cp -R build/HostsManager.app /Applications/`.

`swift run` works for UI work too, but only the `.app` built by the script can register the helper (Phase 2).

The visual reference lives in [`.prototype/`](.prototype/README.md) — open `.prototype/index.html` in a browser.

## How it works

```
HostsManager.app (window, user)  ── reads /etc/hosts directly (world-readable)
        │ XPC: writeHosts(content, expectedSHA256)
        ▼
HostsManagerHelper (root LaunchDaemon, Phase 2)
        validate → backup → atomic write → flush DNS
```

The helper only ever writes `/etc/hosts`, accepts no paths or commands from the app, and only talks to the
signed Hosts Manager app.

## Project layout

```
Sources/Shared/              models, XPC protocol (shared by app + helper)
Sources/HostsManagerApp/     SwiftUI app (WindowGroup), en/th strings
Sources/HostsManagerHelper/  privileged helper (placeholder in Phase 1)
Tests/HostsManagerTests/     XCTest
scripts/build-app.sh         assembles + ad-hoc signs build/HostsManager.app
.prototype/                  HTML reference design
```

## Requirements

- macOS 14 Sonoma or later
- No third-party dependencies

## License

[MIT](LICENSE) © 2026 Watthajak Jinasam
