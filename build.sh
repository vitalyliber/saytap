#!/bin/zsh
# Builds Word Popup.app into ~/Applications and starts it.
set -euo pipefail
cd "${0:A:h}"

APP="$HOME/Applications/Word Popup.app"

swiftc -O -swift-version 5 -target arm64-apple-macosx14.0 \
  -framework Cocoa -framework Carbon -framework AVFoundation \
  -o build/WordPopup Sources/main.swift

pkill -x WordPopup || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Info.plist "$APP/Contents/Info.plist"
cp build/WordPopup "$APP/Contents/MacOS/WordPopup"
# A real certificate keeps the Accessibility permission across rebuilds; an ad-hoc signature
# is identified by its hash, so macOS would forget the permission every time.
codesign --force --sign "Word Popup Signing" "$APP"

open "$APP"
echo "Installed $APP"
