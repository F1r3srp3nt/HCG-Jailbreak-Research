# Integrations: what exists, what Portal uses, what companions would need

HCG Portal owns its interface and its interactions. Every companion is **optional**: Portal declares no `Depends` on
any of them, links none of them, finds them at run time, and works on its own. Portal reads and writes **only** its
own preferences (`com.hakmicapitalgroup.portal`, `…portal.status`); `scripts/validate.sh` fails the build if either
binary even names another HCG product's preference domain.

Contracts were inspected on 18 Nov 2026 before anything new was defined:

| Product | Source inspected | Contract found |
|---|---|---|
| HCG Nexus | HCG-Nexus `8a37a46` (branch `claude/nexus-combined-0.3.1`, = 0.3.1~beta1 code `82412dd`); `main` `3136149` | `HCGNexusBorderInterface` v1 (read-only panel state and border events, for HCG Halo). Darwin names `…hcgnexus/settings-changed`, `…/workspaces-changed`, `…/status-request`. **No way for another tweak to open the panel.** |
| HCG Animation Center | this repository, branch `claude/stoic-gates-07elp7` (0.1.0~beta1, `2d642bd`) | A Settings page (`HCGAnimationCenterPrefs.bundle`, PreferenceLoader label *HCG Animation Center*). Darwin `…animationcenter/preferences-changed`, `…/status-request`, `…/probe-request`. **No URL scheme, no deep link, no runtime interface.** |
| HCG Halo | this repository, branch `claude/hcg-halo-tweak-tfnxxl` (0.3.0~beta1, `e22527d`) | Consumes Nexus's border interface; Settings contract `HCGHaloNexusIntegration` = 1 for Nexus. **No interface for other tweaks to request lighting.** |
| Connector / Origin | none found in any repository this session can list | — |
| HCG Agent Runtime | Agent-Runtime `main` (README only); branch `claude/brave-rubin-7vwtg1` (unmerged) | Loopback HTTP API `/api/v1/tasks…` with preview → `approve {digest}` → run, audit chain. iOS jailbroken adapter: **planned, not implemented** (`docs/platforms/IOS.md`). |

## 1. Nexus — not openable yet (Portal side ready)

**Today:** HCG Nexus 0.3.1~beta1 has no interface that lets another process or tweak open its panel; its panel opens
only from its own edge handle, and only while unlocked. Portal therefore shows **Nexus · Update needed** when Nexus
is installed, **Not installed** when it is not, and does nothing else. It never calls Nexus's internal classes
(`HCGOverlayController`, `simulateHandleActivation` are internal and not a contract).

**Proposed contract (for HCG-Nexus to implement): `HCGNexusPortalInterface`, version 1.** Modelled on Nexus's own
`HCGNexusBorderInterface` so it fits Nexus's conventions:

```objc
// In-process, SpringBoard, main thread. Looked up by name; no link-time dependency either way.
@interface HCGNexusPortalInterface : NSObject
+ (NSInteger)interfaceVersion;                         // 1
+ (nullable instancetype)activeInterface;              // nil while Nexus is disabled or not built
- (BOOL)canOpenPanel;                                  // enabled, panel built, not blocked
- (void)openPanelFromSource:(NSString *)source         // "hcg-portal"
                 completion:(void (^)(BOOL opened, NSString *_Nullable reason))completion;
@end
```

Rules Portal already follows (and Nexus should enforce):

- Portal calls `openPanelFromSource:` **only after** SpringBoard reported a successful authentication for that exact
  selection (see `docs/ARCHITECTURE.md`, *Authentication*). Nexus should still refuse while `isUILocked` and wait up
  to ~3 s for its own lock monitor to report unlocked, then open, then call `completion` once on the main thread.
- No arguments carry user data; `source` is a fixed identifier.
- Portal gives up after 5 s without an answer and records it (*HCG Nexus did not answer*).

**Companion change needed in HCG-Nexus:** add the class above to `Sources/Panel/`, register it when the panel is
built (as `HCGNexusBorderInterface setActiveInterface:` is), document it next to `docs/HALO-BORDER.md`, and test it.
Portal's side is implemented (`src/PortalCompanions.m`) and covered by a test double in the Simulator tests and the
preview (*“after authentication Nexus is asked once to open its panel (contract double)”*). **Not verified against a
real Nexus build.**

## 2. Backgrounds — HCG Animation Center through Settings

**Today:** Animation Center's only user interface is its Settings page. The supported route is therefore the
**Settings app** (`com.apple.Preferences`), opened with the same LaunchServices route HCG Nexus 0.3.1~beta1 uses to
open apps from SpringBoard. The user lands in Settings, where *HCG Animation Center* is listed. Portal does **not**
guess a `prefs:root=` deep link: PreferenceLoader entries have no documented identifier for one.

Installed means both files exist under the jailbreak root: `Library/PreferenceBundles/HCGAnimationCenterPrefs.bundle/Info.plist`
and `Library/PreferenceLoader/Preferences/HCGAnimationCenterPrefs.plist`. Otherwise: **Backgrounds · Not installed**.

**Companion change that would make this direct (HCG Animation Center):** declare and test one route to its page, for
example a documented Settings deep link verified on the device (`prefs:root=…` for its PreferenceLoader entry), or a
small in-process interface `HCGAnimationCenterPortalInterface` v1 with `-openLibraryFromSource:completion:` that
opens Settings at its library. Portal would then switch to it at run time, keeping Settings as the fallback.

**Background scene:** Animation Center may provide the Lock Screen background. They coexist without coordination:
Animation Center draws at index 0 of the Lock wallpaper view or the Cover Sheet window (`HACHosts.m`); Portal draws
on top of the Lock Screen's main page. Neither touches the other.

## 3. Coordinated edge lighting — HCG Halo (optional)

No Halo interface accepts lighting requests, so Portal defines a **one-way, in-process event** that a future Halo
build *may* observe. Nothing depends on it; with no observer it costs one `NSNotificationCenter` post per event.

`PortalLightingEventNotification` = `com.hakmicapitalgroup.portal.lighting-event`, posted on the main thread,
`object` nil, `userInfo` exactly:

| Key | Type | Values |
|---|---|---|
| `event` | NSString | `expanded`, `collapsed`, `authenticating`, `opened`, `unlock`, `hidden` |
| `interfaceVersion` | NSNumber | `1` |
| `palette` | NSString | `signature`, `aurora`, `solar`, `mono` |
| `intensity` | NSNumber | 0 … 1 |

No app names, bundle identifiers, destinations or notification data are ever included (tested).

**Companion change needed in HCG Halo (if wanted):** observe the notification only when the user opts in (for
example *Show Halo on → Lock Screen* plus a new *React to HCG Portal* switch), validate `userInfo` as strictly as it
validates Nexus events, and draw a brief pulse. Halo must not change its own preferences in response.

## 4. Devices — Connector / Origin

No Connector or Origin integration exists in any repository this session can see. **Devices always shows “Not
connected”** and does nothing (no authentication is requested, no command is run). See `docs/ROADMAP.md` for the
authenticated device selection planned later.

## 5. HCG Apps — user-selected shortcuts

Up to six apps chosen in *Settings › HCG Portal › HCG Apps* (installed HCG apps, `com.hakmicapitalgroup.*`, are
suggested first). Stored in Portal's own preferences as `[{id, name}]`. Opening one requests authentication first and
then uses the Nexus-proven launcher (`LSApplicationWorkspace openApplicationWithBundleID:`, falling back to
`-[SpringBoard launchApplicationWithIdentifier:suspended:]`). No deep links.

## 6. Agent Runtime

Not used in 0.1.0~beta1. Its approval contract (preview → approve the exact digest → run, audited) is the model for
the roadmap item *Approved actions through Agent Runtime* (`docs/ROADMAP.md`). Its iOS jailbroken adapter is not
implemented, and its API is loopback-only on the host running it, so Portal cannot reach it today.
