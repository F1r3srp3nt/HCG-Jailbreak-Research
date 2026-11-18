#!/usr/bin/env bash
# HCG Animation Center — PREVIEW and integration run in the iOS Simulator (macOS + Xcode).
#
#   THEOS=~/theos [HALO_DIR=…/HCGHalo] [VORTEX_DIR=…/HCGVortex] [NEXUS_DIR=…/HCG-Nexus] \
#       scripts/preview.sh [output-dir]
#
# Builds preview/HACPreviewApp.m with the REAL tweak code (HAC_PREVIEW_HOST,
# preview notification names) and the REAL Settings bundle (preferences/,
# loaded with -bundle_loader), plus — when their checkouts are given — HCG
# Halo's real controller, HCG Vortex's real engine and HCG Nexus's real panel.
# Runs it in an iPhone simulator, records video, takes a screenshot at every
# HAC-PREVIEW-SHOT marker and makes a contact sheet (needs Pillow).
# Exit status non-zero if any HAC-PREVIEW-CHECK failed or the run did not
# finish. PREVIEW ONLY: no SpringBoard, no device.

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
APP="$OUT/HACPreview.app"; mkdir -p "$APP"
ln -s "$THEOS/vendor/include/Preferences" "$OUT/inc/Preferences"
VERSION=$(sed -n 's/^Version: *//p' control | tr '~' '-')
ARCH=$(uname -m); [ "$ARCH" = x86_64 ] || ARCH=arm64
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
CC=(xcrun --sdk iphonesimulator clang -isysroot "$SDK" -arch "$ARCH" -mios-simulator-version-min=15.0 -fobjc-arc -fobjc-arc-exceptions -g)
KIT=HCGBackgroundKit/Sources/HCGBackgroundKit
BLANKED='"com.hakmicapitalgroup.animationcenter.preview.blanked"'
LOCKSTATE='"com.hakmicapitalgroup.animationcenter.preview.lockstate"'
STRICT=(-Wall -Wextra -Wno-unused-parameter -Werror)
DEFS=(-DHAC_VERSION="\"$VERSION\"" -DHAC_BUILD_ID="\"preview\"" -DHAC_PREVIEW_HOST=1
      -DHAC_BLANKED_NOTIFICATION="$BLANKED" -DHAC_LOCKSTATE_NOTIFICATION="$LOCKSTATE")
INC=(-Isrc -I"$KIT/include" -Ipreferences -Ipreview)
HARNESS=()
LINK=(-framework UIKit -framework QuartzCore -framework CoreGraphics -framework AVFoundation -framework CoreMedia
      -framework CoreVideo -framework ImageIO)
PROVENANCE="$OUT/PROVENANCE.txt"
{
	echo "PREVIEW EVIDENCE — iOS Simulator, stand-in SpringBoard, not a device result."
	echo "HCG Animation Center $VERSION, commit $(git rev-parse HEAD)"
} > "$PROVENANCE"

stamp "HCG Animation Center $VERSION ($(git rev-parse --short=12 HEAD))"
for f in src/HACController.m src/HACHosts.m src/HACProbe.m src/HACPreferences.m src/HACLog.m src/HACPolicy.c \
         "$KIT/HCGBackgroundView.m" "$KIT/HCGBackgroundPreset.m" "$KIT/HCGBackgroundCore.c" \
         preferences/HACLibrary.m preferences/HACMediaImporter.m preferences/HACAIGeneration.m preview/HACTestMedia.m; do
	"${CC[@]}" "${STRICT[@]}" "${DEFS[@]}" "${INC[@]}" -c "$f" -o "$OUT/obj/hac-$(basename "$f").o"
done

if [ -n "${HALO_DIR:-}" ]; then
	HV=$(sed -n 's/^Version: *//p' "$HALO_DIR/control" | tr '~' '-')
	stamp "with HCG Halo $HV ($(git -C "$HALO_DIR" rev-parse --short=12 HEAD 2>/dev/null || echo '?')): real controller"
	echo "HCG Halo $HV, commit $(git -C "$HALO_DIR" rev-parse HEAD 2>/dev/null || echo unknown): real controller and renderer" >> "$PROVENANCE"
	for f in HaloController.m HaloOverlayView.m HaloEdgeWindow.m HaloScreen.m HaloRenderer.m HaloNexusDefinition.m \
	         HaloNexusLink.m HaloPanelBorderView.m HaloPreferences.m HaloLog.m HaloGeometry.c HaloConfig.c HaloProfiles.c \
	         HaloProfiles.generated.c; do
		"${CC[@]}" -w -I"$HALO_DIR/src" -DHALO_VERSION="\"$HV\"" -DHALO_BUILD_ID="\"preview\"" -DHALO_PREVIEW_HOST=1 \
			-DHALO_BLANKED_NOTIFICATION="$BLANKED" -DHALO_LOCKSTATE_NOTIFICATION="$LOCKSTATE" \
			-c "$HALO_DIR/src/$f" -o "$OUT/obj/halo-$f.o"
	done
	HARNESS+=(-DHAC_WITH_HALO -I"$HALO_DIR/src" -DHALO_VERSION="\"$HV\"" -DHALO_BUILD_ID="\"preview\"")
fi
if [ -n "${VORTEX_DIR:-}" ]; then
	VV=$(sed -n 's/^Version: *//p' "$VORTEX_DIR/control" | tr '~' '-')
	stamp "with HCG Vortex $VV ($(git -C "$VORTEX_DIR" rev-parse --short=12 HEAD 2>/dev/null || echo '?')): real engine"
	echo "HCG Vortex $VV, commit $(git -C "$VORTEX_DIR" rev-parse HEAD 2>/dev/null || echo unknown): real engine and effects (hooks applied by the harness, as Tweak.x does)" >> "$PROVENANCE"
	for f in "$VORTEX_DIR"/src/*.m "$VORTEX_DIR"/src/*.c "$VORTEX_DIR"/effects/*.m; do
		"${CC[@]}" -w -I"$VORTEX_DIR/src" -I"$VORTEX_DIR/effects" -DVORTEX_VERSION="\"$VV\"" -DVORTEX_BUILD_ID="\"preview\"" \
			-c "$f" -o "$OUT/obj/vortex-$(basename "$f").o"
	done
	HARNESS+=(-DHAC_WITH_VORTEX -I"$VORTEX_DIR/src" -DVORTEX_VERSION="\"$VV\"")
fi
if [ -n "${NEXUS_DIR:-}" ]; then
	NV=$(sed -n 's/^Version: *//p' "$NEXUS_DIR/control")
	stamp "with HCG Nexus $NV ($(git -C "$NEXUS_DIR" rev-parse --short=12 HEAD 2>/dev/null || echo '?')): real panel"
	echo "HCG Nexus $NV, commit $(git -C "$NEXUS_DIR" rev-parse HEAD 2>/dev/null || echo unknown): real panel (its preview platform)" >> "$PROVENANCE"
	NEXUS_INC=(-I"$NEXUS_DIR/Sources/Core" -I"$NEXUS_DIR/Sources/Panel" -I"$NEXUS_DIR/Sources/Platform/Preview")
	for f in "$NEXUS_DIR"/Sources/Core/*.m "$NEXUS_DIR"/Sources/Panel/*.m "$NEXUS_DIR"/Sources/Platform/Preview/*.m; do
		"${CC[@]}" -w "${NEXUS_INC[@]}" -DHCG_PACKAGE_SCHEME='"preview-hac"' -c "$f" -o "$OUT/obj/nexus-$(basename "$f" .m).o"
	done
	HARNESS+=(-DHAC_WITH_NEXUS "${NEXUS_INC[@]}")
	LINK+=(-framework Network)
fi

"${CC[@]}" "${STRICT[@]}" "${DEFS[@]}" "${INC[@]}" ${HARNESS[@]+"${HARNESS[@]}"} -c preview/HACPreviewApp.m -o "$OUT/obj/hac-harness.o"
"${CC[@]}" "$OUT"/obj/*.o "${LINK[@]}" -o "$APP/HACPreview"

# The real Settings bundle: the view controllers only; the model, importer and
# renderer resolve against the app (-bundle_loader), Preferences at run time.
B="$APP/HCGAnimationCenterPrefs.bundle"; mkdir -p "$B" "$OUT/obj/prefs"
for f in HACRootListController.m HACLibraryViewController.m HACEditorViewController.m HACAIViewController.m HACTheme.m; do
	"${CC[@]}" "${STRICT[@]}" "${DEFS[@]}" "${INC[@]}" -I"$OUT/inc" -c "preferences/$f" -o "$OUT/obj/prefs/$f.o"
done
"${CC[@]}" -bundle -bundle_loader "$APP/HACPreview" -undefined dynamic_lookup "$OUT"/obj/prefs/*.o \
	-framework UIKit -framework PhotosUI -framework UniformTypeIdentifiers -framework AVFoundation -o "$B/HCGAnimationCenterPrefs"
cp -R preferences/Resources/. "$B/"
cp preview/Info.plist "$APP/Info.plist"
for b in "$B" "$APP"; do codesign -s - --force "$b" >/dev/null 2>&1 || true; done
shasum -a 256 "$APP/HACPreview" "$B/HCGAnimationCenterPrefs" | tee "$OUT/inputs.sha256"

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
xcrun simctl io "$UDID" recordVideo --codec h264 --force "$OUT/hac-preview.mp4" > "$OUT/record.log" 2>&1 &
REC=$!
sleep 3
LOG="$OUT/console.log"; : > "$LOG"; : > "$OUT/stderr.log"
launch_app() {
	limit 60 xcrun simctl launch --terminate-running-process --stdout="$LOG" --stderr="$OUT/stderr.log" \
		"$UDID" com.hakmicapitalgroup.animationcenter.preview > "$OUT/launch.txt" 2>&1 || true
	stamp "launch: $(cat "$OUT/launch.txt")"
}
launch_app
if [ ! -s "$LOG" ]; then stamp "no output yet: launching again"; launch_app; fi
taken=""
for _ in $(seq 1 1000); do
	for name in $(sed -n 's/^HAC-PREVIEW-SHOT //p' "$LOG" 2>/dev/null); do
		case " $taken " in *" $name "*) continue ;; esac
		sleep 0.4
		xcrun simctl io "$UDID" screenshot "$OUT/shots/$name.png" >/dev/null 2>&1 && taken="$taken $name"
	done
	grep -q 'HAC-PREVIEW-DONE' "$LOG" 2>/dev/null && break
	sleep 0.25
done
cat "$LOG"
echo "--- stderr (last 60 lines)"; tail -60 "$OUT/stderr.log" || true
sleep 2
kill -INT "$REC" 2>/dev/null || true
wait "$REC" 2>/dev/null || true
xcrun simctl spawn "$UDID" log show --last 10m --style compact \
	--predicate 'process == "HACPreview"' > "$OUT/system.log" 2>&1 || true
for f in ~/Library/Logs/DiagnosticReports/HACPreview*; do [ -f "$f" ] && { echo "--- crash report $f"; head -120 "$f"; cp "$f" "$OUT/"; }; done
xcrun simctl terminate "$UDID" com.hakmicapitalgroup.animationcenter.preview 2>/dev/null || true
xcrun simctl shutdown "$UDID" 2>/dev/null || true

python3 scripts/make_sheet.py "$OUT/shots" "$OUT/hac-preview-sheet.jpg" || echo "contact sheet skipped"
status=0
grep -q 'HAC-PREVIEW-DONE failures=0' "$LOG" || status=1
grep -q 'HAC-PREVIEW-CHECK FAIL' "$LOG" && status=1
stamp "checks: $(grep -c 'HAC-PREVIEW-CHECK PASS' "$LOG" || true) passed, $(grep -c 'HAC-PREVIEW-CHECK FAIL' "$LOG" || true) failed; shots: $(ls "$OUT/shots" | wc -l | xargs)"
ls -la "$OUT" "$OUT/shots"
exit "$status"
