#!/usr/bin/env bash
# HCG Halo — local macOS build (adapted from HCG Vortex) with a complete, timestamped log.
#
#   cd HCGHalo && scripts/macos-build.sh
#
# Uses the same path as CI: Xcode's clang, the patched iPhoneOS16.5.sdk
# (scripts/install-sdk.sh), Theos, ldid,
# dpkg, GNU make; then scripts/build.sh, which builds, packages and runs
# scripts/validate.sh --require-new-abi (the arm64e slices must carry the
# native iOS 14+ pointer-auth ABI from Xcode).
#
# Writes:  build-logs/macos-build-<UTC timestamp>.log  (environment + full build)
#          packages/com.hakmicapitalgroup.halo_<version>_iphoneos-arm64.deb
# Exit status is the build's. Never installs to a device, never publishes.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

if [ "$(uname -s)" != Darwin ]; then
	echo "ERROR: this script is for macOS; on Linux use scripts/build.sh with ALLEMANDE=" >&2
	exit 1
fi

export THEOS="${THEOS:-$HOME/theos}"
# Theos needs GNU make >= 4; macOS ships 3.81. Prefer Homebrew's gnubin.
if command -v brew >/dev/null 2>&1; then
	GNUBIN="$(brew --prefix make 2>/dev/null)/libexec/gnubin"
	[ -d "$GNUBIN" ] && export PATH="$GNUBIN:$PATH"
fi

mkdir -p build-logs
LOG="$(pwd)/build-logs/macos-build-$(date -u +%Y%m%dT%H%M%SZ).log"

# ---- preflight: fail early with a clear reason --------------------------------
problems=()
devdir="$(xcode-select -p 2>/dev/null || true)"
case "$devdir" in
	*/CommandLineTools|"") problems+=("Full Xcode is required (xcode-select -p is '$devdir'). Run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer") ;;
esac
xcrun --sdk iphoneos --show-sdk-path >/dev/null 2>&1 || problems+=("No iPhoneOS SDK from xcrun. Open Xcode once, accept the license (sudo xcodebuild -license accept) and install the iOS platform.")
[ -d "$THEOS/makefiles" ] || problems+=("Theos not found at \$THEOS=$THEOS. Run: git clone --recursive https://github.com/theos/theos.git \"$THEOS\"")
[ -d "$THEOS/sdks/iPhoneOS16.5.sdk/System/Library/PrivateFrameworks/Preferences.framework" ] || problems+=("Patched iPhoneOS16.5.sdk missing from \$THEOS/sdks. Run: THEOS=\"$THEOS\" scripts/install-sdk.sh")
for tool in ldid dpkg-deb dpkg xz python3; do
	command -v "$tool" >/dev/null 2>&1 || problems+=("Missing '$tool'. Run: brew install ldid dpkg xz make")
done
make --version 2>/dev/null | head -1 | grep -q 'GNU Make [4-9]' || problems+=("GNU make >= 4 not on PATH. Run: brew install make")

{
	echo "== HCG Halo macOS build — $(date -u +%Y-%m-%dT%H:%M:%SZ)"
	echo "== environment"
	sw_vers
	echo "arch: $(uname -m)"
	echo "xcode-select: $devdir"
	xcodebuild -version 2>&1
	echo "Xcode iphoneos SDK: $(xcrun --sdk iphoneos --show-sdk-version 2>&1) (not used for linking)"
	echo "build SDK: $THEOS/sdks/iPhoneOS16.5.sdk ($( [ -d "$THEOS/sdks/iPhoneOS16.5.sdk" ] && echo present || echo MISSING))"
	xcrun clang --version 2>&1 | head -1
	make --version 2>&1 | head -1
	echo "ldid: $(command -v ldid || echo missing)"
	dpkg-deb --version 2>&1 | head -1
	python3 --version 2>&1
	echo "THEOS=$THEOS"
	git -C "$THEOS" log -1 --format='Theos %H %cd' 2>&1
	git log -1 --format='HCG Halo %H %cd (%s)' 2>&1
	echo "working tree changes:"; git status --short 2>&1
} >"$LOG" 2>&1

if [ "${#problems[@]}" -gt 0 ]; then
	{ echo "== preflight FAILED"; printf ' - %s\n' "${problems[@]}"; } | tee -a "$LOG" >&2
	echo "Log: $LOG" >&2
	exit 1
fi

echo "== build (full log: $LOG)"
echo "== build" >>"$LOG"
MAKE="make" scripts/build.sh messages=yes 2>&1 | tee -a "$LOG"
status=${PIPESTATUS[0]}

DEB="$(ls -t packages/*.deb 2>/dev/null | head -1 || true)"
{
	echo "== result"
	echo "exit status: $status"
	if [ "$status" -eq 0 ] && [ -n "$DEB" ]; then
		echo "package: $(pwd)/$DEB"
		shasum -a 256 "$DEB"
	else
		echo "build or validation FAILED — see the log above"
	fi
	echo "log: $LOG"
} 2>&1 | tee -a "$LOG"
exit "$status"
