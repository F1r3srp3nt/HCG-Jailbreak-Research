# HCG Animation Center 0.1.0~beta1 handoff

**Free public beta demo, HCG Repo Candidate only. Build-validated and Simulator-tested; not device-tested. Nothing is
published.**

## Package

| | |
|---|---|
| File | `com.hakmicapitalgroup.animationcenter_0.1.0~beta1_iphoneos-arm64.deb` |
| Size | 360,342 bytes |
| SHA-256 | `27a161b3cc323f09940211553b058873218697b49c995812f04e579f97429f60` |
| Source | HCG-Jailbreak-Research `2d642bd29974001de742d6d930a9b30599e8b245` (branch `claude/stoic-gates-07elp7`) |
| Build | macOS/Xcode run [44242604467](https://github.com/F1r3srp3nt/HCG-Jailbreak-Research/actions/runs/44242604467), artifact `hcg-animationcenter-rootless-deb` ID 14399579139 |
| Checks | `validate.sh --require-new-abi`: 0 failures, 0 warnings (CI, and again outside CI from the source commit on the downloaded file); Simulator runtime tests: 103 checks |
| Format | gzip `control.tar.gz` / `data.tar.gz` (the format HCG Vortex 0.1.0~beta2 proved installs on the phone) |
| Contents | `HCGAnimationCenter.dylib` + filter (SpringBoard only), `HCGAnimationCenterPrefs.bundle`, PreferenceLoader entry; `postrm` (purge only) |

## Import

Copy `../../hcg-repo/` onto an HCG-repo review branch (see `HCG-REPO-CHANGES.md`) and run **Prepare packages**. The
manifest `imports/hcg-animationcenter-0.1.0-beta1-rootless.toml` pins the run, commit, artifact and SHA-256, with
`channel = "candidate"`.

## The handoff archive

The **HCG Animation Center handoff archive** workflow (pinned to the values above) re-checks the run and artifact
through the GitHub API, recomputes the SHA-256 from a fresh download, re-runs `validate.sh --require-new-abi` from the
source commit, records the archive format, and bundles the `.deb` with the manifest, listing, changelog, device-test
checklist, recovery notes, compatibility and live-background definitions, `device-info.sh`, licence and
`provenance.json` / `PROVENANCE.md` under `SHA256SUMS`, then extracts it again and verifies it.

## Before installing on a phone

1. `sh device-info.sh` (read-only) and send the report.
2. Follow `DEVICE-TEST-CHECKLIST.md`: install (I1–I4) and runtime are recorded separately; the hierarchy probe (P1)
   comes before judging any background.
3. Keep `RECOVERY.md` at hand. The tweak is off after installation and never modifies the system wallpaper.
