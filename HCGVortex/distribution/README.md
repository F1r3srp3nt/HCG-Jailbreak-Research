# HCG Repo distribution kit — HCG Vortex

**Nothing here publishes anything, and HCG Repo has not been changed.**

## HCG Repo

| | |
|---|---|
| APT source | `https://repo.hakmicapitalgroup.com/repo/` (the old `https://f1r3srp3nt.github.io/HCG-repo/repo/` redirects to it) |
| Website | `https://repo.hakmicapitalgroup.com/` |
| Source repository | [`F1r3srp3nt/HCG-repo`](https://github.com/F1r3srp3nt/HCG-repo) |

Read from HCG-repo's `README.md`, `config/` and `docs/` on 16 Nov 2026. HCG-repo generates `Depiction`, `SileoDepiction`, `Icon` and `Header` itself, from `packages/<id>/package.toml` and its base URL. So this kit no longer hand-writes depiction URLs or a separate Sileo depiction file.

## Proposed files for HCG-repo

| Proposal (here) | Destination in HCG-repo |
|---|---|
| `hcg-repo/packages/com.hakmicapitalgroup.vortex/package.toml` | `packages/com.hakmicapitalgroup.vortex/package.toml` |
| `hcg-repo/packages/com.hakmicapitalgroup.vortex/CHANGELOG.md` | `packages/com.hakmicapitalgroup.vortex/CHANGELOG.md` |
| `hcg-repo/packages/com.hakmicapitalgroup.vortex/icon.png` (180 px) | `packages/com.hakmicapitalgroup.vortex/icon.png` |
| `hcg-repo/imports/hcg-vortex-0.1.0-alpha-rootless.toml` | `imports/hcg-vortex-0.1.0-alpha-rootless.toml` (fill in run, commit, SHA-256) |

HCG-repo's **Prepare packages** workflow imports a pinned artifact on a review branch. Publishing stays HCG-repo's manual **Publish repository** workflow. `python3 scripts/repo_entry.py <deb>` prints the control fields and hashes for a manual cross-check. It no longer prints presentation URLs.

## Before anything is proposed to HCG-repo

- [ ] First device test passed (`docs/DEVICE_TEST_HANDOFF.md`), on a device confirmed by `scripts/device-info.sh`
- [ ] HCG Repo's suspected Sileo crash resolved or ruled out (HCG-repo `docs/SILEO_STABILITY.md`)
- [ ] **Licence decided** (see below)
- [ ] Real on-device screenshots in `screenshots/`
- [ ] Import request filled from the device-tested commit's macOS CI run
- [ ] HCG-repo `[versions."0.1.0~alpha"]` device-test evidence recorded there, or the listing stays *Experimental*

## Licence: unresolved

`../LICENSE` is **draft wording** (all rights reserved; free to install and use; no redistribution). No licence has been chosen. Hakmi Capital Group needs to decide:

- proprietary freeware, as drafted, or an open-source licence (the source repository is public);
- whether redistribution or forks are allowed;
- warranty and liability wording, reviewed by whoever handles HCG's legal terms.

Until then, the package must not be published.

## Other assets

| Item | Status |
|---|---|
| `icon-512.png` | Source icon (512 px) |
| Header image | Not created (`header.jpg` optional in HCG-repo) |
| `screenshots/` | Placeholder; capture on the tested device only |
