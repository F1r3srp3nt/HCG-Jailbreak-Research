# Changelog

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
