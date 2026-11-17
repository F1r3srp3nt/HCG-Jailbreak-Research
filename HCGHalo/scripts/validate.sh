#!/usr/bin/env bash
# HCG Halo — package & source validation (adapted from HCG Vortex's validate.sh).
#
#   scripts/validate.sh [path/to/package.deb] [--require-new-abi]
#
# Checks (each prints PASS/FAIL/WARN):
#   1. Host unit tests (geometry, config, profiles; ASan/UBSan), generated
#      files up to date, packaging-format regression tests
#   2. Settings layout, preference keys, identifiers and ranges agree with the code
#   3. Package metadata (id, name, version, rootless architecture, dependencies)
#  3a. Archive format: gzip members only, each fully decompressed (CRC and
#      length checked), plus dpkg-deb --fsys-tarfile with its exit status
#   4. Payload under /var/jb, required files, permissions, maintainer scripts
#  4a. Version and build ID compiled into both binaries (rebuilt, not renamed);
#      a clean source commit (enforced with --require-new-abi)
#   5. Mach-O: fat arm64 + arm64e, code signature in every slice, arm64e ABI
#      (native new ABI enforced with --require-new-abi)
#   6. Injection filter targets SpringBoard only; expected interfaces compiled in
#   7. No network, process-spawning, privilege, keychain or URL references
#   8. dpkg install + remove simulation in a scratch root leaves nothing behind
#   9. Size and checksums
#
# Requires: bash, python3, dpkg-deb, dpkg, cc. No device needed: this validates
# the BUILD, not runtime behaviour in SpringBoard.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
ROOT=$(pwd)

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
if python3 -I scripts/generate.py --check >"$WORK/gen.txt" 2>&1; then
	pass "generated files up to date (profile table, Root.plist)"
else
	cat "$WORK/gen.txt"; fail "generated files are stale"
fi
if out=$(python3 -I tests/test_deb_format.py 2>&1); then
	pass "packaging format tests: $(echo "$out" | tail -1)"
else
	echo "$out" | tail -10; fail "packaging format tests failed"
fi

# ---------------------------------------------------------------------------
section "2. Source consistency"
python3 -I - "$ROOT" <<'PY' && pass "Root.plist keys, identifiers and ranges match HaloPreferences.m / HaloConfig" || fail "Settings layout and code disagree"
import os, plistlib, re, sys
root = sys.argv[1]
prefs = open(os.path.join(root, "src/HaloPreferences.m")).read()
config_c = open(os.path.join(root, "src/HaloConfig.c")).read()
config_h = open(os.path.join(root, "src/HaloConfig.h")).read()
profiles_h = open(os.path.join(root, "src/HaloProfiles.h")).read()
plist = plistlib.load(open(os.path.join(root, "preferences/Resources/Root.plist"), "rb"))
ok = True
def bad(msg):
    global ok
    print("    " + msg); ok = False

keys = dict(re.findall(r'NSString \*const (HaloKey\w+) = @"([^"]+)"', prefs))
def table(name):
    body = re.search(r"static const HaloName %s\[\] = \{(.*?)\n\};" % name, config_c, re.S).group(1)
    return [m for m in re.findall(r'\{\w+, "([a-z-]+)", "[^"]+"\}', body)]
expect = {"mode": table("kModes"), "colourStyle": table("kStyles"), "lowPower": table("kLowPower"),
          "cutoutMode": table("kCutout"), "direction": ["clockwise", "counterclockwise"]}
macro = lambda src, name: float(re.search(r"#define %s \(?(-?[\d.]+)\)?" % name, src).group(1))
ranges = {
    "brightness": ("HALO_BRIGHTNESS", config_h), "thickness": ("HALO_THICKNESS", config_h),
    "glow": ("HALO_GLOW", config_h), "inset": ("HALO_INSET", config_h), "speed": ("HALO_SPEED", config_h),
    "colourRepeat": ("HALO_REPEAT", config_h), "segments": ("HALO_SEGMENTS", config_h),
    "segmentLength": ("HALO_SEGMENT_LENGTH", config_h),
    "calCornerRadius": ("HALO_CAL_CORNER", profiles_h), "calNotchWidth": ("HALO_CAL_NOTCH_WIDTH", profiles_h),
    "calNotchHeight": ("HALO_CAL_NOTCH_HEIGHT", profiles_h), "calNotchOffset": ("HALO_CAL_NOTCH_OFFSET", profiles_h),
}
seen = set()
for item in plist["items"]:
    key = item.get("key")
    if not key:
        continue
    seen.add(key)
    if key not in keys.values():
        bad(f"unknown key in Root.plist: {key}")
    if item.get("defaults") != "com.hakmicapitalgroup.halo":
        bad(f"{key}: defaults domain {item.get('defaults')}")
    if item.get("PostNotification") != "com.hakmicapitalgroup.halo/preferences-changed":
        bad(f"{key}: notification {item.get('PostNotification')}")
    if key in expect and sorted(item.get("validValues", [])) != sorted(expect[key]):
        bad(f"{key}: plist {item.get('validValues')} != code {expect[key]}")
    if key in ranges:
        prefix, src = ranges[key]
        lo, hi = macro(src, prefix + "_MIN"), macro(src, prefix + "_MAX")
        if (item.get("min"), item.get("max")) != (lo, hi):
            bad(f"{key}: slider {item.get('min')}..{item.get('max')} != code {lo}..{hi}")
for required in ("enabled", "mode", "colourStyle", "brightness", "thickness", "glow", "inset", "speed", "direction",
                 "lowPower", "cutoutMode"):
    if required not in seen:
        bad(f"Settings lacks {required}")
if not re.search(r"HaloKeyEnabled : @NO", prefs):
    bad("master switch must default to off (HaloKeyEnabled : @NO)")
# "automatic" must never be accepted: validProfiles lists implemented profiles only.
code = re.sub(r"//[^\n]*|/\*.*?\*/", "", prefs, flags=re.S)
if '"automatic"' in code or "HALO_PROFILE_AUTOMATIC" in code:
    bad("HaloPreferences.m must not accept the reserved 'automatic' profile")
# Every action / getter named in Root.plist exists in the controller.
controller = open(os.path.join(root, "preferences/HaloRootListController.m")).read()
for item in plist["items"]:
    for sel in (item.get("action"), item.get("get")):
        if sel and not re.search(r"- \(\w+(?: \*)?\)%s\(PSSpecifier \*\)" % re.escape(sel), controller):
            bad(f"Root.plist names {sel} but HaloRootListController.m does not implement it")
sys.exit(0 if ok else 1)
PY
python3 -I - "$ROOT" <<'PY' && pass "Info.plist CFBundleVersion and the PreferenceLoader entry agree with control and the code" || fail "bundle metadata mismatch"
import os, plistlib, re, sys
root = sys.argv[1]
version = re.search(r"^Version: *(\S+)", open(os.path.join(root, "control")).read(), re.M).group(1).replace("~", "-")
info = plistlib.load(open(os.path.join(root, "preferences/Resources/Info.plist"), "rb"))
entry = plistlib.load(open(os.path.join(root, "layout/Library/PreferenceLoader/Preferences/HCGHaloPrefs.plist"), "rb"))["entry"]
assert info["CFBundleVersion"] == version, (info["CFBundleVersion"], version)
assert info["CFBundleShortVersionString"] == version.split("-")[0]
assert info["CFBundleExecutable"] == entry["bundle"] == "HCGHaloPrefs"
assert info["NSPrincipalClass"] == entry["detail"] == "HaloRootListController"
PY

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
[ "$(field Package)" = "com.hakmicapitalgroup.halo" ] && pass "package id com.hakmicapitalgroup.halo" || fail "package id"
[ "$(field Architecture)" = "iphoneos-arm64" ] && pass "rootless architecture iphoneos-arm64" || fail "Architecture is '$(field Architecture)'"
[ "$(basename "$DEB")" = "$(field Package)_$(field Version)_$(field Architecture).deb" ] && pass "canonical file name" || fail "file name $(basename "$DEB")"
deps=$(field Depends)
for d in "mobilesubstrate (>= 0.9.5000)" preferenceloader "firmware (>= 15.0)"; do
	echo "$deps" | grep -qF "$d" && pass "Depends includes $d" || fail "Depends lacks $d ($deps)"
done
HALO_DISPLAY_VERSION=$(src_field Version | tr '~' '-')

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
EXPECTED_FILES="Library/MobileSubstrate/DynamicLibraries/HCGHalo.dylib
Library/MobileSubstrate/DynamicLibraries/HCGHalo.plist
Library/PreferenceBundles/HCGHaloPrefs.bundle/HCGHaloPrefs
Library/PreferenceBundles/HCGHaloPrefs.bundle/Info.plist
Library/PreferenceBundles/HCGHaloPrefs.bundle/Root.plist
Library/PreferenceBundles/HCGHaloPrefs.bundle/icon.png
Library/PreferenceBundles/HCGHaloPrefs.bundle/icon@2x.png
Library/PreferenceBundles/HCGHaloPrefs.bundle/icon@3x.png
Library/PreferenceLoader/Preferences/HCGHaloPrefs.plist"
for f in $EXPECTED_FILES; do
	[ -s "$JB/$f" ] && pass "/var/jb/$f" || fail "missing /var/jb/$f"
done
extra=$(cd "$JB" && find . -type f | sed 's|^\./||' | sort | comm -23 - <(echo "$EXPECTED_FILES" | sort))
[ -z "$extra" ] && pass "no unexpected files" || fail "unexpected files: $extra"
# Theos converts plists to binary on macOS and leaves XML on Linux: compare contents, not bytes.
python3 -I -c 'import plistlib, sys; sys.exit(0 if plistlib.load(open(sys.argv[1], "rb")) == plistlib.load(open(sys.argv[2], "rb")) else 1)' \
	"$JB/Library/PreferenceBundles/HCGHaloPrefs.bundle/Root.plist" "$ROOT/preferences/Resources/Root.plist" \
	&& pass "packaged Root.plist has the generated content" || fail "packaged Root.plist differs from preferences/Resources/Root.plist"
# dpkg-deb -c lists the modes and owners dpkg will apply.
dpkg-deb -c "$DEB" > "$WORK/contents.txt"
python3 -I - "$WORK/contents.txt" <<'PY' && pass "modes: directories 0755, Mach-O binaries 0755 or 0644, other files 0644; no setuid/setgid/world-writable" || fail "unexpected permissions"
import sys
BINARIES = {"var/jb/Library/MobileSubstrate/DynamicLibraries/HCGHalo.dylib",
            "var/jb/Library/PreferenceBundles/HCGHaloPrefs.bundle/HCGHaloPrefs"}
ok = True
for line in open(sys.argv[1]):
    mode, owner, size, date, time, path = line.split(None, 5)
    path = path.strip().lstrip("./")
    if mode.startswith("d"):
        want = {"drwxr-xr-x"}
    elif path in BINARIES:
        want = {"-rwxr-xr-x", "-rw-r--r--"}  # Xcode builds keep executables 0755
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
python3 -I - "$JB" <<'PY' && pass "bundle Info.plist / Root.plist / PreferenceLoader entry parse and agree" || fail "preference bundle plists invalid"
import plistlib, sys
jb = sys.argv[1]
info = plistlib.load(open(f"{jb}/Library/PreferenceBundles/HCGHaloPrefs.bundle/Info.plist", "rb"))
plistlib.load(open(f"{jb}/Library/PreferenceBundles/HCGHaloPrefs.bundle/Root.plist", "rb"))
entry = plistlib.load(open(f"{jb}/Library/PreferenceLoader/Preferences/HCGHaloPrefs.plist", "rb"))["entry"]
assert info["CFBundleExecutable"] == "HCGHaloPrefs"
assert info["NSPrincipalClass"] == entry["detail"] == "HaloRootListController"
assert entry["bundle"] == "HCGHaloPrefs"
PY
ls "$WORK/ctl" | sort > "$WORK/ctl.txt"
[ "$(tr '\n' ' ' < "$WORK/ctl.txt")" = "control postrm " ] && pass "control members: control, postrm" || fail "control members: $(tr '\n' ' ' < "$WORK/ctl.txt")"
if [ -f "$WORK/ctl/postrm" ]; then
	[ -x "$WORK/ctl/postrm" ] && head -1 "$WORK/ctl/postrm" | grep -q '^#!/bin/sh' && pass "postrm is an executable /bin/sh script" || fail "postrm not executable or no shebang"
	python3 -I - "$WORK/ctl/postrm" <<'PY' && pass "postrm deletes only HCG Halo's own preference files, only on purge" || fail "postrm does more than expected"
import re, sys
s = open(sys.argv[1]).read().replace("\\\n", " ")  # join continuation lines
paths = " ".join(re.findall(r"rm -f ([^\n]*)", s)).split()
ok = 'if [ "$1" = "purge" ]' in s and paths and all(p.startswith("/var/mobile/Library/Preferences/com.hakmicapitalgroup.halo.") for p in paths)
sys.exit(0 if ok else 1)
PY
fi

# ---------------------------------------------------------------------------
section "4a. Version and build ID inside the binaries"
BUILD_IDS=$(python3 -I - "$JB" "$HALO_DISPLAY_VERSION" <<'PY'
import re, sys
jb, version = sys.argv[1], sys.argv[2]
ids = set()
for rel in ("Library/MobileSubstrate/DynamicLibraries/HCGHalo.dylib",
            "Library/PreferenceBundles/HCGHaloPrefs.bundle/HCGHaloPrefs"):
    data = open(f"{jb}/{rel}", "rb").read()
    # Exported markers from HaloPreferences.m (compiled into both binaries).
    if (b"HCGHALO-VERSION:" + version.encode() + b"\0") not in data:
        print(f"MISSING-VERSION {rel}"); continue
    found = set(m.decode() for m in re.findall(rb"HCGHALO-BUILD:([0-9A-Za-z.-]+)\0", data))
    if len(found) != 1:
        print(f"MISSING-BUILD {rel}"); continue
    ids |= found
print(" ".join(sorted(ids)))
PY
)
if echo "$BUILD_IDS" | grep -q MISSING-; then
	fail "version $HALO_DISPLAY_VERSION missing from: $BUILD_IDS (rebuild, do not rename)"
else
	pass "both binaries carry version $HALO_DISPLAY_VERSION"
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
FILES = ["Library/MobileSubstrate/DynamicLibraries/HCGHalo.dylib",
         "Library/PreferenceBundles/HCGHaloPrefs.bundle/HCGHaloPrefs"]
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
section "6. SpringBoard injection"
FILTER="$JB/Library/MobileSubstrate/DynamicLibraries/HCGHalo.plist"
if python3 -I - "$FILTER" <<'PY'
import plistlib, re, sys
data = open(sys.argv[1], "rb").read()
if data.startswith(b"bplist") or data.lstrip().startswith(b"<?xml"):
    d = plistlib.loads(data)
    ok = (set(d) == {"Filter"} and set(d["Filter"]) == {"Bundles"} and d["Filter"]["Bundles"] == ["com.apple.springboard"])
else:  # OpenStep text
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
DYLIB="$JB/Library/MobileSubstrate/DynamicLibraries/HCGHalo.dylib"
PREFS="$JB/Library/PreferenceBundles/HCGHaloPrefs.bundle/HCGHaloPrefs"
printable_runs "$DYLIB" > "$WORK/dylib.strings"
printable_runs "$PREFS" > "$WORK/prefs.strings"
for s in SBHomeScreenWindow SBIconController SBApplication 'frontDisplayDidChange:' _MSHookMessageEx \
         com.apple.springboard.hasBlankedScreen com.apple.springboard.lockstate \
         com.hakmicapitalgroup.halo/preferences-changed lineDashPhase transform.rotation.z; do
	grep -qxF -- "$s" "$WORK/dylib.strings" && pass "tweak references $s" || fail "tweak lacks $s"
done
for s in HaloRootListController com.hakmicapitalgroup.halo/status-request; do
	grep -qxF -- "$s" "$WORK/prefs.strings" && pass "Settings bundle references $s" || fail "Settings bundle lacks $s"
done
grep -qF "SBHomeScreen" "$WORK/prefs.strings" && fail "Settings bundle references SpringBoard classes" || pass "Settings bundle references no SpringBoard classes"

# ---------------------------------------------------------------------------
section "7. Forbidden capabilities"
BAD='^_(socket|connect|getaddrinfo|posix_spawn|posix_spawnp|system|execve|execv|fork|vfork|setuid|seteuid|setgid|ptrace|nw_[a-z_]+)$|NSURLSession|NSURLConnection|NSURLRequest|CFNetwork|WKWebView|SecItem|LAContext|ASIdentifierManager|identifierForVendor'
cat "$WORK/dylib.strings" "$WORK/prefs.strings" > "$WORK/all.strings"
if grep -qx '_objc_msgSend' "$WORK/all.strings" && grep -qx '_CFPreferencesCopyAppValue' "$WORK/all.strings"; then
	hits=$(grep -E "$BAD" "$WORK/all.strings" | sort -u || true)
	[ -z "$hits" ] && pass "no networking, process-spawning, privilege, keychain, auth or tracking APIs referenced" || fail "suspicious symbols: $hits"
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
		if "${DPKG[@]}" -r com.hakmicapitalgroup.halo >>"$WORK/dpkg.log" 2>&1; then
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
