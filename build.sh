#!/bin/zsh
# Builds Saytap.app into ~/Applications and starts it.
set -euo pipefail
cd "${0:A:h}"

APP="$HOME/Applications/Saytap.app"
CERTIFICATE="Saytap Signing"
# The Phonon release whose Core ML model the app ships; Package.swift pins the same version of the package.
PHONON_VERSION="0.6.0"
MODEL_URL="https://github.com/gradium-ai/xn-ptts/releases/download/v$PHONON_VERSION/phonon-31m-en-coreml.zip"
MODEL_SHA256="2869326ab074f55ed5b644e68b1befef69dc51545b73296d49f5b4dab14c4218"
MODELS="build/Models-$PHONON_VERSION"

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "Saytap needs a Mac with Apple silicon: Phonon runs on its Neural Engine." >&2
  exit 1
fi

# DEVELOPER_ID="Developer ID Application: …" signs a build to hand out instead, with the hardened runtime
# notarization needs; dmg.sh then packs and notarizes it.
if [[ -z "${DEVELOPER_ID:-}" ]] && ! security find-certificate -c "$CERTIFICATE" >/dev/null 2>&1; then
  echo "No \"$CERTIFICATE\" certificate in the keychain. Create it first: see Install in README.md." >&2
  exit 1
fi

if [[ ! -d "$MODELS" ]]; then
  echo "Downloading the Phonon model (about 140 MB)…"
  mkdir -p build
  curl -fL --progress-bar -o build/model.zip "$MODEL_URL"
  echo "$MODEL_SHA256  build/model.zip" | shasum -a 256 -c --quiet
  rm -rf build/model
  unzip -q build/model.zip -d build/model
  mv build/model/phonon-31m-en "$MODELS"
  rm -rf build/model build/model.zip
fi

ICON="build/AppIcon.icns"
if [[ ! -f "$ICON" || icon.swift -nt "$ICON" ]]; then
  rm -rf build/AppIcon.iconset
  mkdir -p build/AppIcon.iconset
  swift icon.swift build/icon.png
  for size in 16 32 128 256 512; do
    sips -z $size $size build/icon.png --out "build/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) build/icon.png --out "build/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns build/AppIcon.iconset -o "$ICON"
  rm -rf build/AppIcon.iconset build/icon.png
fi

swift build -c release --arch arm64
BINARY="$(swift build -c release --arch arm64 --show-bin-path)/Saytap"

pkill -x Saytap || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
cp "$BINARY" "$APP/Contents/MacOS/Saytap"
cp -R "$MODELS" "$APP/Contents/Resources/Models"
cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"
# A real certificate keeps the Accessibility permission across rebuilds; an ad-hoc signature
# is identified by its hash, so macOS would forget the permission every time.
if [[ -n "${DEVELOPER_ID:-}" ]]; then
  codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$APP"
else
  codesign --force --sign "$CERTIFICATE" "$APP"
fi

open "$APP"
echo "Installed $APP"
