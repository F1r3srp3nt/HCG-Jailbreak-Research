#!/usr/bin/env bash
# HCG Halo × HCG Nexus — PREVIEW evidence in the iOS Simulator (macOS + Xcode).
#
#   NEXUS_DIR=/path/to/HCG-Nexus scripts/nexus-preview.sh [output-dir]
#
# Builds preview/HaloNexusPreview.m into a simulator app together with HCG
# Nexus's REAL panel code (Sources/Core, Sources/Panel, Sources/Platform/Preview)
# and HCG Halo's real link / definition reader / panel border / renderer, copies
# Nexus's REAL Prefs/Resources/HaloBorder.plist into the app bundle (where
# Nexus's +borderDefinitionPath looks in preview builds), then runs the app's
# fixed script while recording video. Each "HALO-PREVIEW-STATE" line marks a
# state; stills are taken from the VIDEO afterwards (decode it sequentially, and
# match each frame by the caption the app draws). simctl screenshots taken live
# are slow on CI runners: they lag behind the script and show the wrong state,
# so none are taken. Exit status: non-zero if any HALO-PREVIEW-CHECK
# failed or the script did not finish.
#
# PREVIEW ONLY: no SpringBoard, no overlay window, no device. Never installs
# anything on a phone.

set -euo pipefail
cd "$(dirname "$0")/.."

limit() { local secs=$1; shift; perl -e 'alarm shift; exec @ARGV or die "exec: $!"' "$secs" "$@"; }
stamp() { echo "==> [$(date -u +%H:%M:%S)] $*"; }

[ "$(uname -s)" = Darwin ] || { echo "ERROR: needs macOS with Xcode" >&2; exit 1; }
: "${NEXUS_DIR:?set NEXUS_DIR to an HCG Nexus checkout}"
[ -f "$NEXUS_DIR/Sources/Panel/HCGNexusBorderInterface.m" ] || { echo "ERROR: $NEXUS_DIR has no border interface (needs HCG Nexus 0.2.2~beta1+)" >&2; exit 1; }
[ -f "$NEXUS_DIR/Prefs/Resources/HaloBorder.plist" ] || { echo "ERROR: $NEXUS_DIR has no Prefs/Resources/HaloBorder.plist" >&2; exit 1; }

OUT=${1:-build-preview}
APP="$OUT/HaloNexusPreview.app"
rm -rf "$OUT"; mkdir -p "$APP"
VERSION=$(sed -n 's/^Version: *//p' control | tr '~' '-')
ARCH=$(uname -m); [ "$ARCH" = x86_64 ] || ARCH=arm64
NEXUS_VERSION=$(sed -n 's/^Version: *//p' "$NEXUS_DIR/control")

stamp "HCG Halo $VERSION ($(git rev-parse --short=12 HEAD)) + HCG Nexus $NEXUS_VERSION ($(git -C "$NEXUS_DIR" rev-parse --short=12 HEAD))"
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
COMMON=(-isysroot "$SDK" -arch "$ARCH" -mios-simulator-version-min=15.0 -fobjc-arc -fobjc-arc-exceptions -g)
OBJ="$OUT/obj"; mkdir -p "$OBJ"
# HCG Nexus: its own flags (preview harness Makefile), its own sources, unchanged.
NEXUS_INC=(-I"$NEXUS_DIR/Sources/Core" -I"$NEXUS_DIR/Sources/Panel" -I"$NEXUS_DIR/Sources/Platform/Preview")
for f in "$NEXUS_DIR"/Sources/Core/*.m "$NEXUS_DIR"/Sources/Panel/*.m "$NEXUS_DIR"/Sources/Platform/Preview/*.m; do
	xcrun --sdk iphonesimulator clang "${COMMON[@]}" -Wall "${NEXUS_INC[@]}" -DHCG_PACKAGE_SCHEME='"preview-halo"' \
		-c "$f" -o "$OBJ/nexus-$(basename "$f" .m).o"
done
# HCG Halo: the tweak's flags.
for f in src/HaloNexusLink.m src/HaloNexusDefinition.m src/HaloPanelBorderView.m src/HaloRenderer.m src/HaloPreferences.m \
         src/HaloLog.m src/HaloGeometry.c src/HaloConfig.c src/HaloProfiles.c src/HaloProfiles.generated.c preview/HaloNexusPreview.m; do
	xcrun --sdk iphonesimulator clang "${COMMON[@]}" -Wall -Wextra -Wno-unused-parameter -Werror -Isrc "${NEXUS_INC[@]}" \
		-DHALO_VERSION="\"$VERSION\"" -DHALO_BUILD_ID="\"preview\"" -c "$f" -o "$OBJ/halo-$(basename "$f").o"
done
xcrun --sdk iphonesimulator clang "${COMMON[@]}" "$OBJ"/*.o -framework UIKit -framework QuartzCore -framework CoreGraphics -framework Network \
	-o "$APP/HaloNexusPreview"
cp preview/Info.plist "$APP/Info.plist"
cp "$NEXUS_DIR/Prefs/Resources/HaloBorder.plist" "$APP/HaloBorder.plist"   # Nexus's real definition
codesign -s - --force "$APP" >/dev/null 2>&1 || true
shasum -a 256 "$NEXUS_DIR/Prefs/Resources/HaloBorder.plist" "$APP/HaloNexusPreview" | tee "$OUT/inputs.sha256"

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
[ -n "$UDID" ] || UDID=$(xcrun simctl list devices available | grep -m1 -Eo 'iPhone[^(]*\(([0-9A-F-]{36})\)' | grep -Eo '[0-9A-F-]{36}')
[ -n "$UDID" ] || { echo "ERROR: no iPhone simulator" >&2; exit 1; }
xcrun simctl list devices | grep "$UDID" | tee "$OUT/simulator.txt"
stamp "booting $UDID"
xcrun simctl boot "$UDID" 2>/dev/null || true
limit 600 xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl ui "$UDID" appearance dark 2>/dev/null || true
xcrun simctl status_bar "$UDID" override --time 9:41 2>/dev/null || true
xcrun simctl install "$UDID" "$APP"

stamp "recording"
xcrun simctl io "$UDID" recordVideo --codec h264 --force "$OUT/halo-nexus-preview.mp4" > "$OUT/record.log" 2>&1 &
REC=$!
sleep 3
LOG="$OUT/console.log"
: > "$LOG"
status=0
limit 180 xcrun simctl launch --console-pty --terminate-running-process "$UDID" com.hakmicapitalgroup.halo.nexus-preview 2>&1 |
while IFS= read -r line; do
	printf '%s\n' "$line" | tee -a "$LOG"
	case "$line" in
	*HALO-PREVIEW-DONE*) break;;
	esac
done || true
sleep 1
kill -INT "$REC" 2>/dev/null || true
wait "$REC" 2>/dev/null || true
xcrun simctl terminate "$UDID" com.hakmicapitalgroup.halo.nexus-preview 2>/dev/null || true
xcrun simctl shutdown "$UDID" 2>/dev/null || true

grep -q 'HALO-PREVIEW-DONE failures=0' "$LOG" || status=1
grep -q 'HALO-PREVIEW-CHECK FAIL' "$LOG" && status=1
stamp "checks: $(grep -c 'HALO-PREVIEW-CHECK PASS' "$LOG" || true) passed, $(grep -c 'HALO-PREVIEW-CHECK FAIL' "$LOG" || true) failed"
ls -la "$OUT"
exit "$status"
