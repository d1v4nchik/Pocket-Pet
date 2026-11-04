#!/bin/bash
# Installs (or updates) Pocket Pet in ~/Applications, without the "can't be checked for malicious software" warning:
#
#   curl -fsSL https://raw.githubusercontent.com/d1v4nchik/Pocket-Pet/main/install.sh | bash
#
# Why there's no warning: macOS only checks apps that are marked as downloaded by a browser. A download made from
# Terminal isn't marked, so instead this script checks the app itself: it must be signed with Pocket Pet's own
# certificate, or nothing is installed. No admin password needed.
set -euo pipefail

REPO="d1v4nchik/Pocket-Pet"
DEST="$HOME/Applications"
# Pocket Pet's signature: its bundle id and the maintainer's certificate (the same check macOS uses for permissions)
REQUIREMENT='identifier "local.honk.desktopgoose" and certificate leaf = H"330d3f7be5063da78c9cbde2798fcfe63d056b12"'

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Downloading Pocket Pet..."
curl -fsSL -o "$TMP/Pocket-Pet.zip" "https://github.com/$REPO/releases/latest/download/Pocket-Pet.zip"
ditto -x -k "$TMP/Pocket-Pet.zip" "$TMP/unpacked"

echo "Checking it's really Pocket Pet..."
if ! codesign --verify --strict -R="$REQUIREMENT" "$TMP/unpacked/Pocket Pet.app" 2>/dev/null; then
    echo "That download isn't signed by Pocket Pet's maintainer, so it wasn't installed."
    exit 1
fi

mkdir -p "$DEST"
pkill -x PocketPet 2>/dev/null || true
rm -rf "$DEST/Pocket Pet.app"
mv "$TMP/unpacked/Pocket Pet.app" "$DEST/"
open "$DEST/Pocket Pet.app"
echo "Done! Pocket Pet is in $DEST and updates itself from now on."
