# Contributing to Pocket Pet

Thanks for taking the time to contribute! Pocket Pet is a small pixel pet for the Mac desktop, and contributions of all
sizes are welcome: bug reports, fixes, new pets and outfits, pixel art, docs and features.

## Before you start

- Check [open issues](../../issues) and [pull requests](../../pulls) to avoid duplicating work.
- For anything beyond a small fix, open an issue first to discuss the change. It saves everyone time if the approach
  needs adjusting.
- By contributing, you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## Development setup

You need a Mac with macOS 13 or newer and Apple's command line tools (`xcode-select --install`). No Xcode project, no
dependencies.

```bash
git clone https://github.com/d1v4nchik/Pocket-Pet.git
cd Pocket-Pet
./build.sh && open "Pocket Pet.app"
```

## Project layout

| File | Purpose |
|---|---|
| `main.swift` | Entry point and the debug render commands |
| `World.swift` | The app: senses (typing, videos, music, fullscreen), settings, menus, calendar, the bell |
| `Pet.swift` | The pet's brain, movement, physics and mouse handling |
| `Pets.swift` | Species and pixel art for every pet and outfit |
| `Art.swift` / `ItemArt.swift` | The pixel canvas, palette, font; snacks, toys and icons |
| `UI.swift` / `Cards.swift` | The menu and the cards by the pet (calendar, music, bell) |
| `Music.swift` | Spotify, Apple Music and other players |
| `Notifications.swift` | The notification bell (browser tabs and banners) |
| `Google.swift`, `ICSCalendar.swift`, `MacCalendar.swift` | Calendar sources |
| `Updater.swift` | Signed self-updates from GitHub releases |
| `build.sh`, `package.sh`, `release.sh` | Build, make the DMG, publish a release |

## Seeing your change without running the app

The app can draw its own art and menus into PNGs, which is handy for pixel art and layout:

```bash
B="Pocket Pet.app/Contents/MacOS/PocketPet"
"$B" --sheet out.png bat     # every pose of one pet
"$B" --icons out.png         # snacks, toys and menu icons
"$B" --panel out.png 1       # the menu (0 Pets, 1 Closet, 2 Music, 3 Settings)
"$B" --card out.png          # the calendar and music cards
```

## Making changes

1. Fork the repo and create a branch off `main`.
2. Keep changes focused: one logical change per pull request.
3. Check that `./build.sh` succeeds, then run the app and try your change on the desktop.
4. Keep it light: the pet should sit near 0–1% CPU while it rests. Avoid timers that run when nothing is happening.

## Submitting a pull request

- Describe *why* the change is needed, not just what it does.
- Reference the issue it closes, if any (`Closes #123`).
- Screenshots or a short recording help a lot for anything visual.

## Reporting bugs

Use the [bug report template](.github/ISSUE_TEMPLATE/bug_report.md). Include steps to reproduce, what you expected and
what actually happened, plus your macOS version.
