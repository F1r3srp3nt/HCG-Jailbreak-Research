#!/usr/bin/env bash
# HCG Vortex — reproducible rootless build.
#
#   THEOS=~/theos scripts/build.sh [extra make arguments, e.g. messages=yes]
#
# macOS + Xcode (canonical, native iOS 14+ arm64e ABI):
#     builds, packages, validates with --require-new-abi
# Linux / other (test builds only):
#     requires allemande (https://github.com/p0358/allemande) to convert the
#     arm64e slices; set ALLEMANDE=/path/to/allemande if it isn't on PATH.
#
# Never installs to a device and never publishes anything.

set -euo pipefail
cd "$(dirname "$0")/.."

: "${THEOS:?THEOS is not set — install Theos (https://theos.dev/docs/installation) and export THEOS}"
[ -d "$THEOS/makefiles" ] || { echo "ERROR: \$THEOS ($THEOS) is not a Theos checkout" >&2; exit 1; }
ls -d "$THEOS"/sdks/iPhoneOS*.sdk >/dev/null 2>&1 || [ "$(uname -s)" = Darwin ] || {
	echo "ERROR: no iPhoneOS SDK in $THEOS/sdks (see docs/BUILD.md)" >&2; exit 1; }

ARGS=(package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless)
VALIDATE_ARGS=()

if [ "$(uname -s)" = Darwin ]; then
	echo "==> macOS: native Xcode toolchain ($(xcrun clang --version | head -1))"
	VALIDATE_ARGS+=(--require-new-abi)
else
	ALLEMANDE="${ALLEMANDE:-$(command -v allemande || true)}"
	if [ -z "$ALLEMANDE" ] || [ ! -x "$ALLEMANDE" ]; then
		cat >&2 <<'EOF'
ERROR: non-macOS toolchains emit the legacy arm64e ABI, which A12+ devices
(including the A13 test device) reject for SpringBoard on iOS 15+.
Build allemande (g++ -std=c++20 -o allemande main.cpp) and set ALLEMANDE=,
or build on macOS / via the GitHub Actions workflow instead.
EOF
		exit 1
	fi
	echo "==> $(uname -s): open-source toolchain + allemande arm64e conversion ($ALLEMANDE)"
	ARGS+=(VORTEX_ABI_CONVERT=1 "ALLEMANDE=$ALLEMANDE")
fi

MAKE="${MAKE:-make}"
"$MAKE" clean >/dev/null
rm -rf packages
"$MAKE" "${ARGS[@]}" "$@"

DEB=$(ls -t packages/*.deb | head -1)
echo "==> built $DEB"
scripts/validate.sh "$DEB" ${VALIDATE_ARGS[@]+"${VALIDATE_ARGS[@]}"}
