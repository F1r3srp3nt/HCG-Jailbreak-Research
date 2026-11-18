# HCG Animation Center

Animated backgrounds for the Home Screen and Lock Screen, from your own videos and GIFs — a rootless jailbreak tweak
by Hakmi Capital Group, with a reusable preset component for HCG apps.

> **0.1.0~beta1 — free public beta demo, HCG Repo Candidate only. Build-validated and Simulator-tested; not yet
> tested on a device.** See `docs/TESTING.md` for exactly what has and hasn't been verified.

## What it does

- **Media library** in Settings: import videos and animated GIFs from Photos or Files, with thumbnails, durations and
  Home / Lock badges. GIFs are converted once to H.264; videos keep their video track only (backgrounds never play
  sound). Damaged, unsupported or oversized files are refused with a reason.
- **Editor with live preview** (the same renderer SpringBoard uses, at the screen's aspect, with icon or clock
  overlays): trim, **fill / fit / crop** (zoom and drag), loop or play once, speed 0.5×–2×, still frame, name.
- **Separate backgrounds for the Home Screen and the Lock Screen** (or the same one). Home Screen first; Lock Screen
  is experimental and off until you turn it on.
- **Behaves like a wallpaper should:** pauses behind apps, when locked (Home) or unlocked (Lock), and when the screen
  is off; frees the decoder after 8 s hidden; follows Reduce Motion and Low Power Mode (still image, keep playing, or
  system wallpaper); shows the still when the device is hot or the video can't play.
- **Recovery:** master switch, *Restore System Wallpaper*, kill switch file, automatic disable after repeated
  SpringBoard crashes. **Your system wallpaper is never modified**, so turning it off or uninstalling shows it again.
- **HCGBackgroundKit:** the versioned **HCG background preset** format (v1) and renderer as a Swift package for HCG
  apps; independent of the tweak.
- **AI backgrounds (later phase):** the HCG AI interface — central access controls, preview first, explicit apply. Not
  connected in this beta.

## Documentation

| | |
|---|---|
| `docs/LIVE-BACKGROUNDS.md` | what is supported, what is refused, the Live Photos investigation |
| `docs/SPRINGBOARD_RESEARCH.md` | the environment as known, header evidence, why each placement / hook |
| `docs/ARCHITECTURE.md` | processes, lifecycle, renderer, files on the device |
| `docs/PRESET-FORMAT.md`, `HCGBackgroundKit/README.md` | the reusable format and component; web renderer notes |
| `docs/AI-BACKGROUNDS.md` | the later-phase AI interface |
| `docs/COMPATIBILITY.md` | requirements, surfaces, coexistence with Halo / Vortex / Nexus |
| `docs/RECOVERY.md` | every way back to the normal wallpaper |
| `docs/BUILD.md`, `docs/TESTING.md` | building, validation, test and preview results |
| `docs/DEVICE_TEST_CHECKLIST.md` | the first device test, step by step |
| `distribution/` | HCG Repo candidate import kit and handoff |

## Build

```bash
THEOS=~/theos scripts/install-sdk.sh
```

```bash
THEOS=~/theos scripts/build.sh
```

The distributable package is the macOS / Xcode build from the **HCG Animation Center build** workflow; Linux builds
(with allemande) are for testing only. Details in `docs/BUILD.md`.

## Package

| | |
|---|---|
| Identifier | `com.hakmicapitalgroup.animationcenter` |
| Name | HCG Animation Center (Beta) |
| Version | `0.1.0~beta1` |
| Architecture | `iphoneos-arm64` (rootless), fat arm64 + arm64e |
| Depends | `mobilesubstrate (>= 0.9.5000)`, `preferenceloader`, `firmware (>= 15.0)` |
| Licence | Proprietary freeware (`LICENSE`) |
