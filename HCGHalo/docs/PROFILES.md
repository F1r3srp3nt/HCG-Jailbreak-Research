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
