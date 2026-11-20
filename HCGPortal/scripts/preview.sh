#!/usr/bin/env bash
# HCG Portal — PREVIEW and integration run in the iOS Simulator (macOS + Xcode).
#
#   THEOS=~/theos scripts/preview.sh [output-dir]
#
# Builds preview/PortalPreviewApp.m with the REAL tweak code, including src/Tweak.m and its
# constructor (PORTAL_PREVIEW_HOST,
# preview notification names) and the REAL Settings bundle (preferences/,
# loaded with -bundle_loader), runs it in an iPhone simulator, records video,
# takes a screenshot at every PORTAL-PREVIEW-SHOT marker and makes a contact
# sheet (needs Pillow). Exit status non-zero if any PORTAL-PREVIEW-CHECK
# failed or the run did not finish. PREVIEW ONLY: no SpringBoard, no device.
# (Adapted from HCG Animation Center's scripts/preview.sh.)

set -euo pipefail
cd "$(dirname "$0")/.."

limit() { local secs=$1; shift; perl -e 'alarm shift; exec @ARGV or die "exec: $!"' "$secs" "$@"; }
stamp() { echo "==> [$(date -u +%H:%M:%S)] $*"; }

[ "$(uname -s)" = Darwin ] || { echo "ERROR: needs macOS with Xcode" >&2; exit 1; }
: "${THEOS:?set THEOS (for the Preferences framework headers)}"
[ -d "$THEOS/vendor/include/Preferences" ] || { echo "ERROR: $THEOS/vendor/include/Preferences missing" >&2; exit 1; }

OUT=${1:-build-preview}
rm -rf "$OUT"; mkdir -p "$OUT/obj" "$OUT/inc" "$OUT/shots"
OUT=$(cd "$OUT" && pwd)
APP="$OUT/PortalPreview.app"; mkdir -p "$APP"
ln -s "$THEOS/vendor/include/Preferences" "$OUT/inc/Preferences"
VERSION=$(sed -n 's/^Version: *//p' control | tr '~' '-')
ARCH=$(uname -m); [ "$ARCH" = x86_64 ] || ARCH=arm64
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
CC=(xcrun --sdk iphonesimulator clang -isysroot "$SDK" -arch "$ARCH" -mios-simulator-version-min=15.0 -fobjc-arc -fobjc-arc-exceptions -g)
STRICT=(-Wall -Wextra -Wno-unused-parameter -Werror)
DEFS=(-DPORTAL_VERSION="\"$VERSION\"" -DPORTAL_BUILD_ID="\"preview\"" -DPORTAL_PREVIEW_HOST=1
      -DPORTAL_BLANKED_NOTIFICATION='"com.hakmicapitalgroup.portal.preview.blanked"'
      -DPORTAL_LOCKSTATE_NOTIFICATION='"com.hakmicapitalgroup.portal.preview.lockstate"')
INC=(-Isrc -Ipreferences -Ipreview)
PROVENANCE="$OUT/PROVENANCE.txt"
{
	echo "PREVIEW EVIDENCE — iOS Simulator, stand-in Lock Screen (CSCoverSheetViewController / SBLockScreenManager stand-ins), not a device result."
	echo "HCG Portal $VERSION, commit $(git rev-parse HEAD)"
	echo "Real code: src/*.m and src/PortalCore.c (the tweak, built with PORTAL_PREVIEW_HOST), preferences/*.m (the Settings bundle)."
	echo "Stand-ins: preview/PortalStandIns.m. The authentication sheet in the screenshots is a labelled stand-in for the system UI."
} > "$PROVENANCE"

stamp "HCG Portal $VERSION ($(git rev-parse --short=12 HEAD))"
for f in src/Tweak.m src/PortalController.m src/PortalOverlayView.m src/PortalView.m src/PortalHost.m src/PortalAuth.m \
         src/PortalLauncher.m src/PortalCompanions.m src/PortalPreferences.m src/PortalLog.m src/PortalCore.c \
         preview/PortalStandIns.m preview/PortalPreviewApp.m; do
	"${CC[@]}" "${STRICT[@]}" "${DEFS[@]}" "${INC[@]}" -c "$f" -o "$OUT/obj/$(basename "$f").o"
done
"${CC[@]}" "$OUT"/obj/*.o -framework UIKit -framework QuartzCore -framework CoreGraphics -o "$APP/PortalPreview"

# The real Settings bundle: its view controllers; the model, solver and
# renderer resolve against the app (-bundle_loader), Preferences at run time.
B="$APP/HCGPortalPrefs.bundle"; mkdir -p "$B" "$OUT/obj/prefs"
for f in PortalRootListController.m PortalPlacementController.m PortalAppsController.m PortalPreviewView.m PortalTheme.m; do
	"${CC[@]}" "${STRICT[@]}" "${DEFS[@]}" "${INC[@]}" -I"$OUT/inc" -c "preferences/$f" -o "$OUT/obj/prefs/$f.o"
done
"${CC[@]}" -bundle -bundle_loader "$APP/PortalPreview" -undefined dynamic_lookup "$OUT"/obj/prefs/*.o \
	-framework UIKit -framework QuartzCore -o "$B/HCGPortalPrefs"
cp -R preferences/Resources/. "$B/"
cp preview/Info.plist "$APP/Info.plist"
for b in "$B" "$APP"; do codesign -s - --force "$b" >/dev/null 2>&1 || true; done
shasum -a 256 "$APP/PortalPreview" "$B/HCGPortalPrefs" | tee "$OUT/inputs.sha256"

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
[ -n "$UDID" ] || { echo "ERROR: no iPhone Pro Max simulator" >&2; exit 1; }
xcrun simctl list devices | grep "$UDID" | tee "$OUT/simulator.txt"
echo "Simulator: $(cat "$OUT/simulator.txt" | xargs)" >> "$PROVENANCE"
stamp "booting $UDID"
xcrun simctl boot "$UDID" 2>/dev/null || true
limit 600 xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl ui "$UDID" appearance dark 2>/dev/null || true
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryLevel 100 2>/dev/null || true
xcrun simctl install "$UDID" "$APP"

stamp "recording"
xcrun simctl io "$UDID" recordVideo --codec h264 --force "$OUT/portal-preview.mp4" > "$OUT/record.log" 2>&1 &
REC=$!
sleep 3
LOG="$OUT/console.log"; : > "$LOG"; : > "$OUT/stderr.log"
launch_app() {
	limit 60 xcrun simctl launch --terminate-running-process --stdout="$LOG" --stderr="$OUT/stderr.log" \
		"$UDID" com.hakmicapitalgroup.portal.preview > "$OUT/launch.txt" 2>&1 || true
	stamp "launch: $(cat "$OUT/launch.txt")"
}
launch_app
for _ in $(seq 1 30); do [ -s "$LOG" ] && break; sleep 1; done
if [ ! -s "$LOG" ]; then stamp "no output after 30 s: launching again"; launch_app; fi
DATA=$(xcrun simctl get_app_container "$UDID" com.hakmicapitalgroup.portal.preview data 2>/dev/null || true)
stamp "app data container: ${DATA:-unknown}"
mkdir -p "$DATA/Documents/shot-ack" 2>/dev/null || true
taken=""
for _ in $(seq 1 1200); do
	for name in $(sed -n 's/^PORTAL-PREVIEW-SHOT //p' "$LOG" 2>/dev/null); do
		case " $taken " in *" $name "*) continue ;; esac
		xcrun simctl io "$UDID" screenshot "$OUT/shots/$name.png" >/dev/null 2>&1 && taken="$taken $name"
		[ -n "$DATA" ] && mkdir -p "$DATA/Documents/shot-ack" && touch "$DATA/Documents/shot-ack/$name"
	done
	grep -q 'PORTAL-PREVIEW-DONE' "$LOG" 2>/dev/null && break
	sleep 0.25
done
cat "$LOG"
echo "--- stderr (last 60 lines)"; tail -60 "$OUT/stderr.log" || true
sleep 2
kill -INT "$REC" 2>/dev/null || true
wait "$REC" 2>/dev/null || true
xcrun simctl spawn "$UDID" log show --last 10m --style compact \
	--predicate 'process == "PortalPreview"' > "$OUT/system.log" 2>&1 || true
for f in ~/Library/Logs/DiagnosticReports/PortalPreview*; do [ -f "$f" ] && { echo "--- crash report $f"; head -120 "$f"; cp "$f" "$OUT/"; }; done
xcrun simctl terminate "$UDID" com.hakmicapitalgroup.portal.preview 2>/dev/null || true
xcrun simctl shutdown "$UDID" 2>/dev/null || true

python3 scripts/make_sheet.py "$OUT/shots" "$OUT/portal-preview-sheet.jpg" || echo "contact sheet skipped"
status=0
grep -q 'PORTAL-PREVIEW-DONE failures=0' "$LOG" || status=1
grep -q 'PORTAL-PREVIEW-CHECK FAIL' "$LOG" && status=1
stamp "checks: $(grep -c 'PORTAL-PREVIEW-CHECK PASS' "$LOG" || true) passed, $(grep -c 'PORTAL-PREVIEW-CHECK FAIL' "$LOG" || true) failed; shots: $(ls "$OUT/shots" | wc -l | xargs)"
ls -la "$OUT" "$OUT/shots"
exit "$status"
