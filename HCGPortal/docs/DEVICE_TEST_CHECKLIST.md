# Device test — HCG Portal 0.1.0~beta3 (lifecycle hardening), 0.1.0~beta2 and 0.1.0~beta1

## 0.1.0~beta3: short test (do this first)

Before installing: if the phone is in Safe Mode, follow `RECOVERY.md` §0 first, and save the SpringBoard crash report.
Record at the top of your notes: **iPhone model, iOS version, jailbreak and version**, and the output of
`dpkg-query -W 'com.hakmicapitalgroup.*'` (every HCG package and its version).

**Portal alone.** Turn off or remove HCG Halo, HCG Animation Center and HCG Nexus for this part.

| # | Step | Expected |
|---|---|---|
| P1 | Install the 0.1.0~beta3 `.deb`; **respring with Portal off**; respring again | normal, no Safe Mode. Settings › HCG Portal: *Off*; *Diagnostics* empty or a clean previous launch |
| P2 | Enable HCG Portal; lock; wake | Status *Active*; portal below the clock |
| P3 | **The triggering sequence:** 10× lock → wake → tap the portal (menu opens) → tap outside (closes) → unlock with Face ID / swipe. Every 3rd time unlock with the menu still open. Twice, let the screen sleep on the Lock Screen and wake it | no respring, no Safe Mode; portal back each time; unlock gesture normal |
| P4 | On the Lock Screen: open the menu, tap Backgrounds, cancel the authentication; then tap it again and authenticate | cancel opens nothing; authenticating opens Settings once |
| P5 | Settings › HCG Portal: Enable off and on 5× (then lock and look) | portal gone at once when off, back when on; only one portal |
| P6 | Respring with Portal **on**; lock; wake | normal; portal back |
| P7 | Settings › HCG Portal: note *Lock Screen container* and *Diagnostics* | send both lines |

**Then one companion at a time.** Enable (or install) **one** of HCG Halo, HCG Animation Center, HCG Nexus, respring,
repeat P2–P3, then turn it off again before the next: Halo → Animation Center → Nexus.

**If SpringBoard crashes or enters Safe Mode at any step:** note the step number and which companions were on, follow
`RECOVERY.md` §0, send the newest `SpringBoard-*.ips` and, once Portal is back (or before removing it), the *Diagnostics*
line. The fix counts as verified only after P3 passes on this phone.


## 0.1.0~beta2 on the phone from the Safe Mode recording (superseded by the 0.1.0~beta3 test above)

| # | Step | Expected |
|---|---|---|
| B0 | If the phone is still in Safe Mode or Beta 1 is installed: exit Safe Mode, **remove 0.1.0~beta1** (`sudo apt remove com.hakmicapitalgroup.portal`), respring. Copy the `SpringBoard-*.ips` reports from around the incident (Settings › Privacy & Security › Analytics & Improvements › Analytics Data) | normal SpringBoard; crash reports saved |
| B1 | `sh device-info.sh` (read-only); confirm `Settings › HCG Portal` is absent | report saved |
| B2 | Install the 0.1.0~beta2 test `.deb` (`sudo dpkg -i …deb`), then **respring with Portal off** | SpringBoard starts normally, no Safe Mode. Settings › HCG Portal: Status *Off* |
| B3 | Respring once more, still off; lock, unlock, open Notification Centre, camera, flashlight | all normal; no portal |
| B4 | Enable HCG Portal | Status *Active* (or *Incompatible: inactive* with a reason: then stop and send the reason) |
| B5 | Lock the phone, wake it | portal below the clock; rings turning |
| B6 | Rows T1–T3, A1–A4, U1–U5 below | as listed |
| B7 | Respring with Portal **on** | starts normally; portal back on the Lock Screen |
| B8 | Recovery: Enable off (gone at once); kill switch file + respring (*Kill switch on*); remove the file, respring; finally uninstall + respring | Lock Screen exactly as before each time |

If SpringBoard crashes at any step: note the step, let the launch guard or Safe Mode stop it, remove the package over
SSH (`RECOVERY.md` §6) and send the newest `SpringBoard-*.ips`.

# First device test — HCG Portal 0.1.0~beta1

Nothing below has been done. Record each row as **pass / fail / not done** with the iOS version, jailbreak and any
screenshot. Install and runtime are separate results. Keep `RECOVERY.md` at hand.

## 0. Before installing (required)

| # | Step | Expected |
|---|---|---|
| D0 | `sh device-info.sh \| tee portal-device-report.txt` over SSH (read-only) and send the report | model, iOS, build, jailbreak and versions recorded; pre-checks pass |
| D1 | Confirm the facts in `COMPATIBILITY.md` (recorded: iPhone 11 Pro Max, iOS 17.4, Dopamine rootless) | match, or stop and report |
| D2 | Passcode and Face ID are set up on the phone | needed for the authentication rows |

## 1. Install

| # | Step | Expected |
|---|---|---|
| I1 | Add HCG Repo Candidate, install **HCG Portal (Beta)** 0.1.0~beta1 | unpacks (gzip members), no errors |
| I2 | Respring | nothing changes on the Lock Screen (off by default) |
| I3 | Settings › HCG Portal opens | dark page with live preview; Status *Off* |

## 2. Lock Screen

| # | Step | Expected |
|---|---|---|
| L1 | Enable HCG Portal, lock the phone, wake it | portal below the clock/widgets, rings turning slowly, particles sparse |
| L2 | Settings › HCG Portal › status footer → *Layout* | anchor class(es) and obstacle classes found on this iOS (copy the line) |
| L3 | Receive 1, 3, 6 notifications | portal stays clear: full → reduced/compact → hidden; never covers a notification |
| L4 | Play music (media controls), start a Live Activity (timer) | portal stays clear of them |
| L5 | Swipe to the camera page and to the Today page | portal moves away with the main page |
| L6 | Lock Screen widgets added / removed | portal stays below them |
| L7 | Position & Size: drag, change size, Reset | Lock Screen follows; Reset restores |
| L8 | Colours, brightness, speed, intensity | Lock Screen follows at once |

## 3. Interaction

| # | Step | Expected |
|---|---|---|
| T1 | Tap the portal | radial menu: Nexus, Backgrounds, Devices, HCG Apps |
| T2 | Tap outside the menu (on the clock, on a notification) | menu collapses; the notification tap still works |
| T3 | Devices | *Not connected*; no Face ID / passcode prompt |
| T4 | Nexus with HCG Nexus 0.3.1~beta1 installed | *Update needed* message; no prompt |
| T5 | VoiceOver on: portal and items announced as buttons | yes |

## 4. Authentication

| # | Step | Expected |
|---|---|---|
| A1 | Locked, Face ID covered: Backgrounds | iOS passcode screen appears; Settings › HCG Portal status *Authentication route* recorded |
| A2 | Enter the passcode | phone unlocks and **Settings** opens (HCG Animation Center listed) |
| A3 | HCG Apps → an app, then **Cancel** the passcode | nothing opens; the portal returns; status *Authentication cancelled* |
| A4 | HCG Apps → an app, Face ID succeeds | exactly that app opens |
| A5 | Start A3, press the side button (screen off), unlock normally | nothing opens on its own |
| A6 | Wrong passcode several times | iOS's own lockout applies; Portal does nothing else |

## 5. Unlock and system gestures

| # | Step | Expected |
|---|---|---|
| U1 | Swipe up from the bottom (Face ID unlocked) | unlocks normally, no delay; brief opening flourish |
| U2 | Same with *Opening Animation on Unlock* off, and with Reduce Motion | no flourish |
| U3 | Pull down Notification Centre while using an app | no portal |
| U4 | Flashlight and camera buttons on the Lock Screen | work |
| U5 | Swipe up starting on the portal | unlock gesture still works |
| U6 | Raise to wake / tap to wake | portal resumes; paused while dark |

## 6. Power and recovery

| # | Step | Expected |
|---|---|---|
| P1 | Low Power Mode on (default *Static*), then *Economy*, then *Hide* | static / slow / gone |
| P2 | Reduce Motion on | static portal |
| R1 | Enable off | portal gone immediately; Lock Screen normal |
| R2 | Kill switch file + respring | *Kill switch on*; nothing drawn |
| R3 | Remove the package + respring | Lock Screen exactly as before |

Battery and performance impact are **not measured**; note anything unusual.
