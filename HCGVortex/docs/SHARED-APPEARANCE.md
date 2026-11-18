# Shared appearance contract: Vortex, Halo, Nexus (plan, not implemented)

**Status: proposal.** Nothing here is implemented in any product yet. Each product keeps working on its own settings
whether or not the others are installed.

## What each product stores today (inspected 18 Nov 2026)

| Product | Where | Appearance-related settings | Change notification |
|---|---|---|---|
| **HCG Vortex** | CFPreferences `com.hakmicapitalgroup.vortex` (`src/VortexPreferences.m`) | `accentColor` (cyan, purple, green, amber, magenta, white), `glowIntensity` 0–1. Motion: per-effect intensities. Reduce Motion follows the system setting | Darwin `com.hakmicapitalgroup.vortex/preferences-changed` |
| **HCG Nexus** (jailbreak tweak) | CFPreferences `com.hakmicapitalgroup.hcgnexus` (`Sources/Core/HCGConstants.m`, `HCGSettings.m`) | Accent is fixed cyan in code (`Sources/Panel/HCGTheme.h`). `animationsEnabled` (bool) is its motion switch. The theme adapts to Increase Contrast and Reduce Transparency | Darwin `com.hakmicapitalgroup.hcgnexus/settings-changed` |
| **HCG Nexus** (standalone app) | Sandboxed `NSUserDefaults` suite `com.hakmicapitalgroup.hcgnexus.app.data` (`Sources/Platform/App/HCGAppPlatform.m`) | As above | none |
| **HCG Halo** | **Not found.** There is no `HCGHalo/` in HCG-Jailbreak-Research (any branch), and code and repository search found no Halo source in the repositories this session can access | unknown | unknown |

## Proposed mechanism

- **A separate, neutral domain:** `com.hakmicapitalgroup.appearance`, in
  `/var/mobile/Library/Preferences/com.hakmicapitalgroup.appearance.plist`.
  - No product owns it.
  - No product ever writes another product's domain.
- **Writing is opt-in and explicit.** A product writes the shared domain only when the user taps **Share This
  Appearance** in that product's Settings. A product's own settings are never changed by another product.
- **Reading is opt-in per product.** Each product gets a **Use Shared Appearance** switch, off by default.
  - When it is on and the shared domain is present and valid, the shared values override that product's own
    appearance values at render time.
  - The product's own stored values are left untouched, so turning the switch off restores them immediately.
- **Absent or invalid falls back.** A missing domain, an unknown `version` or an out-of-range value means that key
  falls back to the product's own setting. Nothing fails or blocks.
- **Notification:** writers post Darwin `com.hakmicapitalgroup.appearance/changed` after writing. Readers re-read on
  it.
- **No network, no daemons, no new dependencies.** It is plain CFPreferences on the device. No product's package
  depends on another's.
- **Sandboxed apps:** the Nexus standalone app cannot read `/var/mobile/Library/Preferences` from its sandbox. It keeps
  its own settings and should not show the switch.

## Keys (version 1)

| Key | Type / range | Meaning | Mapping |
|---|---|---|---|
| `version` | integer, `1` | Contract version; readers ignore other versions | — |
| `accentColor` | string: `cyan` `purple` `green` `amber` `magenta` `white`, or `#RRGGBB` | Primary accent | Vortex: Circuit Flow traces, previews. Nexus: `HCGTheme` cyan accent. Halo: TBD |
| `glowIntensity` | 0.0–1.0 | Glow strength of decorative light | Vortex: trace glow. Nexus: rim light / soft cyan fills. Halo: TBD |
| `motionIntensity` | 0.0–1.0 | Scales decorative motion | Vortex: multiplies effect intensities (0 means stock animation). Nexus: below 0.1 means `animationsEnabled` off |
| `reduceMotion` | `system` \| `always` | Extra motion reduction | Reduced motion = system Reduce Motion **or** `always`. It can only add reduction, never remove the system's |
| `updatedBy` | bundle identifier string | Which product last shared | diagnostics only |
| `updatedAt` | date | When | diagnostics only |

## Rollout (separate, narrowly scoped PRs)

1. **Vortex:**
   - a read-only `VortexSharedAppearance` reader with host tests (valid, missing and invalid values);
   - the Use Shared Appearance and Share This Appearance controls in the Appearance page.
2. **Nexus (its own repository):** the same reader in the jailbreak tweak only, mapped onto `HCGTheme` and
   `animationsEnabled`. The app target is unchanged.
3. **Halo:** once its source is available. Same reader, mapped onto its own settings.
4. **Device check:** install any one product alone, then two together. Toggling sharing in one must never change the
   other's own stored values. Remove one product: the other keeps working with its own values.

## Open questions for the owner

- Should `#RRGGBB` custom colours be allowed, or only the named palette? Named only is simpler to validate.
- Where does HCG Halo live? Its settings must be inspected before mapping is decided.
