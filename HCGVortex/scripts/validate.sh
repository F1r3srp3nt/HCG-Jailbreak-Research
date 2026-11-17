#!/usr/bin/env bash
# HCG Vortex — package & source validation.
#
#   scripts/validate.sh [path/to/package.deb] [--require-new-abi]
#
# Checks (each prints PASS/FAIL/WARN):
#   1. Host unit tests for the math core
#   2. Settings layout / preference identifiers are consistent with the code
#   3. Package metadata (id, version, rootless architecture, dependencies)
#  3a. Archive format: gzip members only, each fully decompressed (CRC and
#      length checked), plus dpkg-deb --fsys-tarfile with its exit status
#   4. Every payload path lives under /var/jb (rootless), required files exist
#   5. Mach-O: fat arm64 + arm64e, code signature present in every slice,
#      arm64e pointer-auth ABI reported (and enforced with --require-new-abi)
#   6. Injection filter targets SpringBoard only; hook targets compiled in
#   7. No network / process-spawning / privilege APIs imported
#   8. dpkg install + remove simulation into a scratch root leaves nothing behind
#
# Requires: bash, python3, dpkg-deb, dpkg, cc (for tests). No device needed —
# this validates the BUILD, not runtime behaviour on SpringBoard.

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
section "1. Math core unit tests"
if command -v cc >/dev/null 2>&1; then
	if out=$(make -s -C tests BUILD="$WORK/tests" test 2>&1); then
		pass "$(echo "$out" | tail -1)"
	else
		echo "$out" | tail -20
		fail "unit tests failed"
	fi
else
	warn "no host C compiler; unit tests skipped"
fi

# ---------------------------------------------------------------------------
section "2. Source consistency"
python3 - "$ROOT" <<'PY' && pass "Root.plist values match VortexPreferences / VortexMath" || fail "Root.plist / code identifier mismatch"
import plistlib, re, sys, os, importlib.util
root = sys.argv[1]
src = open(os.path.join(root, "src/VortexPreferences.m")).read()
math_c = open(os.path.join(root, "src/VortexMath.c")).read()
ids = dict(re.findall(r'NSString \*const (VortexEffectIdentifier\w+|VortexPresetPerDirection) = @"([^"]+)"', src))
effects = {ids[k] for k in ids if k.startswith("VortexEffectIdentifier")}
presets = effects | {ids["VortexPresetPerDirection"]}
easings = set(re.search(r'validEasings \{\s*return @\[([^\]]+)\]', src).group(1).replace('@"', '"').replace('"', '').replace(' ', '').split(','))
directions = set(re.findall(r'\{ VortexDirection\w+,\s+"([a-z-]+)"', math_c))
plist = plistlib.load(open(os.path.join(root, "preferences/Resources/Root.plist"), "rb"))
expect = {"preset": presets, "swipeLeftEffect": effects, "swipeRightEffect": effects,
          "incomingDirection": directions, "outgoingDirection": directions, "easing": easings}
keys_in_code = set(re.findall(r'NSString \*const VortexKey\w+ = @"([^"]+)"', src))
ok = True
for item in plist["items"]:
    key = item.get("key")
    if not key:
        continue
    if key not in keys_in_code:
        print(f"    unknown key in Root.plist: {key}"); ok = False
    if key in expect and set(item.get("validValues", [])) != expect[key]:
        print(f"    {key}: plist {sorted(item.get('validValues', []))} != code {sorted(expect[key])}"); ok = False
spec = importlib.util.spec_from_file_location("gen", os.path.join(root, "scripts/generate_root_plist.py"))
gen = importlib.util.module_from_spec(spec); spec.loader.exec_module(gen)
if gen.ITEMS != plist["items"]:
    print("    Root.plist is stale: run scripts/generate_root_plist.py"); ok = False
sys.exit(0 if ok else 1)
PY

# ---------------------------------------------------------------------------
if [ -z "$DEB" ] || [ ! -f "$DEB" ]; then
	section "3-8. Package checks"
	fail "no .deb found (build first: scripts/build.sh)"
	printf '\nResult: %d failure(s), %d warning(s)\n' "$FAILS" "$WARNS"
	exit 1
fi
section "3. Package metadata — $(basename "$DEB")"
field() { dpkg-deb -f "$DEB" "$1" 2>/dev/null; }
SRC_CONTROL="$ROOT/control"
src_field() { sed -n "s/^$1: *//p" "$SRC_CONTROL"; }
for f in Package Name Version Architecture; do
	if [ "$(field "$f")" = "$(src_field "$f")" ]; then
		pass "$f: $(field "$f") (matches source control)"
	else
		fail "$f is '$(field "$f")', source control says '$(src_field "$f")'"
	fi
done
[ "$(field Architecture)" = "iphoneos-arm64" ] && pass "rootless architecture iphoneos-arm64" || fail "Architecture is '$(field Architecture)'"
VORTEX_DISPLAY_VERSION=$(src_field Version | tr '~' '-')
[ "$(field Section)" = "Tweaks" ] && pass "Section: Tweaks" || fail "Section is '$(field Section)'"
deps=$(field Depends)
for d in mobilesubstrate preferenceloader firmware; do
	echo "$deps" | grep -q "$d" && pass "Depends includes $d" || fail "Depends lacks $d ($deps)"
done

# ---------------------------------------------------------------------------
# Regression check for the packaging selected in 0.1.0~beta2: gzip members
# only (beta1's data.tar.lzma failed to unpack on one phone; cause unconfirmed).
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
# Second, independent decompressor: dpkg-deb's own (the path that failed on
# the phone for beta1). Keep its real exit status.
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
section "4. Payload layout"
dpkg-deb -x "$DEB" "$WORK/pkg"
dpkg-deb -e "$DEB" "$WORK/ctl"
outside=$(cd "$WORK/pkg" && find . -mindepth 1 \( -type f -o -type l \) ! -path './var/jb/*')
[ -z "$outside" ] && pass "all files are under /var/jb" || fail "files outside /var/jb: $outside"
JB="$WORK/pkg/var/jb"
for f in Library/MobileSubstrate/DynamicLibraries/HCGVortex.dylib \
         Library/MobileSubstrate/DynamicLibraries/HCGVortex.plist \
         Library/PreferenceBundles/HCGVortexPrefs.bundle/HCGVortexPrefs \
         Library/PreferenceBundles/HCGVortexPrefs.bundle/Info.plist \
         Library/PreferenceBundles/HCGVortexPrefs.bundle/Root.plist \
         Library/PreferenceBundles/HCGVortexPrefs.bundle/icon.png \
         Library/PreferenceLoader/Preferences/HCGVortexPrefs.plist; do
	[ -s "$JB/$f" ] && pass "/var/jb/$f" || fail "missing /var/jb/$f"
done
python3 - "$JB" <<'PY' && pass "bundle Info.plist / Root.plist / PreferenceLoader entry parse and agree" || fail "preference bundle plists invalid"
import plistlib, sys
jb = sys.argv[1]
info = plistlib.load(open(f"{jb}/Library/PreferenceBundles/HCGVortexPrefs.bundle/Info.plist", "rb"))
plistlib.load(open(f"{jb}/Library/PreferenceBundles/HCGVortexPrefs.bundle/Root.plist", "rb"))
entry = plistlib.load(open(f"{jb}/Library/PreferenceLoader/Preferences/HCGVortexPrefs.plist", "rb"))["entry"]
assert info["CFBundleExecutable"] == "HCGVortexPrefs"
assert info["NSPrincipalClass"] == entry["detail"] == "VortexRootListController"
assert entry["bundle"] == "HCGVortexPrefs"
PY
if [ -f "$WORK/ctl/postrm" ]; then
	grep -q 'purge' "$WORK/ctl/postrm" && pass "postrm only cleans on purge" || warn "postrm present; review it"
fi
for s in preinst postinst prerm; do
	[ -f "$WORK/ctl/$s" ] && warn "maintainer script $s present; review it"
done

# ---------------------------------------------------------------------------
python3 - "$JB" "$VORTEX_DISPLAY_VERSION" <<'PY' && pass "Info.plist CFBundleVersion and both binaries carry version $VORTEX_DISPLAY_VERSION (rebuilt, not renamed)" || fail "version mismatch inside the package (expected $VORTEX_DISPLAY_VERSION): rebuild, do not rename"
import plistlib, sys
jb, version = sys.argv[1], sys.argv[2]
info = plistlib.load(open(f"{jb}/Library/PreferenceBundles/HCGVortexPrefs.bundle/Info.plist", "rb"))
assert info["CFBundleVersion"] == version, info["CFBundleVersion"]
for rel in ("Library/MobileSubstrate/DynamicLibraries/HCGVortex.dylib",
            "Library/PreferenceBundles/HCGVortexPrefs.bundle/HCGVortexPrefs"):
    assert (b"\0" + version.encode() + b"\0") in open(f"{jb}/{rel}", "rb").read(), rel
PY

section "5. Mach-O binaries"
python3 - "$JB" "$REQUIRE_NEW_ABI" <<'PY'
import struct, sys
jb, require_new = sys.argv[1], sys.argv[2] == "1"
FILES = ["Library/MobileSubstrate/DynamicLibraries/HCGVortex.dylib",
         "Library/PreferenceBundles/HCGVortexPrefs.bundle/HCGVortexPrefs"]
LC_SEGMENT_64, LC_CODE_SIGNATURE = 0x19, 0x1D
rc = 0
def out(kind, msg):
    global rc
    color = {"PASS": 32, "FAIL": 31, "WARN": 33}[kind]
    print(f"  \033[{color}m{kind}\033[0m {msg}")
    if kind == "FAIL": rc |= 1
    if kind == "WARN": rc |= 2
def slices(d):
    magic = struct.unpack(">I", d[:4])[0]
    if magic == 0xCAFEBABE:
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
        off, text, signed = 32, 0, False
        for _ in range(ncmds):
            cmd, size = struct.unpack("<II", s[off:off + 8])
            if cmd == LC_SEGMENT_64 and s[off + 8:off + 24].rstrip(b"\0") == b"__TEXT":
                text = struct.unpack("<Q", s[off + 48:off + 56])[0]
            if cmd == LC_CODE_SIGNATURE: signed = True
            off += size
        archs[arch] = (cs, text, signed, s)
    for a in ("arm64", "arm64e"):
        if a not in archs:
            out("FAIL", f"{name}: missing {a} slice"); continue
        cs, text, signed, s = archs[a]
        out("PASS" if text > 0 else "FAIL", f"{name} [{a}]: __TEXT {text} bytes of compiled code")
        out("PASS" if signed else "FAIL", f"{name} [{a}]: LC_CODE_SIGNATURE present")
    if "arm64e" in archs:
        cs, _, _, s = archs["arm64e"]
        versioned = bool(cs & 0x80000000)
        # ObjC class isa pointers signed with the iOS 14+ discriminator 0x6AE1
        # (auth bit 63 set, diversity in bits 32..47) — present in Xcode
        # new-ABI output and in allemande-converted output, absent in raw
        # legacy output.
        isa = sum(1 for i in range(0, len(s) - 7, 8)
                  if (lambda v: (v >> 63) & 1 and ((v >> 32) & 0xFFFF) == 0x6AE1)(struct.unpack_from("<Q", s, i)[0]))
        if versioned:
            out("PASS", f"{name} [arm64e]: versioned pointer-auth ABI (cpusubtype {cs:#x}) — native new-ABI toolchain")
        elif isa:
            msg = (f"{name} [arm64e]: legacy cpusubtype {cs:#x} with {isa} isa pointers re-signed (allemande-converted). "
                   "Theos-documented workaround; use the macOS/Xcode build for distribution.")
            out("FAIL" if require_new else "WARN", msg)
        else:
            out("FAIL", f"{name} [arm64e]: legacy ABI and NOT converted — will not work on A12+ / iOS 15+")
sys.exit(1 if rc & 1 else (3 if rc & 2 else 0))
PY
case $? in 0) ;; 3) WARNS=$((WARNS + 1)) ;; *) FAILS=$((FAILS + 1)) ;; esac

# ---------------------------------------------------------------------------
section "6. SpringBoard injection"
FILTER="$JB/Library/MobileSubstrate/DynamicLibraries/HCGVortex.plist"
# Theos leaves the filter as an old-style (OpenStep) text plist on Linux but
# converts it to a binary plist on macOS; read whichever format it is.
if python3 - "$FILTER" <<'PY'
import plistlib, re, sys
data = open(sys.argv[1], "rb").read()
if data.startswith(b"bplist") or data.lstrip().startswith(b"<?xml"):
    d = plistlib.loads(data)
    ok = (set(d) == {"Filter"} and set(d["Filter"]) == {"Bundles"}
          and d["Filter"]["Bundles"] == ["com.apple.springboard"])
else:  # OpenStep text: { Filter = { Bundles = ( "com.apple.springboard" ); }; }
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

# Printable runs of >= 4 bytes from the whole file (what GNU `strings -a`
# prints). Done in Python so Linux and macOS give identical results: Apple's
# `strings` scans Mach-O files differently and missed symbol names.
printable_runs() {
	python3 -c '
import re, sys
for path in sys.argv[1:]:
    for run in re.findall(rb"[\x20-\x7e]{4,}", open(path, "rb").read()):
        print(run.decode("ascii"))' "$@"
}
DYLIB="$JB/Library/MobileSubstrate/DynamicLibraries/HCGVortex.dylib"
PREFS="$JB/Library/PreferenceBundles/HCGVortexPrefs.bundle/HCGVortexPrefs"
printable_runs "$DYLIB" > "$WORK/dylib.strings"
for s in SBFolderView SBRootFolderView SBIconListView 'scrollViewDidScroll:' layoutSubviews setSublayerTransform: _MSHookMessageEx; do
	grep -qx -- "$s" "$WORK/dylib.strings" && pass "binary references $s" || fail "binary lacks $s"
done

# ---------------------------------------------------------------------------
section "7. Forbidden capabilities"
BAD='^_(socket|connect|getaddrinfo|posix_spawn|posix_spawnp|system|execve|execv|fork|vfork|setuid|seteuid|setgid|ptrace|nw_[a-z_]+)$|NSURLSession|NSURLConnection|CFNetwork|SecItem|LAContext'
printable_runs "$DYLIB" "$PREFS" > "$WORK/all.strings"
# Self-check: the scan must see the imports we know are there, or a clean
# result below would mean nothing.
if grep -qx '_objc_msgSend' "$WORK/all.strings" && grep -qx '_CFPreferencesCopyAppValue' "$WORK/all.strings"; then
	hits=$(grep -E "$BAD" "$WORK/all.strings" | sort -u || true)
	[ -z "$hits" ] && pass "no networking, process-spawning, privilege, keychain or auth APIs referenced" || fail "suspicious symbols: $hits"
else
	fail "symbol scan cannot see known imports (_objc_msgSend, _CFPreferencesCopyAppValue); forbidden-API check is not trustworthy"
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
		if "${DPKG[@]}" -r com.hakmicapitalgroup.vortex >>"$WORK/dpkg.log" 2>&1; then
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

printf '\nResult: %d failure(s), %d warning(s)\n' "$FAILS" "$WARNS"
echo "Note: this validates source and package only. On-device installation and"
echo "runtime behaviour must be verified separately (docs/TESTING.md)."
[ "$FAILS" -eq 0 ]
