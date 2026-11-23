# Gotchas

## Minimized windows are skipped when filtering by subrole

**Cause:** minimized windows report the subrole `AXDialog`, not `AXStandardWindow`. **Fix:** keep windows that are
minimized (`kAXMinimizedAttribute`) regardless of subrole (`Sources/Dockus/main.swift`).

## Restored app does not become active

**Cause:** since macOS 14 one application cannot reliably activate another. **Fix:** after restoring the windows, pass
the click on to the Dock, which activates the app.

## Dock item path does not match the running application

**Cause:** some apps (for example Safari in a cryptex) run from a different path than the Dock item's `AXURL`.
**Fix:** fall back to matching the Dock item title to the application name.

## Accessibility permission lost after every update

**Cause:** the ad-hoc code signature changes on every build. **Fix:** remove the old Dockus entry from the Accessibility
list and grant access again, or sign every build with the same self-signed certificate.

## TCC grant in the end-to-end test fails for ad-hoc signed apps

**Cause:** for an ad-hoc signature, `codesign -d -r-` prints the implicit designated requirement as a comment line
(`# designated => ...`). **Fix:** strip the comment prefix before `csreq`:
`codesign -d -r- "$1" 2>&1 | sed -n 's/^#* *designated => //p' | csreq -r- -b req.bin` (`Tests/e2e.sh`).

## `Tests/e2e.sh` must not run on a personal Mac

**Cause:** it grants Accessibility by writing to the system TCC database, which works only with SIP disabled, as on
GitHub-hosted runners. **Fix:** run it only in CI.
