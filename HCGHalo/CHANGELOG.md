# Changelog

## 0.3.0~beta1 (HCG Repo Candidate, 18 Nov 2026)

**Free public beta demo — simulator-tested, real-device testing pending.** 0.2.0~beta1 and 0.1.0~beta1 are unchanged.

- **Show Halo on** replaces the read-only *Display Context* row (screen edge only; applies at once):
  - **Home Screen Only** — the default; existing users see no change.
  - **Selected App Only** — with an installed-app picker (search, icons, *Enter Bundle ID* fallback). The border
    shows only while that app is in front, unlocked and lit.
  - **Always** — every lit surface: the Lock Screen, the Home Screen and apps.
  - **Always Except Lock Screen** — the Home Screen and apps; hidden whenever the phone is locked.
  - **Always Except When Screen Is Off** — like Always, stated explicitly.
- Settings explains that a fully off display can't show a border (every choice hides the border and pauses rendering
  then), and that Always and Always Except When Screen Is Off behave identically because HCG Halo has no Always-On
  display mode. Low Power Mode and Reduce Motion apply under every choice.
- The choices beyond the Home Screen draw in HCG Halo's own overlay window: never interactive, never key, hidden
  (no compositing) whenever the border is hidden. Home Screen Only keeps the Home Screen window.
- The HCG Nexus panel border is unchanged: it follows the panel's own visibility.
- **Display Zoom:** an iPhone 11 Pro Max with Display Zoom reports 375 × 812 pt (same 1242 × 2688 px panel). 0.2.0
  drew the profile's corners and notch about 10% too large in that case. Halo now detects Display Zoom from the pixel
  size and scales the corners and notch to match; a genuinely different display is reported as a mismatch.
  Settings shows points, pixels, native scale and the model identifier. If you calibrated under Display Zoom,
  reset the calibration.
- Not yet verified on a physical device.

**Candidate build (commit `e22527d`, macOS CI):**
`com.hakmicapitalgroup.halo_0.3.0~beta1_iphoneos-arm64.deb`, 431,720 bytes, SHA-256
`bd8a926667b8ebec5b2a200fc8d8a14bcd21a9a2919e0475ec97a479381defc5` (build run 44246501375, artifact
`hcg-halo-rootless-deb` 14402121490). Earlier 0.3.0~beta1 builds from this branch (`53f55bab…`, `5522441f…`) had
the two bugs below and must not be used.

| Check | Result |
|---|---|
| Host unit tests (Linux and macOS, ASan/UBSan) | pass, 9.4 M checks, including every Show Halo on choice × every input combination and the screen-fit cases |
| Build + `validate.sh --require-new-abi` | pass (run 44246501375) |
| iOS Simulator runtime tests | 446/446 (run 44246501375) |
| Nexus panel preview (with HCG Nexus 0.3.1~beta1) | 17/17 (preview run 44246501303) |
| Settings preview (both real Settings bundles; Show Halo on row, footer, app picker with 24 installed apps, choosing an app) | all checks passed, `failures=0` (run 44246501303) |
| Show Halo on surfaces preview (real controller in a stand-in SpringBoard, iPhone 11 Pro Max Simulator) | 51/51 (run 44246501303): app switching, lock, wake and screen-off under all five choices; live re-hosting; 60 rapid transitions; Always ≡ Always Except When Screen Is Off |
| Device | **not tested** — rows S0–S16 |
| **Published** | **HCG Repo Candidate**, 18 Nov 2026 (owner-approved free demo): HCG-repo PR #10 (`d3a8c99`), Publish run 44379393712. Its live check downloaded and verified every candidate `.deb` (10 packages, 0 errors); the stable source is unchanged. Listing: https://repo.hakmicapitalgroup.com/repo/candidate/depictions/com.hakmicapitalgroup.halo/ |

Found and fixed by the previews before this build: the overlay window never showed the border (its content
view was installed only once the window was shown), and Settings crashed once an app was chosen (a BOOL private
method read as an object).

## 0.2.0~beta1 (unreleased candidate)

**Free public beta demo — not yet device-tested.** Builds on 0.1.0~beta1, which the owner reports running on
their phone; that package is unchanged.

- **Border Target:** Screen Edge (the default, so existing users see no change), HCG Nexus Panel, or Both.
- **HCG Nexus panel border** (needs HCG Nexus 0.2.2~beta1 or a later build with its border interface; no install order, respring once):
  - Halo reads and strictly validates the border definition that Nexus installs on the phone
    (`HCGNexusPrefs.bundle/HaloBorder.plist`).
  - It draws around the live panel through Nexus's versioned interface, so the border follows the panel's real
    position, slide, size, rotation and keyboard resizing.
  - The border is never interactive and never covers the panel's content.
  - It appears only while the panel is shown and is removed at once when Halo is disabled.
  - A missing, incompatible or updated-but-not-resprung Nexus turns only the panel border off, with the reason.
- **Panel look:** Match Screen Edge or a separate look, with presets, mode, colours, brightness, thickness, glow,
  speed, direction, segments and pulse.
- **Panel presets:** Nexus Signature, Reactor and Hologram. These are visual styles only.
- **Panel effects:**
  - Opening trace, synchronised with Nexus's transition and cancelled on reversal.
  - Fade with the panel.
  - A soft workspace pulse.

  All of them are brief, none delays the panel, and the trace is skipped with Reduce Motion.
- **Reset Nexus Lighting:** resets the panel only. The screen edge and the target are kept.
- **Soft Pulse** slider for any mode except Breathing.
- Reduce Transparency removes the panel border's glow. Screen off, Reduce Motion and Low Power apply as for the
  screen edge. The kill switch, crash-loop guard and fault fallback cover both targets.

## 0.1.0~beta1 (unreleased candidate)

**Free public beta demo — not yet device-tested.** First build of HCG Halo.

- Animated light border around the Home Screen edges, following the rounded display corners and the notch.
- Modes: Static, Breathing, Colour Flow, Orbit and Sci-Fi Circuit.
- Colours: single, multiple (bands) or gradient, with 1–6 colours, a colour picker and quick palettes.
- Brightness, thickness, glow, edge inset, speed, direction, colour spacing, and Orbit segment count and length.
- Presets: six built-ins. Save, rename, duplicate and delete your own.
- Device profile: iPhone 11 Pro Max (implemented, not yet device-tested), with calibration for the corner radius
  and the notch. "Automatic — Coming soon" is shown disabled.
- Settings: live preview, engine status, rendering state, version and build ID. Changes apply without a respring.
- Off after installation. Kill switch, crash-loop guard and fault fallback.
- Pauses when the screen is off, when the phone is locked or when an app is in front. Follows Reduce Motion, with a
  choice of Low Power Mode behaviour.
- No account, payment, telemetry or network access.
