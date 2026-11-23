#!/bin/bash
# End-to-end test for build/Dockus.app on a GitHub-hosted macOS runner.
# Grants Accessibility by writing to the system TCC database, which works only with SIP disabled (as on hosted runners).
# Do not run it on a personal Mac.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="$PWD/build/e2e"
DRIVER="$OUT/DockusE2E.app"
DOCKUS="$PWD/build/Dockus.app"
TCC_DB="/Library/Application Support/com.apple.TCC/TCC.db"

rm -rf "$OUT"
mkdir -p "$DRIVER/Contents/MacOS"
swiftc -O Tests/E2E/main.swift -o "$DRIVER/Contents/MacOS/DockusE2E"
cp Tests/E2E/Info.plist "$DRIVER/Contents/Info.plist"
codesign --force --sign - "$DRIVER"

echo "== SF Symbol availability"
python3 - <<'EOF'
import plistlib
data = plistlib.load(open("/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources/name_availability.plist", "rb"))
year = data["symbols"]["dock.arrow.down.rectangle"]
macos = data["year_to_release"][year]["macOS"]
print(f"dock.arrow.down.rectangle: {year}, macOS {macos}")
assert tuple(map(int, macos.split("."))) <= (12, 0), "symbol is not available on macOS 12"
EOF

grant() { # $1 = app bundle, $2 = bundle id
    codesign -d -r- "$1" 2>&1 | sed -n 's/^designated => //p' | csreq -r- -b "$OUT/req.bin"
    local req
    req=$(xxd -p "$OUT/req.bin" | tr -d '\n')
    for service in kTCCServiceAccessibility kTCCServicePostEvent kTCCServiceListenEvent; do
        sudo sqlite3 "$TCC_DB" "INSERT OR REPLACE INTO access
            (service, client, client_type, auth_value, auth_reason, auth_version, csreq, flags, last_modified)
            VALUES ('$service', '$2', 0, 2, 4, 1, X'$req', 0, CAST(strftime('%s','now') AS INTEGER));"
    done
}
grant "$DRIVER" io.github.vdasus.DockusE2E
grant "$DOCKUS" io.github.vdasus.Dockus

run_driver() { # $1 = phase
    rm -f "$OUT/result"
    open -W -n --stdout "$OUT/$1.log" --stderr "$OUT/$1.log" "$DRIVER" --args "$1" "$OUT/result"
    echo "== Driver phase: $1"
    cat "$OUT/$1.log"
    grep -qx PASS "$OUT/result"
}

run_driver baseline

echo "== Starting Dockus"
open "$DOCKUS"
sleep 3
pgrep -x Dockus

echo "== Single instance"
"$DOCKUS/Contents/MacOS/Dockus" &
second=$!
sleep 3
if kill -0 "$second" 2>/dev/null; then
    echo "FAIL: second instance is still running"
    exit 1
fi
wait "$second" # exit code 0 expected; set -e fails the script otherwise
[[ "$(pgrep -x Dockus | wc -l | tr -d ' ')" == "1" ]]
echo "Second instance exited, one Dockus process left"

run_driver dockus

echo "== Memory"
ps -o rss= -p "$(pgrep -x Dockus)" | awk '{printf "Dockus RSS: %.1f MB\n", $1 / 1024}'
pkill -x Dockus
echo "E2E PASS"
