#!/bin/bash
# Builds Pocket Pet.app next to this script. Run: ./build.sh && open "Pocket Pet.app"
# ./build.sh --universal also builds for Intel Macs (slower; package.sh uses it for sharing).
set -euo pipefail
cd "$(dirname "$0")"

APP="Pocket Pet.app"
SOURCES=(main.swift Art.swift Pets.swift Pet.swift ItemArt.swift World.swift Google.swift MacCalendar.swift ICSCalendar.swift
         Cards.swift AppleEvents.swift Music.swift Notifications.swift Updater.swift UI.swift Sound.swift Sheet.swift)

# Version and update settings live in small files next to this script (release.sh sets VERSION).
VERSION="$(cat VERSION 2>/dev/null || echo 3.0)"
UPDATE_REPO="$(cat update-repo.txt 2>/dev/null || true)"            # e.g. yourname/pocket-pet on GitHub
UPDATE_KEY="$(cat update-public-key.txt 2>/dev/null || true)"       # the public half of your signing key
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

if [[ "${1:-}" == "--universal" ]]; then
    TMP="$(mktemp -d)"
    swiftc -O -swift-version 5 -target arm64-apple-macos13 -o "$TMP/arm64" "${SOURCES[@]}"
    swiftc -O -swift-version 5 -target x86_64-apple-macos13 -o "$TMP/x86_64" "${SOURCES[@]}"
    lipo -create -output "$APP/Contents/MacOS/PocketPet" "$TMP/arm64" "$TMP/x86_64"
    rm -rf "$TMP"
else
    swiftc -O -swift-version 5 -o "$APP/Contents/MacOS/PocketPet" "${SOURCES[@]}"
fi

# The app icon is drawn by the app itself, from the same pixel art as the pets.
ICONSET="$(mktemp -d)/AppIcon.iconset"
"$APP/Contents/MacOS/PocketPet" --appicon "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$(dirname "$ICONSET")"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Pocket Pet</string>
    <key>CFBundleDisplayName</key><string>Pocket Pet</string>
    <key>CFBundleIdentifier</key><string>local.honk.desktopgoose</string>
    <key>CFBundleExecutable</key><string>PocketPet</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>PocketPetUpdateRepo</key><string>$UPDATE_REPO</string>
    <key>PocketPetUpdateKey</key><string>$UPDATE_KEY</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSCalendarsFullAccessUsageDescription</key><string>Your pet reads your calendar so it can tell you what is coming up.</string>
    <key>NSCalendarsUsageDescription</key><string>Your pet reads your calendar so it can tell you what is coming up.</string>
    <key>NSAppleEventsUsageDescription</key><string>Pocket Pet shows what's playing in Spotify, and rings a bell when a browser tab gets new messages.</string>
</dict>
</plist>
PLIST

# Bundle id kept from the Honk days so your pet, sign-ins and permissions carry over.
# A fixed identity (instead of the file hash), so macOS keeps Accessibility and browser permissions across rebuilds.
codesign --force --sign - -r='designated => identifier "local.honk.desktopgoose"' "$APP" >/dev/null 2>&1 || true
echo "Built $APP"
