# Changelog

## v1.1.0 — 2026-10-24

A redesign of the main window — same layout as before (and as
[Git Exclude Manager](https://github.com/gomin2013/git-exclude-manager) 1.1), modernised.

### Added

- **History** — a new side panel with the last 30 saves, newest first, each named after what changed ("Turned off
  api.test", "Named section Staging"). Double-click a step (or its ↩ button) to go back to it; going back is a new
  step too, so nothing is lost. Pin versions you want to keep — the file as it was when the app opened is pinned for
  you — and remove a step you don't need with its trash button. Built on the backups the helper keeps (now 30, was
  20); pins and removed steps are stored in `~/Library/Application Support/HostsManager`. Replaces the **Restore
  Previous** button.
- **Side panels as a tool window** — an icon rail on the right edge opens one panel at a time at full height:
  History · AI Agent · Help, with Appearance · Language · About at the bottom (⌥⌘1…6; **–** hides it and gives the
  list the full width). AI Agent opens on first launch. **Help › Hosts Manager Help** (⌘?) opens the Help panel.
- **Appearance** panel — Light / Dark / System, 16 accent colours and 8 gradient themes.
- **12 languages** — English, ไทย, 日本語, 한국어, Tiếng Việt, Bahasa Indonesia, Bahasa Melayu, Filipino, 简体中文,
  繁體中文, Español and Русский. The **Language** panel searches by native name, English name, the name in your
  current language or code; the first launch follows your macOS language.
- **AI Agent** — a start page says what it's for, that `/etc/hosts` is sent with each question, and offers
  one-click questions (or Set Up AI Provider… when none is set). Answers stream in with live steps (attached → waiting → thinking → writing) and seconds, the model's
  thinking when the provider sends it (Ollama, Claude, Gemini), Markdown answers with copyable code blocks, and **Stop**.
- Keyboard: **Space** turns selected entries on/off, **⌫** deletes them, **Return** / double-click edits an entry or
  renames a section.

### Changed

- **New app icon** — a Liquid Glass robot whose visor shows a globe (16–64 px keep the flat globe).
- **Look** — Liquid Glass on macOS 26 (material on 14–15) for search, buttons and the side panel; Sukhumvit Set for
  interface text, SF Mono for addresses and hostnames; checkboxes instead of green circles; no cards; edit / delete
  sit at the end of every row in a quiet secondary colour (no wall of red trash cans — and no hover-only buttons,
  which stuttered while scrolling); sections get an accent bar; the macOS header folds away.
- The window title is `/etc/hosts` with the helper status underneath; when the helper isn't allowed yet, a banner
  above the list says why and opens Login Items.
- Deleting no longer asks for confirmation — every delete can be undone in History.
- The toolbar buttons are gone: Appearance, Language and About are panels on the rail (Settings will come back once
  there is more to set).
- `-demo` no longer registers the helper (it never writes), so a demo run can't touch the installed helper.

### Fixed

- **"Add heading…" looked frozen** — clicking a section heading never let you type (the list took the click). A new
  section now opens its heading for typing (scrolled into view); double-click or Return renames; Esc cancels.
- **Liquid Glass was missing** — the build stamped the app as built with the macOS 14 SDK, so macOS 26 drew it the
  old way. It now records the real SDK (minimum macOS stays 14).
- Contrast: your chat bubbles no longer use white text on a light accent.
- AI Agent: reasoning that some models (qwen3 on Ollama) leak into the answer, ending in a stray `</think>`, now goes
  to the folded thinking; long code lines scroll inside their block instead of running under the panel edge.
- **Comments on entries added extra hostnames** — v1.0 saved `127.0.0.1 a.test # dev box`, and macOS resolves every
  word after the IP, so `#`, `dev` and `box` pointed at 127.0.0.1 too. Comments are now saved on their own `## dev box`
  line above the entry. Entries that still have a same-line comment show ⚠️ and are fixed on your next save.

### Website

- The site speaks the same 12 languages: a language button opens a searchable list; English and Thai are built in,
  the others load on demand. A Thai page at `/hosts-manager/th/` for search engines.
- Phones: Download / About become icons, the app name and the language code show when there is room.
- History is 30 saves; the hosts example shows a `## comment` line.

### Installation

Same as v1.0.2: download `HostsManager-1.1.0.dmg` (and `SHA256SUMS.txt`), drag **Hosts Manager** to
**Applications** (replace the old copy), allow the first launch in **System Settings → Privacy & Security → Open
Anyway** (or `xattr -dr com.apple.quarantine "/Applications/HostsManager.app"`). The helper you already allowed
should keep working; if a banner asks you to allow Hosts Manager, turn it on again in **System Settings → General →
Login Items & Extensions**. Requires an Apple silicon Mac with macOS 14 or later; Liquid Glass needs macOS 26.

## v1.0.2 — 2026-10-17

### Website

- **New site:** [gomin2013.github.io/hosts-manager](https://gomin2013.github.io/hosts-manager/) — features, a
  download and install guide, Privacy Policy and Terms of Use, in English and Thai.
- README links to the website.

### App

- Nothing changes in normal use — if you already run 1.0.0 there is nothing to update.
- For screenshots and recordings: `open HostsManager.app --args -demo` now lets you toggle, add, drag and
  Restore Previous on sample data. Edits stay in memory; `/etc/hosts` is never read or written.

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
