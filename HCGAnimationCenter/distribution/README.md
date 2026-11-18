# HCG Repo distribution kit: HCG Animation Center

**Nothing here publishes anything.** HCG-repo (`F1r3srp3nt/HCG-repo`) was not modified from this project: the files
below are the candidate import request, ready to copy onto an HCG-repo review branch and import with **Prepare
packages**.

| | |
|---|---|
| Target source | **HCG Repo Candidate**: `https://repo.hakmicapitalgroup.com/repo/candidate/` |
| Access | Free public beta demo: no sign-in, no payment, candidate channel only — authorised by the owner on 18 Nov 2026 ("Candidate betas are authorised as free public demos at …/repo/candidate/") |
| Package | `com.hakmicapitalgroup.animationcenter` `0.1.0~beta1` `iphoneos-arm64` (first version) |

## Files: one copy of each

| File (here) | Destination in HCG-repo | Notes |
|---|---|---|
| `hcg-repo/imports/hcg-animationcenter-0.1.0-beta1-rootless.toml` | `imports/…` | **The import manifest.** `channel = "candidate"`, pinned to the CI run, commit, artifact and SHA-256 |
| `hcg-repo/packages/com.hakmicapitalgroup.animationcenter/package.toml` | `packages/…/package.toml` | listing, access exception for exactly `0.1.0~beta1`, known issues, limitations, install, removal |
| `hcg-repo/packages/com.hakmicapitalgroup.animationcenter/CHANGELOG.md` | `packages/…/CHANGELOG.md` | |
| `hcg-repo/packages/com.hakmicapitalgroup.animationcenter/icon.png` | `packages/…/icon.png` | 180 px, **provisional** |
| `hcg-repo/packages/com.hakmicapitalgroup.animationcenter/README.md` | `packages/…/README.md` | asset provenance |
| — | `config/products.toml` | **no entry**: no HCG Store page exists (the web renderer for HCG Store is a separate integration) |
| `handoff/0.1.0-beta1/` | — | handoff notes and proposed HCG-repo edits |
| `icon-512.png` | — | provisional source icon (`scripts/make_icon.py`) |

## 0.1.0~beta1

| | |
|---|---|
| Build | **HCG Animation Center build** run [44242604467](https://github.com/F1r3srp3nt/HCG-Jailbreak-Research/actions/runs/44242604467), conclusion **success**: macOS 15, Xcode, Theos `8167f59`; `validate.sh --require-new-abi` 0 failures / 0 warnings; Simulator runtime tests 103 checks passed |
| Source | `F1r3srp3nt/HCG-Jailbreak-Research@2d642bd29974001de742d6d930a9b30599e8b245` (branch `claude/stoic-gates-07elp7`) |
| Package | `com.hakmicapitalgroup.animationcenter_0.1.0~beta1_iphoneos-arm64.deb`, **360,342 bytes** |
| SHA-256 | `27a161b3cc323f09940211553b058873218697b49c995812f04e579f97429f60` |
| Artifact | `hcg-animationcenter-rootless-deb`, ID 14399579139 (90 days) |
| Format | `debian-binary`, `control.tar.gz`, `data.tar.gz` — all gzip, fully decompressed; `dpkg-deb --fsys-tarfile` exit 0 |
| Re-validation | downloaded artifact re-hashed and re-validated from the source commit outside CI: same SHA-256, 0 failures / 0 warnings |
| Handoff archive | workflow **HCG Animation Center handoff archive** (`.github/workflows/hcg-animationcenter-handoff.yml`): see `handoff/0.1.0-beta1/README.md` |
| Device testing | **None.** Installation not yet attempted; runtime untested (`../docs/DEVICE_TEST_CHECKLIST.md`) |

**Only these bytes are the 0.1.0~beta1 candidate.** Later commits on the branch (documentation, the preview harness)
also ran the build workflow and produced packages with the same version number but a different build ID and
SHA-256 (runs 44243655145 and 44245294301). Those are CI by-products, not candidates; do not import them. A changed
package will get a new version.

The real import must use the CI artifact named in the manifest; **Prepare packages** fetches it on HCG-repo's side and
refuses any other bytes.
