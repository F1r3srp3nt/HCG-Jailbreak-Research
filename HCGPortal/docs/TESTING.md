# Testing: what each test proves, and what it does not

**Nothing has run on a device.** Every result below is from host machines or the iOS Simulator. The Simulator runs
Portal's real code against stand-ins for SpringBoard classes; it is evidence about Portal's logic, drawing and touch
decisions, not about the real Lock Screen.

| Layer | How | Proves | Does not prove |
|---|---|---|---|
| **Host unit tests** (`tests/test_core.c`, `make -C tests test`; ASan + UBSan; GCC and Clang on Linux, Apple clang on macOS) | pure C core | Layout never covers an obstacle below the clock, never rises above the anchor, never enters the bottom reserve, keeps a ≥ 44 pt target (200,000 random screens); full → reduced → compact → hidden transitions; menu items never overlap each other or the portal and stay on screen (50,000 cases, counts 1–6); render plan for every Reduce Motion / Low Power / policy combination; visibility for all 2,048 inputs; pending action performs only the selected action, once, only after its own success within the timeout (200,000 random sequences); value validation with NaN / infinities | anything about UIKit or SpringBoard |
| **Packaging-format tests** (`tests/test_deb_format.py`) | 13 crafted archives | the gzip-only checker rejects lzma, xz, truncated, wrong-CRC, extra or reordered members | — |
| **Build + `validate.sh --require-new-abi`** (macOS CI, Xcode) | the real `.deb` | metadata, gzip members fully decompressed, payload under `/var/jb`, permissions, purge-only `postrm`, version + build ID in both binaries, fat arm64/arm64e with the native arm64e ABI and code signatures, SpringBoard-only filter, every expected interface present, **no passcode / keybag / unlock-bypass, notification-content, other-product preference, network, keychain, LocalAuthentication or URL reference**, dpkg install/remove leaves nothing | that it loads in SpringBoard |
| **Simulator runtime tests** (`scripts/run-simulator-tests.sh`, `tests/test_runtime.m`, headless `simctl spawn`) | real `PortalView`, `PortalOverlayView`, `PortalAuth`, `PortalLauncher`, `PortalPreferences`, `PortalCompanions` | animations / particles / pause / flourish per plan; touches: circle-only orb, items, pass-through, tap-outside collapse, no gesture recognisers, accessibility elements; authentication outcomes (success, cancel, refused, held, replayed callback) against a stand-in `SBLockScreenManager`; constructed-request fallback; preference validation; companion detection; the Nexus contract double; lighting event payload | SpringBoard, real authentication UI |
| **Simulator preview** (`scripts/preview.sh`, workflow *HCG Portal preview*) | real tweak code + real Settings bundle in a stand-in Lock Screen app; video + screenshots | the full flow end to end (see the list below) with the window's own hit-testing; Settings pages render from the real bundle | real SpringBoard hierarchy, real Face ID / passcode UI, finger gestures, window levels, PosterBoard, performance, battery |
| **Device** | `DEVICE_TEST_CHECKLIST.md` | — | **not done** |

## The preview script (stand-in Lock Screen)

Off after installation → enable → idle portal below the clock (anchor measured from the date view and widgets) →
clock, unlock area, camera and flashlight keep their touches → tap: radial menu with Nexus / Backgrounds / Devices /
HCG Apps and *Not installed* / *Not connected* states → tap outside passes through and collapses → unavailable
destinations: message, no authentication, nothing launched → companions installed: Nexus *Update needed*,
Backgrounds available → Backgrounds: authentication requested, nothing opens before success, portal hidden and paused
→ success: exactly Settings opened, once → HCG Apps ring (three apps) → cancel: nothing opens, late success ignored →
app after success: exactly that app, once → screen off during authentication: discarded; rendering paused and resumed
→ refused request: nothing opens, message → Nexus through the contract double: asked once after authentication →
2 notifications: full size, clear; 4 notifications + media: compact orb, clear; 7: hidden, nothing intercepted →
notifications and media controls keep their touches → Reduce Motion static; Low Power static / economy / hide →
colour themes → size and position, Reset → unlock: flourish, dismissal handler returns in < 50 ms, hidden and paused
→ Notification Centre over an unlocked phone: no portal → lock again: back → Enable off: removed, touches reach the
Lock Screen, no Portal view left → Enable on → fault fallback and recovery → Settings root, Position & Size, HCG Apps.

## Results

Candidate commit `4bfed33` (build run 44395826216, preview run 44395826055):

| Check | Result |
|---|---|
| Host unit tests | 2,623,892 checks pass (macOS); Linux GCC + Clang pass |
| `validate.sh --require-new-abi` | 0 failures, 0 warnings (CI; again outside CI and in handoff run 44398734537 on the downloaded bytes) |
| Simulator runtime tests | 66/66 |
| Simulator preview | 81/81, 23 screenshots, 173 s video (artifact `hcg-portal-preview`) |
| Device | not tested |

Found and fixed by these runs before the candidate: the rings were drawn off the core's centre (`.frame` set on
rotated layers); a stand-in lock-state publisher dropped its notify state (the portal correctly hid); headless
`UIControl` actions need an application (tests now deliver target/action directly); a first-UIKit-call stall on a
freshly booted simulator (settle delay + one retry on a time-limit kill, never on a failure).
