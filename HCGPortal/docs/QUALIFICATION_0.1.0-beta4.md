# HCG Portal 0.1.0~beta4: physical-device qualification

The owner runs this on the test iPhone. No step installs or changes anything unless the owner types it. The
installation step happens only after the owner's explicit authorization.

## The package

| | |
|---|---|
| File | `com.hakmicapitalgroup.portal_0.1.0~beta4_iphoneos-arm64.deb` |
| Size | 293,942 bytes |
| SHA-256 | `8a186d99a63d38c2bc4fb25d40bcfd773bbc042e5309063e0a87fc4d584164e4` |
| Source | `F1r3srp3nt/HCG-Jailbreak-Research` commit `1298ded` (branch `claude/portal-0.1.0-beta4-unlock-gate`) |
| CI | *HCG Portal build* run [44871433709](https://github.com/F1r3srp3nt/HCG-Jailbreak-Research/actions/runs/44871433709), artifact 14693943993 (zip SHA-256 `b3232c3f…aee1573`, as GitHub records it); *preview* run [44871433770](https://github.com/F1r3srp3nt/HCG-Jailbreak-Research/actions/runs/44871433770) on the same commit |
| Inside | build ID `1298ded2d930`, version string `0.1.0-beta4`, injection filter `com.apple.springboard` only. The Settings plists and `postrm` are identical to the source commit |

## 0. What you need

- The iPhone, unlocked, on the same network as a computer.
- SSH working as `mobile`, with a known `sudo` password. NewTerm works for every step except copying files.
- From this repository: the `.deb` above and `HCGPortal/scripts/qualify-beta4.sh`.
- About 45 minutes. Keep one SSH session open throughout: it is the way back if SpringBoard misbehaves.

## 1. Copy the files (on the computer)

```bash
scp com.hakmicapitalgroup.portal_0.1.0~beta4_iphoneos-arm64.deb qualify-beta4.sh mobile@IPHONE_IP:/var/mobile/Documents/
```

## 2. Preflight, read-only (on the iPhone)

```bash
cd /var/mobile/Documents && sh qualify-beta4.sh preflight com.hakmicapitalgroup.portal_0.1.0~beta4_iphoneos-arm64.deb | tee preflight.txt
```

It reports:
- the model, iOS and build, the Dopamine root and version hint;
- ElleKit, PreferenceLoader, Sileo/Zebra, every HCG package and the installed Portal version;
- every SpringBoard tweak, tagged where its binary references the Cover Sheet, the Lock Screen or touch handling
  (possible conflicts);
- recovery readiness: apt, sbreload, kill switch, Candidate source, cached `.deb`, `dpkg --audit`, crash reports;
- the `.deb`'s SHA-256, size, version and architecture.

**Stop if any line says FAIL.** Also note, by hand:
- the Dopamine version and its *Tweak Injection* setting (in the Dopamine app);
- whether a passcode, Face ID or Touch ID is set up.

Send `preflight.txt` and those notes. Do not continue until the report has been reviewed: other tweaks tagged
*CoverSheet* or *Touch* are reviewed before installing.

## 3. Preserve the way back (copies only)

```bash
sh qualify-beta4.sh backup /var/mobile/Documents/portal-backup
```

```bash
cd /var/mobile/Documents/portal-backup && apt-get download com.hakmicapitalgroup.portal=0.1.0~beta3
```

The second command only downloads beta 3 (if the Candidate source is configured) so it can be reinstalled offline. It
installs nothing.

## 4. Authorization gate

Only after the owner says "install beta 4 on this iPhone".

## 5. Install with Portal OFF first

1. Settings › HCG Portal › **Enable HCG Portal → off** (if beta 3 is installed and on). An upgrade keeps settings, so
   this makes the first launch of beta 4 an "off" launch, the path that crashed beta 1.
2. Install and respring:

```bash
sudo dpkg -i /var/mobile/Documents/com.hakmicapitalgroup.portal_0.1.0~beta4_iphoneos-arm64.deb
```

```bash
sbreload
```

Wait one minute after SpringBoard is back (the launch guard counts launches that end within 30 s). Then:

```bash
sh /var/mobile/Documents/qualify-beta4.sh status
```

Expected: `tweakVersion: 0.1.0-beta4`, `buildID: 1298ded2d930`, `state: disabled`, no Safe Mode.

## 6. Tests

Run `sh qualify-beta4.sh status` after each row marked **S** and keep the output. Rows Q1–Q8 run with Portal alone:
turn off HCG Animation Center, HCG Halo and HCG Nexus in their Settings pages, and respring once.

| # | Requirement | Steps | Pass when |
|---|---|---|---|
| Q1 | Install | §5 | no Safe Mode, no crash; status as above |
| Q2 | **Inaccessible while locked** (S) | Settings › HCG Portal › Enable on. Lock. Wake. Look at and touch the area below the clock. With VoiceOver on (optional), swipe through the Lock Screen | nothing of Portal is visible, touchable or announced. Status `visibility: locked`, `access: locked: …` |
| Q3 | Face ID matched, still on the Lock Screen (S) | Wake and look at the phone so the padlock opens, but do not swipe up | still nothing. Status `access: locked` |
| Q4 | Unlock: Face ID / Touch ID / passcode (S) | For each method available: lock, unlock with it, swipe up, then pull the Cover Sheet down from the top | the portal appears below the clock (brief opening animation). Status `visibility: visible`, `access: unlocked: every source reports unlocked` |
| Q5 | **Orb and menu** (S) | Tap the orb; tap outside; tap the orb again; wait 12 s | menu opens; tap outside closes it; it closes by itself after 12 s. Status `touch: … taps …, … activations`, **cancelled 0** |
| Q6 | **Menu buttons and actions** (S) | Devices; Nexus; HCG Apps (choose apps first in Settings › HCG Portal › HCG Apps) then one app; Backgrounds (Animation Center installed) | *Not connected*; *Not installed* or *Update needed*; the app ring, then the Cover Sheet closes and that app opens once; the Cover Sheet closes and Settings opens once. `lastAction` says what opened |
| Q7 | **Dismissal and ordinary gestures** | On the pulled-down Cover Sheet: swipe up to close; swipe left (widgets) and right (camera); scroll notifications; long-press the wallpaper; flashlight and camera buttons; start a swipe on the orb | everything behaves as without Portal; a swipe starting on the orb is a swipe |
| Q8 | **Relock** (S) | Pull down, open the menu, press the side button. Wake | menu and portal gone at once; the locked Lock Screen shows nothing. `counters` include `accessRevocations` |
| Q9 | **Stale action** (S) | Pull down, open the menu, tap Backgrounds and press the side button immediately; unlock | nothing opens. If something opened, `lastAction` and the timing matter: note them |
| Q10 | **Rapid lock/unlock** | 10× quickly: lock, wake, unlock, pull down, tap the orb, tap outside | no crash; never visible while locked; the orb always responds |
| Q11 | **Respring** (S) | With the portal on screen: `sbreload` | after the respring the locked Lock Screen shows nothing; unlock and pull down: exactly one portal |
| Q12 | **Reboot and first unlock** (S) | Reboot. Unlock once (needed to open Dopamine) and jailbreak. Dopamine restarts userspace: **before unlocking again**, wake, look, pull down on the Lock Screen. Then unlock and pull down | nothing before that unlock; the portal after it. Status after the unlock: `access: unlocked` |
| Q13 | Evidence | Settings › HCG Portal: screenshot the status section | *iPhone lock state*, *Touches*, *Breadcrumb*, *Diagnostics* lines are readable |

**HCG Animation Center coexistence:**

| # | Steps | Pass when |
|---|---|---|
| Q14 | Enable Animation Center (Home Screen and, if you use it, Lock Screen playback). Respring. Repeat Q2, Q4, Q5, Q6 (Backgrounds), Q8 | both work; Portal still appears only when unlocked; Backgrounds opens Settings once |
| Q15 | Disable Animation Center (its Enable off). Respring. Repeat Q2, Q5, Q8 | same as Q14. Backgrounds still opens Settings (the package is installed) |
| Q16 | Optional: remove Animation Center, respring, tap Backgrounds | *HCG Animation Center isn't installed*, nothing opens. Reinstall it afterwards if wanted |

Then, one at a time: enable HCG Halo, respring, repeat Q2, Q4 and Q5; then the same for HCG Nexus.

## 7. If something goes wrong

- **The orb does not respond (Q5):** send the `touch:` line.
  - `0 down` means touches never reach Portal: another tweak or view takes them. Disable non-HCG tweaks the preflight
    tagged *CoverSheet* or *Touch*, one at a time.
  - `cancelled > 0` with `last cancelled by …` names the recognizer that won.
- **Portal visible while locked, or something opens after a lock:** a security failure. Stop the test and turn Portal
  off at once:

```bash
touch /var/mobile/Library/Preferences/com.hakmicapitalgroup.portal.disabled && sbreload
```

  Then send the `status` output and the exact steps.
- **SpringBoard crashes or enters Safe Mode:** in the Safe Mode screen do not tap *Exit* yet. From SSH:

```bash
sudo apt remove com.hakmicapitalgroup.portal
```

  Then respring. Save the newest report from `/var/mobile/Library/Logs/CrashReporter/SpringBoard-*.ips`.
- **No SSH and SpringBoard keeps failing:** reboot (Dopamine is semi-untethered, so the phone starts without tweaks).
  In the Dopamine app turn *Tweak Injection* off, jailbreak, remove Portal, turn injection back on.

## 8. Rollback commands (this device)

| Goal | Command |
|---|---|
| Off at once, keep everything | Settings › HCG Portal › Enable off |
| Load nothing, keep the package | `touch /var/mobile/Library/Preferences/com.hakmicapitalgroup.portal.disabled && sbreload` |
| Undo the kill switch | `rm /var/mobile/Library/Preferences/com.hakmicapitalgroup.portal.disabled && sbreload` |
| Back to beta 3 (from the backup) | `sudo dpkg -i /var/mobile/Documents/portal-backup/com.hakmicapitalgroup.portal_0.1.0~beta3_iphoneos-arm64.deb && sbreload` |
| Back to beta 3 (from Candidate) | `sudo apt install --allow-downgrades com.hakmicapitalgroup.portal=0.1.0~beta3 && sbreload` |
| Remove Portal, keep settings | `sudo apt remove com.hakmicapitalgroup.portal && sbreload` |
| Remove Portal and its own files | `sudo apt purge com.hakmicapitalgroup.portal && sbreload` |

Beta 3 shows the portal on the locked Lock Screen and has the unresponsive orb. Roll back to it only to compare.

## 9. Report back

`preflight.txt`, the `status` outputs, the Settings screenshot (Q13), the Q1–Q16 results (pass / fail and notes),
and any `SpringBoard-*.ips` from the test.
