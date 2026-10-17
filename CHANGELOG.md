# Changelog

## v1.0.2 — 2026-10-17

### Website

- **New site:** [gomin2013.github.io/hosts-manager](https://gomin2013.github.io/hosts-manager/) — features, a
  download and install guide, Privacy Policy and Terms of Use, in English and Thai.
- README links to the website.

### App

- No changes since v1.0.0 apart from the version number — if you already run 1.0.0 there is nothing to update.

### Installation

Same as v1.0.0: download `HostsManager-1.0.2.dmg` (and `SHA256SUMS.txt`), drag **Hosts Manager** to
**Applications**, allow the first launch in **System Settings → Privacy & Security → Open Anyway** (or
`xattr -dr com.apple.quarantine "/Applications/HostsManager.app"`), then allow the helper once in
**System Settings → General → Login Items & Extensions**. Requires an Apple silicon Mac with macOS 14 or later.

_v1.0.1 was never published; this release replaces it._

## v1.0.0 — 2026-10-16

First release of the **rewritten Hosts Manager** — a native macOS app for editing `/etc/hosts`, built on the same
design as [Git Exclude Manager](https://github.com/gomin2013/git-exclude-manager). It replaces the old Settings
Extension / menu bar versions of this repository: a regular app you open from Launchpad. English and Thai UI.

### Highlights

- **Edit `/etc/hosts` visually** — add, edit (live IPv4 / IPv6 and hostname validation), enable/disable
  (`# 127.0.0.1 api.test`), search (⌘F) and delete entries. `localhost` / `broadcasthost` are locked 🔒.
- **Your file stays yours** — untouched lines keep their exact spacing, tabs, comments and line endings; the macOS
  header is shown as-is at the top.
- **Sections & drag** — a blank line plus an optional `# heading` is a section; type the heading inline and drag
  rows (a section moves with its heading). **⌘-click / ⇧-click** selects several rows — sections and entries — to
  drag them together. Double-click or right-click → Edit.
- **Safe writes** — a small root helper (LaunchDaemon via `SMAppService`) is the only thing that writes the file.
  It validates the content (must keep `127.0.0.1 localhost`), refuses to overwrite a file another app changed,
  keeps the last 20 backups, writes atomically (0644) and flushes the DNS cache. It only accepts the exact app it
  ships inside (pinned by code-signature hash).
- **Restore Previous** — one click reverts the last save; click again to undo.
- **Preview Raw / Import / Export** — see exactly what will be written (Copy ⇧⌘C); import any hosts file
  (**Merge** new entries or **Replace** yours — this Mac's system entries stay); export a byte-identical copy.
- **AI Agent (optional)** — chat about your entries, Quick Messages and ✨ Generate Comment with Apple Foundation
  Models (on-device), Ollama (local), OpenAI, Gemini or Claude. Questions include your `/etc/hosts` — choose an
  on-device provider to keep it on your Mac. API keys are stored in the Keychain; the AI never edits the file.
- **Native macOS** — Help panel, light / dark / system appearance, VoiceOver labels, and a fennec fox icon that
  renders natively on macOS 26.

### Requirements

- macOS 14 Sonoma or later (Apple Foundation Models needs macOS 26 with Apple Intelligence enabled)
- AI features are optional; cloud providers need your own API key, Ollama needs `ollama serve` running

### Installation

Download `HostsManager-1.0.0.dmg` (and `SHA256SUMS.txt`) from the GitHub release, open it and drag
**Hosts Manager** to **Applications** — run it from Applications, not from the DMG.

This build is **not notarized** (no Developer ID yet), so macOS blocks the first launch once:
open it, then **System Settings → Privacy & Security → Open Anyway** — or run
`xattr -dr com.apple.quarantine "/Applications/HostsManager.app"`.
Then allow the helper once in **System Settings → General → Login Items & Extensions**.
