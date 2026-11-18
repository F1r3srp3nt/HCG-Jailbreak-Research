# HCG Nexus panel border

HCG Halo 0.2.0~beta1 can draw its border around the **HCG Nexus** panel as well as, or instead of, the screen
edge. HCG Nexus (`com.hakmicapitalgroup.hcgnexus`) is a separate package. Both remain independently installable,
and neither depends on the other.

The responsibilities are split:

- **HCG Nexus** provides a versioned, declarative **border definition** that it installs on the phone. It also
  provides a small runtime **interface**: the live panel's border host view and its open, close, geometry and
  workspace events.
- **HCG Halo** owns everything visual: the renderer, modes, colours, glow, presets, effects and settings. It
  also loads and validates the installed Nexus definition.

The installed file **describes** the integration. Where the border is drawn always comes from the **running panel**,
never from the file.

The same contract is documented from Nexus's side in HCG-Nexus `docs/HALO-BORDER.md`.

## Compatibility and install order

> **Install HCG Nexus 0.3.1~beta1 with HCG Halo 0.2.0~beta1.** Nexus 0.3.1~beta1 is the combined Nexus release: the
> redesign, Command Mode and this border interface. 0.2.2~beta1, the interface on the 0.2.1 code, also works but is
> superseded. 0.3.0~beta1 never shipped. Halo checks for the interface and the definition, not for a version number.

| HCG Halo | HCG Nexus | Panel border |
|---|---|---|
| 0.2.0~beta1 | **0.3.1~beta1** (recommended), 0.2.2~beta1, or a later build that includes border interface 1 and the definition | Available |
| 0.2.0~beta1 | a build without the border interface (0.2.1~beta1 and earlier; the unshipped 0.3.0~beta1) | Off: *Requires compatible HCG Nexus* |
| 0.2.0~beta1 | absent, disabled, or 0.2.1~beta1 and earlier | Off: *Requires compatible HCG Nexus* + reason. Screen edge unaffected |
| 0.1.0~beta1 | any | No panel border (screen edge only) |

Install in either order and **respring once** after installing or updating either one. Neither package declares
`Depends` on the other.

## The installed resource Halo reads

```
<jbroot>/Library/PreferenceBundles/HCGNexusPrefs.bundle/HaloBorder.plist
(rootless: /var/jb/Library/PreferenceBundles/HCGNexusPrefs.bundle/HaloBorder.plist)
```

How Halo finds it (`HaloNexusLink`, `HaloNexusDefinition`):

1. **In SpringBoard:**
   - It asks the running Nexus: `+[HCGNexusBorderInterface borderDefinitionPath]`. Nexus derives the path
     from its own loaded image.
   - Only if that method is missing does it fall back to the same path derived from Halo's own loaded image
     (`…/Library/MobileSubstrate/DynamicLibraries/HCGHalo.dylib` or `…/usr/lib/TweakInject/HCGHalo.dylib`
     → `<jbroot>`).
2. **In Settings:** the sibling bundle of `HCGHaloPrefs.bundle`, i.e. `../HCGNexusPrefs.bundle/HaloBorder.plist`.

Halo **never** bundles, copies or downloads this file. `scripts/validate.sh` fails if any `HaloBorder.plist` exists
in this project or in the package.

**Validation** (`HaloNexusDefinition`):

- The file must be a regular file of at most 16 KB.
- Its property list is parsed as data only; nothing in it is executed.
- Schema 1 is strict:
  - exact keys; unknown keys are rejected;
  - types;
  - ranges (corner radius 0…64, outset 0…12, glow margin 8…64);
  - known capabilities;
  - schema and interface versions;
  - Nexus version ≥ 0.2.2~beta1.

These are the same rules as Nexus's `scripts/check_halo_border.py`. Any problem leaves the panel border off,
with *Requires compatible HCG Nexus: <reason>* shown in both Settings pages.

The file is re-read and re-validated whenever settings change, Nexus (re)installs its panel, or the Settings page
opens. If the file's `nexusVersion` differs from the running Nexus's `nexusVersion`, then Nexus was updated
without a respring. The border stays off and asks for a respring.

## The runtime interface (version 1)

- **Lookup:** Halo finds `HCGNexusBorderInterface` with `NSClassFromString` (no link-time dependency).
- **Version:** it requires `+interfaceVersion == 1`.
- **Selectors:** it checks every selector before sending it.
- **Attachment:** it adds one `HaloPanelBorderView` to `+activeInterface.borderHostView`. That is a
  non-interactive view inside the panel, with the panel's bounds.

Events arrive as the in-process notification `com.hakmicapitalgroup.hcgnexus.border-event`, on the main thread
and delivered synchronously. Each one is accepted only if:

- the sender is the active interface (for `installed`) or the interface Halo is attached to (all other events);
- `userInfo` has exactly the expected types: `event` is one of the eight known names, `generation` is a number,
  `duration` is finite and between 0 and 5 s, and `interfaceVersion` is 1.

Everything else is ignored.

| Event | Halo does |
|---|---|
| `installed` | re-read the definition and attach |
| `will-open` | show; play the opening trace if enabled (not with Reduce Motion / crossfade) |
| `did-open` | settle in the selected mode |
| `will-close` | cancel the trace (this also handles an opening reversed mid-way). With *Fade With Panel* the border fades with the panel because it is inside it; otherwise it is hidden at once |
| `did-close` | hide and freeze the animation clock |
| `geometry` | re-layout from the live host bounds and corner radius |
| `workspace-changed` | one soft pulse (about 0.5 s, peak 50 % opacity: never a flash) |
| `removed` | remove the border view |

## Rendering

- **Placement.** The light runs `outset` points outside the live panel edge (2 pt from the definition),
  concentric with the panel's corners.
- **Glow room.** The view extends `glowMargin` (36 pt) beyond the panel, so the glow is not clipped.
- **Interior mask.** With `clipInterior`, an even-odd mask removes the panel's interior, so the light can
  never cover the panel's content or controls.
- **No touches.** The view returns nil from hit-testing and is hidden from accessibility.
- **Following the panel.** The view lives inside the panel, so it inherits the panel's slide, alpha, rotation
  and resizing with no per-frame work. It cannot outlive the panel.
- **Renderer.** It is the same Core Animation renderer as the screen edge, with all five modes (Static,
  Breathing, Colour Flow, Orbit, Sci-Fi Circuit).
- **When it draws.** Only while the panel is shown. It is hidden and frozen (layer speed 0) when the panel is
  closed, when the screen is off, or when *Low Power Mode → Hide Border* applies.
- **Accessibility.** Reduce Motion makes every mode static and skips the trace. Reduce Transparency removes the
  glow.
- **Disabling.** The master switch, the kill switch, the crash-loop guard and the fault fallback all remove it.

## Settings

- **HCG Halo › Border Target:** Screen Edge / HCG Nexus Panel / Both. The footer shows whether a compatible
  Nexus is installed and what SpringBoard reports.
- **HCG Halo › Nexus Panel Border** opens a page, also opened from Settings › HCG Nexus › Appearance › Halo
  border (Nexus pushes `HaloNexusBorderController` from this bundle, contract `HCGHaloNexusIntegration` = 1).
  The page has:
  - a live preview on the panel outline from the installed definition, with *Replay Opening*;
  - status;
  - the target;
  - *Match Screen Edge*;
  - presets (Nexus Signature, Reactor, Hologram, then all others);
  - mode, colour style, colours, brightness, thickness, glow, speed, soft pulse, segments, segment length and
    direction;
  - the three effects;
  - **Reset Nexus Lighting**, which resets only the panel's look and effects.

Changes appear in the preview at once. SpringBoard applies them immediately; slider changes are sent on release.

## Switching from HCG Nexus (HCG Halo 0.2.1~beta1, contract `HCGHaloNexusControl` 1)

HCG Nexus 0.3.2~beta1 shows **Use HCG Halo border** in its Appearance settings (Settings › HCG Nexus and the
panel's own Settings), with the states *Not installed*, *Incompatible*, *Disabled*, *Ready* and *Active*.
HCG Nexus never writes HCG Halo's settings. It calls HCG Halo's own class:

```objc
@interface HaloNexusControl : NSObject                    // src/HaloNexusControl.h
+ (NSInteger)controlVersion;                               // 1
+ (NSDictionary *)nexusBorderStatus;                       // enabled, target, panelBorderOn, state, nexusState, nexusDetail, haloVersion
+ (BOOL)setNexusBorderEnabled:(BOOL)enabled error:(NSString **)error;
@end
```

- It is compiled into **both** binaries: HCG Nexus finds it with `NSClassFromString` in SpringBoard
  (`HCGHalo.dylib`) and in Settings (`HCGHaloPrefs.bundle`, whose Info.plist declares `HCGHaloNexusControl` = 1).
- **The rules never turn the screen edge on:**

  | Before | Turn on | Turn off |
  |---|---|---|
  | HCG Halo off | enabled = on, target = *HCG Nexus Panel* | no change |
  | on, *Screen Edge* | target = *Both* | no change |
  | on, *HCG Nexus Panel* | no change | enabled = off |
  | on, *Both* | no change | target = *Screen Edge* |

- **Refused, nothing written:** while the kill switch file exists or the launch guard has turned HCG Halo off.
  Only the user lifts those, in HCG Halo.
- After writing, it posts `com.hakmicapitalgroup.halo/preferences-changed`. SpringBoard applies the change at
  once and rewrites its status, which HCG Nexus reads for *Ready*.
- *Active* is HCG Nexus's own observation: HCG Halo's view is attached to the open panel's border host.
- **Tests:** `tests/test_nexus.m` covers every combination of before-state and switch, and checks that the screen
  edge is never turned on or off by the switch. It also covers both safety stops and a live round trip through
  HCG Halo's preferences.

## Status

| Check | How | Result |
|---|---|---|
| Canonical macOS/Xcode build + `validate.sh --require-new-abi` (Nexus contract constants, interface strings, no bundled definition) | CI run [44216299888](https://github.com/F1r3srp3nt/HCG-Jailbreak-Research/actions/runs/44216299888), commit `778c21a`. Re-validated locally from that commit on the downloaded artifact | **Pass**, 0 failures, 0 warnings, native arm64e ABI |
| Simulator runtime tests, **415 checks**, including **105 Nexus panel border checks**. Covered: definition fixtures; the panel view (geometry, mask, touches, effects, cleanup); the link with Nexus absent, incompatible, missing / malformed / outdated definition, waiting, version mismatch, attached, forged / malformed events, reversal, close-fade off, Reduce Motion, screen off, disable, 60 repeated cycles, Nexus update and removal | `scripts/run-simulator-tests.sh`, CI. The link is driven by a test double registered under the interface's class name | **Pass** (runs 44214405128 and 44216299888) |
| **Preview evidence**: HCG Nexus 0.2.2~beta1's real panel code and real `HaloBorder.plist` (HCG-Nexus `b68768f`) plus Halo's real link and renderer. The scripted run covers open with trace, workspace pulse, the three panel presets, all five modes, close, reversed opening, Halo off/on, Nexus off, and 30 rapid cycles | `scripts/nexus-preview.sh`, workflow *HCG Halo × Nexus preview*, run [44216300027](https://github.com/F1r3srp3nt/HCG-Jailbreak-Research/actions/runs/44216300027) (artifact `halo-nexus-preview-evidence`: 176 s video + console log) | **14/14 structural checks pass**. Stills: [`preview/halo-nexus-preview-sheet.jpg`](preview/halo-nexus-preview-sheet.jpg). **Simulator only** |
| **Against the final HCG Nexus 0.3.1~beta1** (HCG-Nexus `82412dd`, run 44225979728, SHA-256 `b6750cf1…41c3`): the panel preview with Command Mode steps, plus both Settings entry points built from both packages' real Settings bundles | workflow *HCG Halo × Nexus preview*, run [44231328827](https://github.com/F1r3srp3nt/HCG-Jailbreak-Research/actions/runs/44231328827) (Nexus `8a37a46`, whose code is the same as `82412dd`) | **Panel 17/17. Settings: 25 distinct checks, all passed, 0 failures** (38 PASS lines: the launcher retried, so steps A1–B3 ran twice, passing both times). Covered: Nexus › Appearance › Halo border opens Halo's page (*0.3.1~beta1 · compatible*), and Halo › Nexus Panel Border (target, Reactor, reset confirmation); a malformed or missing definition shows *Requires compatible HCG Nexus*. **Simulator only** |
| On the phone, with HCG Nexus 0.3.1~beta1 | manual: [DEVICE_TEST_CHECKLIST.md](DEVICE_TEST_CHECKLIST.md#hcg-nexus-panel-border-020beta1) | **pending** |

The preview runs as an ordinary app in the simulator. It shows the panel border's look and its lifecycle against
Nexus's real code. Each state line in its log also records Nexus's own `panelState` and whether the panel and
border are actually on screen. It does **not** show SpringBoard, the overlay window, real gestures (the opening
is triggered through Nexus's `simulateHandleActivation`), rotation, the keyboard, or device performance and
battery use.

The workspace pulse is brief and soft, so it is hard to see in a still.
