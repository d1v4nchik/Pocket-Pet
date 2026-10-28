#!/bin/bash
# Makes "dist/Pocket Pet.dmg" to send to friends: works on Apple Silicon and Intel Macs (macOS 13 or newer).
# Opening it shows Pocket Pet next to an Applications shortcut, plus a short note on how to open it the first time.
# ./package.sh --no-build just repackages the app that's already built.
set -euo pipefail
cd "$(dirname "$0")"

[[ "${1:-}" == "--no-build" ]] || ./build.sh --universal

STAGE="$(mktemp -d)/Pocket Pet"
mkdir -p "$STAGE"
cp -R "Pocket Pet.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/How to open Pocket Pet.txt" <<'TXT'
Pocket Pet — a little pixel pet that lives on your desktop.

1. Drag Pocket Pet onto the Applications folder.
   Not an admin on your Mac? Put it in the Applications folder inside your home folder
   instead (Finder → Go → Home, make a folder called Applications if there isn't one).
   It works from anywhere, no password needed.
2. Open it.
3. The first time, macOS may say it can't check the app for malicious software
   (it isn't from the App Store). Either:
   - System Settings → Privacy & Security, scroll down, click "Open Anyway" next to
     Pocket Pet and confirm (this can ask for an admin password), or
   - without any password: open Terminal and paste
       xattr -dr com.apple.quarantine ~/Applications/Pocket\ Pet.app
     (change the path if you put it somewhere else), then open Pocket Pet again.
4. Your pet appears on screen. Click the paw in the menu bar (or right-click the pet) for its menu.

Optional, all in the menu's Settings:
- Calendar: paste your Google Calendar's private link, or use the Mac's Calendar app.
- Notification bell: rings for new messages in browser tabs (Chrome, Safari, Brave, Edge, Arc, Vivaldi, Opera).
  Allow Accessibility to have it ring for every app's notifications.
- Music: shows and controls what's playing in Spotify.
TXT

mkdir -p dist
rm -f "dist/Pocket Pet.dmg"
hdiutil create -volname "Pocket Pet" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "dist/Pocket Pet.dmg" >/dev/null
rm -rf "$(dirname "$STAGE")"
echo "Made dist/Pocket Pet.dmg ($(du -h "dist/Pocket Pet.dmg" | cut -f1))"
