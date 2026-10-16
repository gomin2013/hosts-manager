#!/bin/bash
# Packages build/HostsManager.app into build/HostsManager-<version>.dmg (app + /Applications link).
# Usage:
#   scripts/make-dmg.sh                                   # ad-hoc build, local testing only
#   SIGN_ID="Developer ID Application: Name (TEAMID)" \
#   NOTARY_PROFILE=hm-notary scripts/make-dmg.sh         # signed + notarized + stapled, ready to ship
# NOTARY_PROFILE comes from: xcrun notarytool store-credentials <name> --apple-id ... --team-id ...
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/HostsManager.app"
SIGN_ID="${SIGN_ID:--}"

"$ROOT/scripts/build-app.sh" release

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$ROOT/build/HostsManager-$VERSION.dmg"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -volname "Hosts Manager $VERSION" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null

if [ "$SIGN_ID" != "-" ]; then
    codesign --force --sign "$SIGN_ID" --timestamp "$DMG"
fi

if [ -n "${NOTARY_PROFILE:-}" ]; then
    [ "$SIGN_ID" != "-" ] || { echo "NOTARY_PROFILE needs SIGN_ID (Developer ID); ad-hoc builds can't be notarized" >&2; exit 1; }
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
    spctl --assess --type open --context context:primary-signature -v "$DMG"
fi

echo "Built $DMG"
