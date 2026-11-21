# Recovery and uninstall

HCG Portal adds one view to the Lock Screen. It changes no system file, no wallpaper, no passcode or security setting
and no other product's settings. Recovery is always "stop drawing" or "stop loading", and the normal Lock Screen —
including the unlock gesture, notifications, media controls, the flashlight and the camera — is exactly as before.
Use the first option that is available.

## 0. From Safe Mode (do this before installing anything else)

SpringBoard's Safe Mode starts without tweaks, so HCG Portal is not running while you are in it.

1. Tap **Exit Safe Mode** (or **Restart SpringBoard**) only **after** step 2, or SpringBoard may load Portal again.
2. Turn Portal off for good, in whichever way is available:
   - **Sileo / Zebra:** open it (it still works in Safe Mode), remove **HCG Portal (Beta)**, confirm.
   - **NewTerm / SSH:** `sudo apt remove com.hakmicapitalgroup.portal`
   - **Keep the package, load nothing:** `touch /var/mobile/Library/Preferences/com.hakmicapitalgroup.portal.disabled`
3. Now exit Safe Mode / respring. The Lock Screen is the normal one.
4. Before trying another build, save the crash report (see *Crash reports* below) and run
   `dpkg-query -W com.hakmicapitalgroup.portal` so the exact version installed at the time is known.

If SpringBoard keeps returning to Safe Mode after Portal is removed, Portal is not the cause of that loop: remove the
most recently installed or updated tweak next.

## Crash reports

- **On the phone:** Settings › Privacy & Security › Analytics & Improvements › Analytics Data. Open the newest
  `SpringBoard-<date>.ips` from around the incident, tap Share, and save or send it.
- **Over SSH:** `ls -lt /var/mobile/Library/Logs/CrashReporter/ | head` and copy the `SpringBoard-*.ips` files from
  around the incident.
- After the next launch, Settings › HCG Portal › *Diagnostics* shows the step Portal was on when SpringBoard last
  stopped (0.1.0~beta3 and later).

## 1. In Settings (the usual way)

Settings › HCG Portal:
- **Enable HCG Portal** → off. The portal is removed at once, with no respring. Any authentication still waiting is
  discarded. This is a standard switch, reachable with VoiceOver, Switch Control and Voice Control.
- **Reset Appearance**, **Position & Size › Reset**, **Reset All HCG Portal Settings** (which also turns it off).

## 2. Package manager (Sileo / Zebra)

Remove **HCG Portal (Beta)**, then respring. Remove keeps your settings; **Purge** also deletes HCG Portal's own
preference, status and kill-switch files (`postrm`), and nothing else.

## 3. Kill switch over SSH (keep the package, load nothing)

```sh
ssh mobile@<device-ip>
touch /var/mobile/Library/Preferences/com.hakmicapitalgroup.portal.disabled
sbreload
```

Settings then shows *Kill switch on*. Delete the file and respring to undo.

## 4. Automatic stop (launch guard)

Three SpringBoard launches in a row that each end within 30 s with Portal installed (0.1.0~beta3: enabled or not;
earlier builds: only while enabled) → Portal does nothing and Settings shows *Auto-disabled*. Collect `SpringBoard-…` crash logs (Settings › Privacy & Security › Analytics & Improvements ›
Analytics Data) first, then turn Enable off and on and respring to try again.

## 5. SpringBoard will not start

- **Safe mode:** ElleKit may start SpringBoard without tweaks after repeated crashes; remove Portal over SSH (§6).
- **Reboot:** rootless jailbreaks such as Dopamine are semi-untethered, so the phone starts as stock iOS with no
  tweaks. Before re-jailbreaking, turn off tweak injection in the jailbreak app, jailbreak, remove Portal over SSH,
  then turn tweak injection back on.

## 6. Uninstall over SSH

```sh
ssh mobile@<device-ip>
sudo apt remove com.hakmicapitalgroup.portal
sbreload
```

## 7. Installing a test build, and rolling back (0.1.0~beta4)

Install a test build only after the owner has approved it. Nothing is installed on a device automatically.

1. Copy the `.deb` to the iPhone (for example over SSH, or AirDrop to Filza) and check it before installing:
   `shasum -a 256 com.hakmicapitalgroup.portal_0.1.0~beta4_iphoneos-arm64.deb`. It must match the published SHA-256.
2. Install it: `sudo dpkg -i com.hakmicapitalgroup.portal_0.1.0~beta4_iphoneos-arm64.deb` (or open it in Sileo).
   Respring. Portal is off after installing and keeps your existing settings.
3. Turn it on in Settings › HCG Portal. It appears only after you unlock and pull down the Cover Sheet.

To roll back, use the first option that fits:
- **Turn it off:** Settings › HCG Portal › Enable off. It is gone at once.
- **Remove it** (recommended if anything goes wrong): `sudo apt remove com.hakmicapitalgroup.portal`, then
  `sbreload`. Settings are kept. `sudo apt purge com.hakmicapitalgroup.portal` also removes them.
- **Stop it loading but keep it installed:** the kill switch (§3).
- **Go back to 0.1.0~beta3** (HCG Repo Candidate): `sudo apt install com.hakmicapitalgroup.portal=0.1.0~beta3`,
  then respring. Note that 0.1.0~beta3 shows the portal on the **locked** Lock Screen and asks for authentication per
  item. It also has the unresponsive-tap problem this build addresses. Use it only to compare, not as the fix.

If SpringBoard enters Safe Mode after installing, follow §0.

## Files HCG Portal creates

| Path | Content | Removed by |
|---|---|---|
| `/var/mobile/Library/Preferences/com.hakmicapitalgroup.portal.plist` | your settings and chosen apps | purge |
| `/var/mobile/Library/Preferences/com.hakmicapitalgroup.portal.status.plist` | last engine status, launch-guard counter | purge |
| `/var/mobile/Library/Preferences/com.hakmicapitalgroup.portal.disabled` | kill switch (only if you created it) | purge or `rm` |
