# HCG Halo 0.2.0~beta1 handoff (with HCG Nexus 0.2.2~beta1)

**Free public beta demos, candidate channel only. Not device-tested. Nothing is published.**

## Packages

| | HCG Halo 0.2.0~beta1 | HCG Nexus 0.2.2~beta1 |
|---|---|---|
| Package | `com.hakmicapitalgroup.halo_0.2.0~beta1_iphoneos-arm64.deb` | `com.hakmicapitalgroup.hcgnexus_0.2.2~beta1_iphoneos-arm64.deb` |
| Size | 391,074 bytes | 466,766 bytes |
| SHA-256 | `391a4421de98225169e0f1ba37b63bd3b7cc4b5321d00dbed7b689be85ae6e54` | `696b15849e6fcf60c8216e9187a353a3cb1256e1a88b57e968660d5138fb3f52` |
| Source | HCG-Jailbreak-Research `778c21a168fd957fa3f1195a91d4144e9ca36913` (branch `claude/halo-nexus-border`) | HCG-Nexus `b68768f829a6505a167368c4d8dc6d0710ec5450` (branch `claude/nexus-halo-border`) |
| Build | macOS/Xcode run [44216299888](https://github.com/F1r3srp3nt/HCG-Jailbreak-Research/actions/runs/44216299888), artifact `hcg-halo-rootless-deb` ID 14388546682 (kept until 2027-02-16) | Xcode "Build package" run [44214599706](https://github.com/F1r3srp3nt/HCG-Nexus/actions/runs/44214599706), artifact `hcg-nexus-rootless-deb` ID 14387323372 (**expires 2026-11-25**) |
| Checks | `validate.sh --require-new-abi`: 0 failures, 0 warnings (CI, and locally from the source commit on the downloaded file); 415 simulator runtime checks | `scripts/check.sh` all pass; `inspect-package.py rootless --require-new-arm64e-abi` all OK, including `HaloBorder.plist` valid with `nexusVersion` = 0.2.2~beta1 |
| Format | gzip `control.tar.gz` / `data.tar.gz` | gzip `control.tar.gz` / `data.tar.gz` |

**Baseline preserved:** HCG Halo 0.1.0~beta1 (SHA-256 `c0a3301c9b38cdac812d439fb919c3a77bfcb7999c52ea174d799e88ba24c9af`)
and its import, pool file and handoff are unchanged.

**Handoff archive:** run [44218558190](https://github.com/F1r3srp3nt/HCG-Jailbreak-Research/actions/runs/44218558190),
artifact `hcg-halo-0.2.0-beta1-handoff` (ID 14389860802, kept until 2027-02-16). The run:

- checked the build run and artifact through the GitHub API;
- recomputed the SHA-256 from a fresh download;
- re-ran `validate.sh --require-new-abi` from `778c21a`;
- re-extracted the archive and verified `SHA256SUMS`.

## Compatibility and install order

- **Order:** install Halo 0.2.0~beta1 and Nexus 0.2.2~beta1 in either order, then respring once.
- **No dependency:** neither package declares `Depends` on the other.
- **Halo without a compatible Nexus:** this covers Nexus absent, 0.2.1~beta1, and the separate 0.3.0~beta1 line,
  which has no border interface. Halo shows *Requires compatible HCG Nexus*, and its screen edge is unaffected.
- **Nexus without Halo:** the normal panel.
- **Version note:** 0.3.0~beta1 was already taken by a separate Nexus line, so this build is 0.2.2~beta1. A
  package manager may offer that 0.3.0~beta1 as an upgrade, and it would remove the border interface.

## HCG-repo

Review PR [F1r3srp3nt/HCG-repo#8](https://github.com/F1r3srp3nt/HCG-repo/pull/8). Prepare packages run 44218298900
imported both artifacts (commit `cb82167`), and the pooled files match the pins. The review branch is
[`candidate/hcg-halo-0.2.0-beta1-nexus-0.2.2-beta1`](https://github.com/F1r3srp3nt/HCG-repo/tree/candidate/hcg-halo-0.2.0-beta1-nexus-0.2.2-beta1).
It holds both import manifests (`channel = "candidate"`), the `exception_versions` additions for exactly these two
versions, the listings and the changelogs.

## Preview evidence (not a device result)

Workflow *HCG Halo × Nexus preview*, run
[44216300027](https://github.com/F1r3srp3nt/HCG-Jailbreak-Research/actions/runs/44216300027). It ran HCG Nexus's
real panel code with HCG Halo's real link and renderer in the iOS Simulator. All 14 structural checks passed. The
artifact holds the 176 s video and the console log. Stills: `../../docs/preview/halo-nexus-preview-sheet.jpg`.

## Device test

Rows N0–N17 in `../../docs/DEVICE_TEST_CHECKLIST.md` and HCG-Nexus `docs/HALO-BORDER.md`. All are pending.
