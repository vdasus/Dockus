# Decisions

## 2026-11-23 Swift and AppKit only, no dependencies

Dockus is a single Swift Package executable using AppKit and the Accessibility API, with no third-party packages.
**Why:** small footprint, near-zero idle CPU, nothing to audit or update.

## 2026-11-23 Build in GitHub Actions, sign ad-hoc

`build.sh` builds a universal binary on a `macos-15` runner and signs it ad-hoc (`codesign -s -`); a `v*` tag publishes
a GitHub Release. **Why:** the target Mac has no development tools, and no Apple Developer Program membership is used.
Cost: the Accessibility permission must be granted again after each update (stable self-signed signing is an optional
future step, see README).

## 2026-11-23 Support macOS 12 Monterey

Deployment target `12.0`; `build.sh` fails unless every slice has `minos 12.0`.
**Why:** the app must run on Monterey. This rules out `SMAppService` (macOS 13), see below.

## 2026-11-23 Launch at Login through a LaunchAgent plist

The menu item writes or removes `~/Library/LaunchAgents/io.github.vdasus.Dockus.plist`.
**Why:** `SMAppService` requires macOS 13. The plist stores the app path, so the option must be set again after moving the app.

## 2026-11-23 Single instance through flock

On startup Dockus takes an exclusive non-blocking `flock` on `~/Library/Application Support/<bundle id>/instance.lock`
and exits if it is held. **Why:** the OS releases the lock when the process ends, including after a crash; no stale lock files.

## 2026-11-23 Restore windows, then let the Dock activate the app

When all windows of the clicked app are minimized, Dockus restores them and passes the click on instead of consuming it.
**Why:** since macOS 14 one application cannot reliably activate another; the Dock can.

## 2026-11-23 Public domain license

The project is released under The Unlicense. **Why:** personal tool, no restrictions wanted.

## 2026-11-23 Semantic versioning from git tags, shown in the menu

A release tag `vX.Y.Z` sets the version (fix: patch, feature: minor, breaking change: major); untagged CI builds get
`<last tag>-dev.<run number>`. The menu bar menu shows `Dockus <version>`. **Why:** the user must see which build is
installed; the tag is the single source of the version, so no version file needs to be kept in sync.
