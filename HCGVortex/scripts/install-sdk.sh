#!/usr/bin/env bash
# Installs the patched iPhoneOS16.5.sdk from theos/sdks into $THEOS/sdks.
#
#   THEOS=~/theos scripts/install-sdk.sh
#
# Why: the Settings bundle links the private Preferences.framework. Xcode's
# public iPhoneOS SDK has no stubs for private frameworks
# ("ld: framework 'Preferences' not found"); theos/sdks' patched SDKs do.
# Both Makefiles pin TARGET to this SDK, so Linux and macOS build against the
# same headers and stubs. On macOS the compiler is still Xcode's clang.
#
# Pinned to a theos/sdks commit for reproducibility.

set -euo pipefail

: "${THEOS:?THEOS is not set}"
SDK=iPhoneOS16.5.sdk
REPO=https://github.com/theos/sdks.git
COMMIT=0222fd5413cf4b9af096f37b4621afa2688572f7

DEST="$THEOS/sdks/$SDK"
if [ -d "$DEST/System/Library/PrivateFrameworks/Preferences.framework" ]; then
	echo "==> $SDK already installed at $DEST"
	exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
echo "==> fetching $SDK from theos/sdks @ ${COMMIT:0:12}"
git -C "$tmp" init -q
git -C "$tmp" remote add origin "$REPO"
git -C "$tmp" config core.sparseCheckout true
echo "/$SDK/" > "$tmp/.git/info/sparse-checkout"
git -C "$tmp" fetch -q --depth 1 --filter=blob:none origin "$COMMIT"
git -C "$tmp" checkout -q FETCH_HEAD

[ -d "$tmp/$SDK/System/Library/PrivateFrameworks/Preferences.framework" ] || {
	echo "ERROR: fetched SDK lacks Preferences.framework" >&2
	exit 1
}
mkdir -p "$THEOS/sdks"
rm -rf "$DEST"
mv "$tmp/$SDK" "$DEST"
echo "==> installed $DEST"
