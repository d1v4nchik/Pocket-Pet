#!/bin/bash
# Builds Pocket Pet.app next to this script. Run: ./build.sh && open "Pocket Pet.app"
# ./build.sh --universal also builds for Intel Macs (slower; package.sh uses it for sharing).
set -euo pipefail
cd "$(dirname "$0")"

APP="Pocket Pet.app"
SIGNING="$HOME/.pocketpet/signing"     # .keychain-db, .pass, .id (made once by ./build.sh --new-signing-identity)

# A certificate of your own (it never leaves this Mac), so every build and update is the same app to macOS
# and Accessibility, Calendar and Automation stay allowed. Without one, builds are ad-hoc signed.
if [[ "${1:-}" == "--new-signing-identity" ]]; then
    [[ -f "$SIGNING.keychain-db" ]] && { echo "Already have one at $SIGNING.keychain-db"; exit 1; }
    mkdir -p "$(dirname "$SIGNING")"; chmod 700 "$(dirname "$SIGNING")"
    TMP="$(mktemp -d)"
    /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 7300 -subj "/CN=Pocket Pet Signing" -keyout "$TMP/key" -out "$TMP/crt" \
        -addext "keyUsage=critical,digitalSignature" -addext "extendedKeyUsage=critical,codeSigning" -addext "basicConstraints=critical,CA:false" 2>/dev/null
    /usr/bin/openssl pkcs12 -export -inkey "$TMP/key" -in "$TMP/crt" -out "$TMP/id.p12" -passout pass:pocketpet
    PW="$(/usr/bin/openssl rand -hex 24)"
    BEFORE=(); while read -r k; do BEFORE+=("$(eval echo "$k")"); done < <(security list-keychains -d user)
    security create-keychain -p "$PW" "$SIGNING.keychain-db"
    security list-keychains -d user -s "${BEFORE[@]}"                    # keep it out of Keychain Access
    security set-keychain-settings "$SIGNING.keychain-db"
    security import "$TMP/id.p12" -k "$SIGNING.keychain-db" -P pocketpet -T /usr/bin/codesign >/dev/null
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PW" "$SIGNING.keychain-db" >/dev/null
    printf %s "$PW" > "$SIGNING.pass"; chmod 600 "$SIGNING.pass"
    /usr/bin/openssl x509 -in "$TMP/crt" -noout -fingerprint -sha1 | sed 's/.*=//; s/://g' > "$SIGNING.id"
    rm -rf "$TMP"
    echo "Made $SIGNING.keychain-db. Back up ~/.pocketpet: without it, an update would need Accessibility switched on again."
    exit 0
fi

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
    <key>NSHumanReadableCopyright</key><string>Copyright © 2026 d1v4nchik. Free software under the GPL-3.0.</string>
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
if [[ -f "$SIGNING.keychain-db" ]]; then
    # codesign only finds certificates on the keychain search list, so it joins the list just for this.
    BEFORE=(); while read -r k; do BEFORE+=("$(eval echo "$k")"); done < <(security list-keychains -d user)
    trap 'security list-keychains -d user -s "${BEFORE[@]}"' EXIT
    security unlock-keychain -p "$(cat "$SIGNING.pass")" "$SIGNING.keychain-db"
    security list-keychains -d user -s "${BEFORE[@]}" "$SIGNING.keychain-db"
    codesign --force --sign "$(cat "$SIGNING.id")" "$APP" 2>&1 | grep -v "replacing existing signature" || true
    security list-keychains -d user -s "${BEFORE[@]}"; trap - EXIT
else
    codesign --force --sign - -r='designated => identifier "local.honk.desktopgoose"' "$APP" >/dev/null 2>&1 || true
fi
echo "Built $APP"
