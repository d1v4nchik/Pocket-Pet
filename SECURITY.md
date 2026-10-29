# Security Policy

## Supported Versions

Only the latest release is supported. Pocket Pet updates itself (menu › Settings › App › Check for updates), so please
update before reporting an issue.

## Reporting a Vulnerability

If you find a security vulnerability (for example: a way to make Pocket Pet install an update that wasn't signed by the
maintainer, run commands through a web page's title or a notification, or leak calendar, Spotify or notification
details), please **do not** open a public issue.

Instead, report it privately using [GitHub Security Advisories](../../security/advisories/new) for this repository.
Include:

- A description of the vulnerability and its impact
- Steps to reproduce
- Your macOS version and the Pocket Pet version

You should receive an initial response within a few days. Once a fix is available, we'll coordinate on disclosure timing
before any public writeup.

## How Pocket Pet Handles Your Data

- **Updates** are signed with an Ed25519 key that never leaves the maintainer's Mac. Pocket Pet checks the signature of
  every download against the public key built into the app, and refuses anything that doesn't match.
- **Sign-ins** (Google Calendar, Spotify) and your private calendar link are stored in the macOS Keychain. They are only
  ever sent to Google, Spotify or the calendar link's own server.
- **Notifications:** with Accessibility allowed, Pocket Pet reads notification banners only to see which app or website
  they came from. Message text is not stored, shown or sent anywhere.
- **Browser tabs:** tab titles are read to spot unread counts like "(2)". Addresses and titles that end up in scripts
  are escaped so a web page can't inject commands.
- **Typing:** Pocket Pet only counts keystrokes (from the system's counter) to know *that* you're typing, never *what*.
- **No analytics, no tracking, no accounts.** Besides the services you connect, the only network requests are the update
  check here on GitHub and looking up album covers for Apple Music songs.

## Scope Notes

Pocket Pet is distributed without an Apple Developer ID, so macOS shows a warning the first time it's opened. Only
download it from this repository's [Releases](../../releases) page.
