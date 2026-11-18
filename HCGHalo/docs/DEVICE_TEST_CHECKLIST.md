# HCG Halo 0.1.0~beta1: device test checklist

**First device: iPhone 11 Pro Max.** Its iOS version, build and jailbreak are **not confirmed**. Fill in step 0
first. Do not install until the step 0 report has been reviewed. Record installation and runtime as **separate**
results: a successful install says nothing about runtime.

Nothing in this checklist has been done yet.

## 0. Before installing: confirm the device (no changes made)

1. Copy `scripts/device-info.sh` to the phone and run it over SSH as `mobile`:
   `sh device-info.sh | tee halo-device-report.txt`. It is read-only.
2. Send the full report for review. Fill in:

| Field | Value |
|---|---|
| Date | |
| Tester | |
| Model and identifier (expect iPhone 11 Pro Max, `iPhone12,5`) | |
| iOS version (build) | |
| Jailbreak, version, rootless? | |
| Injector (ElleKit version) and PreferenceLoader version | |
| Package manager and version | |
| Other SpringBoard tweaks installed | |
| Package file and SHA-256 (must match the import manifest) | |

**Go only if** every pre-check passes, the device is rootless (`/var/jb`), `dpkg --print-architecture` is
`iphoneos-arm64`, and the iOS version is ≥ 15.0. Have recovery ready (`RECOVERY.md`) and a way in over SSH.

## A. Installation (record as `stage = "install"`)

| # | Step | Expected | Result |
|---|---|---|---|
| A1 | Add `https://repo.hakmicapitalgroup.com/repo/candidate/` and refresh | source loads; HCG Halo (Beta) listed | |
| A2 | Open the depiction | version `0.1.0~beta1`; **free**, no sign-in or payment; beta / not device-tested labels | |
| A3 | Install; accept only the expected dependencies (`mobilesubstrate` provider, `preferenceloader`, `firmware`) | dpkg finishes without errors. **Save the full log** | |
| A4 | Before respringing, the Home Screen is unchanged | Halo is off after installation | |
| A5 | Respring | SpringBoard returns normally | |

## B. Off by default

| # | Step | Expected | Result |
|---|---|---|---|
| B1 | Settings › HCG Halo opens | dark pane, preview, version `0.1.0-beta1`, build ID shown | |
| B2 | Status | *Off*. Footer shows "Reported by SpringBoard at …". Rendering: *Not drawing* | |
| B3 | Home Screen | no border | |

## C. Static mode on the Home Screen

| # | Step | Expected | Result |
|---|---|---|---|
| C1 | Turn **Enable HCG Halo** on and go to the Home Screen | a static cyan → violet gradient border appears **without a respring** | |
| C2 | Corners and notch | the line follows all four corners and wraps the notch. Note any gap or overlap, with screenshots | |
| C3 | Calibration (`PROFILES.md`) | values that make it exact: corner ___, notch width ___, depth ___, position ___ | |
| C4 | Touch: open apps, open and drag folders, enter jiggle mode, swipe pages, tap icons at the very edge and corners, use the dock | everything works exactly as without Halo | |
| C5 | System gestures: Home swipe, app switcher, Notification Centre, Control Centre, Spotlight, Today View, App Library | unchanged. Note where the border appears (Today View, App Library and folders are in the Home Screen window) | |
| C6 | VoiceOver on: swipe through the Home Screen | the border is never announced or focused | |
| C7 | Settings status | *Active*. Rendering *Hidden: app in front* (Settings is an app). App detection: *active (frontDisplayDidChange: hook)* | |

## D. Visibility and power

| # | Step | Expected | Result |
|---|---|---|---|
| D1 | Open an app, then return Home | border hidden in the app, back on the Home Screen | |
| D2 | Lock, then unlock | not shown on the Lock Screen; back after unlock | |
| D3 | Screen off for 30 s, on | nothing visible while off; resumes | |
| D4 | Reduce Motion on (Accessibility › Motion), with an animated mode | border becomes static immediately; animates again when off | |
| D5 | Low Power Mode with each policy (Static, Keep Animating, Hide) | behaves as named | |
| D6 | Rotate (if the Home Screen rotates on this device) | the border follows the physical edges; the notch stays at the physical top | |

## E. Modes and settings (each applies without a respring)

| # | Step | Expected | Result |
|---|---|---|---|
| E1 | Breathing | smooth pulse; speed slider changes the pace | |
| E2 | Colour Flow | colours travel around; direction switch reverses them; colour spacing repeats the palette | |
| E3 | Orbit, with 1–4 segments and the length slider | segments with comet tails travel smoothly, with no jump at the loop point | |
| E4 | Sci-Fi Circuit | dim trace, drifting segments, fast pulses, blinking nodes at corners and notch | |
| E5 | Colours: single, multiple, gradient; add, remove, reorder, picker; quick palettes | border and preview update | |
| E6 | Brightness, thickness, glow, inset | update live | |
| E7 | Presets: apply a built-in; save, rename, duplicate and delete your own | as described. The switch, profile and calibration are unchanged | |
| E8 | Reset Appearance / Reset Calibration | only their own settings reset | |
| E9 | Device Profile page | "Automatic — Coming soon" and planned models cannot be selected; iPhone 11 Pro Max is ticked | |

## F. Stability (record only what is observed; nothing is claimed in advance)

| # | Step | Result |
|---|---|---|
| F1 | 15 minutes of normal use with an animated mode: any SpringBoard crash, freeze or glitch? | |
| F2 | Battery and thermals: anything noticeable? (Not measured before this test) | |
| F3 | Crash logs (Analytics Data, `SpringBoard-…`) collected if anything went wrong | |

## G. Recovery and removal

| # | Step | Expected | Result |
|---|---|---|---|
| G1 | Enable off | border gone immediately | |
| G2 | Kill switch: `touch …/com.hakmicapitalgroup.halo.disabled`, respring | no border even with Enable on; status *Kill switch on*. Then `rm` and respring | |
| G3 | Remove the package, respring | Home Screen stock; Settings entry gone; settings file kept | |
| G4 | Reinstall, then purge | settings restored after reinstall; purge deletes only Halo's own preference files | |

## HCG Nexus panel border (0.2.0~beta1)

This is for 0.2.0~beta1 with HCG Nexus **0.3.1~beta1**, both from HCG Repo Candidate. Install them in either order,
then respring once. Nothing is installed automatically. Keep section G at hand. The 0.1.0~beta1 package is the
known-good baseline: reinstall it to go back.

| # | Step | Expected | Result |
|---|---|---|---|
| N0 | Halo 0.2.0~beta1 alone (no Nexus), target unchanged | Screen edge exactly as on 0.1.0~beta1; Border Target footer: *Requires compatible HCG Nexus* | |
| N1 | Nexus 0.3.1~beta1 alone (Halo removed) | Normal Nexus panel; Settings › HCG Nexus › Appearance › Halo border explains HCG Halo 0.2.0~beta1+ is needed | |
| N2 | Both installed, respring. Settings › HCG Halo › Nexus Panel Border | *HCG Nexus 0.3.1~beta1 · compatible*; preview shows the panel outline; *Replay Opening* traces it | |
| N3 | Same page from Settings › HCG Nexus › Appearance › Halo border | The same page and the same values | |
| N4 | Enable both; Border Target **HCG Nexus Panel**; open the panel | Light trace once around the panel, then Nexus Signature; no border on the screen edge; panel controls all respond | |
| N5 | Close by outside tap, then by the close button | The border fades with the panel; nothing is left on screen | |
| N6 | Start dragging the handle and let go before it opens (cancel); open and close quickly several times | No stray or orphaned border; the trace stops when the opening reverses | |
| N7 | Switch workspace in the panel | One soft pulse, no flash | |
| N8 | Rotate inside a landscape app with the panel open; type in a panel text field (keyboard) | The border follows the panel's new size and position | |
| N9 | Presets Reactor and Hologram; then each of the five modes; Thickness, Glow, Speed, Direction | Applies at once, without a respring; Reset Nexus Lighting restores Nexus Signature and leaves the screen edge unchanged | |
| N10 | Border Target **Both** | Screen edge on the Home Screen and the panel border while the panel is open | |
| N11 | Reduce Motion on | No trace; static border; Nexus crossfades | |
| N12 | Reduce Transparency on | Panel border without glow | |
| N13 | Low Power Mode with *Hide Border* | Panel border hidden | |
| N14 | Lock the phone with the panel open; unlock | Panel and border gone on lock; nothing left after unlock | |
| N15 | Turn Enable HCG Halo off with the panel open | The border disappears at once; the panel is unaffected | |
| N16 | Turn Enable HCG Nexus off | Panel and border gone; screen edge (if targeted) unaffected | |
| N17 | Halo's kill switch (G2) with target Both | No border anywhere | |

## Recording

Recording in HCG Repo is done by HCG Repo's maintainers, from this checklist
(`distribution/handoff/0.1.0-beta1/HCG-REPO-CHANGES.md` shows the format). A runtime **pass** needs sections A–E
and G to pass. Any SpringBoard crash, a touch or gesture regression, or an accessibility problem is a **fail**
(or a *partial*, with the reason) and goes in Known issues. Then update `PROFILES.md` as it describes.
