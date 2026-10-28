#!/bin/bash
# Publishes a new version to everyone who has Pocket Pet:   ./release.sh 3.2 "What's new"
# Their Pocket Pets notice within a few hours and offer the update; new friends just download the DMG from the release page.
#
# Needs: GitHub's gh tool, signed in; update-repo.txt (yourname/pocket-pet); your signing key in ~/.pocketpet/update-key.
# Back that key up: without it you can't sign updates, and friends would have to reinstall by hand.
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:?usage: ./release.sh <version> <notes>}"
NOTES="${2:-}"
REPO="$(cat update-repo.txt)"
KEY="$HOME/.pocketpet/update-key"
[[ -f "$KEY" ]] || { echo "No signing key at $KEY"; exit 1; }

echo "$VERSION" > VERSION
./build.sh --universal

# the update itself (a zip of the app) and its signature
mkdir -p dist
rm -f dist/Pocket-Pet.zip dist/Pocket-Pet.zip.sig
ditto -c -k --keepParent "Pocket Pet.app" dist/Pocket-Pet.zip
"Pocket Pet.app/Contents/MacOS/PocketPet" --sign-update dist/Pocket-Pet.zip "$KEY" > dist/Pocket-Pet.zip.sig

# and the DMG, for friends installing for the first time
./package.sh --no-build

gh release create "v$VERSION" dist/Pocket-Pet.zip dist/Pocket-Pet.zip.sig "dist/Pocket Pet.dmg" \
    --repo "$REPO" --title "Pocket Pet $VERSION" --notes "$NOTES"
echo "Published $VERSION: https://github.com/$REPO/releases/latest"
