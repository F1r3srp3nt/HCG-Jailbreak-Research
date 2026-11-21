# Device test checklist — HCG Animation Center 0.1.0~beta1 / 0.2.0~alpha1

**Nothing here has been done yet.** Record each row as *pass*, *fail* (with what you saw) or *not run*. A row passes
only when you saw it on the phone; Simulator results do not count here. Install and runtime are recorded separately.

Keep recovery ready before installing (`RECOVERY.md`): SSH access, and the kill switch command:

```bash
touch /var/mobile/Library/Preferences/com.hakmicapitalgroup.animationcenter.disabled
```

## 0. Confirm the device (read-only, before installing)

```bash
sh device-info.sh | tee animationcenter-device-report.txt
```

| | Value |
|---|---|
| Model identifier | |
| iOS version (build) | |
| Jailbreak + version | |
| ElleKit / PreferenceLoader | |
| HCG Halo / Vortex / Nexus versions installed | |
| Other SpringBoard tweaks (esp. wallpaper tweaks) | |
| Pre-checks result | |

Stop if pre-checks fail. Send the report for review.

## 1. Install (record separately from runtime)

| # | Step | Expected | Result |
|---|---|---|---|
| I1 | Add HCG Repo Candidate, install **HCG Animation Center (Beta)** 0.1.0~beta1 | installs without errors (gzip package) | |
| I2 | Confirm the file: `dpkg-query -W com.hakmicapitalgroup.animationcenter` and SHA-256 of the downloaded .deb | `0.1.0~beta1`, SHA-256 as in PROVENANCE | |
| I3 | Respring | nothing changes (off after installation); wallpaper normal | |
| I4 | Settings › HCG Animation Center opens | Status *Off*; Environment row filled in | |

## 2. Probe (before judging any background)

| # | Step | Expected | Result |
|---|---|---|---|
| P1 | Enable, then *Advanced › Write Hierarchy Probe* | footer shows a path under `/var/mobile/Library/HCGAnimationCenter/Diagnostics/` | |
| P2 | Copy that file off the phone and send it | — | |
| P3 | Note the *Environment* row text | — | |

## 3. Library and editor

| # | Step | Expected | Result |
|---|---|---|---|
| L1 | Import a video from Photos | progress, then a thumbnail with its length | |
| L2 | Import an animated GIF from Photos or Files | converted, thumbnail, "GIF" badge | |
| L3 | Try a still photo, a Live Photo, and a damaged file | each refused with a clear reason; nothing added | |
| L4 | Cancel an import of a long video | stops; nothing added | |
| L5 | Editor: trim, Fill / Fit / Crop (zoom + drag), Loop off, speeds 0.5×–2× | the preview follows each change; no sound | |
| L6 | Change the still frame, leave the editor, reopen | edits kept; thumbnail updated | |
| L7 | Export Preset… | share sheet with a `.hcgbackground` folder | |

## 4. Home Screen (implemented first)

| # | Step | Expected | Result |
|---|---|---|---|
| H1 | Apply a video to the Home Screen, Enable on | plays behind icons and dock within ~1 s, no respring; Now says *Playing* | |
| H2 | Tap icons, open folders, Today View, App Library, Spotlight | everything works; blurs show the video behind | |
| H3 | Open an app, return | paused while the app is open, resumes | |
| H4 | Lock, wait 10 s, unlock | Home paused while locked; resumes | |
| H5 | Fit with a landscape video; Crop with zoom | bars in the chosen colour; crop matches the preview | |
| H6 | Turn on Reduce Motion | still image shown; off again → plays | |
| H7 | Low Power Mode with each setting (still / play / system) | as chosen | |
| H8 | Restore System Wallpaper | normal wallpaper at once | |
| H9 | Leave it playing 10 minutes; note battery and heat | no stutter in SpringBoard; record observations | |

## 5. Lock Screen (experimental)

| # | Step | Expected | Result |
|---|---|---|---|
| K1 | Apply a background to the Lock Screen (accept *experimental*), lock | Now says which placement attached; record whether it is **visible** under the clock | |
| K2 | If not visible: *Lock Screen Placement › Cover Sheet Window*, lock again | record visibility | |
| K3 | Screen off / on while locked | pauses with the screen; plays again on wake | |
| K4 | Swipe to unlock; pull down Notification Centre while unlocked | record what the Lock background does during the animation | |
| K5 | Loop off on the Lock background | plays once each wake, then holds | |
| K6 | Same as Home | the Home background shows on the Lock Screen too | |

## 5b. Orientation and transformation (0.2.0~alpha1)

Use real camera files: a portrait video, a landscape video, a square one, a screen recording, and one filmed with the
phone held sideways. Note each file's size and what the editor's *Source* row says.

| # | Step | Expected | Result |
|---|---|---|---|
| O1 | Import each file | *Source* row shows the size and the detected metadata rotation; preview upright without touching anything | |
| O2 | Rotate 90° / 180° / 270°, flip H / V, on a landscape clip | preview turns clockwise / mirrors at once; still (Reduce Motion on) matches the video | |
| O3 | Fit, Fill / Crop, Stretch; zoom and drag in each | Fit: bars, whole region; Fill: covers; Stretch: exact fill, distorted | |
| O4 | Apply to Home Screen | SpringBoard shows exactly the preview (orientation, framing); icons unaffected | |
| O5 | Switch to *Lock Screen* in the editor, change rotation, apply to Lock | Lock Screen shows its own settings; Home unchanged | |
| O6 | Trim, speed 2×, loop off, still frame on a rotated background | all still apply; still is turned like the video | |
| O7 | Reset Transformations | back to the source as recorded | |
| O8 | Export a pack (*Export… › Animation Pack*), import it back | both placements return | |
| O9 | 4K landscape and 3840 × 1080 clips | 3840 × 1080 imported without *converted*; 4K converted, upright, same aspect | |
| O10 | 10 minutes playing a rotated 4K-converted clip | note battery, heat, any stutter (compare with H9) | |

## 6. Coexistence (each pair, then all together)

| # | Step | Expected | Result |
|---|---|---|---|
| C1 | HCG Halo on (Home Screen Only) | Halo's border above the video; both animate | |
| C2 | Halo *Always* (overlay window) | border above apps and Lock; video unaffected | |
| C3 | HCG Vortex: swipe pages with several effects | icons transform above the video; video does not move; no flicker | |
| C4 | Vortex + Halo + background together, 20 swipes | no frame glitches attributable to the background | |
| C5 | HCG Nexus panel open / close over the Home Screen | panel above; video keeps playing | |
| C6 | Halo's Nexus panel border with the background on | border and panel unaffected | |
| C7 | Disable Animation Center with the others on | others unchanged | |
| C8 | Disable each other tweak | background unchanged | |
| C9 | All four installed, respring 3 times | no crash, no *Auto-disabled* | |

## 7. Recovery

| # | Step | Expected | Result |
|---|---|---|---|
| R1 | Kill switch file + respring | Status *Disabled by kill switch*; normal wallpaper | |
| R2 | Delete the file + respring | works again | |
| R3 | Uninstall + respring | normal wallpaper; no leftovers in `/var/jb` | |
| R4 | Reinstall | library and choices are back | |
| R5 | Purge | `/var/mobile/Library/HCGAnimationCenter` and the preferences removed | |
