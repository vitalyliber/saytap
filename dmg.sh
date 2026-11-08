#!/bin/zsh
# Packs a built Saytap.app into build/Saytap.dmg: a window with the app, an arrow and Applications to drag it onto.
# Usage: ./dmg.sh [path/to/Saytap.app]; the default is the app build.sh installs.
# DEVELOPER_ID="Developer ID Application: …" signs the disk image, and NOTARY_PROFILE, a profile saved with
# `xcrun notarytool store-credentials`, also notarizes and staples it.
set -euo pipefail
cd "${0:A:h}"

SOURCE_APP="${1:-$HOME/Applications/Saytap.app}"
VOLUME="Saytap"
MOUNT="/Volumes/$VOLUME"
DMG="build/Saytap.dmg"
WRITABLE_DMG="build/Saytap-writable.dmg"
STAGING="build/dmg"
# The window and the centres of its icons; dmg-background.swift draws the arrow between them.
WINDOW_LEFT=200
WINDOW_TOP=120
WINDOW_WIDTH=640
WINDOW_HEIGHT=400
ICON_SIZE=128
LABEL_SIZE=13
ICON_Y=190
APP_X=170
APPLICATIONS_X=470
# Room for the .DS_Store Finder writes into the image.
SPARE_MEGABYTES=20
# Finder notices a new disk a moment after it's mounted.
FINDER_WAIT_TRIES=20
FINDER_WAIT_STEP=0.5
FINDER_SETTLE_SECONDS=5

if [[ ! -d "$SOURCE_APP" ]]; then
  echo "No app at $SOURCE_APP. Run ./build.sh first, or pass the app's path." >&2
  exit 1
fi
if [[ -d "$MOUNT" ]]; then
  echo "$MOUNT is already mounted. Eject it first." >&2
  exit 1
fi

rm -rf "$STAGING" "$WRITABLE_DMG" "$DMG"
mkdir -p "$STAGING/.background"
# Without extended attributes, so a downloaded app doesn't carry its quarantine flag into the image.
ditto --noextattr --noqtn "$SOURCE_APP" "$STAGING/Saytap.app"
ln -s /Applications "$STAGING/Applications"
swift dmg-background.swift 1 build/dmg-background.png
swift dmg-background.swift 2 build/dmg-background@2x.png
tiffutil -cathidpicheck build/dmg-background.png build/dmg-background@2x.png -out "$STAGING/.background/background.tiff" 2>/dev/null

size=$(( $(du -sm "$STAGING" | cut -f1) + SPARE_MEGABYTES ))
hdiutil create -quiet -srcfolder "$STAGING" -volname "$VOLUME" -fs HFS+ -format UDRW -size "${size}m" "$WRITABLE_DMG"
hdiutil attach -quiet -readwrite -noverify -noautoopen "$WRITABLE_DMG"
for _ in {1..$FINDER_WAIT_TRIES}; do
  [[ "$(osascript -e "tell application \"Finder\" to exists disk \"$VOLUME\"")" == "true" ]] && break
  sleep "$FINDER_WAIT_STEP"
done

# Finder saves the window's look in the image's .DS_Store. It keeps the window's size and bars from the first
# opening, but drops view options set then, so those go in on a second opening a few seconds later.
osascript <<EOF
tell application "Finder"
  tell disk "$VOLUME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {$WINDOW_LEFT, $WINDOW_TOP, $((WINDOW_LEFT + WINDOW_WIDTH)), $((WINDOW_TOP + WINDOW_HEIGHT))}
    close
    open
    update without registering applications
    delay 2
    close
  end tell
  delay $FINDER_SETTLE_SECONDS
  tell disk "$VOLUME"
    open
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to $ICON_SIZE
    set text size of viewOptions to $LABEL_SIZE
    set background picture of viewOptions to file ".background:background.tiff"
    set position of item "Saytap.app" of container window to {$APP_X, $ICON_Y}
    set position of item "Applications" of container window to {$APPLICATIONS_X, $ICON_Y}
    close
  end tell
end tell
EOF

# Finder writes them a few seconds after the window closes; detaching earlier loses them.
for _ in {1..$FINDER_WAIT_TRIES}; do
  python3 -c "import plistlib, sys
BACKGROUND_PICTURE = 2
d = open('$MOUNT/.DS_Store', 'rb').read()
i = d.find(b'icvpblob')
sys.exit(i < 0 or b'bwspblob' not in d or plistlib.loads(d[i + 12:i + 12 + int.from_bytes(d[i + 8:i + 12], 'big')]).get('backgroundType') != BACKGROUND_PICTURE)" && break
  sleep "$FINDER_WAIT_STEP"
done

# The disk icon goes on last: hdiutil leaves it out of -srcfolder, and Finder drops it while it lays out the window.
cp "$SOURCE_APP/Contents/Resources/AppIcon.icns" "$MOUNT/.VolumeIcon.icns"
SetFile -a C "$MOUNT"
sync
hdiutil detach -quiet "$MOUNT"
hdiutil convert -quiet "$WRITABLE_DMG" -format ULFO -o "$DMG"
rm -rf "$WRITABLE_DMG" "$STAGING"

if [[ -n "${DEVELOPER_ID:-}" ]]; then
  codesign --sign "$DEVELOPER_ID" --timestamp "$DMG"
fi
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
fi

echo "Made $DMG"
