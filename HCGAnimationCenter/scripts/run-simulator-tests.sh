#!/usr/bin/env bash
# HCG Animation Center — runtime tests in the iOS Simulator (macOS + Xcode only).
#
#   scripts/run-simulator-tests.sh
#
# Builds tests/test_runtime.m with the preset format, renderer, preferences,
# importer, library and AI interface for the iOS Simulator, boots an iPhone
# simulator and runs it there with `simctl spawn`. This exercises AVFoundation,
# ImageIO, Core Animation and CFPreferences for real, but NOT SpringBoard: it
# is no substitute for a device test. (Adapted from HCG Halo's script.)

set -euo pipefail
cd "$(dirname "$0")/.."

limit() { local secs=$1; shift; perl -e 'alarm shift; exec @ARGV or die "exec: $!"' "$secs" "$@"; }
stamp() { echo "==> [$(date -u +%H:%M:%S)] $*"; }

[ "$(uname -s)" = Darwin ] || { echo "ERROR: needs macOS with Xcode" >&2; exit 1; }

OUT=tests/build/sim
mkdir -p "$OUT"
VERSION=$(sed -n 's/^Version: *//p' control | tr '~' '-')
ARCH=$(uname -m)
[ "$ARCH" = x86_64 ] || ARCH=arm64
KIT=HCGBackgroundKit/Sources/HCGBackgroundKit

stamp "building tests/test_runtime.m for the iOS Simulator ($ARCH, iOS 15.0 minimum)"
xcrun --sdk iphonesimulator clang -fobjc-arc -fobjc-arc-exceptions -arch "$ARCH" -mios-simulator-version-min=15.0 \
	-Wall -Wextra -Wno-unused-parameter -Werror \
	-DHAC_VERSION="\"$VERSION\"" -DHAC_BUILD_ID="\"simulator-test\"" \
	-DHAC_EXAMPLE_PRESET="\"$PWD/HCGBackgroundKit/Examples/Aurora.hcgbackground\"" \
	-Isrc -I"$KIT/include" -Ipreferences -Ipreview \
	tests/test_runtime.m preview/HACTestMedia.m \
	src/HACPreferences.m src/HACPolicy.c src/HACProbe.m src/HACHosts.m \
	preferences/HACLibrary.m preferences/HACMediaImporter.m preferences/HACAIGeneration.m \
	"$KIT/HCGBackgroundView.m" "$KIT/HCGBackgroundPreset.m" "$KIT/HCGBackgroundCore.c" \
	-framework UIKit -framework QuartzCore -framework CoreGraphics -framework AVFoundation -framework CoreMedia \
	-framework CoreVideo -framework ImageIO -o "$OUT/test_runtime"

UDID=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
best = None
for runtime, items in devices.items():
    if "iOS" not in runtime:
        continue
    for d in items:
        if d.get("isAvailable") and d["name"].startswith("iPhone"):
            key = (runtime, d["name"])
            if best is None or key > best[0]:
                best = (key, d["udid"])
print(best[1] if best else "")')
[ -n "$UDID" ] || { echo "ERROR: no available iPhone simulator" >&2; xcrun simctl list devices available; exit 1; }
xcrun simctl list devices | grep "$UDID" || true

stamp "booting $UDID (a first boot on CI can take several minutes)"
xcrun simctl boot "$UDID" 2>/dev/null || true
limit 600 xcrun simctl bootstatus "$UDID" -b || { stamp "simulator did not finish booting within 600 s"; exit 1; }

status=0
stamp "running the tests (limit 480 s)"
limit 480 xcrun simctl spawn "$UDID" "$PWD/$OUT/test_runtime" || status=$?
[ "$status" -eq 142 ] && stamp "test_runtime timed out (SIGALRM)"
stamp "finished with status $status"
xcrun simctl shutdown "$UDID" 2>/dev/null || true
exit "$status"
