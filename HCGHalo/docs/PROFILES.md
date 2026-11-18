# Device profiles

A profile describes the display outline the light follows: the screen size in points, the corner radius and the
cutout (notch). Profiles live in **`data/profiles.json`**, the only source. `scripts/generate.py` turns that file
into `src/HaloProfiles.generated.c`, and `validate.sh` fails if the generated file is stale.

## Terms

| Term | Meaning |
|---|---|
| **Implemented** | The outline is entered and the profile can be selected. It may still be slightly off: calibrate it |
| **Device-tested** | Someone has checked this profile on that iPhone, and the result is recorded below. It is a separate flag (`device_tested`) and is `false` for every profile in 0.1.0~beta1. A unit test enforces that |
| **Planned** | Listed so the selector shows what is coming. It has no geometry and cannot be selected; the Settings row is disabled and the validator refuses it |
| **Automatic** | Reserved and **not implemented**. Settings shows "Automatic — Coming soon", disabled. The validator never accepts the identifier `automatic` |

## iPhone 11 Pro Max (`iphone-11-pro-max`, `iPhone12,5`)

| Value | Reference | Source |
|---|---|---|
| Screen | 414 × 896 pt @3x (1242 × 2688 px) | Apple Human Interface Guidelines device dimensions |
| Corner radius | 39.0 pt (circular approximation of the continuous corner) | public measurements; **not measured by HCG** |
| Notch | 209 × 30 pt, top flare radius 6 pt, bottom corner radius 20 pt, centred | public measurements of the 6.5-inch notched display; **not measured by HCG** |

**Status: implemented, not yet device-tested.**

Settings also shows what iOS itself reports (`_displayCornerRadius`, when available) and the screen size, as
calibration aids. Halo never uses them to choose a profile.

### "375 × 812 pt" on an iPhone 11 Pro Max: Display Zoom (0.3.0~beta1)

**What Halo measures.** `UIScreen.mainScreen.fixedCoordinateSpace.bounds`: the screen in **points**, portrait,
whatever the orientation. That is the coordinate space the border is drawn in. Since 0.3.0~beta1 the status also
shows `nativeBounds` (pixels), the native scale and the model identifier, e.g.
*375 × 812 pt @3x · 1242 × 2688 px (native scale 3.31) · iPhone12,5*.

**Why 375 × 812.** It is either:

| Pixels (`nativeBounds`) | Model identifier | Meaning |
|---|---|---|
| 1242 × 2688 px | `iPhone12,5` | **iPhone 11 Pro Max with Display Zoom** (Settings › Display & Brightness › Display Zoom › *Larger Text*). The same panel is drawn with fewer, larger points: 414 → 375 pt wide, a factor of 375 / 414 = 0.906 (native scale 3.31 instead of 3) |
| 1125 × 2436 px | `iPhone12,3`, `iPhone11,2`, `iPhone10,3/6` | a different phone: iPhone 11 Pro, XS or X. This profile does not apply |

**What 0.2.0~beta1 drew in that case.** `HaloOverlayView` replaced the profile's width and height with the measured
375 × 812, but kept the corner radius and notch in the profile's 414-pt units: corner 39 pt, notch 209 × 30 pt in
zoomed points. On the glass that is a corner of about 43 pt and a notch of about 231 × 33 pt in standard points:
**roughly 10% too large**, the notch about 22 pt too wide. Settings called it a *MISMATCH* and said the border was
"stretched", which was wrong: the frame fitted, the corners and notch didn't.

**What 0.3.0~beta1 does.** `halo_profile_fit()` (`src/HaloProfiles.c`) compares the pixels:

- same points → **match**: the profile applies as is;
- same pixels, fewer points, the same factor on both axes → **Display Zoom**: corners and notch are scaled by
  points ÷ profile points (0.906), so they stay the same size on the glass;
- anything else → **mismatch**: the frame still fits the screen, the profile's corners and notch are left unscaled,
  and Settings says *a different display, not Display Zoom* and asks for the right profile.

Calibration deltas are screen points added **after** the scaling. If you calibrated under Display Zoom on
0.2.0~beta1, those deltas were compensating for the bug: **Reset Calibration** after updating.

**Device verification: pending.** The host tests check the arithmetic (the zoomed outline has the same proportions
as the standard one), and the Simulator runs on an iPhone 11 Pro Max at standard zoom. Display Zoom itself, and
whether the corners and notch now line up on the glass, can only be checked on the phone (checklist rows S12–S14).

## Calibration

These are applied on top of the selected profile, in points:

| Setting | Range | Applies to |
|---|---|---|
| Corner radius | ±20 | all four screen corners |
| Notch width | ±40 | the notch |
| Notch depth | ±15 | the notch |
| Notch position | ±20 | horizontal shift of the notch |
| Notch: Trace / Straight Edge | — | follow the notch outline, or run straight behind it |

The edge inset (0–20 pt) is an appearance setting and is saved with presets. The values are clamped so the outline
always stays valid. The host tests render every combination of calibration extremes.

**How to calibrate on the device:** set Mode to Static, Thickness to 1–2 pt, Glow to 0 and Edge Inset to 0. Then
adjust the corner radius until the line hugs the corners evenly, and the notch values until it wraps the notch
without a gap or overlap. Record the final values in the device test.

## Adding a profile

1. Add or complete the entry in `data/profiles.json`:
   - `status: "implemented"`, with `screen`, `corner_radius`, `cutout` (`none` or `notch`) and `sources`;
   - say where each value comes from;
   - leave `device_tested` false.
2. Run `python3 scripts/generate.py`, then `make -C tests test`.
3. The tests check the new outline at every calibration extreme. `tests/test_core.c` currently expects exactly one
   implemented profile, so update that check deliberately.
4. Dynamic Island devices need a new cutout kind in `HaloGeometry.c`. The generator refuses unknown kinds.

## Recording a device test

Only after a real test (`DEVICE_TEST_CHECKLIST.md`), add a row here with the device, iOS and build, jailbreak, date,
result and a link to the evidence. Then, and only if the result was a pass, set `device_tested: true` and update
the `tests/test_core.c` expectation in the same commit.

| Profile | Device | iOS (build) | Jailbreak | Date | Result | Evidence |
|---|---|---|---|---|---|---|
| — | — | — | — | — | none recorded | — |
