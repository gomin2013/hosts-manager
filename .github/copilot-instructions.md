# GitHub Copilot Instructions — Hosts Manager

## Project Context

Native macOS **app** (Dock / Launchpad, `WindowGroup`) for editing `/etc/hosts` safely — same app type as
git-exclude-manager — plus a root **LaunchDaemon helper** reached over XPC, the only code allowed to write
`/etc/hosts`. Standard app menu provides ⌘Q / ⌘W; one main window (`CommandGroup(replacing: .newItem)` → Add Entry).

| Item | Value |
|---|---|
| Platform | macOS 14+ |
| Language | Swift 6 (tools 6.0, strict concurrency) |
| Build | SPM only (`Package.swift`) — no Xcode project; `.app` assembled by `scripts/build-app.sh` |
| Dependencies | **None** (CI fails otherwise) |
| Bundle IDs | `com.hostsmanager.app` / `com.hostsmanager.helper` (Mach service = helper ID) |
| Languages | English + Thai (`en.lproj`, `th.lproj`) |
| Tests | XCTest — `swift test` |
| Lint | `swiftlint lint --strict` |

## Layout

```
Sources/Shared/              HelperProtocol.swift, Models/ (HostEntry, HostsLine, HelperError),
                             Services/ (HostsParser, Validation)
Sources/HostsManagerApp/     HostsManagerApp.swift, Views/, ViewModels/, Services/ (XPCService, HelperService,
                             LanguageService), Resources/{en,th}.lproj/Localizable.strings, Info.plist
Sources/HostsManagerHelper/  main.swift, Info.plist
Tests/HostsManagerTests/     one file per concern, Fixtures/ for hosts samples
.prototype/                  static HTML reference design — UI must match it
```

## Architecture

- **MVVM:** Views hold no logic → `@MainActor @Observable` ViewModels → Services.
- **Models:** `struct` + `Codable, Hashable, Sendable`.
- **Reads:** the app reads `/etc/hosts` directly (world-readable).
- **Writes:** only via `XPCService.writeHosts(content, expectedSHA256:)` → helper.
- **Line model:** `HostsLine` = `.entry / .comment / .blank / .unknown`. A `#` line whose remainder is a valid
  entry is a *disabled* entry.
- **Rows (same as git-exclude-manager):** a blank line is a section; exactly one `# heading` right after it is the
  section title. Other comment runs are verbatim comment blocks (`HostsViewModel.rows(from:)`).
- **UI layout mirrors git-exclude-manager:** toolbar + ⚙ Settings, action row (Add · Section · Import · Export ·
  Restore Previous · Preview Raw), right-column panels (AI Agent, Help) in `SidePanels.swift`.
- **Round-trip is lossless:** `serialize(parse(x)) == x` for untouched files.

```swift
@objc protocol HelperProtocol {
    func version(reply: @escaping (String) -> Void)
    func writeHosts(_ content: String, expectedSHA256: String, reply: @escaping (NSError?) -> Void)
}
```

## Security Rules (root helper — non-negotiable)

- The helper writes **only** `/etc/hosts`; never accept a path, filename, or command from the client.
- Re-validate on the helper side: ≤ 1 MB, valid UTF-8, no NUL; reject if on-disk SHA-256 ≠ `expectedSHA256`.
- `NSXPCListener.setConnectionCodeSigningRequirement` — only `com.hostsmanager.app` may connect.
- Backup to `/Library/Application Support/HostsManager/Backups/` (root-owned) — **never** `/tmp` or `/var/tmp`.
- Atomic write: temp file in `/private/etc/` → `rename` → `0644 root:wheel`.
- DNS flush with fixed argv via `Process` (`/usr/bin/dscacheutil -flushcache`, `/usr/bin/killall -HUP mDNSResponder`)
  — never through a shell.
- Never use `AuthorizationExecuteWithPrivileges`; never store passwords or tokens.
- System entries (`localhost`, `broadcasthost`, `::1 localhost`) are read-only.

## Code Style

- `@MainActor` on ViewModels; wrap XPC callbacks with `withCheckedThrowingContinuation`.
- Validate IPs with `inet_pton` (no regex); hostnames per RFC 1123 (≤ 253 chars, labels ≤ 63, no leading/trailing `-`).
- Logging: `Logger(subsystem: "com.hostsmanager", category: …)` — no `print()`.
- No `DispatchQueue.main.async`, no UIKit, no business logic in Views.
- Every user-facing string goes through `String(localized:)`; add the key to **both** `en` and `th`.
- System semantic colors only; icon-only buttons need `.help()` + `.accessibilityLabel()`.
- SwiftLint limits: line 120, file 400, function body 50, cyclomatic complexity 10.

## Naming

| Kind | Convention | Example |
|---|---|---|
| View | noun + `View`/`Row`/`Sheet` | `HostsView`, `HostRow`, `EditorSheet` |
| ViewModel | feature + `ViewModel` | `HostsViewModel` |
| Service | noun + `Service` (stateless where possible) | `XPCService` |
| Localization key | `area.item` | `btn.save`, `err.invalidIP`, `help.toggle` |
| Test | `test<Behavior>` | `testDisabledEntryRoundTrips` |

## Testing

- Parser: fixtures (stock macOS hosts, CRLF, tabs, IPv6, inline comments, garbage lines) must round-trip.
- Helper logic: run against a temp directory — tests must never touch the real `/etc/hosts`.
- XPC: integration tests with `NSXPCListener.anonymous()`.
- New XPC method ⇒ update `HelperProtocol` + add an integration test.

## Commits

`2026 <Verb> <Thing> (<Part>).` — e.g. `2026 Added Backend Implementation (Sources).`

## Context Documents

Local planning docs live in `.claude/` (not committed): `steering/` (product, tech, constraints, roadmap),
`specs/` (requirements, design, decisions, phases), `plugins/*/skills/` (parser, privileged helper, window app patterns).
