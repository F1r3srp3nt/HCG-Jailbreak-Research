# Diagnosis: HCG Portal 0.1.0~beta3 is drawn but does not respond

**Status:** leading cause identified from iOS 17.0.3 header evidence and the code, and reproduced as a *mechanism* in
the iOS Simulator. **Not yet confirmed on the affected iPhone.** The screen recording and device logs mentioned in the
request did not reach this session: no file was attached, and the session's upload folders were empty. 0.1.0~beta4
records the evidence on the phone that will confirm or rule out this cause (see *How the device test decides*).

## What was reported

On a Dopamine (rootless) iPhone, HCG Portal 0.1.0~beta3, which HCG Repo Candidate publishes, shows the portal.
Tapping it produces no functional response.

## The touch path in 0.1.0~beta1–3

- The orb and the four item discs are `PortalCircleControl`, a plain `UIControl` subclass. Their only activation was
  UIControl touch tracking: `addTarget:… forControlEvents:UIControlEventTouchUpInside` (`src/PortalOverlayView.m`).
- The overlay sits in the Cover Sheet's main page (`CSCoverSheetViewController.mainPageContentViewController.view`).
  It takes a touch only inside the orb's circle and the expanded item discs. Its `hitTest:` was correct and is unit
  tested.

## Evidence

1. **SpringBoard has gesture recognizers above Portal (iOS 17.0.3 headers, `MTACS/iOS-17-Runtime-Headers` @
   `d1d960d`).**
   - `CSCoverSheetView` declares `UITapGestureRecognizer *backgroundContentGestureRecognizer`,
     `UITapGestureRecognizer *quickNoteGestureRecognizer`, `UILongPressGestureRecognizer *complicationGestureRecognizer`,
     `UIGestureRecognizer *dateViewGestureRecognizer`, `UIGestureRecognizer *wallpaperGestureRecognizer` and an
     `SBSearchGesture`.
   - It installs them **on its scroll view**: `-_setupBackgroundContentGestureOnScrollView:`,
     `-_setupQuickNoteGestureOnScrollView:`, `-_setupComplicationGestureOnScrollView:`,
     `-_setupDateViewGestureOnScrollView:`, `-_setupWallpaperGestureOnScrollView:`.
   - `CSCoverSheetViewController` is their delegate (`gestureRecognizerShouldBegin:`,
     `gestureRecognizer:shouldRequireFailureOfGestureRecognizer:`,
     `_gestureRecognizer:isLocatedOverHorizontalContentRegionInViewController:`). It also owns a
     `_posterSwitcherGestureRecognizer` (long press).
   - The scroll view is an ancestor of the main page, and so of Portal. Every touch on the orb is therefore also
     delivered to these recognizers.
2. **SpringBoard decides by location, and does not know Portal exists.** To the delegate, a tap on the orb is a tap
   on otherwise empty Cover Sheet background. If a SpringBoard tap recognizer recognizes it, UIKit cancels the touch in
   the control (`cancelsTouchesInView` is YES by default). The control receives `touchesCancelled:`, never
   `UIControlEventTouchUpInside`, and nothing happens. That matches "drawn, does not respond" exactly.
3. **No test ever delivered a real touch.**
   - The preview called `-sendActionsForControlEvents:` on the control found by `-hitTest:`.
   - The runtime tests called the action selectors directly.
   - The stand-in Cover Sheet had no scroll view and no SpringBoard recognizers.

   So the touch path that fails on a phone was never exercised. This is how beta 3 passed 115/115 preview checks and
   still did not respond on the device.
4. **Simulator reproduction of the mechanism (0.1.0~beta4 preview, step T0).**
   - The preview injects real `UITouch`/`UIEvent` objects carrying an IOHIDEvent through
     `-[UIApplication sendEvent:]`, using the KIF technique (`preview/PortalTouchSynth.m`).
   - Step T0 taps a plain `UIControl` inside a scroll view that carries a `UITapGestureRecognizer`, and reports the
     result as notes.
   - The 0.1.0~beta4 preview then runs the real Portal overlay inside a Cover Sheet stand-in that has the same
     recognizers.

   The results are in the CI log of the beta 4 preview run (see the README status). They are a Simulator result, not a
   device result.

## Ruled out, with evidence

- **HCG Animation Center** (0.1.0~beta1, commit `2d642bd`, the build in HCG Repo Candidate) cannot take Portal's
  touches.
  - Its only hook is `-[SpringBoard frontDisplayDidChange:]`, which calls the original first (`src/Tweak.x`).
  - Its background views set `userInteractionEnabled = NO`, return `nil` from `hitTest:withEvent:` and `NO` from
    `pointInside:withEvent:` (`HCGBackgroundView.m`).
  - It inserts them at index 0 of the Cover Sheet window, or on the wallpaper view (`HACHosts.m`).
  - It does not read or change Portal's preferences, gestures or visibility.
- **HCG Nexus** (0.3.2~beta1 source, `main` @ `3136149`).
  - Its overlay window returns `nil` when the hit view is the window itself (`HCGOverlayWindow -hitTest:`).
  - Its policy hides the panel whenever the Cover Sheet is visible (`HCGOverlayPolicy.m`).
  - On the Cover Sheet, only its edge handle could take a touch, and only on the handle itself.
- **HCG Halo** (`HaloEdgeWindow`) draws the border in its own window at its own level. Its source on
  `claude/halo-nexus-control-0.3` adds no gesture recognizer to SpringBoard's Cover Sheet.
- **Portal's own hit test** is unit tested. Only the circle and the expanded discs take touches. That was not the
  fault.

**Not ruled out without device evidence:**
- Another tweak, outside HCG, that adds a full-screen interactive view above the Cover Sheet.
- A different Cover Sheet hierarchy on the phone's iOS version.

The beta 4 diagnostics distinguish both from the cause above (next section).

## How the device test decides

0.1.0~beta4 shows a **Touches** line in Settings › HCG Portal: `down / up / cancelled / taps / activations` and
*last cancelled by <recognizer> on <view>*. Counts accumulate from SpringBoard start. After tapping the orb a few
times:

| Settings shows | Meaning |
|---|---|
| taps and activations go up, menu opens | fixed: Portal's own recognizer wins |
| down goes up, cancelled goes up, *last cancelled by UITapGestureRecognizer on CS…* | a SpringBoard recognizer still wins: the cause above, not yet fully fixed (send the line) |
| down stays 0 | touches never reach Portal: something above the Cover Sheet takes them (another tweak, or another view on this iOS) |

## The fix in 0.1.0~beta4

- Each control (orb and items) has its own `PortalTapRecognizer`.
  - Its delegate returns YES from `gestureRecognizer:shouldBeRequiredToFailByGestureRecognizer:` for other **tap**
    recognizers. A SpringBoard tap that saw the same touch therefore waits for Portal's tap to fail.
  - This applies only to touches that land on Portal's orb or items, because those are the only touches Portal's
    recognizer receives.
- Long presses (poster switcher) and pans (scrolling, dismissing, search) are never held back.
- Nothing in SpringBoard is hooked or reconfigured.
- Activation no longer depends on UIControl tracking. VoiceOver activation goes through `accessibilityActivate`.
- The Simulator verifies with injected touches that:
  - a tap on the orb opens the menu while SpringBoard's background tap does not fire;
  - a tap elsewhere still reaches SpringBoard's background tap;
  - a long press on the orb still reaches the long-press recognizer;
  - a swipe that starts on the orb is not taken as a tap.
