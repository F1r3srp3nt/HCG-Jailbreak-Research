# HCG Vortex 0.1.0~beta2: HCG Repo Candidate import handoff

**Packaging compatibility candidate — installation fix not yet device-verified.**

0.1.0~beta2 is a packaging-only rebuild of 0.1.0~beta1 with gzip package members. It is meant for HCG Repo's
**candidate** source, `https://repo.hakmicapitalgroup.com/repo/candidate/` (HCG-repo `docs/CANDIDATE.md`). It does
not go in the stable source. 0.1.0~beta1 is unchanged and must stay as it is: same version, same SHA-256
`bb0af727…07673eea`.

| File | What it is | Where it goes in HCG-repo |
|---|---|---|
| `com.hakmicapitalgroup.vortex_0.1.0~beta2_iphoneos-arm64.deb` | The Xcode-built package. **Prepare packages** fetches it from the pinned artifact; this copy is for review | not committed by hand |
| `imports/hcg-vortex-0.1.0-beta2-rootless.toml` | Import request with `channel = "candidate"`, pinned to the run, commit and SHA-256 | `imports/hcg-vortex-0.1.0-beta2-rootless.toml` |
| `CHANGELOG.md` | Changelog entry for exactly this version | prepend to `packages/com.hakmicapitalgroup.vortex/CHANGELOG.md` |
| `DEVICE-TESTING.md` | Install: not yet attempted. Runtime: untested | read before adding any `device_tests` entry |
| `HCG-REPO-CHANGES.md` | The `package.toml` edits, including the **access decision this version needs** | `packages/com.hakmicapitalgroup.vortex/package.toml` |
| `COMPARISON.md` | Every difference from 0.1.0~beta1, each one accounted for | reference |
| `FORMAT.txt` | Archive members, compression and the exit status of each decompression | reference |
| `VALIDATE.txt` | `validate.sh --require-new-abi` output from the handoff run | reference |
| `PROVENANCE.md`, `provenance.json` | Commit, run, artifact ID, filename, size, SHA-256 and how each was checked | reference |
| `control.txt`, `contents.txt` | `dpkg-deb -f` and `dpkg-deb -c` output | reference |
| `LICENSE` | Proprietary freeware terms | reference |
| `SHA256SUMS` | SHA-256 of every file above | verify first |

## Verify

```sh
tar -xzf hcg-vortex-0.1.0-beta2-handoff.tar.gz
cd hcg-vortex-0.1.0-beta2-handoff
shasum -a 256 -c SHA256SUMS          # Linux: sha256sum -c SHA256SUMS
```

Every line must end in `OK`. The `.deb` line must match the `sha256` in the import request:
`a326759a697899ee938b3db3ccc62521994c01084880b43802c0769f90179395`.

## Not claimed

- **That the installation failure is fixed.** Not until a phone installs this build.
- **What caused beta1's failure.** Unconfirmed.
- **Device compatibility or runtime behaviour.** None. See `DEVICE-TESTING.md`.
- **Publication.** None. Publishing is HCG-repo's manual **Publish** workflow, and it needs the access decision in
  `HCG-REPO-CHANGES.md`.
