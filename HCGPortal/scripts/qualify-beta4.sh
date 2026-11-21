#!/bin/sh
# HCG Portal 0.1.0~beta4 — physical-device qualification helper.
#
# Run ON THE IPHONE over SSH (or NewTerm), as the mobile user:
#
#   sh qualify-beta4.sh preflight [path/to/com.hakmicapitalgroup.portal_0.1.0~beta4_iphoneos-arm64.deb]
#   sh qualify-beta4.sh status
#   sh qualify-beta4.sh collect  > portal-beta4-report.txt
#   sh qualify-beta4.sh backup   [directory]          (default /var/mobile/Documents/hcg-portal-backup-<time>)
#
# preflight, status and collect are READ-ONLY: they install nothing, change no
# setting and write no file (apart from what you redirect with >). backup only
# COPIES Portal's own preference files and the currently installed Portal
# package into the backup directory you name. Nothing here installs, removes,
# resprings or touches authentication; those are commands you type yourself
# (docs/QUALIFICATION_0.1.0-beta4.md).

EXPECTED_SHA256=8a186d99a63d38c2bc4fb25d40bcfd773bbc042e5309063e0a87fc4d584164e4
EXPECTED_SIZE=293942
EXPECTED_VERSION=0.1.0~beta4
EXPECTED_BUILD=1298ded2d930
PKG=com.hakmicapitalgroup.portal
PREFS=/var/mobile/Library/Preferences
STATUS_PLIST=$PREFS/com.hakmicapitalgroup.portal.status.plist
SETTINGS_PLIST=$PREFS/com.hakmicapitalgroup.portal.plist
KILL_SWITCH=$PREFS/com.hakmicapitalgroup.portal.disabled
DYLIBS=/var/jb/Library/MobileSubstrate/DynamicLibraries
CANDIDATE=repo.hakmicapitalgroup.com/repo/candidate

pkgver() { dpkg-query -W -f '${Version}' "$1" 2>/dev/null; }
sha256_of() {
	if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
	elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1
	else echo "no-sha256-tool"; fi
}
fail=0
warn=0
ok()   { echo "  ok    $1"; }
bad()  { echo "  FAIL  $1"; fail=1; }
note() { echo "  WARN  $1"; warn=1; }

plist_key() { # plist_key FILE KEY: prints a value with whichever plist tool exists
	if command -v plutil >/dev/null 2>&1; then plutil -key "$2" "$1" 2>/dev/null
	elif command -v plistutil >/dev/null 2>&1; then plistutil -i "$1" 2>/dev/null | sed -n "/<key>$2<\/key>/{n;p;}" | sed 's/<[^>]*>//g;s/^[[:space:]]*//'
	else echo "(no plutil/plistutil: read Settings > HCG Portal instead)"; fi
}

device() {
	echo "== Device"
	model=$(sysctl -n hw.machine 2>/dev/null || uname -m)
	echo "Model identifier:    $model (Settings > General > About for the marketing name)"
	ios=$(sw_vers -productVersion 2>/dev/null)
	[ -z "$ios" ] && ios=$(sed -n '/<key>ProductVersion<\/key>/{n;s/.*<string>\(.*\)<\/string>.*/\1/p;}' /System/Library/CoreServices/SystemVersion.plist 2>/dev/null)
	build=$(sw_vers -buildVersion 2>/dev/null)
	echo "iOS:                 ${ios:-unknown} ${build:+($build)}"
	echo "CPU subtype:         $(sysctl -n hw.cpusubtype 2>/dev/null) (2 = arm64e)"
	echo "Jailbreak root:      $(readlink /var/jb 2>/dev/null || echo 'MISSING')"
	[ -d /var/jb/basebin ] && echo "Dopamine basebin:    present"
	app=$(find /var/containers/Bundle/Application -maxdepth 2 -name 'Dopamine.app' 2>/dev/null | head -1)
	if [ -n "$app" ] && command -v plutil >/dev/null 2>&1; then
		echo "Dopamine:            $(plutil -key CFBundleShortVersionString "$app/Info.plist" 2>/dev/null)"
	else
		echo "Dopamine:            ${app:+app found; }read the version and the 'Tweak Injection' setting in the Dopamine app"
	fi
	echo "Uptime:              $(uptime 2>/dev/null)"
	echo "Free space (/var):   $(df -h /var 2>/dev/null | tail -1 | awk '{print $4}')"
	echo "Passcode / Face ID:  (not readable from a script: state in your report whether a passcode, Face ID or Touch ID is set)"
}

packages() {
	echo "== Packages"
	for p in ellekit preferenceloader org.coolstar.sileo xyz.willy.zebra $PKG com.hakmicapitalgroup.animationcenter \
		com.hakmicapitalgroup.halo com.hakmicapitalgroup.vortex com.hakmicapitalgroup.hcgnexus; do
		printf '  %-42s %s\n' "$p" "$(pkgver "$p" || true)"
	done
	echo "  all HCG packages:"
	dpkg-query -W 'com.hakmicapitalgroup.*' 2>/dev/null | sed 's/^/    /'
	echo "  substrate providers: $(dpkg-query -W -f '${Package} ${Version} [${Provides}]\n' 2>/dev/null | grep -i substrate | tr '\n' ';')"
}

tweaks() {
	echo "== SpringBoard tweaks (injected into the same process as Portal)"
	for f in "$DYLIBS"/*.plist; do
		[ -e "$f" ] || continue
		grep -qi 'com.apple.springboard' "$f" 2>/dev/null || continue
		name=$(basename "$f" .plist)
		tags=""
		d="$DYLIBS/$name.dylib"
		if [ -r "$d" ]; then
			grep -q -a 'CSCoverSheetViewController' "$d" 2>/dev/null && tags="$tags CoverSheet"
			grep -q -a 'CSMainPage\|CSScrollView\|CSCoverSheetView' "$d" 2>/dev/null && tags="$tags CoverSheetViews"
			grep -q -a 'SBLockScreenManager\|SBDashBoard' "$d" 2>/dev/null && tags="$tags LockScreen"
			grep -q -a 'sendEvent:\|_UIGestureEnvironment\|hitTest:withEvent:' "$d" 2>/dev/null && tags="$tags Touch"
		fi
		echo "  - $name${tags:+   [references:$tags]}"
	done
	echo "  (Tags are string references, not proof of a conflict. Non-HCG tweaks tagged CoverSheet/Touch are the ones"
	echo "   to disable first if the orb does not respond; see the 'Touches' line in Settings.)"
}

recovery() {
	echo "== Recovery readiness"
	command -v apt >/dev/null 2>&1 && ok "apt available (sudo apt remove $PKG)" || bad "apt not found"
	command -v sbreload >/dev/null 2>&1 && ok "sbreload available" || note "sbreload not found (use 'killall SpringBoard' or the package manager's respring)"
	[ -w "$PREFS" ] && ok "kill switch can be created: touch $KILL_SWITCH" || note "$PREFS not writable as this user (create the kill switch with sudo)"
	[ -e "$KILL_SWITCH" ] && note "kill switch is ON right now (Portal will do nothing until it is removed)"
	if grep -rqs "$CANDIDATE" /var/jb/etc/apt/sources.list.d/ /var/jb/etc/apt/sources.list 2>/dev/null; then
		ok "HCG Repo Candidate is configured (beta3 can be reinstalled: sudo apt install $PKG=0.1.0~beta3)"
	else
		note "HCG Repo Candidate not found in apt sources (Sileo may hold it elsewhere); keep a beta3 .deb copy via 'backup'"
	fi
	cached=$(ls /var/jb/var/cache/apt/archives/${PKG}_*.deb 2>/dev/null | tr '\n' ' ')
	[ -n "$cached" ] && ok "cached Portal packages: $cached" || note "no cached Portal .deb in apt's cache"
	audit=$(dpkg --audit 2>/dev/null)
	[ -z "$audit" ] && ok "dpkg --audit: clean" || bad "dpkg --audit reports problems: fix them before installing ($audit)"
	n=$(ls /var/mobile/Library/Logs/CrashReporter 2>/dev/null | grep -c '^SpringBoard')
	echo "  info  SpringBoard crash reports on the phone: $n"
	ls -t /var/mobile/Library/Logs/CrashReporter 2>/dev/null | grep '^SpringBoard' | head -3 | sed 's/^/          /'
	echo "  info  SSH: you are using it now. Keep this session open during the whole test."
}

verify_deb() {
	deb="$1"
	echo "== Package to install: $deb"
	[ -r "$deb" ] || { bad "file not readable"; return; }
	sum=$(sha256_of "$deb")
	[ "$sum" = "$EXPECTED_SHA256" ] && ok "SHA-256 $sum" || bad "SHA-256 $sum (expected $EXPECTED_SHA256): DO NOT INSTALL"
	size=$(wc -c < "$deb" | tr -d ' ')
	[ "$size" = "$EXPECTED_SIZE" ] && ok "size $size bytes" || bad "size $size bytes (expected $EXPECTED_SIZE)"
	v=$(dpkg-deb -f "$deb" Version 2>/dev/null)
	[ "$v" = "$EXPECTED_VERSION" ] && ok "Version $v" || bad "Version '$v' (expected $EXPECTED_VERSION)"
	a=$(dpkg-deb -f "$deb" Architecture 2>/dev/null)
	[ "$a" = iphoneos-arm64 ] && ok "Architecture $a" || bad "Architecture '$a'"
}

preflight() {
	echo "== HCG Portal $EXPECTED_VERSION preflight ($(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)) — read-only"
	device
	packages
	tweaks
	recovery
	echo "== Checks"
	[ "$(sysctl -n hw.cpusubtype 2>/dev/null)" = 2 ] && ok "arm64e" || bad "arm64e CPU"
	[ -d /var/jb ] && ok "rootless /var/jb" || bad "rootless /var/jb"
	[ "$(dpkg --print-architecture 2>/dev/null)" = iphoneos-arm64 ] && ok "dpkg iphoneos-arm64" || bad "dpkg iphoneos-arm64"
	dpkg-query -W -f '${Provides} ${Package}\n' 2>/dev/null | grep -qi mobilesubstrate && ok "mobilesubstrate provider (ElleKit)" || bad "mobilesubstrate provider"
	[ -n "$(pkgver preferenceloader)" ] && ok "PreferenceLoader" || bad "PreferenceLoader"
	cur=$(pkgver $PKG)
	case "$cur" in
		"") ok "Portal not installed (fresh install)" ;;
		0.1.0~beta3) ok "Portal 0.1.0~beta3 installed (upgrade; settings are kept)" ;;
		0.1.0~beta4) note "Portal 0.1.0~beta4 already installed" ;;
		*) note "Portal $cur installed (unexpected version: send this report first)" ;;
	esac
	[ -n "$1" ] && verify_deb "$1"
	if [ "$fail" = 0 ]; then
		w=""; [ "$warn" = 1 ] && w=" with warnings (read the WARN lines)"
		echo "Result: preflight passed$w. Send this report, then install ONLY after the owner's authorization."
	else
		echo "Result: preflight FAILED. Do not install."
	fi
}

status() {
	echo "== HCG Portal status ($(date -u +%H:%M:%SZ 2>/dev/null)) — read-only"
	echo "Installed:           $(pkgver $PKG || echo 'not installed')"
	[ -e "$KILL_SWITCH" ] && echo "Kill switch:         ON"
	if [ ! -r "$STATUS_PLIST" ]; then echo "No status yet ($STATUS_PLIST): respring once with Portal installed."; return; fi
	for k in tweakVersion buildID state detail visibility access touch phase previousSession lastAction host scene hooks; do
		printf '%-20s %s\n' "$k:" "$(plist_key "$STATUS_PLIST" "$k" | tr '\n' ' ')"
	done
	printf '%-20s %s\n' "counters:" "$(plist_key "$STATUS_PLIST" counters | tr '\n' ' ' | tr -s ' ')"
	printf '%-20s %s\n' "enabled (setting):" "$(plist_key "$SETTINGS_PLIST" enabled)"
	echo "(SpringBoard writes this shortly after each change; Settings > HCG Portal shows the same lines.)"
}

backup() {
	dir="${1:-/var/mobile/Documents/hcg-portal-backup-$(date +%Y%m%d-%H%M%S)}"
	echo "== Backup to $dir (copies only)"
	mkdir -p "$dir" || { echo "cannot create $dir"; exit 1; }
	for f in "$SETTINGS_PLIST" "$STATUS_PLIST"; do [ -e "$f" ] && cp -p "$f" "$dir/" && echo "  copied $f"; done
	dpkg-query -W 'com.hakmicapitalgroup.*' > "$dir/hcg-packages.txt" 2>/dev/null && echo "  wrote hcg-packages.txt"
	for d in /var/jb/var/cache/apt/archives/${PKG}_*.deb; do [ -e "$d" ] && cp -p "$d" "$dir/" && echo "  copied $d"; done
	if ! ls "$dir"/${PKG}_0.1.0~beta3_*.deb >/dev/null 2>&1 && [ "$(pkgver $PKG)" = 0.1.0~beta3 ]; then
		echo "  beta3 .deb not in apt's cache. To keep a rollback copy, run yourself (downloads only, installs nothing):"
		echo "    cd \"$dir\" && apt-get download $PKG=0.1.0~beta3"
	fi
	echo "Done. Nothing was installed or changed."
}

collect() {
	preflight "$1"
	echo
	status
}

case "$1" in
	preflight) preflight "$2" ;;
	status) status ;;
	collect) collect "$2" ;;
	backup) backup "$2" ;;
	*) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
