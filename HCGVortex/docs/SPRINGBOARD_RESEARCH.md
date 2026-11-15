# SpringBoard Research — Home Screen paging (iOS 17)

Status: **header-level research complete; on-device (iOS 17.4) verification pending.**

## Sources and their limits

| Source | What it is | Used for |
|---|---|---|
| `MTACS/iOS-17-Runtime-Headers` (GitHub, commit `d1d960d`, Nov 2023) | class-dump of **iOS 17.0.3** frameworks | class names, ivars, selectors, superclasses |
| `theos/sdks` iPhoneOS16.5.sdk | patched SDK (public + private framework stubs) | compiling; links UIKit/QuartzCore/Preferences only |
| Theos vendor headers (`Preferences/*.h`) | community headers | Settings bundle |

**No iOS 17.4 header dump or device was available.** Every SpringBoard
assumption below is therefore *verified for 17.0.3 headers only*. To make
that safe, the tweak re-verifies each one at runtime on the device before
installing any hook (see "Runtime verification gate"). If anything is missing
on 17.4 the tweak installs **no hooks**, leaves the Home Screen stock, and
reports the exact missing piece in Settings → HCG Vortex → Engine Detail.

No method signature in this project was invented: every selector used appears
verbatim in the 17.0.3 dump, and every call site is guarded.

## Where Home Screen paging lives (iOS 17)

Since iOS 14 the Home Screen UI is in `SpringBoardHome.framework`, but the
classes keep their `SB` prefix and are registered in the SpringBoard process.

```
SBIconController / SBRootFolderController  (view controllers)
└─ SBRootFolderView : SBFolderView : UIView          ← scroll delegate, layout owner
   ├─ SBIconScrollView : BSUIScrollView : UIScrollView   ← horizontal paging scroller
   │   ├─ SBIconListView  (page 1)   ← icons + widgets of one page
   │   ├─ SBIconListView  (page 2)
   │   └─ …
   ├─ leadingCustomViewController  (Today View, "page -1")   — separate wrapper view
   ├─ trailingCustomViewController (App Library)              — separate wrapper view
   └─ SBDockView / SBDockIconListView                          — NOT inside the scroller
```

Relevant declarations (iOS 17.0.3 dump):

| Class | Selector / ivar | Notes |
|---|---|---|
| `SBFolderView` | `- (void)scrollViewDidScroll:(id)` | implemented by SBFolderView itself (it is the `SBIconScrollViewDelegate`) |
| `SBFolderView` | `- (void)layoutSubviews` | implemented by SBFolderView itself; root view adds `_layoutSubviews*` helpers |
| `SBFolderView` | `@property (readonly) UIScrollView *scrollView` | `SBIconScrollView * _scrollView` ivar |
| `SBFolderView` | `@property (readonly, copy) NSArray *iconListViews` | page views |
| `SBFolderView` | `@property (readonly) long long currentPageIndex` | **read only** by Vortex (diagnostics) |
| `SBFolderView` | `@property (readonly, getter=isEditing) bool editing` | jiggle mode |
| `SBFolderView` | `firstIconPageIndex`, `lastIconPageIndex`, `_leadingCustomPageCount`, `_pageWidth`, `_pageSpacing` | not used — geometry is measured instead (more robust across versions) |
| `SBRootFolderView` | `leadingCustomView*`, `trailingCustomView*`, `dockView`, `dockListView` | confirms Today View / App Library / dock are separate views |
| `SBRootFolderView` | *no* `scrollViewDidScroll:` override in 17.0.3 | so hooking `SBFolderView` covers the root view |
| `SBIconScrollView` | overrides `setContentOffset:` / `setContentOffset:animated:` | not hooked (see alternatives) |
| `BSUIScrollView` | `setContentOffset:withAnimationSettings:completion:` | BaseBoard-driven animated offset changes exist |
| `SBIconListView : UIView` | `editing`, `iconLocation`, icon/widget layout | page container; widgets are subviews of it |

## How a page transition works (observed model)

1. The user drags `SBIconScrollView` (a paging `UIScrollView`).
2. Every offset change calls the delegate, `-[SBFolderView scrollViewDidScroll:]`,
   which updates page-control state, Today View / App Library visibility
   progress, dock fade, etc.
3. On release, the scroller decelerates/snaps to a page; SpringBoard updates
   `currentPageIndex` (`_setCurrentPageIndex:` / `_currentPageIndexDidChange…`).
4. `layoutSubviews` positions `SBIconListView`s side by side at a fixed pitch.

**Transition progress** can therefore be derived purely from geometry:
`(scrollView.bounds.midX − page.center.x) / pitch`. That is what
`VortexNavigation` does — it never asks SpringBoard to change anything.

## Hook design decisions

| Decision | Reason |
|---|---|
| Hook `-[SBFolderView scrollViewDidScroll:]`, call `%orig` first | fires on every offset change (drag, deceleration, programmatic animated scroll); SpringBoard's own bookkeeping completes before Vortex looks |
| Hook `-[SBFolderView layoutSubviews]`, call `%orig` first | re-applies presentation if layout moves pages mid-transition |
| Filter to `SBRootFolderView` at runtime | folders (`SBFolderView` instances inside folder UI) keep stock paging |
| Require `[folderView scrollView] == scrollView` | ignore any other scroll view the folder view might delegate (e.g. search) |
| Hook only selectors **SBFolderView implements itself** (checked with `class_copyMethodList`) | `%orig` always has a real IMP; no reliance on hook-engine handling of inherited methods |
| Transform `SBIconListView.layer.sublayerTransform` | see below |
| Never write `contentOffset`, `currentPageIndex`, frames, or `view.transform` | page index, touch handling and layout remain SpringBoard's |

### Which visual layer is safe to transform

* `view.transform` on `SBIconListView` — **rejected.** SpringBoard sets list
  view frames during layout; UIKit documents `frame` as undefined while
  `transform` is non-identity, so a layout pass mid-transition could leave a
  page permanently misplaced.
* `layer.transform` — same problem (it backs `view.transform`).
* `layer.sublayerTransform` — **chosen.** It moves the page's *contents*
  (icons, widgets) without changing the view's frame/center/bounds, is
  ignored by UIKit layout, and is not used by hit-testing. After a transition
  it is reset to identity, so hit-testing is exactly stock. It also supports
  `m34` perspective and 3D rotation for the v0.2.0 cube/flip effects.
* `layer.opacity` — used only when an effect fades. Vortex records the
  original value, adopts any change SpringBoard makes meanwhile, and only
  restores if nobody else changed it.

### Widgets, dock, Today View, App Library

* **Widgets** on Home Screen pages are subviews of their page's
  `SBIconListView`, so they move with the page and are restored with it.
* **Dock** is outside the scroller and is never touched (list views not
  descendant of the scroll view are filtered out, which excludes
  `SBDockIconListView`).
* **Today View / App Library** are custom pages outside the icon page range.
  When the presented position leaves `[first icon page, last icon page]` the
  engine restores everything and stays stock, so those transitions are
  untouched (`vortex_nav_step` → `inRange = 0`).
* **Edit (jiggle) mode** — the engine stands down while `isEditing` is true,
  so icon dragging between pages is stock.

## Alternatives considered

| Alternative | Why not (for v0.1.0) |
|---|---|
| Hook `-[SBIconScrollView setContentOffset:]` | works, but gives no folder-view context; also fires for folder scrollers; the delegate hook gives both |
| Hook `_setCurrentPageIndex:` / `scrollViewDidEndDecelerating:` | only fire at the end; Vortex needs continuous progress |
| Replace the paging animation (custom scroller / gesture) | would interfere with touch handling and page state — explicitly out of scope |
| Snapshot-based transitions | spec forbids screenshots/pre-recorded animations; also breaks live widgets |
| Older (iOS 13–16) Cylinder-style hooks | not assumed; every selector re-derived from the 17.0.3 dump and re-checked at runtime |

## Runtime verification gate (on device)

`VortexCoreCompatibilityFailure()` runs in SpringBoard before `%init`:

1. classes exist: `SBFolderView` (UIView), `SBRootFolderView` (SBFolderView),
   `SBIconScrollView` (UIScrollView), `SBIconListView` (UIView);
2. `SBFolderView` implements `scrollViewDidScroll:` and `layoutSubviews`
   **itself**;
3. `SBRootFolderView` responds to `scrollView`.

Non-fatal observations are reported too (e.g. if `SBRootFolderView` gains its
own `scrollViewDidScroll:` override on 17.4, or `iconListViews` / `isEditing`
disappear — the engine then falls back to scroll-view subviews and loses the
edit-mode bypass respectively).

Result is written to the `com.hakmicapitalgroup.vortex.status` preferences
domain and shown in Settings → HCG Vortex → Development.

## Verifying on the authorized test device

These steps establish the iOS 17.4 facts that this document could not:

1. Install the package (docs/TESTING.md) and respring.
2. Settings → HCG Vortex → Engine Status should read **Active**; Engine Detail
   lists any compatibility notes. **Incompatible** includes the exact missing
   class or selector.
3. With Diagnostic Logging on, stream logs from a Mac:
   `log stream --device --predicate 'subsystem == "com.hakmicapitalgroup.vortex"'`
   (or Console.app filtered on `HCGVortex`).
4. For deeper inspection use a runtime inspector you already trust on the
   device (e.g. FLEXing) to confirm the hierarchy above on 17.4, then update
   this file with the confirmed facts and the iOS build number.

## Open items (blockers until verified on device)

* iOS 17.4 selector availability (expected to match 17.0.3; gated at runtime).
* Whether animated programmatic scrolls (page-dot taps, `setContentOffset:
  withAnimationSettings:`) report intermediate offsets through
  `scrollViewDidScroll:` on 17.4. If they only report the end value, those
  particular transitions are simply stock (no glitch) — confirm visually.
* Whether `SBIconScrollView` clips to bounds on 17.4 (affects where vertical
  effects visually cut off; not a correctness issue).
