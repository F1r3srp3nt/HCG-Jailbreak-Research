# Accessibility

Target: WCAG 2.2 level AA. Automated checks run in `tests/e2e.mjs`; results in `docs/test-results/e2e.json`.

## Automated (axe-core 4.10.2, Chromium via Playwright), 21 Nov 2026

| Layout | Appearance | Rules passed | Violations |
|---|---|---|---|
| Desktop 1280 px | Dark | 60 | **0** |
| Desktop 1280 px | Light | 60 | **0** |
| iPhone 13 | Dark | 61 | **0** |
| iPhone 13 | Light | 61 | **0** |

Rule sets: `wcag2a`, `wcag2aa`, `wcag21a`, `wcag21aa`, `wcag22aa`, `best-practice`. Every collapsible section was opened
and a checker result was displayed before scanning, so hidden content was included.

Found and fixed during testing: on phones, wide tables and one command block scrolled sideways without being reachable
by keyboard (`scrollable-region-focusable`). Tables are now focusable, named scroll regions; commands wrap.

## Built in

- Landmarks: skip link, `header`, labelled `nav` (primary and chapters), `main`, `footer`; one `h1`, chapters `h2`.
- Every chapter, table region, form control and fieldset has a visible or programmatic label.
- Checker: native form controls, `fieldset`/`legend` for radio groups, help text via `aria-describedby`; the result is
  announced (`aria-live`) and focus moves to its heading.
- Route tabs follow the ARIA tabs pattern (arrow keys, Home/End, roving `tabindex`).
- Progress uses `role="progressbar"` with a text value; “Mark chapter complete” buttons expose `aria-pressed`; the
  chapter list announces “(completed)”.
- Copy buttons, theme changes, expand/collapse and resets are announced through a polite live region.
- Illustrations have descriptive `alt` text; diagrams also carry `<title>`/`<desc>` inside the SVG.
- Colour: both themes use HCG tokens checked by axe for contrast; status is never shown by colour alone (badges carry
  words).
- `prefers-reduced-motion` disables smooth scrolling and the banner glow (inherited from HCG's `site.css`);
  `forced-colors` replaces clipped shapes with borders; print stylesheet expands everything.
- Works without JavaScript for reading; only the checker, progress and theme toggle need it (a `noscript` note says so).
- Touch targets are at least 40–46 px high; no horizontal page scroll at 320 px.

## Keyboard checks (automated)

Skip link is the first Tab stop and moves focus to `main`; route tabs switch with arrow keys and keep focus on the
selected tab.

## Still recommended (manual)

- VoiceOver on iPhone (Safari) and on macOS: read through chapters 7–10 and use the checker.
- 200 % browser zoom and iOS Larger Text.
- Windows High Contrast mode.
