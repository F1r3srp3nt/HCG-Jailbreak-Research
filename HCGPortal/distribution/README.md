# HCG Repo distribution kit: HCG Portal

| | |
|---|---|
| Target source | **HCG Repo Candidate**: `https://repo.hakmicapitalgroup.com/repo/candidate/` |
| Access | Free public beta demo: no sign-in, no payment, candidate channel only — authorised by the owner on 18 Nov 2026 ("The beta is authorised as a free public candidate demo at …/repo/candidate/") |
| Package | `com.hakmicapitalgroup.portal` `0.1.0~beta1` `iphoneos-arm64` (first version) |
| Stable source | **untouched**: no stable entry, no promotion |

## Files: one copy of each

| File (here) | Destination in HCG-repo | Notes |
|---|---|---|
| `hcg-repo/imports/hcg-portal-0.1.0-beta1-rootless.toml` | `imports/…` | **The import manifest.** `channel = "candidate"`, pinned to the CI run, commit, artifact and SHA-256 |
| `hcg-repo/packages/com.hakmicapitalgroup.portal/package.toml` | `packages/…/package.toml` | listing, access exception for exactly `0.1.0~beta1`, known issues, limitations, install, removal |
| `hcg-repo/packages/com.hakmicapitalgroup.portal/CHANGELOG.md` | `packages/…/CHANGELOG.md` | |
| `hcg-repo/packages/com.hakmicapitalgroup.portal/icon.png` | `packages/…/icon.png` | 180 px, **provisional** |
| `hcg-repo/packages/com.hakmicapitalgroup.portal/README.md` | `packages/…/README.md` | asset provenance |
| — | `config/products.toml` | **no entry**: no HCG Store page exists |
| `handoff/0.1.0-beta1/` | — | handoff notes and the HCG-repo edits (ACCESS, CANDIDATE) |
| `icon-512.png` | — | provisional source icon (`scripts/make_icon.py`) |

## 0.1.0~beta1 — the candidate bytes

| | |
|---|---|
| Build | **HCG Portal build** run [44395826216](https://github.com/F1r3srp3nt/HCG-Jailbreak-Research/actions/runs/44395826216), conclusion **success**: macOS 15, Xcode, Theos `8167f59`; host tests (2.6 M checks); `validate.sh --require-new-abi` 0 failures / 0 warnings; Simulator runtime tests 66/66 |
| Source | `F1r3srp3nt/HCG-Jailbreak-Research@4bfed3342fa38d83bd06fe2c38cfd9478666b3c9` (branch `claude/quirky-johnson-furqhh`) |
| Package | `com.hakmicapitalgroup.portal_0.1.0~beta1_iphoneos-arm64.deb`, **273,714 bytes** |
| SHA-256 | `9ccfeb9b6b832edb3e8745c8e1774d93cc5623ebde1023102cf95bb139220dae` |
| Artifact | `hcg-portal-rootless-deb`, ID 14470690859 (expires 2027-02-16) |
| Format | `debian-binary`, `control.tar.gz`, `data.tar.gz` — all gzip, fully decompressed; `dpkg-deb --fsys-tarfile` exit 0 |
| Re-validation | downloaded artifact re-hashed and re-validated from the source commit outside CI (Linux): same SHA-256, 0 failures / 0 warnings |
| Preview | workflow **HCG Portal preview** on the same commit (see `../docs/TESTING.md`) |
| Device testing | **None.** Installation not yet attempted; runtime untested (`../docs/DEVICE_TEST_CHECKLIST.md`) |

**Only these bytes are the 0.1.0~beta1 candidate.** Earlier and later commits on the branch also ran the build
workflow and produced packages with the same version number but a different build ID and SHA-256. Those are CI
by-products; do not import them. A changed package gets a new version.
