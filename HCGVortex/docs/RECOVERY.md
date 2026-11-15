# Recovery

HCG Vortex only changes how Home Screen pages are *drawn*. It modifies no
system files, no layout data and no security settings, so recovery is always
"stop loading the tweak" — your Home Screen arrangement is never altered.

Pick the first option that is available to you.

## 1. In Settings (tweak loads, something looks wrong)

Settings → HCG Vortex →
* **Enable Vortex** off — takes effect immediately, no respring; or
* **Restore Default Behavior** — stock animation, settings kept; or
* **Reset Preferences** — back to defaults.

## 2. Package manager (Sileo / Zebra)

Packages → HCG Vortex → **Remove** → respring when prompted.
"Remove" keeps your settings; "Purge" (if offered) also deletes them.

## 3. SpringBoard keeps crashing (safe mode)

If SpringBoard crashes repeatedly, ElleKit/Dopamine start SpringBoard in
**safe mode** without tweaks. From safe mode, open Sileo/Zebra and remove
HCG Vortex as in §2.

Dopamine also lets you disable tweak injection entirely from the Dopamine app
(Settings → "Tweak Injection" off, then userspace reboot). Re-enable it after
removing the package.

## 4. Kill switch over SSH (keep the package installed, load nothing)

```sh
ssh mobile@<device-ip>
touch /var/mobile/Library/Preferences/com.hakmicapitalgroup.vortex.disabled
killall -9 SpringBoard        # or: sbreload
```
On next launch HCG Vortex installs **no hooks** and reports "Kill switch on".
Undo with `rm` on the same file and respring.

## 5. Uninstall over SSH

```sh
ssh mobile@<device-ip>
sudo apt remove com.hakmicapitalgroup.vortex     # or: sudo dpkg -r com.hakmicapitalgroup.vortex
sbreload
```

Last resort if dpkg itself is unavailable (removes the injected library; the
package database will still list the package until dpkg is fixed):
```sh
sudo rm /var/jb/Library/MobileSubstrate/DynamicLibraries/HCGVortex.dylib \
        /var/jb/Library/MobileSubstrate/DynamicLibraries/HCGVortex.plist
sbreload
```

## 6. Remove settings manually

```sh
rm -f /var/mobile/Library/Preferences/com.hakmicapitalgroup.vortex.plist \
      /var/mobile/Library/Preferences/com.hakmicapitalgroup.vortex.status.plist \
      /var/mobile/Library/Preferences/com.hakmicapitalgroup.vortex.disabled
killall cfprefsd
```

## Files installed by the package

```
/var/jb/Library/MobileSubstrate/DynamicLibraries/HCGVortex.dylib
/var/jb/Library/MobileSubstrate/DynamicLibraries/HCGVortex.plist
/var/jb/Library/PreferenceBundles/HCGVortexPrefs.bundle/{HCGVortexPrefs,Info.plist,Root.plist,icon*.png}
/var/jb/Library/PreferenceLoader/Preferences/HCGVortexPrefs.plist
```
Created at runtime (user data, outside the package):
```
/var/mobile/Library/Preferences/com.hakmicapitalgroup.vortex.plist         (your settings)
/var/mobile/Library/Preferences/com.hakmicapitalgroup.vortex.status.plist  (engine status)
```

## What HCG Vortex never does

No network connections, analytics, telemetry or auto-updates; no changes to
authentication, passcode, Face ID, keychain or security settings; no writes
to protected system paths; no persistent changes to the Home Screen layout.
