#!/usr/bin/env bash
# HCG Portal — package & source validation (adapted from HCG Animation Center's,
# HCG Halo's and HCG Vortex's validate.sh).
#
#   scripts/validate.sh [path/to/package.deb] [--require-new-abi]
#
# Checks (each prints PASS/FAIL/WARN):
#   1. Host unit tests (layout, menu, render plan, visibility, pending action;
#      ASan/UBSan), Root.plist up to date, packaging-format regression tests
#   2. Settings layout, preference keys, identifiers and choices agree with the code
#   3. Package metadata (id, name, version, rootless architecture, dependencies)
#  3a. Archive format: gzip members only, each fully decompressed (CRC and
#      length checked), plus dpkg-deb --fsys-tarfile with its exit status
#   4. Payload under /var/jb, required files, permissions, maintainer scripts
#  4a. Version and build ID compiled into both binaries (rebuilt, not renamed);
#      a clean source commit (enforced with --require-new-abi)
#   5. Mach-O: fat arm64 + arm64e, code signature in every slice, arm64e ABI
#      (native new ABI enforced with --require-new-abi)
#   6. Injection filter targets SpringBoard only; expected interfaces compiled in;
#      NO passcode / unlock-bypass, notification-content or other product's
#      preference-domain reference
#   7. No network, process-spawning, privilege, keychain or URL references
#   8. dpkg install + remove simulation in a scratch root leaves nothing behind
#   9. Size and checksums
#
# Requires: bash, python3, dpkg-deb, dpkg, cc. No device needed: this validates
# the BUILD, not runtime behaviour in SpringBoard.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
ROOT=$(pwd)
PKG_ID=com.hakmicapitalgroup.portal

DEB=""
REQUIRE_NEW_ABI=0
for arg in "$@"; do
	case "$arg" in
		--require-new-abi) REQUIRE_NEW_ABI=1 ;;
		*.deb) DEB="$arg" ;;
		*) echo "unknown argument: $arg" >&2; exit 2 ;;
	esac
done
if [ -z "$DEB" ]; then
	DEB=$(ls -t packages/*.deb 2>/dev/null | head -1 || true)
fi

FAILS=0
WARNS=0
pass() { printf '  \033[32mPASS\033[0m %s\n' "$*"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$*"; FAILS=$((FAILS + 1)); }
warn() { printf '  \033[33mWARN\033[0m %s\n' "$*"; WARNS=$((WARNS + 1)); }
section() { printf '\n\033[1m%s\033[0m\n' "$*"; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# ---------------------------------------------------------------------------
section "1. Host tests"
if command -v cc >/dev/null 2>&1; then
	if out=$(make -s -C tests BUILD="$WORK/tests" test 2>&1); then
		pass "$(echo "$out" | tail -1)"
	else
		echo "$out" | tail -20
		fail "core unit tests failed"
	fi
else
	warn "no host C compiler; unit tests skipped"
fi
if python3 -I scripts/generate_root_plist.py --check >"$WORK/gen.txt" 2>&1; then
	pass "Root.plist up to date with scripts/generate_root_plist.py"
else
	cat "$WORK/gen.txt"; fail "Root.plist is stale"
fi
if out=$(python3 -I tests/test_deb_format.py 2>&1); then
	pass "packaging format tests: $(echo "$out" | tail -1)"
else
	echo "$out" | tail -10; fail "packaging format tests failed"
fi

# ---------------------------------------------------------------------------
section "2. Source consistency"
python3 -I - "$ROOT" <<'PY2' && pass "Root.plist keys, defaults, choices and selectors match PortalPreferences / PortalCore / the controller" || fail "Settings layout and code disagree"
import os, plistlib, re, sys
root = sys.argv[1]
src = lambda p: open(os.path.join(root, p)).read()
prefs, core, controller = src("src/PortalPreferences.m"), src("src/PortalCore.c"), src("preferences/PortalRootListController.m")
plist = plistlib.load(open(os.path.join(root, "preferences/Resources/Root.plist"), "rb"))
ok = True
def bad(msg):
    global ok
    print("    " + msg); ok = False
keys = dict(re.findall(r'NSString \*const (PortalKey\w+) = @"([^"]+)"', prefs))
def ids(name):
    return re.findall(r'"([a-z]+)"', re.search(r"static const char \*const %s\[[^\]]*\] = \{([^}]*)\}" % name, core).group(1))
expect = {"palette": ids("kPaletteIds"), "lowPower": ids("kLowPowerIds")}
defaults = {"enabled": False, "unlockAnimation": True, "diagnosticLogging": False, "palette": "signature",
            "lowPower": "static", "brightness": 0.85, "speed": 1.0, "intensity": 0.6}
ranges = {"brightness": (0.2, 1.0), "speed": (0.25, 2.0), "intensity": (0.0, 1.0)}
header = src("src/PortalCore.h")
num = lambda n: float(re.search(r"#define %s \(?(-?[0-9.]+)\)?" % n, header).group(1))
code_defaults = {"brightness": num("PORTAL_BRIGHTNESS_DEFAULT"), "speed": num("PORTAL_SPEED_DEFAULT"), "intensity": num("PORTAL_INTENSITY_DEFAULT")}
code_ranges = {"brightness": (num("PORTAL_BRIGHTNESS_MIN"), 1.0), "speed": (num("PORTAL_SPEED_MIN"), num("PORTAL_SPEED_MAX")), "intensity": (0.0, 1.0)}
seen = set()
for item in plist["items"]:
    key = item.get("key")
    for sel in (item.get("action"), item.get("get")):
        if sel and not re.search(r"- \(\w+(?: \*)?\)%s\(PSSpecifier \*\)" % re.escape(sel), controller):
            bad(f"Root.plist names {sel} but PortalRootListController.m does not implement it")
    if not key:
        continue
    seen.add(key)
    if key not in keys.values():
        bad(f"unknown key in Root.plist: {key}")
    if item.get("defaults") != "com.hakmicapitalgroup.portal":
        bad(f"{key}: defaults domain {item.get('defaults')}")
    if item.get("PostNotification") != "com.hakmicapitalgroup.portal/preferences-changed":
        bad(f"{key}: notification {item.get('PostNotification')}")
    if key in expect and item.get("validValues") != expect[key]:
        bad(f"{key}: plist {item.get('validValues')} != code {expect[key]}")
    if key in defaults and item.get("default") != defaults[key]:
        bad(f"{key}: plist default {item.get('default')!r} != {defaults[key]!r}")
    if key in code_defaults and abs(item.get("default") - code_defaults[key]) > 1e-9:
        bad(f"{key}: plist default {item.get('default')} != PortalCore.h {code_defaults[key]}")
    if key in ranges and ((item.get("min"), item.get("max")) != ranges[key] or ranges[key] != code_ranges[key]):
        bad(f"{key}: range plist {(item.get('min'), item.get('max'))} code {code_ranges[key]}")
for required in defaults:
    if required not in seen:
        bad(f"Settings lacks {required}")
for key, fallback in (("PortalKeyEnabled", "NO"), ("PortalKeyUnlockAnimation", "YES"), ("PortalKeyDiagnosticLogging", "NO")):
    if not re.search(r"Bool\(d, %s, %s\)" % (key, fallback), prefs):
        bad(f"{key} must default to {fallback} in PortalPreferences.m")
if "PORTAL_PREVIEW_HOST" in src("Makefile") + src("preferences/Makefile"):
    bad("preview-only defines must never reach the package")
sys.exit(0 if ok else 1)
PY2
python3 -I - "$ROOT" <<'PY2' && pass "Info.plist versions and PreferenceLoader entry agree with control and the code" || fail "bundle metadata mismatch"
import os, plistlib, re, sys
root = sys.argv[1]
version = re.search(r"^Version: *(\S+)", open(os.path.join(root, "control")).read(), re.M).group(1).replace("~", "-")
info = plistlib.load(open(os.path.join(root, "preferences/Resources/Info.plist"), "rb"))
entry = plistlib.load(open(os.path.join(root, "layout/Library/PreferenceLoader/Preferences/HCGPortalPrefs.plist"), "rb"))["entry"]
assert info["CFBundleVersion"] == version, (info["CFBundleVersion"], version)
assert info["CFBundleShortVersionString"] == version.split("-")[0]
assert info["CFBundleExecutable"] == entry["bundle"] == "HCGPortalPrefs"
assert info["NSPrincipalClass"] == entry["detail"] == "PortalRootListController"
PY2

# ---------------------------------------------------------------------------
if [ -z "$DEB" ] || [ ! -f "$DEB" ]; then
	section "3-9. Package checks"
	fail "no .deb found (build first: scripts/build.sh)"
	printf '\nResult: %d failure(s), %d warning(s)\n' "$FAILS" "$WARNS"
	exit 1
fi
section "3. Package metadata — $(basename "$DEB")"
field() { dpkg-deb -f "$DEB" "$1" 2>/dev/null; }
src_field() { sed -n "s/^$1: *//p" "$ROOT/control"; }
for f in Package Name Version Architecture Depends Section; do
	if [ "$(field "$f")" = "$(src_field "$f")" ]; then
		pass "$f: $(field "$f") (matches source control)"
	else
		fail "$f is '$(field "$f")', source control says '$(src_field "$f")'"
	fi
done
[ "$(field Package)" = "$PKG_ID" ] && pass "package id $PKG_ID" || fail "package id"
[ "$(field Architecture)" = "iphoneos-arm64" ] && pass "rootless architecture iphoneos-arm64" || fail "Architecture is '$(field Architecture)'"
[ "$(basename "$DEB")" = "$(field Package)_$(field Version)_$(field Architecture).deb" ] && pass "canonical file name" || fail "file name $(basename "$DEB")"
deps=$(field Depends)
for d in "mobilesubstrate (>= 0.9.5000)" preferenceloader "firmware (>= 15.0)"; do
	echo "$deps" | grep -qF "$d" && pass "Depends includes $d" || fail "Depends lacks $d ($deps)"
done
PORTAL_DISPLAY_VERSION=$(src_field Version | tr '~' '-')

# ---------------------------------------------------------------------------
section "3a. Archive format (gzip members, full decompression)"
FAILS_BEFORE_FMT=$FAILS
FMT_OUT=$(python3 -I "$ROOT/scripts/check_deb_format.py" "$DEB" 2>&1)
FMT_RC=$?
DATA_RAW=""
while IFS= read -r line; do
	case "$line" in
		"PASS "*) pass "${line#PASS }" ;;
		"FAIL "*) fail "${line#FAIL }" ;;
		"INFO data_uncompressed_bytes="*) DATA_RAW=${line#INFO data_uncompressed_bytes=} ;;
		*) echo "  $line" ;;
	esac
done <<< "$FMT_OUT"
[ "$FMT_RC" -eq 0 ] || [ "$FAILS" -gt "$FAILS_BEFORE_FMT" ] || fail "check_deb_format.py exited $FMT_RC without reporting a failure"
if [ -n "$DATA_RAW" ]; then
	dpkg-deb --fsys-tarfile "$DEB" > "$WORK/data.tar" 2>"$WORK/fsys.err"
	FSYS_RC=$?
	FSYS_BYTES=$(wc -c < "$WORK/data.tar" | tr -d ' ')
	if [ "$FSYS_RC" -eq 0 ] && [ "$FSYS_BYTES" = "$DATA_RAW" ]; then
		pass "dpkg-deb --fsys-tarfile exit 0, $FSYS_BYTES bytes (same as the gzip check)"
	else
		cat "$WORK/fsys.err"
		fail "dpkg-deb --fsys-tarfile exit $FSYS_RC, $FSYS_BYTES bytes (gzip check: $DATA_RAW)"
	fi
fi

# ---------------------------------------------------------------------------
section "4. Payload layout and permissions"
dpkg-deb -x "$DEB" "$WORK/pkg"
dpkg-deb -e "$DEB" "$WORK/ctl"
outside=$(cd "$WORK/pkg" && find . -mindepth 1 \( -type f -o -type l \) ! -path './var/jb/*')
[ -z "$outside" ] && pass "all files are under /var/jb" || fail "files outside /var/jb: $outside"
JB="$WORK/pkg/var/jb"
EXPECTED_FILES="Library/MobileSubstrate/DynamicLibraries/HCGPortal.dylib
Library/MobileSubstrate/DynamicLibraries/HCGPortal.plist
Library/PreferenceBundles/HCGPortalPrefs.bundle/HCGPortalPrefs
Library/PreferenceBundles/HCGPortalPrefs.bundle/Info.plist
Library/PreferenceBundles/HCGPortalPrefs.bundle/Root.plist
Library/PreferenceBundles/HCGPortalPrefs.bundle/icon.png
Library/PreferenceBundles/HCGPortalPrefs.bundle/icon@2x.png
Library/PreferenceBundles/HCGPortalPrefs.bundle/icon@3x.png
Library/PreferenceLoader/Preferences/HCGPortalPrefs.plist"
for f in $EXPECTED_FILES; do
	[ -s "$JB/$f" ] && pass "/var/jb/$f" || fail "missing /var/jb/$f"
done
extra=$(cd "$JB" && find . -type f | sed 's|^\./||' | sort | comm -23 - <(echo "$EXPECTED_FILES" | sort))
[ -z "$extra" ] && pass "no unexpected files" || fail "unexpected files: $extra"
python3 -I -c 'import plistlib, sys; sys.exit(0 if plistlib.load(open(sys.argv[1], "rb")) == plistlib.load(open(sys.argv[2], "rb")) else 1)' \
	"$JB/Library/PreferenceBundles/HCGPortalPrefs.bundle/Root.plist" "$ROOT/preferences/Resources/Root.plist" \
	&& pass "packaged Root.plist has the generated content" || fail "packaged Root.plist differs from preferences/Resources/Root.plist"
dpkg-deb -c "$DEB" > "$WORK/contents.txt"
python3 -I - "$WORK/contents.txt" <<'PY' && pass "modes: directories 0755, Mach-O binaries 0755 or 0644, other files 0644; no setuid/setgid/world-writable" || fail "unexpected permissions"
import sys
BINARIES = {"var/jb/Library/MobileSubstrate/DynamicLibraries/HCGPortal.dylib",
            "var/jb/Library/PreferenceBundles/HCGPortalPrefs.bundle/HCGPortalPrefs"}
ok = True
for line in open(sys.argv[1]):
    mode, owner, size, date, time, path = line.split(None, 5)
    path = path.strip().lstrip("./")
    if mode.startswith("d"):
        want = {"drwxr-xr-x"}
    elif path in BINARIES:
        want = {"-rwxr-xr-x", "-rw-r--r--"}
    else:
        want = {"-rw-r--r--"}
    if mode not in want:
        print(f"    {mode} {path} (expected {' or '.join(sorted(want))})"); ok = False
sys.exit(0 if ok else 1)
PY
if awk '{print $2}' "$WORK/contents.txt" | grep -Eqv '^(root/(root|wheel)|0/(0|root|wheel))$'; then
	warn "some entries are not owned by root: $(awk '{print $2}' "$WORK/contents.txt" | sort -u | tr '\n' ' ')"
else
	pass "owner: $(awk '{print $2}' "$WORK/contents.txt" | sort -u | tr '\n' ' ')"
fi
ls "$WORK/ctl" | sort > "$WORK/ctl.txt"
[ "$(tr '\n' ' ' < "$WORK/ctl.txt")" = "control postrm " ] && pass "control members: control, postrm" || fail "control members: $(tr '\n' ' ' < "$WORK/ctl.txt")"
if [ -f "$WORK/ctl/postrm" ]; then
	[ -x "$WORK/ctl/postrm" ] && head -1 "$WORK/ctl/postrm" | grep -q '^#!/bin/sh' && pass "postrm is an executable /bin/sh script" || fail "postrm not executable or no shebang"
	python3 -I - "$WORK/ctl/postrm" <<'PY' && pass "postrm deletes only HCG Portal's own preferences, status and kill switch, only on purge" || fail "postrm does more than expected"
import re, sys
s = open(sys.argv[1]).read().replace("\\\n", " ")
paths = " ".join(re.findall(r"rm -r?f ([^\n]*)", s)).split()
allowed = lambda p: p.startswith("/var/mobile/Library/Preferences/com.hakmicapitalgroup.portal.")
ok = 'if [ "$1" = "purge" ]' in s and paths and all(allowed(p) for p in paths)
# Nothing touches other packages or restarts anything.
ok = ok and "killall" not in s and "sbreload" not in s
sys.exit(0 if ok else 1)
PY
fi

# ---------------------------------------------------------------------------
section "4a. Version and build ID inside the binaries"
BUILD_IDS=$(python3 -I - "$JB" "$PORTAL_DISPLAY_VERSION" <<'PY'
import re, sys
jb, version = sys.argv[1], sys.argv[2]
ids = set()
for rel in ("Library/MobileSubstrate/DynamicLibraries/HCGPortal.dylib",
            "Library/PreferenceBundles/HCGPortalPrefs.bundle/HCGPortalPrefs"):
    data = open(f"{jb}/{rel}", "rb").read()
    if (b"HCGPORTAL-VERSION:" + version.encode() + b"\0") not in data:
        print(f"MISSING-VERSION {rel}"); continue
    found = set(m.decode() for m in re.findall(rb"HCGPORTAL-BUILD:([0-9A-Za-z.-]+)\0", data))
    if len(found) != 1:
        print(f"MISSING-BUILD {rel}"); continue
    ids |= found
print(" ".join(sorted(ids)))
PY
)
if echo "$BUILD_IDS" | grep -q MISSING-; then
	fail "version $PORTAL_DISPLAY_VERSION missing from: $BUILD_IDS (rebuild, do not rename)"
else
	pass "both binaries carry version $PORTAL_DISPLAY_VERSION"
	case "$BUILD_IDS" in
		*" "*|"") fail "binaries carry inconsistent build IDs: '$BUILD_IDS'" ;;
		*-dirty|unknown*)
			if [ "$REQUIRE_NEW_ABI" -eq 1 ]; then fail "build ID $BUILD_IDS: distributable builds need a clean source commit"
			else warn "build ID $BUILD_IDS (uncommitted changes): test build only"; fi ;;
		*) pass "build ID $BUILD_IDS (source commit) in both binaries" ;;
	esac
fi

# ---------------------------------------------------------------------------
section "5. Mach-O binaries"
python3 -I - "$JB" "$REQUIRE_NEW_ABI" <<'PY'
import struct, sys
jb, require_new = sys.argv[1], sys.argv[2] == "1"
FILES = ["Library/MobileSubstrate/DynamicLibraries/HCGPortal.dylib",
         "Library/PreferenceBundles/HCGPortalPrefs.bundle/HCGPortalPrefs"]
LC_SEGMENT_64, LC_CODE_SIGNATURE, LC_BUILD_VERSION = 0x19, 0x1D, 0x32
rc = 0
def out(kind, msg):
    global rc
    color = {"PASS": 32, "FAIL": 31, "WARN": 33}[kind]
    print(f"  \033[{color}m{kind}\033[0m {msg}")
    if kind == "FAIL": rc |= 1
    if kind == "WARN": rc |= 2
def slices(d):
    if struct.unpack(">I", d[:4])[0] == 0xCAFEBABE:
        n = struct.unpack(">I", d[4:8])[0]
        for i in range(n):
            ct, cs, off, size, _ = struct.unpack(">IIIII", d[8 + i * 20:28 + i * 20])
            yield d[off:off + size]
    else:
        yield d
for rel in FILES:
    d = open(f"{jb}/{rel}", "rb").read()
    name = rel.rsplit("/", 1)[-1]
    archs = {}
    for s in slices(d):
        magic, ct, cs, ft, ncmds, sizeofcmds = struct.unpack("<IIIIII", s[:24])
        if magic != 0xFEEDFACF or ct != 0x0100000C:
            out("FAIL", f"{name}: unexpected slice magic={magic:#x} cputype={ct:#x}"); continue
        arch = "arm64e" if (cs & 0xFF) == 2 else "arm64"
        off, text, signed, minos = 32, 0, False, None
        for _ in range(ncmds):
            cmd, size = struct.unpack("<II", s[off:off + 8])
            if cmd == LC_SEGMENT_64 and s[off + 8:off + 24].rstrip(b"\0") == b"__TEXT":
                text = struct.unpack("<Q", s[off + 48:off + 56])[0]
            if cmd == LC_CODE_SIGNATURE: signed = True
            if cmd & 0x7FFFFFFF in (0xC, 0x18, 0x1F, 0x20, 0x23):
                path_offset = struct.unpack_from("<I", s, off + 8)[0]
                dependency = s[off + path_offset:off + size].split(b"\0", 1)[0]
                if b"substrate" in dependency.lower():
                    out("FAIL", f"{name}: links {dependency.decode(errors='replace')}; resolve the hook API only on enable")
            if cmd == LC_BUILD_VERSION:
                platform, v = struct.unpack("<II", s[off + 8:off + 16])
                minos = (platform, f"{v >> 16}.{(v >> 8) & 0xFF}")
            off += size
        archs[arch] = (cs, text, signed, minos, s)
    for a in ("arm64", "arm64e"):
        if a not in archs:
            out("FAIL", f"{name}: missing {a} slice"); continue
        cs, text, signed, minos, s = archs[a]
        out("PASS" if text > 0 else "FAIL", f"{name} [{a}]: __TEXT {text} bytes of compiled code")
        out("PASS" if signed else "FAIL", f"{name} [{a}]: LC_CODE_SIGNATURE present")
        out("PASS" if minos == (2, "15.0") else "FAIL", f"{name} [{a}]: platform iOS, minimum OS {minos[1] if minos else '?'} (expected 15.0)")
    if "arm64e" in archs:
        cs, _, _, _, s = archs["arm64e"]
        versioned = bool(cs & 0x80000000)
        isa = sum(1 for i in range(0, len(s) - 7, 8)
                  if (lambda v: (v >> 63) & 1 and ((v >> 32) & 0xFFFF) == 0x6AE1)(struct.unpack_from("<Q", s, i)[0]))
        if versioned:
            out("PASS", f"{name} [arm64e]: versioned pointer-auth ABI (cpusubtype {cs:#x}) — native new-ABI toolchain")
        elif isa:
            msg = (f"{name} [arm64e]: legacy cpusubtype {cs:#x} with {isa} isa pointers re-signed (allemande-converted). "
                   "Test build only; distribute the macOS/Xcode build.")
            out("FAIL" if require_new else "WARN", msg)
        else:
            out("FAIL", f"{name} [arm64e]: legacy ABI and NOT converted — will not load on A12+ / iOS 15+")
sys.exit(1 if rc & 1 else (3 if rc & 2 else 0))
PY
case $? in 0) ;; 3) WARNS=$((WARNS + 1)) ;; *) FAILS=$((FAILS + 1)) ;; esac

# ---------------------------------------------------------------------------
section "6. SpringBoard injection, authentication and privacy safety"
FILTER="$JB/Library/MobileSubstrate/DynamicLibraries/HCGPortal.plist"
if python3 -I - "$FILTER" <<'PY'
import plistlib, re, sys
data = open(sys.argv[1], "rb").read()
if data.startswith(b"bplist") or data.lstrip().startswith(b"<?xml"):
    d = plistlib.loads(data)
    ok = (set(d) == {"Filter"} and set(d["Filter"]) == {"Bundles"} and d["Filter"]["Bundles"] == ["com.apple.springboard"])
else:
    text = data.decode("utf-8", "replace")
    ok = (re.findall(r"\b([A-Za-z]+)\s*=", text) == ["Filter", "Bundles"]
          and re.findall(r'"([^"]*)"', text) == ["com.apple.springboard"])
sys.exit(0 if ok else 1)
PY
then
	pass "filter injects into com.apple.springboard only"
else
	fail "unexpected filter: $(python3 -c 'import sys;print(repr(open(sys.argv[1],"rb").read()[:200]))' "$FILTER")"
fi
printable_runs() {
	python3 -I -c '
import re, sys
for path in sys.argv[1:]:
    for run in re.findall(rb"[\x20-\x7e]{4,}", open(path, "rb").read()):
        print(run.decode("ascii"))' "$@"
}
DYLIB="$JB/Library/MobileSubstrate/DynamicLibraries/HCGPortal.dylib"
PREFS="$JB/Library/PreferenceBundles/HCGPortalPrefs.bundle/HCGPortalPrefs"
printable_runs "$DYLIB" > "$WORK/dylib.strings"
printable_runs "$PREFS" > "$WORK/prefs.strings"
for s in CSCoverSheetViewController SBLockScreenManager SBCoverSheetPresentationManager \
         isUILocked isInSecureApp isProtectedDataAvailable 'setCoverSheetPresented:animated:withCompletion:' mainPageContentViewController \
         'viewWillAppear:' 'viewDidDisappear:' viewDidLayoutSubviews MSHookMessageEx _dlsym \
         LSApplicationWorkspace 'openApplicationWithBundleID:' com.apple.Preferences \
         com.apple.springboard.hasBlankedScreen com.apple.springboard.lockstate \
         com.hakmicapitalgroup.portal/preferences-changed com.hakmicapitalgroup.portal/status-request \
         com.hakmicapitalgroup.portal.lighting-event HCGNexusPortalInterface 'openPanelFromSource:completion:'; do
	grep -qxF -- "$s" "$WORK/dylib.strings" && pass "tweak references $s" || fail "tweak lacks $s"
done
# 0.1.0~beta4: Portal never requests, performs or handles authentication. It only READS the lock state
# iOS reports (isUILocked, Darwin lockstate, isProtectedDataAvailable) and stays closed unless all say unlocked.
REQUEST='unlockWithRequest|createUnlockRequest|SBLockScreenUnlockRequest|unlockUIFromSource'
hits=$(grep -E "$REQUEST" "$WORK/dylib.strings" "$WORK/prefs.strings" | sort -u || true)
[ -z "$hits" ] && pass "no authentication or unlock request is made (Portal only reads iOS's lock state)" || fail "unlock-request references: $hits"
BYPASS='attemptUnlockWithPasscode|_attemptUnlockWithPasscode|attemptUnlockWithMesa|unlockUIFromSource|_finishUIUnlockFromSource|setPasscode|MCPasscodeManager|MCProfileConnection|SBFUserAuthenticationController|_setAuthenticated|keybag|MKBUnlockDevice|LAContext|evaluatePolicy'
hits=$(grep -E "$BYPASS" "$WORK/dylib.strings" "$WORK/prefs.strings" | sort -u || true)
[ -z "$hits" ] && pass "no passcode, keybag or unlock-without-authentication API is referenced" || fail "authentication-bypass references: $hits"
# No notification content is read (obstacles are measured by frame only).
PRIVATE='NCNotificationRequest|BBBulletin|bulletinID|NCNotificationContent|UNNotificationContent|sectionIdentifier|NCNotificationDispatcher'
hits=$(grep -E "$PRIVATE" "$WORK/dylib.strings" "$WORK/prefs.strings" | sort -u || true)
[ -z "$hits" ] && pass "no notification-content API is referenced" || fail "notification-content references: $hits"
# No other product's preferences are read or written.
OTHERS='com\.hakmicapitalgroup\.(halo|hcgnexus|animationcenter|vortex)(\.|/|$)'
hits=$(grep -E "$OTHERS" "$WORK/dylib.strings" "$WORK/prefs.strings" | sort -u || true)
[ -z "$hits" ] && pass "no other HCG product's preference domain or notification is referenced" || fail "other products' domains: $hits"
for s in PortalRootListController PortalPlacementController PortalAppsController com.hakmicapitalgroup.portal/status-request; do
	grep -qxF -- "$s" "$WORK/prefs.strings" && pass "Settings bundle references $s" || fail "Settings bundle lacks $s"
done
grep -qE "CSCoverSheet|SBLockScreenManager" "$WORK/prefs.strings" && fail "Settings bundle references SpringBoard Lock Screen classes" || pass "Settings bundle references no SpringBoard Lock Screen classes"

# ---------------------------------------------------------------------------
section "7. Forbidden capabilities"
BAD='^_(socket|connect|getaddrinfo|posix_spawn|posix_spawnp|system|execve|execv|fork|vfork|setuid|seteuid|setgid|ptrace|nw_[a-z_]+)$|NSURLSession|NSURLConnection|NSURLRequest|CFNetwork|WKWebView|SecItem|LAContext|ASIdentifierManager|identifierForVendor|PHPhotoLibrary|requestAuthorization'
cat "$WORK/dylib.strings" "$WORK/prefs.strings" > "$WORK/all.strings"
if grep -qx '_objc_msgSend' "$WORK/all.strings" && grep -qx '_CFPreferencesCopyAppValue' "$WORK/all.strings"; then
	hits=$(grep -E "$BAD" "$WORK/all.strings" | sort -u || true)
	[ -z "$hits" ] && pass "no networking, process-spawning, privilege, keychain, tracking or Photos-library-access APIs referenced" || fail "suspicious symbols: $hits"
	urls=$(grep -Eo 'https?://[^ ]+' "$WORK/all.strings" | grep -v '^http://www.apple.com/DTDs/' | sort -u || true)
	[ -z "$urls" ] && pass "no URLs in either binary" || fail "URLs in binaries: $urls"
else
	fail "symbol scan cannot see known imports (_objc_msgSend, _CFPreferencesCopyAppValue); the check is not trustworthy"
fi

# ---------------------------------------------------------------------------
section "8. Install / remove simulation (scratch root, not a device)"
if command -v dpkg >/dev/null 2>&1; then
	R="$WORK/sim"
	mkdir -p "$R/root" "$R/admin/updates" "$R/admin/info"
	: > "$R/admin/status"
	DPKG=(dpkg --root="$R/root" --admindir="$R/admin" --force-not-root --force-depends --force-architecture --force-script-chrootless --log=/dev/null)
	if "${DPKG[@]}" -i "$DEB" >"$WORK/dpkg.log" 2>&1; then
		n=$(cd "$R/root" && find . -type f | wc -l | tr -d " ")
		pass "installed into scratch root ($n files)"
		if "${DPKG[@]}" -r "$PKG_ID" >>"$WORK/dpkg.log" 2>&1; then
			left=$(cd "$R/root" && find . -type f)
			[ -z "$left" ] && pass "dpkg -r removed every installed file" || fail "files left after removal: $left"
		else
			tail -5 "$WORK/dpkg.log"; fail "dpkg -r failed"
		fi
	else
		tail -5 "$WORK/dpkg.log"; warn "dpkg simulation unavailable on this host"
	fi
else
	warn "dpkg not available; removal simulation skipped"
fi

# ---------------------------------------------------------------------------
section "9. Size and checksums"
python3 -I - "$DEB" <<'PY'
import hashlib, os, sys
p = sys.argv[1]
data = open(p, "rb").read()
print(f"  file    {os.path.basename(p)}")
print(f"  size    {len(data)} bytes")
print(f"  sha256  {hashlib.sha256(data).hexdigest()}")
print(f"  sha512  {hashlib.sha512(data).hexdigest()}")
PY

printf '\nResult: %d failure(s), %d warning(s)\n' "$FAILS" "$WARNS"
echo "Note: this validates source and package only. Installation and runtime"
echo "behaviour on a device must be verified separately (docs/DEVICE_TEST_CHECKLIST.md)."
[ "$FAILS" -eq 0 ]
