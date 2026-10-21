# Prototype

Interactive HTML mock of the Hosts Manager main window. It is the visual and behavioural reference for the
SwiftUI app — change the design here first, then mirror it in Swift. The layout deliberately matches
**git-exclude-manager** so its users feel at home.

## Files

| File | Purpose | SwiftUI counterpart |
|---|---|---|
| `index.html` | Window: toolbar, hosts list, side panels; editor / delete / raw preview / about sheets | `HostsView`, `HostRow`, `SidePanels`, `EditorSheet`, `RawPreviewView`, `SettingsPanels` |
| `stylesheets/app.css` | macOS system look, light / dark | system semantic colors |
| `javascripts/shared.js` | Mock lines, **i18n table (en / th)**, `lineText`, validation, system-entry rule | `Localizable.strings`, `HostsLine.text`, `HostEntry.isSystem` |
| `javascripts/main.js` | Rows, search, toggle, editor, delete, drag, sections, panels, settings | `HostsViewModel`, `EditorViewModel` |

## Quick Run

Open `index.html` in a browser, or:

```bash
cd .prototype && python3 -m http.server 8080   # → http://localhost:8080
```

## Layout (same as git-exclude-manager)

```
┌ Hosts Manager ───────────────────────────────────────────── ⚙ Settings ▾ ┐
│ /etc/hosts · helper status            │ › AI Agent                    ⚙  │
│ ⌕ Search IP or hostname...            │   Not Set                        │
│ ⊕Add ☰Section ⤓Import ⤒Export  ↶Restore Previous 👁Preview Raw │ chat · quick messages · input │
│ ## Host Database … (comment block)    │ › Help                           │
│ ● 127.0.0.1  localhost            🔒  │   topics                         │
│ ≡ Local dev ───────────────────── 🗑  │                                  │
│ ● 127.0.0.1  api.test web.test  ✎ 🗑  │                                  │
│ 8 entries (5 enabled)                 │                                  │
└───────────────────────────────────────┴──────────────────────────────────┘
```

## Behaviours

- **Rows** (same rule as `HostsViewModel.rows`): a blank line is a **section**; exactly one `# heading` right after it
  is the section's title ("Add heading…" when empty). Any other run of comment lines is a verbatim **comment block**;
  the macOS header ("Host Database") above the first entry can't be deleted.
- **System entries** (`127.0.0.1 localhost`, `255.255.255.255 broadcasthost`, `::1 localhost`) — 🔒, no toggle,
  edit, delete or drag.
- **Search** (⌘F) — IP or hostname, case-insensitive; only matching entries are shown; drag is disabled.
- **Add / Edit** (⊕, ⌘N, ✎, double-click) — live validation of IP (IPv4 / IPv6) and each hostname (RFC 1123).
- **Section** heading — type in "Add heading…" to rename (writes `# heading` after the blank line).
- **Delete** — confirmation sheet for entries, sections and comment blocks.
- **Drag** — any row except system ones, also across sections.
- **Preview Raw** — the file exactly as it would be written, with Copy.
- **Side panels** — AI Agent (mock here; works in the app — ⚙ picks Apple / Ollama / OpenAI / Gemini / Claude) and
  Help; ▸/▾ folds, remembered.
- **Settings** (⚙) — language en / th, appearance system / light / dark, About.
- Import / Export / Restore Previous are disabled here (they need file panels / the helper) — they work in the app.
- Esc closes any sheet. The title bar is drawn for context only — ⌘Q / ⌘W come from the native app menu.

## Notes

- Mock only: nothing touches `/etc/hosts`; reloading the page resets the data.
- Keep `shared.js` keys and `Sources/HostsManagerApp/Resources/{en,th}.lproj/Localizable.strings` in sync
  (`%@` / `%ld` placeholders are the same in both) — `LocalizationTests` checks it.
