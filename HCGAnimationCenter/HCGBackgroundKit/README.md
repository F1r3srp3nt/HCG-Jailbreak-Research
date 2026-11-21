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

## Orientation and transformation (1.1)

A preset may carry `layout.transform` (rotate 0 / 90 / 180 / 270, flip, stretch; `PRESET-FORMAT.md`). The view
applies it as one affine transform to the still and the video layer, on top of the file's own orientation metadata —
nothing is re-encoded and layout edits never reload the decoder. In code: `preset.rotation`, `flipHorizontal`,
`flipVertical`, `stretch`, `resetTransform()`; the view reports `mediaFrame`, `mediaBounds` and `mediaTransform`.
Kit 1.0 (and apps built with it) ignore the transform and show the clip upright, so adopting 1.1 is optional.

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
Sources/HCGBackgroundKit/include/HCGBackgroundKit.h      umbrella header (HCG_BACKGROUND_KIT_VERSION "1.1.0")
Sources/HCGBackgroundKit/include/HCGBackgroundCore.h     C rules: limits, layout (and transformed layout, 1.1), sanitising, GIF timing
Sources/HCGBackgroundKit/include/HCGBackgroundPreset.h   the preset model (read / validate / write)
Sources/HCGBackgroundKit/include/HCGBackgroundView.h     the renderer
Schema/hcg-background-preset-v1.schema.json
Examples/Aurora.hcgbackground/preset.json                (media files not included)
```

The C core is unit-tested on Linux and macOS (`../tests/test_core.c`); the model and renderer in the iOS Simulator
(`../tests/test_runtime.m`).
