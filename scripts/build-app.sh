#!/bin/bash
# Assembles build/HostsManager.app with the root helper registered as a LaunchDaemon (SMAppService.daemon).
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
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Library/LaunchDaemons"

cp Sources/HostsManagerApp/Info.plist "$APP/Contents/Info.plist"
cp "$BIN/HostsManager" "$BIN/HostsManagerHelper" "$APP/Contents/MacOS/"
cp -R Sources/HostsManagerApp/Resources/*.lproj "$APP/Contents/Resources/"
# Icons (regenerate: swift scripts/make-icon.swift): Assets.car for macOS 26+, AppIcon.icns for 14–15
cp Packaging/Assets.car Packaging/AppIcon.icns "$APP/Contents/Resources/"

# Runs as root; launchd starts it on demand when the app connects to its Mach service.
cat > "$APP/Contents/Library/LaunchDaemons/$HELPER_ID.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$HELPER_ID</string>
	<key>BundleProgram</key>
	<string>Contents/MacOS/HostsManagerHelper</string>
	<key>MachServices</key>
	<dict>
		<key>$HELPER_ID</key>
		<true/>
	</dict>
	<key>AssociatedBundleIdentifiers</key>
	<array>
		<string>com.hostsmanager.app</string>
	</array>
</dict>
</plist>
PLIST

# Sign inside-out: helper first, then the app bundle that seals it.
codesign --force --options runtime --sign "$SIGN_ID" --identifier "$HELPER_ID" "$APP/Contents/MacOS/HostsManagerHelper"
codesign --force --options runtime --sign "$SIGN_ID" "$APP"
codesign --verify --strict "$APP"

echo "Built $APP"
