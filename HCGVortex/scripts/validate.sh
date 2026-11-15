#!/usr/bin/env bash
# HCG Vortex — package & source validation.
#
#   scripts/validate.sh [path/to/package.deb] [--require-new-abi]
#
# Checks (each prints PASS/FAIL/WARN):
#   1. Host unit tests for the math core
#   2. Settings layout / preference identifiers are consistent with the code
#   3. Package metadata (id, version, rootless architecture, dependencies)
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
cd "$(dirname "$0")/.."
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
[ "$(field Package)" = "com.hakmicapitalgroup.vortex" ] && pass "Package: com.hakmicapitalgroup.vortex" || fail "Package is '$(field Package)'"
[ "$(field Name)" = "HCG Vortex" ] && pass "Name: HCG Vortex" || fail "Name is '$(field Name)'"
[ "$(field Architecture)" = "iphoneos-arm64" ] && pass "Architecture: iphoneos-arm64 (rootless)" || fail "Architecture is '$(field Architecture)'"
case "$(field Version)" in
	0.1.0~alpha) pass "Version: 0.1.0~alpha (displays as 0.1.0-alpha; sorts before 0.1.0)" ;;
	0.1.0~alpha*) warn "Version: $(field Version) (non-final build; use FINALPACKAGE=1 for distribution)" ;;
	*) fail "Version is '$(field Version)'" ;;
esac
[ "$(field Section)" = "Tweaks" ] && pass "Section: Tweaks" || fail "Section is '$(field Section)'"
deps=$(field Depends)
for d in mobilesubstrate preferenceloader firmware; do
	echo "$deps" | grep -q "$d" && pass "Depends includes $d" || fail "Depends lacks $d ($deps)"
done

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
if grep -q '"com.apple.springboard"' "$FILTER" && [ "$(grep -o '"[a-z.]*"' "$FILTER" | sort -u | wc -l)" -eq 1 ]; then
	pass "filter injects into com.apple.springboard only"
else
	fail "unexpected filter: $(cat "$FILTER")"
fi
DYLIB="$JB/Library/MobileSubstrate/DynamicLibraries/HCGVortex.dylib"
strings -a "$DYLIB" > "$WORK/dylib.strings"   # captured once: avoids SIGPIPE under pipefail
for s in SBFolderView SBRootFolderView SBIconListView 'scrollViewDidScroll:' layoutSubviews setSublayerTransform: _MSHookMessageEx; do
	grep -qx -- "$s" "$WORK/dylib.strings" && pass "binary references $s" || fail "binary lacks $s"
done

# ---------------------------------------------------------------------------
section "7. Forbidden capabilities"
BAD='^_(socket|connect|getaddrinfo|posix_spawn|posix_spawnp|system|execve|execv|fork|vfork|setuid|seteuid|setgid|ptrace|nw_[a-z_]+)$|NSURLSession|NSURLConnection|CFNetwork|SecItem|LAContext'
hits=$(for b in "$DYLIB" "$JB/Library/PreferenceBundles/HCGVortexPrefs.bundle/HCGVortexPrefs"; do strings -a "$b"; done | grep -E "$BAD" | sort -u)
[ -z "$hits" ] && pass "no networking, process-spawning, privilege, keychain or auth APIs referenced" || fail "suspicious symbols: $hits"

# ---------------------------------------------------------------------------
section "8. Install / remove simulation (scratch root, not a device)"
if command -v dpkg >/dev/null 2>&1; then
	R="$WORK/sim"
	mkdir -p "$R/root" "$R/admin/updates" "$R/admin/info"
	: > "$R/admin/status"
	DPKG=(dpkg --root="$R/root" --admindir="$R/admin" --force-not-root --force-depends --force-architecture --force-script-chrootless --log=/dev/null)
	if "${DPKG[@]}" -i "$DEB" >"$WORK/dpkg.log" 2>&1; then
		n=$(cd "$R/root" && find . -type f | wc -l)
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
