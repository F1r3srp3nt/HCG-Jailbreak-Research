#!/usr/bin/env bash
# HCG Halo × HCG Nexus — PREVIEW of both Settings entry points (macOS + Xcode).
#
#   THEOS=~/theos NEXUS_DIR=/path/to/HCG-Nexus scripts/settings-preview.sh [output-dir]
#
# Compiles the REAL Settings bundles of both packages for the iOS Simulator from
# their own sources:
#   HCGHaloPrefs.bundle  (preferences/ + the shared src/ files, as preferences/Makefile)
#   HCGNexusPrefs.bundle (Prefs/ + Sources/Core + Sources/Panel + the SpringBoard store, as Prefs/Makefile,
#                         with its real Prefs/Resources, including HaloBorder.plist)
# Both link Preferences.framework lazily (-undefined dynamic_lookup); the harness
# (preview/HaloSettingsPreview.m) loads it from the simulator runtime, then installs
# the bundles side by side and drives both entry points:
#   Settings › HCG Nexus › Appearance › Halo border  and  Settings › HCG Halo › Nexus Panel Border.
# Records video; exit status non-zero if any HALO-SETTINGS-CHECK failed or the script
# did not finish. PREVIEW ONLY: no Settings app, no PreferenceLoader, no device.

set -euo pipefail
cd "$(dirname "$0")/.."

limit() { local secs=$1; shift; perl -e 'alarm shift; exec @ARGV or die "exec: $!"' "$secs" "$@"; }
stamp() { echo "==> [$(date -u +%H:%M:%S)] $*"; }

[ "$(uname -s)" = Darwin ] || { echo "ERROR: needs macOS with Xcode" >&2; exit 1; }
: "${THEOS:?set THEOS (for the Preferences framework headers)}"
: "${NEXUS_DIR:?set NEXUS_DIR to an HCG Nexus checkout}"
[ -d "$THEOS/vendor/include/Preferences" ] || { echo "ERROR: $THEOS/vendor/include/Preferences missing" >&2; exit 1; }

OUT=${1:-build-settings-preview}
APP="$OUT/HaloSettingsPreview.app"
rm -rf "$OUT"; mkdir -p "$APP/Stage" "$OUT/obj" "$OUT/inc"
OUT=$(cd "$OUT" && pwd); APP="$OUT/HaloSettingsPreview.app"   # absolute: simctl writes the app's stdout there
ln -s "$THEOS/vendor/include/Preferences" "$OUT/inc/Preferences"   # only these headers, nothing else from Theos
VERSION=$(sed -n 's/^Version: *//p' control | tr '~' '-')
ARCH=$(uname -m); [ "$ARCH" = x86_64 ] || ARCH=arm64
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
CC=(xcrun --sdk iphonesimulator clang -isysroot "$SDK" -arch "$ARCH" -mios-simulator-version-min=15.0 -fobjc-arc -fobjc-arc-exceptions -g)
BUNDLE_LD=(-bundle -undefined dynamic_lookup -framework UIKit -framework QuartzCore -framework CoreGraphics -framework CoreFoundation)

stamp "HCG Halo $VERSION ($(git rev-parse --short=12 HEAD)) + HCG Nexus $(sed -n 's/^Version: *//p' "$NEXUS_DIR/control") ($(git -C "$NEXUS_DIR" rev-parse --short=12 HEAD))"

# --- HCG Halo Settings bundle (same sources and flags as preferences/Makefile) ---
H="$APP/Stage/HCGHaloPrefs.bundle"; mkdir -p "$H" "$OUT/obj/halo"
for f in preferences/*.m src/HaloPreferences.m src/HaloRenderer.m src/HaloNexusDefinition.m src/HaloPanelBorderView.m \
         src/HaloGeometry.c src/HaloConfig.c src/HaloProfiles.c src/HaloProfiles.generated.c; do
	"${CC[@]}" -Wall -Wextra -Wno-unused-parameter -Isrc -I"$OUT/inc" \
		-DHALO_VERSION="\"$VERSION\"" -DHALO_BUILD_ID="\"settings-preview\"" -c "$f" -o "$OUT/obj/halo/$(basename "$f").o"
done
"${CC[@]}" "${BUNDLE_LD[@]}" "$OUT"/obj/halo/*.o -o "$H/HCGHaloPrefs"
cp -R preferences/Resources/. "$H/"

# --- HCG Nexus Settings bundle (same sources and flags as its Prefs/Makefile) ---
N="$APP/Stage/HCGNexusPrefs.bundle"; mkdir -p "$N" "$OUT/obj/nexus"
for f in "$NEXUS_DIR"/Prefs/HCGNexusRootListController.m "$NEXUS_DIR"/Sources/Core/*.m "$NEXUS_DIR"/Sources/Panel/*.m \
         "$NEXUS_DIR"/Sources/Platform/SpringBoard/HCGPreferencesKeyValueStore.m; do
	"${CC[@]}" -Wall -I"$NEXUS_DIR/Sources/Core" -I"$NEXUS_DIR/Sources/Panel" -I"$NEXUS_DIR/Sources/Platform/SpringBoard" \
		-I"$OUT/inc" -DHCG_PACKAGE_SCHEME='"rootless"' -DHCG_BUILD_ID='"settings-preview"' -DHCG_BUILD_CONFIG='"preview"' \
		-c "$f" -o "$OUT/obj/nexus/$(basename "$f").o"
done
"${CC[@]}" "${BUNDLE_LD[@]}" -framework Network "$OUT"/obj/nexus/*.o -o "$N/HCGNexusPrefs"
cp -R "$NEXUS_DIR/Prefs/Resources/." "$N/"          # includes Nexus's real HaloBorder.plist

# --- harness app ---
"${CC[@]}" -Wall -Wextra -Wno-unused-parameter -Werror preview/HaloSettingsPreview.m \
	-framework UIKit -framework CoreFoundation -o "$APP/HaloSettingsPreview"
python3 - "$APP/Info.plist" <<'PY'
import plistlib, sys
d = plistlib.load(open("preview/Info.plist", "rb"))
d.update(CFBundleExecutable="HaloSettingsPreview", CFBundleIdentifier="com.hakmicapitalgroup.halo.settings-preview",
         CFBundleName="HaloSettingsPreview", CFBundleDisplayName="Halo Settings Preview")
plistlib.dump(d, open(sys.argv[1], "wb"))
PY
for b in "$H" "$N" "$APP"; do codesign -s - --force "$b" >/dev/null 2>&1 || true; done
shasum -a 256 "$N/HaloBorder.plist" "$H/HCGHaloPrefs" "$N/HCGNexusPrefs" | tee "$OUT/inputs.sha256"

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
[ -n "$UDID" ] || { echo "ERROR: no iPhone simulator" >&2; exit 1; }
xcrun simctl list devices | grep "$UDID" | tee "$OUT/simulator.txt"
stamp "booting $UDID"
xcrun simctl boot "$UDID" 2>/dev/null || true
limit 600 xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl ui "$UDID" appearance dark 2>/dev/null || true
xcrun simctl status_bar "$UDID" override --time 9:41 2>/dev/null || true
codesign --verify --deep --strict "$APP" 2>&1 | tee "$OUT/codesign.txt" || echo "codesign verify reported problems (see above)"
xcrun simctl install "$UDID" "$APP"
stamp "installed; app container: $(xcrun simctl get_app_container "$UDID" com.hakmicapitalgroup.halo.settings-preview 2>&1)"

stamp "recording"
xcrun simctl io "$UDID" recordVideo --codec h264 --force "$OUT/halo-settings-preview.mp4" > "$OUT/record.log" 2>&1 &
REC=$!
sleep 4
LOG="$OUT/console.log"; : > "$LOG"; : > "$OUT/stderr.log"
# Launch detached with stdout/stderr redirected to files (more robust than a pty on CI), then poll.
# simctl keeps the launch call open while stdout is redirected: run it in the background.
xcrun simctl launch --terminate-running-process --stdout="$LOG" --stderr="$OUT/stderr.log" \
	"$UDID" com.hakmicapitalgroup.halo.settings-preview > "$OUT/launch.txt" 2>&1 &
LAUNCH=$!
sleep 5
stamp "launch: $(cat "$OUT/launch.txt")"
for _ in $(seq 1 90); do
	grep -q 'HALO-SETTINGS-DONE' "$LOG" 2>/dev/null && break
	sleep 2
done
cat "$LOG"
echo "--- stderr (last 60 lines)"; tail -60 "$OUT/stderr.log" || true
sleep 2
kill -INT "$REC" 2>/dev/null || true
wait "$REC" 2>/dev/null || true
xcrun simctl spawn "$UDID" log show --last 10m --style compact \
	--predicate 'process == "HaloSettingsPreview" OR eventMessage CONTAINS "settings-preview"' > "$OUT/system.log" 2>&1 || true
echo "--- system log (last 80 lines)"; tail -80 "$OUT/system.log" || true
for f in ~/Library/Logs/DiagnosticReports/HaloSettingsPreview*; do [ -f "$f" ] && { echo "--- crash report $f"; head -120 "$f"; cp "$f" "$OUT/"; }; done
xcrun simctl terminate "$UDID" com.hakmicapitalgroup.halo.settings-preview 2>/dev/null || true
kill "$LAUNCH" 2>/dev/null || true
xcrun simctl shutdown "$UDID" 2>/dev/null || true

status=0
grep -q 'HALO-SETTINGS-DONE failures=0' "$LOG" || status=1
grep -q 'HALO-SETTINGS-CHECK FAIL' "$LOG" && status=1
stamp "checks: $(grep -c 'HALO-SETTINGS-CHECK PASS' "$LOG" || true) passed, $(grep -c 'HALO-SETTINGS-CHECK FAIL' "$LOG" || true) failed"
ls -la "$OUT"
exit "$status"
