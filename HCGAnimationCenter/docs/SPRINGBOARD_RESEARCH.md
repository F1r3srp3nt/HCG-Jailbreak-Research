# SpringBoard research: where an animated background can live

Status: **header-level research and Simulator stand-in tests done; the test device's iOS version, jailbreak and real
view hierarchy are NOT yet confirmed.** Every placement below is checked at run time, reported in Settings, and can be
switched in *Settings › Advanced* without a new build. The read-only *Write Hierarchy Probe* records what the device
really has (`src/HACProbe.m`).

## 1. What is known about the test environment

| Fact | Value | Source | Confirmed? |
|---|---|---|---|
| Device | iPhone 11 Pro Max (A13, arm64e) | HCG Vortex `docs/device-tests/2026-11-18-recording-0.3.0.md` (wallpaper text), Vortex/Halo docs | Model seen on video; not confirmed with `device-info.sh` |
| iOS | 17.4 is named in the Vortex brief; HCG-repo's Nexus listing names iPhone 13 Pro, iOS 16.5 | Vortex `docs/COMPATIBILITY.md` | **No.** Public Dopamine releases (rootless) are documented for iOS 15.0–16.x; 17.4 would need confirmation |
| Jailbreak | Dopamine (rootless, `/var/jb`), ElleKit, Zebra | Vortex `docs/INSTALL-FAILURE-0.1.0-beta1.md` | Reported, not confirmed |
| Runs on it today | HCG Halo 0.1.0~beta1 (owner report); HCG Vortex 0.3.0~beta1 (video) | Halo `package.toml`, Vortex recording review | Partial device evidence |
| Package format that installs | gzip `control.tar.gz` / `data.tar.gz` (lzma failed) | Vortex 0.1.0~beta2 | Yes, for Vortex |

Nothing is assumed from this table. **Step 0 of `DEVICE_TEST_CHECKLIST.md` runs `scripts/device-info.sh` (read-only)**
and the first enable writes a hierarchy probe before any background is judged.

The one strong inference: HCG Halo 0.1.0~beta1 draws inside **`SBHomeScreenWindow`** on this phone, and the Vortex
recording shows Halo's border on the Home Screen. So the Home Screen window class exists and accepts added subviews
there. That is why the Home Screen surface uses that window by default.

## 2. Sources and their limits

| Source | What | Used for |
|---|---|---|
| `MTACS/iOS-17-Runtime-Headers` @ `d1d960d` | class-dump of iOS **17.0.3** | wallpaper controller, PaperBoardUI, Cover Sheet |
| `xybp888/iOS-Header`, folder `14.5` | class-dump of iOS **14.5** | the same classes four versions earlier |
| HCG Halo 0.3.0 / HCG Vortex 0.3.1 sources (this repository) | what already works on the phone | Home Screen window, hook chain |
| `theos/sdks` iPhoneOS16.5.sdk | compiling | — |

No iOS 15 or 16 dump was available. Interfaces present in **both** 14.5 and 17.0.3 are treated as likely in between,
and still checked at run time.

## 3. Findings

### Wallpaper (both 14.5 and 17.0.3)

```
SBWallpaperController : NSObject
  + sharedInstance                         (14.5 ✓  17.0.3 ✓)
  - _wallpaperViewForVariant:(long long)   (14.5 ✓  17.0.3 ✓)   variant 0 = Lock, 1 = Home
  - setWallpaperHidden:variant:reason:     (17.0.3)              NOT used: it would change the system's wallpaper state
  - addWallpaperOverlay: / removeWallpaperOverlay:  (17.0.3)     NOT used: undocumented contract
  ivars (17.0.3): _wallpaperWindow, _wallpaperContainerView, _wallpaperViewController (PBUIWallpaperViewController),
                  _activeLockScreenPosterConfiguration … (PosterBoard)
PBUIWallpaperViewController (17.0.3): homescreenWallpaperView, lockscreenWallpaperView, sharedWallpaperView
PBUIPosterWallpaperViewController (17.0.3): PosterBoard path with replica / portal providers per variant
_SBWallpaperWindow : SBFWindow             the window behind everything
```

iOS 16 introduced PosterBoard: the Lock Screen wallpaper is rendered by a poster extension and SpringBoard shows it
through replica / portal views. Whether `_wallpaperViewForVariant:` still returns a live view for a poster wallpaper,
and whether a subview added to it appears on the Lock Screen, **cannot be decided from headers**. The probe answers it.

### Home Screen and Lock Screen windows (both versions)

```
SBHomeScreenWindow : SBWindow              icons, dock, widgets, folders, App Library; transparent over the wallpaper window
SBCoverSheetWindow : SBSecureWindow        the Lock Screen / Notification Centre (secure: drawn while locked)
-[SpringBoard frontDisplayDidChange:]      app in front (HCG Halo hooks it; hook chains are safe)
```

## 4. Decisions

| Decision | Why |
|---|---|
| **Never call a wallpaper-changing API.** No `setWallpaper…`, `setWallpaperHidden…`, `updateWallpaperForLocations…`, PosterBoard services, or wallpaper files. `validate.sh` fails if any such name is in either binary. | Turning the tweak off, a fault, or uninstalling must leave the user's wallpaper exactly as it was. Since it was never touched, there is nothing to restore. |
| **Draw in our own view, added to an existing view.** No method of a wallpaper, Home Screen or Cover Sheet class is hooked. | Smallest possible footprint; removing the view is a complete undo. |
| **Home Screen default: `SBHomeScreenWindow`, index 0.** | Proven on the phone by Halo; above the wallpaper window, below every icon, dock, widget, folder and Halo's border (Halo adds itself on top). Taps go straight through (the view never hit-tests). Dock and folder blurs sample what is behind them, so they blur the video. |
| Home Screen alternative: the Home **wallpaper view** (`_wallpaperViewForVariant:1`), on top. | Follows the wallpaper's own zoom and dimming if iOS animates that view. Optional until the probe shows it is live. |
| **Lock Screen default ladder: Lock wallpaper view, then `SBCoverSheetWindow` index 0.** | On classic wallpapers the Lock wallpaper view is what the Cover Sheet shows through. Where the wallpaper view is not used for drawing (likely with PosterBoard), the Cover Sheet window is the fallback. Both are checked at run time; neither is assumed to work. **Lock Screen is off by default and labelled experimental.** |
| Lock background hidden whenever the phone is unlocked. | A wallpaper view may be shared by both variants; hiding avoids the Lock video showing on the Home Screen. |
| One hook, `-[SpringBoard frontDisplayDidChange:]`, `%orig` first, installed only when enabled. | Pause behind apps, same as HCG Halo (proven hook chain). Without it the Home background pauses only when locked or dark. |
| Screen and lock state from `com.apple.springboard.hasBlankedScreen` / `com.apple.springboard.lockstate` (read-only). | Public Darwin notifications, no hook; same as Halo. Unreadable → assume lit / unlocked (fail open; the background then just keeps its normal rules). |

## 5. What the first device run must answer (probe + checklist)

1. iOS version and jailbreak (device-info.sh).
2. Home Screen: is the background visible behind the icons with `homeWindow`? (expected yes)
3. Lock Screen: does `_wallpaperViewForVariant:0` return a view in a window? Does a subview of it show on the Lock
   Screen, or is the Lock wallpaper drawn by a poster replica elsewhere? If not, does `coverSheet` show it?
4. Unlock animation and Notification Centre pull-down: what the Lock background does.
5. Window list and levels (probe) for HCG Nexus and Halo's overlay window.

The answers go into this file and decide whether 0.2 changes the default Lock placement.
