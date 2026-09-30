#!/usr/bin/env bash
# Build the SwiftPM executable and assemble it into True.app -- no Xcode required.
# Never launches the app. ASCII-only on purpose (non-ASCII next to $vars breaks under some locales).
# Usage: scripts/package.sh [debug|release]
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-debug}"
APP="True.app"
BIN="True"
BUNDLE_ID="net.prismlens.true"
VERSION="0.1.0"

echo "==> swift build ($CONFIG)..."
nice -n 10 swift build -j 4 -c "$CONFIG"

BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
BIN_PATH="$BIN_DIR/$BIN"
[ -f "$BIN_PATH" ] || { echo "ERROR: build product not found at $BIN_PATH"; exit 1; }

echo "==> assembling $APP ..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_PATH" "$APP/Contents/MacOS/$BIN"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>True</string>
  <key>CFBundleDisplayName</key><string>True</string>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>${BIN}</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

# Sign with a stable self-signed identity, NOT ad-hoc. macOS keys every privacy grant (Music, Desktop,
# Documents, ...) to the app's designated requirement. Ad-hoc pins that to the binary's cdhash, so each
# rebuild reads as a brand-new app and every permission popup comes back. A certificate makes the
# requirement cert-based, so "Allow" survives rebuilds. Same identity and reasoning as deck/build.sh.
IDENTITY="Deck Signing"
KEYCHAIN="$HOME/Library/Keychains/deck-signing.keychain-db"
if security find-certificate -c "$IDENTITY" "$KEYCHAIN" >/dev/null 2>&1; then
  # The signing keychain has a blank password and relocks itself; unlock it here or macOS pops a
  # password dialog that the Mac login password does not satisfy.
  security unlock-keychain -p "" "$KEYCHAIN" >/dev/null 2>&1 || true
  codesign --force --sign "$IDENTITY" --keychain "$KEYCHAIN" "$APP"
  codesign --verify --strict "$APP"
  echo "    signed with '$IDENTITY' (permission grants survive rebuilds)"
else
  echo "WARNING: no '$IDENTITY' certificate in $KEYCHAIN -- falling back to ad-hoc."
  echo "         Every permission popup will return after this build. See deck/build.sh to recreate it."
  codesign --force --deep --sign - "$APP" >/dev/null 2>&1 && echo "    ad-hoc signed"
fi
echo "OK: built $APP (not launched)"
