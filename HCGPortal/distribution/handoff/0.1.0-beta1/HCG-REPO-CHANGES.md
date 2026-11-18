# HCG-repo changes for HCG Portal 0.1.0~beta1

Apply on a review branch, `candidate/hcg-portal-0.1.0-beta1`, then let **Prepare packages** import the pinned build.
(Done 18 Nov 2026: branch pushed, Prepare packages IMPORTED, PR #11 merged as `ba1026c`, Publish run 44402572548
succeeded with online verification.)

## 1. New package: `packages/com.hakmicapitalgroup.portal/`

Copy `package.toml`, `CHANGELOG.md`, `icon.png` (provisional), `README.md` from `hcg-repo/packages/…`.

```toml
[access]
level = "connect"
exception_versions = ["0.1.0~beta1"]

[versions."0.1.0~beta1"]
status = "experimental"
label = "Free public beta demo — Simulator-tested, not yet device-tested."
```

`level = "connect"` is HCG's default and decides nothing about production; the exception keeps exactly this version a
free demo in the candidate source only. No `device_tests` entry until a phone has attempted the install.

## 2. Import manifest

`imports/hcg-portal-0.1.0-beta1-rootless.toml` (unchanged copy). Expected: `IMPORTED`, pool SHA-256
`9ccfeb9b6b832edb3e8745c8e1774d93cc5623ebde1023102cf95bb139220dae`, lock entry `channel: candidate`.

## 3. Docs

- `docs/ACCESS.md`, decisions table: add
  `| HCG Portal (com.hakmicapitalgroup.portal) | connect (HCG default; production access not decided). Exception (owner, 18 Nov 2026): 0.1.0~beta1 only is a free public beta demo, candidate channel only |`
- `docs/CANDIDATE.md`: add Portal `0.1.0~beta1` to the free-exception list and an inventory row (source, run,
  artifact, SHA-256, size; Simulator-tested, not device-tested; Nexus *Update needed*; Devices *Not connected*).

## 4. Review checklist for the importer

- Entitlements: none on either binary.
- Links only system frameworks (UIKit, QuartzCore, CoreGraphics, Preferences for the bundle) and CydiaSubstrate; no
  network APIs, URLs, LocalAuthentication, keychain, passcode or notification-content APIs (`validate.sh` §6–7).
- `postrm` only on purge, only `/var/mobile/Library/Preferences/com.hakmicapitalgroup.portal.*`.
- `bin/hcgrepo channel … stable` should be refused (free demo stays in candidate).

## 5. Not changed

`config/products.toml` (no store page), other packages, the stable source.
