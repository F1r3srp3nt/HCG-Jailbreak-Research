# HCG-repo changes for HCG Animation Center 0.1.0~beta1 (proposed; not applied)

HCG-repo was outside this project's repository access, so nothing there was changed. Apply on a review branch, e.g.
`candidate/hcg-animationcenter-0.1.0-beta1`, then run **Prepare packages**.

## 1. New package: `packages/com.hakmicapitalgroup.animationcenter/`

Copy from `hcg-repo/packages/com.hakmicapitalgroup.animationcenter/`: `package.toml`, `CHANGELOG.md`, `icon.png`
(provisional), `README.md`.

### Access decision

```toml
[access]
level = "connect"
exception = "Free public beta demo … for the versions in exception_versions only …"
exception_versions = ["0.1.0~beta1"]
```

- The exception follows the owner's instruction of 18 Nov 2026: candidate betas are free public demos at
  `https://repo.hakmicapitalgroup.com/repo/candidate/` (no account, no payment).
- `level = "connect"` is HCG's default and does not decide production pricing or access. With a non-public level,
  the free-demo policy keeps this version in the candidate source only.

### Version entry

```toml
[versions."0.1.0~beta1"]
status = "experimental"
label = "Free public beta demo — Simulator-tested, not yet device-tested."
```

No `device_tests` entry until a phone has attempted the install.

## 2. Import manifest

`imports/hcg-animationcenter-0.1.0-beta1-rootless.toml` (copy unchanged). Expected import result: `IMPORTED`, pool file
SHA-256 `27a161b3cc323f09940211553b058873218697b49c995812f04e579f97429f60`, lock entry `channel: candidate`.

## 3. Review checklist for the importer

- Entitlements: none on either binary (`[review]` makes any entitlement fail the import).
- Links only system frameworks (UIKit, AVFoundation, CoreMedia, ImageIO, PhotosUI, UniformTypeIdentifiers, …) and
  CydiaSubstrate; no network APIs or URLs (validated).
- `postrm` only on purge, only this package's preferences and `/var/mobile/Library/HCGAnimationCenter`.
- `bin/hcgrepo channel … stable` should be refused (free demo stays in candidate).

## 4. Not changed

`config/products.toml` (no store page), other packages, access code, stable source.
