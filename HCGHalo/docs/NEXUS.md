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

> The Nexus build with this interface is **0.2.2~beta1**: the 0.2.1~beta1 candidate code plus the interface.
> 0.3.0~beta1 is already used by a separate Nexus line without it. Halo checks for the interface and the
> definition, not for a version number, so any later Nexus build that includes them works.

| HCG Halo | HCG Nexus | Panel border |
|---|---|---|
| 0.2.0~beta1 | 0.2.2~beta1, or a later build that includes border interface 1 and the definition | Available |
| 0.2.0~beta1 | 0.3.0~beta1 from the separate `claude/hcg-nexus-tweak-yb1ii2` line (no border interface) | Off: *Requires compatible HCG Nexus* |
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

## Status

| Check | How | Result |
|---|---|---|
| Builds, both binaries, `validate.sh` (Nexus contract constants, no bundled definition, interface strings) | Linux toolchain locally; macOS/Xcode CI for the candidate | see the pull request |
| Simulator runtime tests: definition fixtures, panel view (geometry, mask, touches, effects, cleanup), link (absent, incompatible, missing / malformed / outdated definition, waiting, version mismatch, attached, forged / malformed events, reversal, close fade off, Reduce Motion, screen off, disable, repeated cycles, Nexus update, removal) | `scripts/run-simulator-tests.sh`, CI. The link is driven by a test double registered under the interface's class name | see the pull request |
| **Preview evidence**: HCG Nexus's real panel code and real `HaloBorder.plist` plus Halo's real link and renderer, scripted open / trace / workspace / presets / all modes / close / reversed open / Halo disabled / Nexus disabled / 30 cycles, with video and screenshots | `scripts/nexus-preview.sh`, workflow *HCG Halo × Nexus preview* | see the pull request. **Simulator only** |
| On the phone, with HCG Nexus 0.2.2~beta1 | manual: [DEVICE_TEST_CHECKLIST.md](DEVICE_TEST_CHECKLIST.md#hcg-nexus-panel-border-020beta1) | **pending** |

The preview runs as an ordinary app in the simulator. It shows the panel border's look and its lifecycle against
Nexus's real code, but **not** SpringBoard, the overlay window, real gestures or device performance.
