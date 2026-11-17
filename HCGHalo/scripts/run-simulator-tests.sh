#!/usr/bin/env bash
# HCG Halo — runtime tests in the iOS Simulator (macOS + Xcode only).
#
#   scripts/run-simulator-tests.sh
#
# Builds tests/test_runtime.m with the renderer, overlay view and preferences
# code for the iOS Simulator, boots an available iPhone simulator and runs it
# there with `simctl spawn`. This exercises Core Animation, UIKit hit-testing
# and CFPreferences for real, but NOT SpringBoard: it is no substitute for a
# device test.

set -euo pipefail
cd "$(dirname "$0")/.."

[ "$(uname -s)" = Darwin ] || { echo "ERROR: needs macOS with Xcode" >&2; exit 1; }

OUT=tests/build/sim
mkdir -p "$OUT"
VERSION=$(sed -n 's/^Version: *//p' control | tr '~' '-')
ARCH=$(uname -m)
[ "$ARCH" = x86_64 ] || ARCH=arm64

echo "==> building tests/test_runtime.m for the iOS Simulator ($ARCH, iOS 15.0 minimum)"
xcrun --sdk iphonesimulator clang -fobjc-arc -fobjc-arc-exceptions -arch "$ARCH" -mios-simulator-version-min=15.0 \
	-Wall -Wextra -Wno-unused-parameter -Werror \
	-DHALO_VERSION="\"$VERSION\"" -DHALO_BUILD_ID="\"simulator-test\"" -Isrc \
	tests/test_runtime.m src/HaloPreferences.m src/HaloRenderer.m src/HaloOverlayView.m \
	src/HaloGeometry.c src/HaloConfig.c src/HaloProfiles.c src/HaloProfiles.generated.c \
	-framework UIKit -framework QuartzCore -framework CoreGraphics -o "$OUT/test_runtime"

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

echo "==> booting $UDID"
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b

status=0
echo "==> running"
xcrun simctl spawn "$UDID" "$PWD/$OUT/test_runtime" || status=$?
xcrun simctl shutdown "$UDID" 2>/dev/null || true
exit "$status"
