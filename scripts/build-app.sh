#!/bin/bash
# Assembles build/HostsManager.app (menu bar app + helper binary).
# Usage: scripts/build-app.sh [debug|release]
#   SIGN_ID="Developer ID Application: ..." to sign for distribution (default: ad-hoc "-").
set -euo pipefail

CONFIG="${1:-release}"
SIGN_ID="${SIGN_ID:--}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/HostsManager.app"
HELPER_ID="com.hostsmanager.helper"

cd "$ROOT"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp Sources/HostsManagerApp/Info.plist "$APP/Contents/Info.plist"
cp "$BIN/HostsManager" "$BIN/HostsManagerHelper" "$APP/Contents/MacOS/"
cp -R Sources/HostsManagerApp/Resources/*.lproj "$APP/Contents/Resources/"
# Phase 2: Contents/Library/LaunchDaemons/$HELPER_ID.plist (BundleProgram + MachServices) for SMAppService.daemon

# Sign inside-out: helper first, then the app bundle that seals it.
codesign --force --options runtime --sign "$SIGN_ID" --identifier "$HELPER_ID" "$APP/Contents/MacOS/HostsManagerHelper"
codesign --force --options runtime --sign "$SIGN_ID" "$APP"
codesign --verify --strict "$APP"

echo "Built $APP"
