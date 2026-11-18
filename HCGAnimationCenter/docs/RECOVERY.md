# Recovery

HCG Animation Center **never changes your system wallpaper**. It draws its own view on top of it. Every way of
turning it off simply removes that view, so the normal wallpaper is what you see. `validate.sh` fails the build if
either binary references an API that sets, hides or reloads the system wallpaper.

| Situation | What to do | Result |
|---|---|---|
| You want your normal wallpaper back | Settings › HCG Animation Center › **Restore System Wallpaper** (or turn **Enable** off) | Immediate, no respring. Library and choices kept |
| One screen only | Turn **Home Screen Background** or **Lock Screen Background** off, or choose **None (system)** | Immediate |
| A background looks wrong or a video is damaged | Nothing: it falls back to its still image, or to the system wallpaper | Settings › Now says why |
| Settings can't be opened | Over SSH: `touch /var/mobile/Library/Preferences/com.hakmicapitalgroup.animationcenter.disabled`, then respring (`killall -9 SpringBoard` or the package manager) | Does nothing at all until the file is deleted |
| SpringBoard crashes repeatedly | Nothing: after **3** SpringBoard launches in a row that end within 30 s while enabled, it disables itself (*Auto-disabled*). Turn Enable off and on, then respring, to try again | Stays off |
| Still stuck | Reboot. Rootless jailbreaks such as Dopamine are semi-untethered: the phone starts as stock iOS without tweaks. Remove the package before re-enabling tweak injection | Stock |
| Uninstall | Remove **HCG Animation Center (Beta)** in your package manager, respring | Normal wallpaper. Library and settings are kept for a reinstall |
| Remove everything | **Purge** the package (`apt purge com.hakmicapitalgroup.animationcenter`) | Also deletes the preferences, the kill switch file and `/var/mobile/Library/HCGAnimationCenter` (your imported copies; the originals in Photos / Files are untouched) |

Checks in CI (`scripts/validate.sh`): `dpkg -i` then `dpkg -r` in a scratch root leaves no file behind; `postrm` deletes
only this package's own preferences and library, and only on purge.
Simulator preview: *Disabled → every background view removed, the system wallpaper untouched and visible.*
