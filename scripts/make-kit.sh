#!/usr/bin/env bash
# Build a macOS 14+ install kit for another Mac: dist/True-macOS14-kit/ and dist/True-macOS14-kit.zip.
# Universal (arm64 + x86_64) True.app, ad-hoc signed (not notarised). Never launches or installs anything.
# Usage: scripts/make-kit.sh
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
KIT="$ROOT/dist/True-macOS14-kit"

for arch in arm64 x86_64; do
  case "$arch" in arm64) sp=.build-arm;; x86_64) sp=.build-x86;; esac
  echo "==> swift build release $arch (minos 14.0)..."
  nice -n 10 swift build -c release --triple "$arch-apple-macosx14.0" --scratch-path "$sp" -j 4
done

rm -rf "$KIT" "$ROOT/dist/True-macOS14-kit.zip"
mkdir -p "$KIT" "$ROOT/dist/.tmp"
lipo -create .build-arm/arm64-apple-macosx/release/True .build-x86/x86_64-apple-macosx/release/True \
     -output "$ROOT/dist/.tmp/True"

TRUE_PREBUILT_BIN="$ROOT/dist/.tmp/True" TRUE_APP_OUT="$KIT/True.app" TRUE_SIGN=adhoc scripts/package.sh release
rm -rf "$ROOT/dist/.tmp"

cat > "$KIT/Install True.command" <<'INSTALL'
#!/bin/bash
# Installs True into ~/Applications and opens it. Safe to run again to update.
cd "$(dirname "$0")" || exit 1
if [ "$(sw_vers -productVersion | cut -d. -f1)" -lt 14 ]; then
  echo "True needs macOS 14 (Sonoma) or newer. This Mac has $(sw_vers -productVersion)."
  read -r -p "Press Return to close."; exit 1
fi
mkdir -p "$HOME/Applications"
osascript -e 'tell application "True" to quit' >/dev/null 2>&1
rm -rf "$HOME/Applications/True.app"
cp -R "True.app" "$HOME/Applications/True.app" || { echo "Copy failed."; read -r -p "Press Return to close."; exit 1; }
# The zip was downloaded, so macOS marks it "quarantined". True is signed on the maker's Mac, not
# notarised by Apple, so without this Gatekeeper refuses to open it.
xattr -dr com.apple.quarantine "$HOME/Applications/True.app"
echo "Installed to ~/Applications/True.app"
open "$HOME/Applications/True.app"
INSTALL
chmod +x "$KIT/Install True.command"

cat > "$KIT/READ ME.txt" <<'README'
TRUE for macOS 14 (Sonoma) or newer
====================================

True is a terminal workspace for running Claude Code agents side by side, with a voice assistant
(Nova), a command bar, a screenshot tray and more. This kit runs on Apple Silicon and Intel Macs.

INSTALL
  1. Unzip True-macOS14-kit.zip (double-click it).
  2. Double-click "Install True.command".
       - If macOS says it can't be opened: right-click it > Open > Open.
         (Or: System Settings > Privacy & Security > "Open Anyway".)
  3. It copies True to ~/Applications, clears the "downloaded from the internet" flag, and opens it.
  To update later, run Install True.command again from a newer kit.

ABOUT THE SECURITY WARNING
  True is signed locally on the maker's Mac, not notarised by Apple. Installing with
  Install True.command removes the download flag so Gatekeeper lets it open. If you copy True.app
  by hand instead, run:   xattr -dr com.apple.quarantine /path/to/True.app
  or right-click True.app > Open the first time.

PERMISSIONS IT WILL ASK FOR (all optional; say No and the related feature just stays off)
  - Microphone .............. Nova (voice) and voice mode in programs you run inside True.
  - Speech Recognition ...... Nova listens for its wake word on-device (nothing is sent to Apple).
  - Automation / Apple Events  Nova opens, quits and controls other apps when you ask.
  - Input Monitoring / Accessibility: the global push-to-talk key (fn) that wakes Nova.
  - Screen Recording ........ Nova's screenshots of what is on screen.
  - Files and Folders ....... Desktop, Documents, Downloads: the screenshot tray, projects, file tools.
  Because True is signed ad-hoc, macOS may ask again after you install an update.

WHAT TO SET UP ON THIS MAC
  - Claude Code: install it (https://claude.com/claude-code) and sign in. True's agent panes run the
    "claude" command. Without it, True still works as a plain terminal workspace.
  - API keys for Nova (voice assistant): open True > Settings and paste your own keys
    (Anthropic for the brain, ElevenLabs for the voice if you want it). Keys are stored in this
    Mac's Keychain. No keys are included in this kit. Without keys, Nova stays quiet.
  - Optional: Tailscale (for Remote Access to True from a phone), git, ripgrep (brew install ripgrep).
  - True keeps its own files in ~/.true and reads Claude Code's folder ~/.claude (created by Claude Code).

WHAT LOOKS DIFFERENT ON macOS 14 AND 15
  macOS 26 has the new "Liquid Glass" look. On macOS 14 and 15 True uses frosted-blur panels with a thin
  edge instead, and standard bordered buttons. Everything works the same.

NOT TESTED ON macOS 14 HARDWARE
  This build was compiled and checked for macOS 14 compatibility, but its maker had no macOS 14
  machine to run it on. If something misbehaves, tell the maker which screen and what you clicked.
README

( cd "$ROOT/dist" && ditto -c -k --keepParent --norsrc "True-macOS14-kit" "True-macOS14-kit.zip" )
echo "OK: $KIT"; echo "OK: $ROOT/dist/True-macOS14-kit.zip"
