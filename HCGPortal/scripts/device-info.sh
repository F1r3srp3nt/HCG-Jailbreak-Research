#!/bin/sh
# HCG Portal — device report for the first test install. READ-ONLY.
# (Adapted from HCG Vortex's and HCG Halo's scripts/device-info.sh.)
#
# Run ON THE IPHONE over SSH, as the mobile user:
#     sh device-info.sh | tee portal-device-report.txt
#
# It installs nothing, writes no files except your own `tee` copy, and
# changes no settings. Send the full output back for review BEFORE installing
# HCG Portal: the go/no-go decision is made from this report. Nothing about the
# device is assumed from other projects' tests.

echo "== HCG Portal device report ($(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null))"

# ---- Hardware --------------------------------------------------------------
model=$(sysctl -n hw.machine 2>/dev/null || uname -m)
echo "Model identifier:   $model"
case "$model" in
	iPhone12,5) echo "                    = iPhone 11 Pro Max (A13, arm64e)" ;;
	iPhone12,3) echo "                    = iPhone 11 Pro (A13, arm64e)" ;;
	iPhone12,1) echo "                    = iPhone 11 (A13, arm64e)" ;;
	iPhone14,2) echo "                    = iPhone 13 Pro (A15, arm64e)" ;;
	iPhone14,3) echo "                    = iPhone 13 Pro Max (A15, arm64e)" ;;
	*) echo "                    (not in this script's list: confirm in Settings > General > About)" ;;
esac
cpusub=$(sysctl -n hw.cpusubtype 2>/dev/null)
case "$cpusub" in
	2) echo "CPU subtype:        2 (arm64e)" ;;
	"") echo "CPU subtype:        unknown" ;;
	*) echo "CPU subtype:        $cpusub (NOT arm64e)" ;;
esac

# ---- iOS ---------------------------------------------------------------------
ios=""
build=""
if command -v sw_vers >/dev/null 2>&1; then
	ios=$(sw_vers -productVersion 2>/dev/null)
	build=$(sw_vers -buildVersion 2>/dev/null)
fi
SV=/System/Library/CoreServices/SystemVersion.plist
if [ -z "$ios" ] && [ -r "$SV" ]; then
	ios=$(sed -n '/<key>ProductVersion<\/key>/{n;s/.*<string>\(.*\)<\/string>.*/\1/p;}' "$SV" 2>/dev/null)
	build=$(sed -n '/<key>ProductBuildVersion<\/key>/{n;s/.*<string>\(.*\)<\/string>.*/\1/p;}' "$SV" 2>/dev/null)
fi
echo "iOS version:        ${ios:-unknown (read Settings > General > About)}"
echo "iOS build:          ${build:-unknown}"
echo "Kernel:             $(uname -r 2>/dev/null) — $(uname -v 2>/dev/null | cut -c1-80)"

# ---- Jailbreak ---------------------------------------------------------------
if [ -d /var/jb ]; then
	echo "Jailbreak root:     /var/jb -> $(readlink /var/jb 2>/dev/null || echo '(not a symlink)')"
else
	echo "Jailbreak root:     /var/jb MISSING (not a rootless jailbreak)"
fi
[ -d /var/jb/basebin ] && echo "Dopamine basebin:   present (/var/jb/basebin)"
dopamine_app=$(find /var/containers/Bundle/Application -maxdepth 2 -name 'Dopamine.app' 2>/dev/null | head -1)
dopamine_ver=""
if [ -n "$dopamine_app" ] && command -v plutil >/dev/null 2>&1; then
	dopamine_ver=$(plutil -key CFBundleShortVersionString "$dopamine_app/Info.plist" 2>/dev/null)
fi
if [ -n "$dopamine_ver" ]; then
	echo "Dopamine version:   $dopamine_ver"
elif [ -n "$dopamine_app" ]; then
	echo "Dopamine version:   app found, version not readable here (read it in the Dopamine app)"
else
	echo "Dopamine version:   Dopamine.app not found (other jailbreak? state which and its version)"
fi
echo "dpkg architecture:  $(dpkg --print-architecture 2>/dev/null || echo 'dpkg not found')"

# ---- Packages ------------------------------------------------------------------
pkgver() { dpkg-query -W -f '${Version}' "$1" 2>/dev/null; }
echo "ElleKit:            $(pkgver ellekit || true)"
echo "Substrate provider: $(dpkg-query -W -f '${Package} ${Version} [${Provides}]\n' 2>/dev/null | grep -i 'mobilesubstrate\|substrate' | tr '\n' ';')"
echo "PreferenceLoader:   $(pkgver preferenceloader || true)"
echo "Sileo:              $(pkgver org.coolstar.sileo || true)"
echo "Zebra:              $(pkgver xyz.willy.zebra || true)"
echo "HCG Portal:         $(pkgver com.hakmicapitalgroup.portal || echo 'not installed')"
echo "HCG Animation Ctr:  $(pkgver com.hakmicapitalgroup.animationcenter || echo 'not installed')"
echo "HCG Halo:           $(pkgver com.hakmicapitalgroup.halo || echo 'not installed')"
echo "HCG Vortex:         $(pkgver com.hakmicapitalgroup.vortex || echo 'not installed')"
echo "HCG Nexus:          $(pkgver com.hakmicapitalgroup.hcgnexus || echo 'not installed')"

# ---- Other SpringBoard tweaks (possible conflicts) -----------------------------
echo "SpringBoard tweaks:"
for f in /var/jb/Library/MobileSubstrate/DynamicLibraries/*.plist; do
	[ -e "$f" ] || continue
	if grep -qi 'com.apple.springboard' "$f" 2>/dev/null; then echo "  - $(basename "$f" .plist)"; fi
done

# ---- Leftovers from earlier tests ----------------------------------------------
P=/var/mobile/Library/Preferences
for f in "$P/com.hakmicapitalgroup.portal.plist" "$P/com.hakmicapitalgroup.portal.status.plist" \
	"$P/com.hakmicapitalgroup.portal.disabled"; do
	[ -e "$f" ] && echo "Existing file:      $f"
done
# Lock Screen companions Portal can open (presence only).
for b in HCGAnimationCenterPrefs HCGNexusPrefs; do [ -d "/var/jb/Library/PreferenceBundles/$b.bundle" ] && echo "Settings bundle:    $b.bundle present"; done
# Wallpaper type: PosterBoard (iOS 16+) keeps its posters here; only presence is reported, never contents.
[ -d /var/mobile/Library/Application\ Support/PosterBoard ] && echo "PosterBoard data:   present (iOS 16+ poster wallpapers)"
echo "Free space (/var):  $(df -h /var 2>/dev/null | tail -1 | awk '{print $4}')"

# ---- Pre-checks (necessary, not sufficient) --------------------------------------
echo "== Pre-checks"
fail=0
check() { if [ "$1" = ok ]; then echo "  ok    $2"; else echo "  FAIL  $2"; fail=1; fi; }
[ "$cpusub" = 2 ] && check ok "arm64e CPU" || check no "arm64e CPU (the package's arm64e slice targets A12+)"
major=${ios%%.*}
case "$major" in ''|*[!0-9]*) check no "iOS version readable" ;; *) [ "$major" -ge 15 ] && check ok "iOS >= 15 (package minimum)" || check no "iOS >= 15 (package minimum)" ;; esac
[ -d /var/jb ] && check ok "rootless /var/jb" || check no "rootless /var/jb"
[ "$(dpkg --print-architecture 2>/dev/null)" = iphoneos-arm64 ] && check ok "dpkg architecture iphoneos-arm64" || check no "dpkg architecture iphoneos-arm64"
dpkg-query -W -f '${Provides} ${Package}\n' 2>/dev/null | grep -qi 'mobilesubstrate' && check ok "mobilesubstrate provider installed" || check no "mobilesubstrate provider installed (ElleKit)"
[ -n "$(pkgver preferenceloader)" ] && check ok "PreferenceLoader installed" || check no "PreferenceLoader installed"
if [ "$fail" = 0 ]; then
	echo "Result: pre-checks passed. Send this report for review; do not install HCG Portal yet."
else
	echo "Result: pre-checks FAILED. Do not install."
fi
