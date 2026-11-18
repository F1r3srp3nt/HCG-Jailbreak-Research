# HCGBackgroundKit

Opt-in component for HCG apps: reads, validates and writes **HCG background presets** (format version 1) and renders
them with `HCGBackgroundView`. It is the same code HCG Animation Center uses in SpringBoard and in its Settings preview.

- **No dependency on the tweak.** An app that adopts it works the same with or without HCG Animation Center installed,
  on jailbroken and stock devices.
- No network access, no Photos access, no private API.
- iOS 15+, Objective-C (usable from Swift), ARC.

Format specification: `../docs/PRESET-FORMAT.md`. Schema: `Schema/hcg-background-preset-v1.schema.json`.

## Add it during development

Xcode › File › Add Package Dependencies… › **Add Local…** › select this `HCGBackgroundKit` folder. Then:

```swift
import HCGBackgroundKit

let folder = Bundle.main.url(forResource: "Aurora", withExtension: "hcgbackground")!
let preset = try HCGBackgroundPreset(contentsOf: folder)   // refuses newer major versions and unsafe file names
let background = HCGBackgroundView(frame: view.bounds)
background.autoresizingMask = [.flexibleWidth, .flexibleHeight]
background.setPreset(preset, folder: folder)
background.display = .playing                              // .paused, .still, .none
view.insertSubview(background, at: 0)
```

Objective-C:

```objc
@import HCGBackgroundKit;

NSError *error = nil;
HCGBackgroundPreset *preset = [HCGBackgroundPreset presetWithContentsOfURL:folder error:&error];
if (!preset) { /* show your normal background; error.localizedDescription says why */ }
HCGBackgroundView *background = [[HCGBackgroundView alloc] initWithFrame:self.view.bounds];
[background setPreset:preset folder:folder];
background.display = HCGBackgroundDisplayPlaying;
```

## Responsibilities of the host app

| | |
|---|---|
| Visibility | Set `display` to `.paused` / `.none` when the background is not on screen (the view does not watch your app's lifecycle beyond AVFoundation's background policy). |
| Reduce Motion | Use `.still` when `UIAccessibility.isReduceMotionEnabled` (unless your product decides otherwise). |
| Memory | Call `releasePlayer()` on memory warnings or when hidden for a while; the still stays. |
| Errors | Implement `HCGBackgroundViewDelegate`: a damaged or missing video is reported once and the view falls back to the still. |
| Bundling | Ship the `.hcgbackground` folder (preset.json + media + still) in your bundle, or download it into your own container. File names inside are plain names; the kit never reads outside the folder. |

## Files

```
Package.swift
Sources/HCGBackgroundKit/include/HCGBackgroundKit.h      umbrella header (HCG_BACKGROUND_KIT_VERSION "1.0.0")
Sources/HCGBackgroundKit/include/HCGBackgroundCore.h     C rules: limits, layout, sanitising, GIF timing
Sources/HCGBackgroundKit/include/HCGBackgroundPreset.h   the preset model (read / validate / write)
Sources/HCGBackgroundKit/include/HCGBackgroundView.h     the renderer
Schema/hcg-background-preset-v1.schema.json
Examples/Aurora.hcgbackground/preset.json                (media files not included)
```

The C core is unit-tested on Linux and macOS (`../tests/test_core.c`); the model and renderer in the iOS Simulator
(`../tests/test_runtime.m`).
