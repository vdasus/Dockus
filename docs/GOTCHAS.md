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

Symptom: the menu shows "Grant Accessibility Access…" although Dockus is checked in the Accessibility list.
**Cause:** the ad-hoc code signature changes on every build, and the checked entry belongs to the old signature.
**Fix:** `tccutil reset Accessibility io.github.vdasus.Dockus`, then grant access again (no restart needed), or sign
every build with the same self-signed certificate.

## TCC grant in the end-to-end test fails for ad-hoc signed apps

**Cause:** for an ad-hoc signature, `codesign -d -r-` prints the implicit designated requirement as a comment line
(`# designated => ...`). **Fix:** strip the comment prefix before `csreq`:
`codesign -d -r- "$1" 2>&1 | sed -n 's/^#* *designated => //p' | csreq -r- -b req.bin` (`Tests/e2e.sh`).

## `Tests/e2e.sh` must not run on a personal Mac

**Cause:** it grants Accessibility by writing to the system TCC database, which works only with SIP disabled, as on
GitHub-hosted runners. **Fix:** run it only in CI.

## Clicking the active app's Dock icon minimizes and immediately restores its windows (macOS 12)

**Cause:** minimizing inside the event tap callback blocks for the minimize animation; macOS disables the tap after its
timeout and delivers the click to the Dock, which restores the window. **Fix:** decide in the callback, swallow the
click, and minimize later with `DispatchQueue.main.async` (`Sources/Dockus/main.swift`).
