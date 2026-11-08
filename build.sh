#!/bin/zsh
# Builds Word Popup.app into ~/Applications and starts it.
set -euo pipefail
cd "${0:A:h}"

APP="$HOME/Applications/Word Popup.app"
CERTIFICATE="Word Popup Signing"
MINIMUM_MACOS="15.0"

if ! security find-certificate -c "$CERTIFICATE" >/dev/null 2>&1; then
  echo "No \"$CERTIFICATE\" certificate in the keychain. Create it first: see Install in README.md." >&2
  exit 1
fi

mkdir -p build
swiftc -O -swift-version 5 -target "$(uname -m)-apple-macosx$MINIMUM_MACOS" \
  -framework Cocoa -framework Carbon -framework AVFoundation \
  -o build/WordPopup Sources/main.swift

pkill -x WordPopup || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Info.plist "$APP/Contents/Info.plist"
cp build/WordPopup "$APP/Contents/MacOS/WordPopup"
# A real certificate keeps the Accessibility permission across rebuilds; an ad-hoc signature
# is identified by its hash, so macOS would forget the permission every time.
codesign --force --sign "$CERTIFICATE" "$APP"

open "$APP"
echo "Installed $APP"
