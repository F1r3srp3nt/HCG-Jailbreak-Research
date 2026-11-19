# HCG Halo 0.1.0~beta1: HCG Repo Candidate import handoff

**Free public beta demo — not yet device-tested.**

This handoff is for HCG Repo's **candidate** source, `https://repo.hakmicapitalgroup.com/repo/candidate/`. It
does not go in the stable source. HCG Halo candidate builds are authorised as free public beta demos: no account
and no payment. That does not change production pricing or access policies. There is no expiry date and no remote
disabling.

| | |
|---|---|
| Package | `com.hakmicapitalgroup.halo` · **HCG Halo (Beta)** · `0.1.0~beta1` · `iphoneos-arm64` (rootless) |
| Source commit | `F1r3srp3nt/HCG-Jailbreak-Research@ab439f8bd0990500ba373616073a1d9b108686e6` |
| Build | macOS CI run [44062061609](https://github.com/F1r3srp3nt/HCG-Jailbreak-Research/actions/runs/44062061609) (HCG Halo build), `validate.sh --require-new-abi` |
| Artifact | `hcg-halo-rootless-deb` (ID 14317739735), kept until 2027-02-15 |
| `.deb` SHA-256 | `c0a3301c9b38cdac812d439fb919c3a77bfcb7999c52ea174d799e88ba24c9af` |
| Size | 264,782 bytes |
| Device testing | **None.** Installation not yet attempted; runtime untested |

## Archive contents

| File | What it is | Where it goes in HCG-repo |
|---|---|---|
| `com.hakmicapitalgroup.halo_0.1.0~beta1_iphoneos-arm64.deb` | The Xcode-built package. **Prepare packages** fetches it from the pinned artifact; this copy is for review | not committed by hand |
| `hcg-repo/imports/hcg-halo-0.1.0-beta1-rootless.toml` | The **only** import request: `channel = "candidate"`, pinned to the run, commit and SHA-256 | `imports/` |
| `hcg-repo/packages/com.hakmicapitalgroup.halo/` | `package.toml` (listing, access exception, known issues, version entry), `CHANGELOG.md`, provisional `icon.png`, `README.md` | `packages/com.hakmicapitalgroup.halo/` |
| `HCG-REPO-CHANGES.md` | The proposed edits and the **access-level decision for the owner** | read first |
| `KNOWN-ISSUES.md` | Known issues and open questions | reference (also in `package.toml`) |
| `DEVICE-TEST-CHECKLIST.md`, `RECOVERY.md` | The first device test and recovery steps | reference |
| `icon-512-provisional.png` | Provisional source icon | reference |
| `FORMAT.txt` | Archive members, compression and decompression exit statuses | reference |
| `VALIDATE.txt` | `validate.sh --require-new-abi` from the source commit, re-run in the handoff run | reference |
| `PROVENANCE.md`, `provenance.json` | Commit, run, artifact ID, file name, size, SHA-256 and how each was checked | reference |
| `control.txt`, `contents.txt` | `dpkg-deb -f` and `dpkg-deb -c` output | reference |
| `LICENSE` | Proprietary freeware terms | reference |
| `SHA256SUMS` | SHA-256 of every file above | verify first |

## Verify

```sh
tar -xzf hcg-halo-0.1.0-beta1-handoff.tar.gz
cd hcg-halo-0.1.0-beta1-handoff
shasum -a 256 -c SHA256SUMS          # Linux: sha256sum -c SHA256SUMS
```

Every line must end in `OK`. The `.deb` line must match the `sha256` in the import request.

## Not claimed

- **Device compatibility or runtime behaviour.** No phone has installed this build.
- **Performance or battery figures.** Not measured.
- **Support for any iPhone other than the profile list's implemented entry.** Only iPhone 11 Pro Max is implemented,
  and it is not device-tested.
- **Publication.** None. Publishing is HCG-repo's manual **Publish** workflow, after the access decision in
  `HCG-REPO-CHANGES.md`.
