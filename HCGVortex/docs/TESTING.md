# Testing

## Status levels used in this project

| Level | Meaning | v0.1.0-alpha |
|---|---|---|
| Source implemented | code written, compiles | **Yes** |
| Build successful | Theos produced a `.deb` with no errors (`-Werror`) | **Yes** (Linux toolchain + allemande); macOS CI: see workflow run |
| Package validated | `scripts/validate.sh` passes | **Yes** (1 expected warning on Linux builds: converted arm64e ABI) |
| Device installation successful | installed on the A13 / iOS 17.4 device | **No — not performed** |
| Runtime behaviour verified | effects observed working on device | **No — not performed** |

Nothing above "Package validated" may be claimed until the device steps below
are executed by someone with the authorized device.

## Automated (no device)

```sh
make -C tests test          # math core: easing, direction matrix, nav state
                            # machine, continuity sweeps, smoothing (ASan/UBSan)
scripts/validate.sh         # source consistency + package checks + dpkg
                            # install/remove simulation
```

What the unit tests prove: the pure math produces no visible jumps across
every built-in effect pair, parameter set, reversal and multi-page flick; that
exactly one page (the real current page) is visible when settled; that the
stock effect produces no transform at all; and that smoothing converges
without overshoot. They do **not** prove anything about SpringBoard.

The tests were mutation-checked during development: deliberately breaking
the incoming start position, page roles, the intensity fade or the solver
each produced thousands of failures.

## Device test plan (requires explicit authorization)

### Install
1. Copy the `.deb` to the device; install with Sileo/Zebra (**Install from
   file**) or `sudo dpkg -i com.hakmicapitalgroup.vortex_0.1.0~alpha_iphoneos-arm64.deb`
   then `sbreload`/respring.
2. Settings → HCG Vortex opens (this alone verifies the Preferences bundle
   loads in the arm64e Preferences process).
3. Engine Status = **Active**. Record Engine Detail.

If the status is **Incompatible**, record the detail, stop, and update
`docs/SPRINGBOARD_RESEARCH.md`. The Home Screen should be fully stock.

### Functional matrix
Run each with Duration 0 and Duration 0.4, Speed 1 and 2, Linear and Ease
In-Out:

| # | Test | Expected |
|---|---|---|
| F1 | Reverse Slide, swipe left page 1→2 | page 2 enters from the **left**, page 1 exits right; page dots show 2 |
| F2 | Reverse Slide, swipe right 2→1 | page 1 enters from the right |
| F3 | Vertical Rise, both directions | incoming rises from below, outgoing moves up; no horizontal motion |
| F4 | Vertical Fall, both directions | incoming from above, outgoing moves down |
| F5 | Per-Swipe (left = Rise, right = Fall) | each direction uses its own effect |
| F6 | Custom, incoming Top Left, outgoing Bottom Right | diagonal motion |
| F7 | Reverse Animation on Rise | behaves like Fall |
| F8 | Intensity 0.5 | outgoing moves half way and fades; no pop at the end |
| F9 | Fade Pages | cross-fade during motion |
| F10 | Restore Default Behavior | stock animation immediately, no respring |
| F11 | Enable Vortex off | stock immediately |

### Robustness
| # | Test | Expected |
|---|---|---|
| R1 | Drag half way and release (snaps back) | returns cleanly, no residual offset |
| R2 | Drag, reverse past the start page | other neighbour becomes incoming, no jump |
| R3 | Flick, then grab during deceleration | follows finger, no jump |
| R4 | Fast flicks across several pages | continuous |
| R5 | Tap an icon immediately after a transition | launches the icon under the finger |
| R6 | Page dots tap / scrub | correct page; effect may be stock for animated jumps (see research open items) |
| R7 | Swipe from page 1 to Today View and back | Today View transition stock; page 1 intact |
| R8 | Swipe from last page to App Library and back | stock; last page intact |
| R9 | Enter jiggle mode, drag an icon across pages | stock behaviour |
| R10 | Open a folder, page inside it | stock paging |
| R11 | Widgets (Smart Stack, interactive widgets) on transitioning pages | move with page; interactive after settle |
| R12 | Dock | never moves |
| R13 | Lock/unlock, open/close apps mid-transition | Home Screen intact |
| R14 | Change settings mid-transition | restores then applies |
| R15 | Respring ×3 | Engine Status Active each time |
| R16 | Kill switch: `touch /var/mobile/Library/Preferences/com.hakmicapitalgroup.vortex.disabled`, respring | status "Kill switch on", stock Home Screen |
| R17 | Uninstall via Sileo, respring | stock, no residual files under `/var/jb` from this package |

### Performance
Use Instruments (Core Animation FPS) or the Display Frame Rate in Settings →
Developer if enabled: transitions should hold the same frame rate as stock.
Record before/after.

### Logs
Enable Diagnostic Logging, then on a Mac:
```sh
log stream --device --predicate 'subsystem == "com.hakmicapitalgroup.vortex"'
```
Attach logs for any failure. No crash should appear in
Settings → Privacy & Security → Analytics Data → `SpringBoard-*.ips`
referencing `HCGVortex.dylib`.

## Reporting template

```
Device / iOS build / Dopamine version:
Package version + build source (macOS CI / Linux):
Engine Status / Detail:
Tests passed:
Tests failed (with steps, video if possible):
Logs:
```
