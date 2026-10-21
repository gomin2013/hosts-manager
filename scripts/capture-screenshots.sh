#!/bin/bash
# Website / README screenshots from the app's -demo mode (steering: never real hostnames). Same idea as
# git-exclude-manager's scripts/capture-screenshots.sh. Brings each window to the front for a few seconds — don't type
# while it runs (~1 min, ~3 min with --ai). Settings go in as launch arguments (argument domain), so your own
# preferences are never touched.
# Usage: scripts/capture-screenshots.sh [--ai]
#   --ai  also the AI Agent answer, through your configured AI provider (Ollama qwen3.8 takes ~90 s).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/HostsManager.app"
IMG="$ROOT/docs/assets/img"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"; pkill -f "$APP/Contents/MacOS/HostsManager" || true' EXIT

# Window ID of the app's main window (screencapture -l keeps the rounded corners transparent)
cat > "$TMP/winid.swift" <<'EOF'
import CoreGraphics
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
for w in list where (w[kCGWindowOwnerName as String] as? String) == "Hosts Manager"
    && (w[kCGWindowLayer as String] as? Int) == 0
    && ((w[kCGWindowBounds as String] as? [String: Any])?["Width"] as? Double ?? 0) > 600 {
    print(w[kCGWindowNumber as String]!); break
}
EOF
swiftc -O "$TMP/winid.swift" -o "$TMP/winid"

# shot <name> <seconds to wait> [app args]
shot() {
    local name=$1 wait=$2; shift 2
    pkill -f "$APP/Contents/MacOS/HostsManager" || true
    sleep 1.5
    open -n "$APP" --args -demo -app.language en "$@"
    sleep 5
    # -demo sizes its own window to 1432×972 (HostsManagerApp)
    osascript -e 'tell application id "com.hostsmanager.app" to activate'
    sleep "$wait"
    screencapture -x -o -l"$("$TMP/winid")" "$TMP/$name.png"
    echo "captured $name"
}

# Debug build: -demoHistory, -editEntry and -ask are DEBUG-only; the window is otherwise the release UI
"$ROOT/scripts/build-app.sh" debug >/dev/null
shot dark 2 -ui.toolPanel agent -app.appearance dark
shot light 2 -ui.toolPanel agent -app.appearance light
shot history 2 -ui.toolPanel history -app.appearance dark -demoHistory
shot editor 2 -ui.toolPanel agent -app.appearance dark -editEntry

# Crops (1432×972 window: tool window x 1068…1388 from y 42; Local dev…Blocked sections y 258…568; editor sheet
# x 504…928, y 360…612)
cp "$TMP/dark.png" "$IMG/hm-main-dark.png"
cp "$TMP/light.png" "$IMG/hm-main-light.png"
cp "$TMP/dark.png" "$ROOT/docs/images/screenshot.png"
sips -c 310 960 --cropOffset 258 0 "$TMP/dark.png" --out "$IMG/hm-sections.png" >/dev/null
sips -c 490 320 --cropOffset 42 1068 "$TMP/history.png" --out "$IMG/hm-history.png" >/dev/null
sips -c 252 424 --cropOffset 360 504 "$TMP/editor.png" --out "$IMG/hm-editor-crop.png" >/dev/null   # the sheet

if [ "${1:-}" = "--ai" ]; then
    shot ai 110 -ui.toolPanel agent -app.appearance dark -ask \
        "Block ads.example.org and tracker.example.org: a hosts code block with only the lines, then one short sentence."
    sips -c 740 320 --cropOffset 42 1068 "$TMP/ai.png" --out "$IMG/hm-ai-panel.png" >/dev/null
fi

"$ROOT/scripts/build-app.sh" >/dev/null   # back to release
swift "$ROOT/scripts/make-og-image.swift"   # social card uses the new hm-main-dark.png
echo "Updated: $(cd "$ROOT" && git status --short docs/ | tr '\n' ' ')"
