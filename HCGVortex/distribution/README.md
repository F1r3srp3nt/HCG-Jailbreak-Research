# HCG Repo distribution kit — HCG Vortex

**Nothing here publishes anything, and HCG Repo has not been changed.**

## HCG Repo

| | |
|---|---|
| APT source | `https://repo.hakmicapitalgroup.com/repo/` (the old `https://f1r3srp3nt.github.io/HCG-repo/repo/` redirects to it) |
| Website | `https://repo.hakmicapitalgroup.com/` |
| Source repository | [`F1r3srp3nt/HCG-repo`](https://github.com/F1r3srp3nt/HCG-repo) |

Read from HCG-repo's `README.md`, `config/` and `docs/` on 16 Nov 2026. HCG-repo generates `Depiction`, `SileoDepiction`, `Icon` and `Header` itself, from `packages/<id>/package.toml` and its base URL. So this kit no longer hand-writes depiction URLs or a separate Sileo depiction file.

The step-by-step handoff, with the release candidate's artifact and dry-run results, is in **`HCG-REPO-HANDOFF.md`**.

## Proposed files for HCG-repo

| Proposal (here) | Destination in HCG-repo |
|---|---|
| `hcg-repo/packages/com.hakmicapitalgroup.vortex/package.toml` | `packages/com.hakmicapitalgroup.vortex/package.toml` |
| `hcg-repo/packages/com.hakmicapitalgroup.vortex/CHANGELOG.md` | `packages/com.hakmicapitalgroup.vortex/CHANGELOG.md` |
| `hcg-repo/packages/com.hakmicapitalgroup.vortex/icon.png` (180 px) | `packages/com.hakmicapitalgroup.vortex/icon.png` |
| `hcg-repo/packages/com.hakmicapitalgroup.vortex/header.jpg` (1200×400, BETA badge) | `packages/com.hakmicapitalgroup.vortex/header.jpg` |
| `hcg-repo/imports/hcg-vortex-0.1.0-beta1-rootless.toml` | `imports/hcg-vortex-0.1.0-beta1-rootless.toml` (pinned to RC run 43970942708) |

HCG-repo's **Prepare packages** workflow imports a pinned artifact on a review branch. Publishing stays HCG-repo's manual **Publish repository** workflow. `python3 scripts/repo_entry.py <deb>` prints the control fields and hashes for a manual cross-check. It no longer prints presentation URLs.

## Before anything is proposed to HCG-repo

- [ ] First device test passed (`docs/DEVICE_TEST_HANDOFF.md`), on a device confirmed by `scripts/device-info.sh`
- [ ] HCG Repo's suspected Sileo crash resolved or ruled out (HCG-repo `docs/SILEO_STABILITY.md`)
- [x] Licence model decided: proprietary freeware
- [ ] Optional: on-device screenshots in `screenshots/` (not required by HCG-repo)
- [x] Import request filled from the release candidate's macOS CI run (commit 7d5e5b9)
- [ ] HCG-repo `[versions."0.1.0~beta1"]` device-test evidence recorded there, or the listing stays *Experimental*

## Licence

**Decided: proprietary freeware** (`../LICENSE`). Free to download and use; no redistribution, modified versions or sale without HCG's permission; source published for transparency only. Nothing third-party is bundled in the package. The wording has not been reviewed by counsel.

## Other assets

| Item | Status |
|---|---|
| `icon-512.png` | Source icon (512 px) |
| Header image | `hcg-repo/packages/com.hakmicapitalgroup.vortex/header.jpg` (`scripts/make_listing_header.py`) |
| `screenshots/` | Placeholder; capture on the tested device only |
