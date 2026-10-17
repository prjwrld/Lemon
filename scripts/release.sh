#!/bin/zsh
# Publishes a new version of Lemon to everyone:
#
#   ./scripts/release.sh 1.0 [notes.txt]
#
# 1. archives Lemon (Release, Developer ID) with today's build number and exports it;
# 2. re-signs Sparkle's helpers and the app inside out (hardened runtime, secure timestamp) and checks them;
# 3. packs it in a DMG with the install window (Config/dmg-settings.py), signs it, has Apple notarize it (a few
#    minutes) and staples the ticket;
# 4. signs the update with Lemon's update key (Keychain, account "lemon") and rewrites appcast.xml;
# 5. deploys Updates/public to https://lemon-updates.edupurspose.workers.dev (fixbyai.in/lemon/download → /Lemon.dmg).
#
# Installed copies find the update within a day, download it in the background and install it when Lemon quits.
# notes.txt (optional): what's new, one line per change ("- " bullets or plain lines); shown in the update window.
# Needs once: a notarytool profile (NOTARY_PROFILE, default rightly-notary: same Apple team as Rightly) and the
# Sparkle key (generate_keys --account lemon). Tools: Sparkle's bin and dmgbuild (paths below, shared with Rightly).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: scripts/release.sh VERSION [notes.txt]}"
NOTES="${2:-}"
PROFILE="${NOTARY_PROFILE:-rightly-notary}"
SITE="Updates/public"
BASE_URL="https://lemon-updates.edupurspose.workers.dev/"
SPARKLE_BIN="${SPARKLE_BIN:-$HOME/Projects/TalkIT/Packages/TalkITApp/.build/artifacts/sparkle/Sparkle/bin}"
DMGBUILD="${DMGBUILD:-$HOME/Projects/TalkIT/.tools/dmgbuild/bin/dmgbuild}"
WRANGLER="${WRANGLER:-Server/node_modules/.bin/wrangler}"
IDENTITY="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -1)"
[[ -n "$IDENTITY" ]] || { echo "✗ No Developer ID Application identity found"; exit 1; }
[[ -x "$SPARKLE_BIN/generate_appcast" ]] || { echo "✗ Sparkle tools not found at $SPARKLE_BIN"; exit 1; }
[[ -x "$DMGBUILD" ]] || { echo "✗ dmgbuild not found: python3 -m venv .tools/dmgbuild && .tools/dmgbuild/bin/pip install dmgbuild==1.6.7"; exit 1; }
[[ -x "$WRANGLER" ]] || { echo "✗ wrangler not found: (cd Server && npm install)"; exit 1; }
[[ -f Vendor/bin/ffmpeg ]] || { echo "✗ Vendor/bin/ffmpeg is missing: run scripts/build-ffmpeg.sh first"; exit 1; }
if [[ -f "$SITE/Lemon-$VERSION.dmg" ]]; then echo "✗ Version $VERSION is already published; pick a new one."; exit 1; fi

# Don't ship with placeholder store settings. Lemon Squeezy's are only needed while it's switched on.
CONFIG=Lemon/Core/License.swift
if grep -q 'REPLACE-WITH\|example\.com' <(grep -vE 'checkoutURL|lemonsqueezy' "$CONFIG") \
   || { grep -q 'lemonSqueezyEnabled = true' "$CONFIG" && grep -qE 'productID: Int\? = nil|example\.lemonsqueezy' "$CONFIG"; }; then
  echo "✗ Fill in StoreConfig in $CONFIG first (links, Razorpay page, key server; Lemon Squeezy only if it's on)." >&2
  exit 1
fi

BUILD_NUMBER="$(date +%Y%m%d%H%M)"
ARCHIVE=build/Lemon.xcarchive
EXPORT=build/export
APP="$EXPORT/Lemon.app"
DMG="build/Lemon-$VERSION.dmg"
rm -rf "$ARCHIVE" "$EXPORT" "$DMG"

echo "▸ Archiving Lemon $VERSION ($BUILD_NUMBER)"
xcodebuild -project Lemon.xcodeproj -scheme Lemon -configuration Release -archivePath "$ARCHIVE" \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" archive -quiet
echo "▸ Exporting (Developer ID)"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist scripts/ExportOptions.plist -exportPath "$EXPORT" -quiet

echo "▸ Signing inside out (Sparkle's helpers, the framework, the media helper, the app)"
FW="$APP/Contents/Frameworks/Sparkle.framework"
sign() { codesign --force --options runtime --timestamp --sign "$IDENTITY" "$@"; }
sign "$FW/Versions/B/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$FW/Versions/B/XPCServices/Downloader.xpc"
sign "$FW/Versions/B/Autoupdate"
sign "$FW/Versions/B/Updater.app"
sign "$FW"
sign "$APP/Contents/Helpers/ffmpeg"
sign --preserve-metadata=entitlements,requirements,flags "$APP"
codesign --verify --deep --strict --verbose=1 "$APP"

echo "▸ Packing the DMG (install window: Config/dmg-settings.py)"
"$DMGBUILD" -s Config/dmg-settings.py -D app="$APP" "Lemon" "$DMG" >/dev/null
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

echo "▸ Notarizing with Apple (usually 1–5 minutes)"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature --verbose "$DMG"

echo "▸ Signing the update and writing the appcast"
cp "$DMG" "$SITE/"
if [[ -n "$NOTES" ]]; then
  # Release notes next to the DMG with the same name: generate_appcast puts them in the update.
  { echo "<ul>"; sed -e 's/^- //' -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e '/^$/d' -e 's|.*|<li>&</li>|' "$NOTES"; echo "</ul>"; } \
    > "$SITE/Lemon-$VERSION.html"
fi
"$SPARKLE_BIN/generate_appcast" --account lemon --download-url-prefix "$BASE_URL" -o "$SITE/appcast.xml" "$SITE"
# A stable download link for the website: /Lemon.dmg always points at the newest version.
echo "/Lemon.dmg /Lemon-$VERSION.dmg 302" > "$SITE/_redirects"

echo "▸ Publishing"
(cd Updates && "../$WRANGLER" deploy 2>&1 | grep -E "Uploaded|Deployed|workers.dev|ERROR")
echo "✓ Lemon $VERSION is live: ${BASE_URL}Lemon.dmg  (and https://fixbyai.in/lemon/download)"
