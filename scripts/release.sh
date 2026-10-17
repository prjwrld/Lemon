#!/bin/zsh
# Builds a signed, notarized Lemon.zip you can put on your website.
#
# One-time setup (stores your notarization login in the Keychain):
#   xcrun notarytool store-credentials lemon-notary --apple-id YOUR_APPLE_ID --team-id WR42UXPTXW
# It asks for an app-specific password (make one at account.apple.com → Sign-In and Security).
#
# Usage:  ./scripts/release.sh            (sign + notarize)
#         ./scripts/release.sh --no-notarize   (sign only, for a quick check)
set -euo pipefail
cd "$(dirname "$0")/.."

ARCHIVE=build/Lemon.xcarchive
EXPORT=build/export
ZIP=build/Lemon.zip

# Don't ship with the placeholder store settings (any licence key would be accepted).
if grep -qE 'productID: Int\? = nil|example\.(com|lemonsqueezy)' Lemon/Core/License.swift; then
  echo "✗ Fill in StoreConfig in Lemon/Core/License.swift first (product ID, checkout link, website, support email)." >&2
  exit 1
fi

rm -rf "$ARCHIVE" "$EXPORT" "$ZIP"
echo "▸ Archiving (Release, Developer ID)…"
xcodebuild -project Lemon.xcodeproj -scheme Lemon -configuration Release \
  -archivePath "$ARCHIVE" archive -quiet

echo "▸ Exporting…"
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportOptionsPlist scripts/ExportOptions.plist -exportPath "$EXPORT" -quiet

echo "▸ Checking signature…"
codesign --verify --deep --strict --verbose=2 "$EXPORT/Lemon.app"

ditto -c -k --keepParent "$EXPORT/Lemon.app" "$ZIP"

if [[ "${1:-}" == "--no-notarize" ]]; then
  echo "✓ Signed (not notarized): $ZIP"
  exit 0
fi

echo "▸ Sending to Apple for notarization (a few minutes)…"
xcrun notarytool submit "$ZIP" --keychain-profile lemon-notary --wait

echo "▸ Stapling the ticket to the app…"
xcrun stapler staple "$EXPORT/Lemon.app"
rm "$ZIP" && ditto -c -k --keepParent "$EXPORT/Lemon.app" "$ZIP"
spctl --assess --type execute --verbose "$EXPORT/Lemon.app"
echo "✓ Ready to upload: $ZIP"
