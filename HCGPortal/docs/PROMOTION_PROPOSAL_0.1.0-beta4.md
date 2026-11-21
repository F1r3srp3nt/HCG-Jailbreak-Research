# Proposal: HCG Portal 0.1.0~beta4 → HCG Repo Candidate (replacing 0.1.0~beta3)

**Status: DRAFT, NOT READY.** Physical-device qualification has not been run
(`docs/QUALIFICATION_0.1.0-beta4.md`). The recommendation is **do not promote yet**. This document is completed with
the device results, then put to the owner. Publication needs the owner's separate, explicit approval. Nothing here
changes HCG Repo, Candidate or Stable.

## What would change for Candidate users

| | 0.1.0~beta3 (Candidate today) | 0.1.0~beta4 (proposed) |
|---|---|---|
| Where Portal appears | on the **locked** Lock Screen, below the clock | only on the Cover Sheet pulled down **after iOS has unlocked** the iPhone; nothing on the locked Lock Screen |
| Opening a destination | asks for Face ID / Touch ID / passcode through `-[SBLockScreenManager unlockWithRequest:]` | no authentication request at all: the iPhone is already unlocked; Portal re-checks iOS's lock state at the tap, after the Cover Sheet closes and in the launcher |
| Locking | Portal stays on the Lock Screen | removes Portal at once and discards anything pending; actions from before a lock can never run |
| Lock state unknown | (Lock Screen product: shown) | fails closed: hidden, Settings says why |
| Orb and menu taps | unresponsive on the reporting iPhone (cause: SpringBoard's Cover Sheet tap recognizers win over plain `UIControl`s) | Portal's own tap recognizers that SpringBoard's taps wait for; touch diagnostics in Settings |
| Settings | Status, layout, Diagnostics | adds *iPhone lock state*, *Touches*, *Breadcrumb* |

Shipped code: 21 files, +632 / −326 lines against `579213e`. The core changes:
- `src/PortalController.m`, `src/PortalCore.c/.h`: access gate, epochs, revocation.
- `src/PortalOverlayView.m`: tap recognizers and diagnostics.
- `src/PortalLauncher.m`: gate before calling iOS.
- `src/PortalAuth.m/.h` removed.
- `scripts/validate.sh`: forbids any unlock request.

The full list is in `CHANGELOG.md`; the reasoning is in `docs/SECURITY.md` and
`docs/DIAGNOSIS_0.1.0-beta3-unresponsive.md`.

## Evidence

| Evidence | Result | Source |
|---|---|---|
| Package bytes | SHA-256 `8a186d99a63d38c2bc4fb25d40bcfd773bbc042e5309063e0a87fc4d584164e4`, 293,942 bytes; re-downloaded and re-verified against GitHub's artifact digest; build ID `1298ded2d930` embedded; Settings plists and `postrm` identical to the source | run 44871433709 |
| `validate.sh --require-new-abi` | 0 failures / 0 warnings, in CI and again outside CI on the downloaded bytes; no Substrate load command; no unlock request; no passcode, keybag or authentication API | same |
| Host tests | 2,927,359 checks (all 3⁵ access inputs, 200,000-step lock/unlock epoch storms) | same |
| Simulator runtime | 65/65 | same |
| Simulator preview, real UIKit touch events | 122/122 (locked / before first unlock / unlocked; finger taps; relock mid-opening; rapid lock and unlock; fail closed; Animation Center present and absent; 20 lock/unlock cycles) | run 44871433770 |
| **Physical iPhone** | **pending**: Q1–Q16 | to be filled from the owner's report |

## Go / no-go criteria

**Go** only if all of the following pass on the physical iPhone:
- Q1 (install, no Safe Mode);
- Q2 and Q3 (nothing while locked);
- Q4 (appears after unlock);
- Q5 and Q6 (orb, buttons and actions respond);
- Q8 and Q9 (relock and stale action);
- Q11 and Q12 (respring, reboot, first unlock);
- Q14 and Q15 (Animation Center on and off).

No security failure may be observed at all.

**No-go** on any of the following:
- anything visible, touchable or opening while locked;
- an action that runs after a lock;
- a SpringBoard crash or Safe Mode;
- an unresponsive orb with no explanation in *Touches*.

## Risks

1. **Product behaviour changes for existing beta 3 users.** Portal leaves the locked Lock Screen. The listing text
   (`notes`, `known_issues`, `limitations`, `install` in HCG-repo `packages/com.hakmicapitalgroup.portal/package.toml`)
   must be rewritten, or users will look for it on the Lock Screen.
2. **One device, one iOS version.** The interfaces are verified against iOS 17.0.3 headers. Other versions fail
   closed: Portal hidden, with a Settings explanation, rather than unsafe.
3. **`isProtectedDataAvailable` inside SpringBoard** is unobserved until Q4. A misreport would keep Portal hidden.
   That is a functional risk, not a security one.
4. **Other tweaks** that change the Cover Sheet's gestures or views were not tested.
5. **Downgrade is manual.** apt does not downgrade automatically, so a later withdrawal of beta 4 from Candidate does
   not move installed phones back.
6. **Access policy.** HCG-repo's free-demo exception lists `0.1.0~beta1` and `0.1.0~beta3` only. Beta 4 needs its own
   owner decision on access; this proposal does not change access or pricing.

## Rollback plan

- **Per device:** `docs/QUALIFICATION_0.1.0-beta4.md` §8.
  - Enable off: immediate.
  - Kill switch: `touch …portal.disabled && sbreload`.
  - `sudo apt remove com.hakmicapitalgroup.portal`.
  - `sudo apt install --allow-downgrades com.hakmicapitalgroup.portal=0.1.0~beta3`.
- **Candidate, if a problem appears after publication:**
  - The owner approves withdrawing beta 4 through HCG-repo's normal reviewed change: an import request revert,
    *Prepare packages*, a PR and a manual *Publish*.
  - beta 3 is then the newest Candidate version again.
  - The listing's `known_issues` names the issue and the per-device commands above.
  - Stable is not involved at any point.

## If approved: the publication steps (not performed now)

1. Add `imports/hcg-portal-0.1.0-beta4-rootless.toml` to HCG-repo, pinned to run 44871433709, commit `1298ded`,
   artifact `hcg-portal-rootless-deb` and SHA-256 `8a186d99…164e4`.
2. Update the listing text for the unlocked-only behaviour.
3. Record the owner's access decision for `0.1.0~beta4`.
4. *Prepare packages*, then a PR, a review and a merge.
5. The owner runs *Publish* manually. Verify online and confirm Stable is unchanged.

## Recommendation

**Not yet.** Promote 0.1.0~beta4 to Candidate only after the device qualification passes every Go row. Until then,
beta 3 stays as the Candidate build.

Meanwhile, consider adding a known-issues note to beta 3's listing: on the reporting iPhone, the orb does not
respond. That is a listing-text change and would also need owner approval.
