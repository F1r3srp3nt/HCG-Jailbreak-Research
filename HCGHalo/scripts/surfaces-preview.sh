#!/usr/bin/env bash
# HCG Halo — PREVIEW of "Show Halo on" in the iOS Simulator (macOS + Xcode).
#
#   scripts/surfaces-preview.sh [output-dir]
#
# Builds preview/HaloSurfacesPreview.m with HCG Halo's REAL SpringBoard code
# (HaloController, HaloEdgeWindow, HaloOverlayView, HaloRenderer,
# HaloPreferences, ...) into a Simulator app that stands in for SpringBoard
# (see the file's header), then runs its fixed script while recording video:
# app switching, lock, wake and screen-off under every Show Halo on choice,
# live switching between them, and 60 rapid transitions.
#
# Lock and screen-off use preview notification names, so the Simulator's real
# SpringBoard is never touched. Exit status: non-zero if any
# HALO-SURFACES-CHECK failed or the script did not finish.
# PREVIEW ONLY: not SpringBoard, not a device. Never installs on a phone.

set -euo pipefail
cd "$(dirname "$0")/.."

limit() { local secs=$1; shift; perl -e 'alarm shift; exec @ARGV or die "exec: $!"' "$secs" "$@"; }
stamp() { echo "==> [$(date -u +%H:%M:%S)] $*"; }

[ "$(uname -s)" = Darwin ] || { echo "ERROR: needs macOS with Xcode" >&2; exit 1; }

OUT=${1:-build-surfaces-preview}
APP="$OUT/HaloSurfacesPreview.app"
rm -rf "$OUT"; mkdir -p "$APP" "$OUT/obj"
OUT=$(cd "$OUT" && pwd); APP="$OUT/HaloSurfacesPreview.app"
VERSION=$(sed -n 's/^Version: *//p' control | tr '~' '-')
ARCH=$(uname -m); [ "$ARCH" = x86_64 ] || ARCH=arm64
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
CC=(xcrun --sdk iphonesimulator clang -isysroot "$SDK" -arch "$ARCH" -mios-simulator-version-min=15.0 -fobjc-arc -fobjc-arc-exceptions -g)
DEFS=(-DHALO_VERSION="\"$VERSION\"" -DHALO_BUILD_ID="\"surfaces-preview\"" -DHALO_PREVIEW_HOST=1
      -DHALO_BLANKED_NOTIFICATION='"com.hakmicapitalgroup.halo.preview.blanked"'
      -DHALO_LOCKSTATE_NOTIFICATION='"com.hakmicapitalgroup.halo.preview.lockstate"')

stamp "HCG Halo $VERSION ($(git rev-parse --short=12 HEAD))"
for f in src/HaloController.m src/HaloEdgeWindow.m src/HaloOverlayView.m src/HaloRenderer.m src/HaloPreferences.m \
         src/HaloScreen.m src/HaloNexusLink.m src/HaloNexusDefinition.m src/HaloPanelBorderView.m src/HaloLog.m \
         src/HaloGeometry.c src/HaloConfig.c src/HaloProfiles.c src/HaloProfiles.generated.c preview/HaloSurfacesPreview.m; do
	"${CC[@]}" -Wall -Wextra -Wno-unused-parameter -Werror -Isrc "${DEFS[@]}" -c "$f" -o "$OUT/obj/$(basename "$f").o"
done
"${CC[@]}" "$OUT"/obj/*.o -framework UIKit -framework QuartzCore -framework CoreGraphics -o "$APP/HaloSurfacesPreview"
python3 - "$APP/Info.plist" <<'PY'
import plistlib, sys
d = plistlib.load(open("preview/Info.plist", "rb"))
d.update(CFBundleExecutable="HaloSurfacesPreview", CFBundleIdentifier="com.hakmicapitalgroup.halo.surfaces-preview",
         CFBundleName="HaloSurfacesPreview", CFBundleDisplayName="Halo Surfaces Preview")
plistlib.dump(d, open(sys.argv[1], "wb"))
PY
codesign -s - --force "$APP" >/dev/null 2>&1 || true
shasum -a 256 "$APP/HaloSurfacesPreview" | tee "$OUT/inputs.sha256"

# Prefer an iPhone 11 Pro Max Simulator (the profile's own model); create one if the runtime offers it.
UDID=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
best = None
for runtime, items in json.load(sys.stdin)["devices"].items():
    if "iOS" not in runtime: continue
    for d in items:
        if d.get("isAvailable") and d["name"] == "iPhone 11 Pro Max":
            if best is None or runtime > best[0]: best = (runtime, d["udid"])
print(best[1] if best else "")')
if [ -z "$UDID" ]; then
	RUNTIME=$(xcrun simctl list runtimes -j | python3 -c '
import json, sys
rs = [r for r in json.load(sys.stdin)["runtimes"] if r.get("isAvailable") and r["platform"] == "iOS"
      and any(t.get("name") == "iPhone 11 Pro Max" for t in r.get("supportedDeviceTypes", []))]
print(sorted(rs, key=lambda r: r["version"])[-1]["identifier"] if rs else "")')
	[ -n "$RUNTIME" ] && UDID=$(xcrun simctl create "Halo 11 Pro Max" "com.apple.CoreSimulator.SimDeviceType.iPhone-11-Pro-Max" "$RUNTIME" 2>/dev/null || true)
fi
if [ -z "$UDID" ]; then
	UDID=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
best = None
for runtime, items in json.load(sys.stdin)["devices"].items():
    if "iOS" not in runtime: continue
    for d in items:
        if d.get("isAvailable") and d["name"].startswith("iPhone") and "Pro Max" in d["name"]:
            key = (runtime, d["name"])
            if best is None or key > best[0]: best = (key, d["udid"])
print(best[1] if best else "")')
fi
[ -n "$UDID" ] || { echo "ERROR: no iPhone simulator" >&2; exit 1; }
xcrun simctl list devices | grep "$UDID" | tee "$OUT/simulator.txt"
stamp "booting $UDID"
xcrun simctl boot "$UDID" 2>/dev/null || true
limit 600 xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl ui "$UDID" appearance dark 2>/dev/null || true
xcrun simctl status_bar "$UDID" override --time 9:41 2>/dev/null || true
xcrun simctl install "$UDID" "$APP"

stamp "recording"
xcrun simctl io "$UDID" recordVideo --codec h264 --force "$OUT/halo-surfaces-preview.mp4" > "$OUT/record.log" 2>&1 &
REC=$!
sleep 4
LOG="$OUT/console.log"; : > "$LOG"; : > "$OUT/stderr.log"
# Foreground launch with stdout to a file and a time limit (what reliably starts the app on CI); retry once.
launch_app() {
	limit 60 xcrun simctl launch --terminate-running-process --stdout="$LOG" --stderr="$OUT/stderr.log" \
		"$UDID" com.hakmicapitalgroup.halo.surfaces-preview > "$OUT/launch.txt" 2>&1 || true
	stamp "launch: $(cat "$OUT/launch.txt")"
}
launch_app
if [ ! -s "$LOG" ]; then stamp "no output yet: launching again"; launch_app; fi
for _ in $(seq 1 90); do
	grep -q 'HALO-SURFACES-DONE' "$LOG" 2>/dev/null && break
	sleep 2
done
cat "$LOG"
echo "--- stderr (last 40 lines)"; tail -40 "$OUT/stderr.log" || true
sleep 2
kill -INT "$REC" 2>/dev/null || true
wait "$REC" 2>/dev/null || true
for f in ~/Library/Logs/DiagnosticReports/HaloSurfacesPreview*; do [ -f "$f" ] && { echo "--- crash report $f"; head -120 "$f"; cp "$f" "$OUT/"; }; done
xcrun simctl terminate "$UDID" com.hakmicapitalgroup.halo.surfaces-preview 2>/dev/null || true
xcrun simctl shutdown "$UDID" 2>/dev/null || true

status=0
grep -q 'HALO-SURFACES-DONE failures=0' "$LOG" || status=1
grep -q 'HALO-SURFACES-CHECK FAIL' "$LOG" && status=1
stamp "checks: $(grep -c 'HALO-SURFACES-CHECK PASS' "$LOG" || true) passed, $(grep -c 'HALO-SURFACES-CHECK FAIL' "$LOG" || true) failed"
ls -la "$OUT"
exit "$status"
