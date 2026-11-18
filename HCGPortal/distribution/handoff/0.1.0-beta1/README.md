# HCG Portal 0.1.0~beta1 handoff

**Free public beta demo, HCG Repo Candidate only. Build-validated and Simulator-tested; NOT device-tested.**

## Package

| | |
|---|---|
| File | `com.hakmicapitalgroup.portal_0.1.0~beta1_iphoneos-arm64.deb` |
| Size | 273,714 bytes |
| SHA-256 | `9ccfeb9b6b832edb3e8745c8e1774d93cc5623ebde1023102cf95bb139220dae` |
| Source | HCG-Jailbreak-Research `4bfed3342fa38d83bd06fe2c38cfd9478666b3c9` (branch `claude/quirky-johnson-furqhh`) |
| Build | macOS/Xcode run [44395826216](https://github.com/F1r3srp3nt/HCG-Jailbreak-Research/actions/runs/44395826216), artifact `hcg-portal-rootless-deb` ID 14470690859 |
| Checks | `validate.sh --require-new-abi`: 0 failures, 0 warnings (CI, and again outside CI on the downloaded file); Simulator runtime tests: 66/66 |
| Format | gzip `control.tar.gz` / `data.tar.gz` (the format HCG Vortex 0.1.0~beta2 proved installs on the phone) |
| Contents | `HCGPortal.dylib` + filter (SpringBoard only), `HCGPortalPrefs.bundle`, PreferenceLoader entry; `postrm` (purge only) |

## Import

Copy `../../hcg-repo/` onto an HCG-repo review branch (see `HCG-REPO-CHANGES.md`) and run **Prepare packages**. The
manifest `imports/hcg-portal-0.1.0-beta1-rootless.toml` pins the run, commit, artifact and SHA-256 with
`channel = "candidate"`. Then merge and run **Publish** (owner). The stable source is not touched.

## The handoff archive

The **HCG Portal handoff archive** workflow (`.github/workflows/hcg-portal-handoff.yml`, pinned to the values above)
re-checks the run and artifact through the GitHub API, recomputes the SHA-256 from a fresh download, re-runs
`validate.sh --require-new-abi` from the source commit, records the archive format, and bundles the `.deb` with the
manifest, listing, changelog, device-test checklist, recovery, compatibility, integrations and roadmap notes,
`device-info.sh`, licence and `provenance.json` / `PROVENANCE.md` under `SHA256SUMS`, then extracts and verifies it.

## Before installing on a phone

1. `sh device-info.sh` (read-only) and send the report; confirm iOS and jailbreak (`COMPATIBILITY.md`).
2. Follow `DEVICE-TEST-CHECKLIST.md`: install (I1–I3) and runtime are recorded separately.
3. Keep `RECOVERY.md` at hand. Portal is off after installation.
