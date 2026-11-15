# Changelog — HCG Vortex

## 0.1.0-alpha (Debian version `0.1.0~alpha`)

First alpha. **Not yet verified on a device** — see docs/TESTING.md.

### Added
- Animation engine that separates real page navigation from presentation:
  SpringBoard's paging, page index, layout and touch handling are untouched;
  only page *contents* are transformed (`sublayerTransform`).
- Effects: **Reverse Slide**, **Vertical Rise**, **Vertical Fall**, plus
  iOS Default and **Custom Directions** (8-way direction matrix, independent
  incoming/outgoing directions).
- Per-swipe-direction effects, Reverse Animation, Duration (presentation
  smoothing), Speed Multiplier, Intensity (parallax + fade), five easing
  modes, optional page fade.
- Native Settings pane with HCG branding, live apply (no respring), engine
  status and compatibility diagnostics.
- Safety: runtime compatibility gate (no hooks unless every SpringBoard
  selector is present), master switch, file-based kill switch, exception
  circuit breaker, full transform restoration on settle/cancel/disable,
  stock behaviour for folders, Today View, App Library and edit mode.
- Host unit tests for the math core; package validation script; macOS CI.
