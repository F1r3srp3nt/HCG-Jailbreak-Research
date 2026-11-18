# Recovery and uninstall

HCG Portal adds one view to the Lock Screen. It changes no system file, no wallpaper, no passcode or security setting
and no other product's settings. Recovery is always "stop drawing" or "stop loading", and the normal Lock Screen —
including the unlock gesture, notifications, media controls, the flashlight and the camera — is exactly as before.
Use the first option that is available.

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

Three SpringBoard launches in a row that each end within 30 s while Portal is enabled → Portal stops and Settings shows
*Auto-disabled*. Collect `SpringBoard-…` crash logs (Settings › Privacy & Security › Analytics & Improvements ›
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

## Files HCG Portal creates

| Path | Content | Removed by |
|---|---|---|
| `/var/mobile/Library/Preferences/com.hakmicapitalgroup.portal.plist` | your settings and chosen apps | purge |
| `/var/mobile/Library/Preferences/com.hakmicapitalgroup.portal.status.plist` | last engine status, launch-guard counter | purge |
| `/var/mobile/Library/Preferences/com.hakmicapitalgroup.portal.disabled` | kill switch (only if you created it) | purge or `rm` |
