# Recovery and uninstall

HCG Halo only draws a view on the Home Screen. It changes no system files, no Home Screen layout and no security
settings. Recovery is therefore always "stop drawing" or "stop loading", and your Home Screen arrangement is never
altered. Use the first option that is available to you.

## 1. In Settings (the usual way)

Settings › HCG Halo:
- **Enable HCG Halo** → off. The border is removed immediately, with no respring. This is a standard switch,
  reachable with VoiceOver, Switch Control and Voice Control.
- **Reset Appearance**: back to the default look. Your presets, profile and calibration are kept.
- **Reset Calibration**: back to the profile's reference outline.

## 2. Package manager (Sileo / Zebra)

Packages › HCG Halo (Beta) › **Remove**, then respring when prompted. Remove keeps your settings and presets.
**Purge** also deletes HCG Halo's own preference files (`postrm`), and nothing else.

## 3. Kill switch over SSH (keep the package, load nothing)

```sh
ssh mobile@<device-ip>
touch /var/mobile/Library/Preferences/com.hakmicapitalgroup.halo.disabled
sbreload                      # or: killall -9 SpringBoard
```

On the next launch, HCG Halo does nothing and Settings shows *Kill switch on*. To undo it, delete the file and
respring.

## 4. Automatic stop (launch guard)

If three SpringBoard launches in a row each end within 30 seconds while Halo is enabled, Halo stops drawing and
Settings shows *Auto-disabled*. Collect the crash logs first (Settings › Privacy & Security › Analytics & Improvements
› Analytics Data, entries named `SpringBoard-…`). Then turn **Enable HCG Halo** off and on, and respring, to try
again.

## 5. SpringBoard will not start

- **Safe mode.** If SpringBoard crashes repeatedly, ElleKit may start it without tweaks. Remove HCG Halo over SSH
  from there (§6).
- **Reboot.** Rootless jailbreaks such as Dopamine are semi-untethered, so the phone starts as stock iOS with no
  tweaks. Before jailbreaking again, turn off tweak injection in the jailbreak app (the setting's name varies by
  version). Jailbreak, remove HCG Halo over SSH, turn tweak injection back on and do a userspace reboot.

## 6. Uninstall over SSH

```sh
ssh mobile@<device-ip>
sudo apt remove com.hakmicapitalgroup.halo        # or: sudo dpkg -r com.hakmicapitalgroup.halo
sbreload
```

Use this only as a last resort if dpkg itself is unavailable. It removes the injected library, but the package
database will still list the package until dpkg is fixed:

```sh
sudo rm /var/jb/Library/MobileSubstrate/DynamicLibraries/HCGHalo.dylib \
        /var/jb/Library/MobileSubstrate/DynamicLibraries/HCGHalo.plist
sbreload
```

## Files HCG Halo creates

| Path | Content | Removed by |
|---|---|---|
| `/var/mobile/Library/Preferences/com.hakmicapitalgroup.halo.plist` | your settings and presets | purge, or delete it by hand |
| `/var/mobile/Library/Preferences/com.hakmicapitalgroup.halo.status.plist` | last engine status, launch-guard counter | purge |
| `/var/mobile/Library/Preferences/com.hakmicapitalgroup.halo.disabled` | kill switch (only if you created it) | purge, or `rm` |
