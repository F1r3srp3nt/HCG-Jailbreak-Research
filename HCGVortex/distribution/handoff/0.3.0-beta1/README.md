# HCG Vortex 0.3.0~beta1: HCG Repo Candidate import handoff

**Free public demo for the candidate channel. Not yet installed or tested on a device.**

0.3.0~beta1 adds:
- the **Orbital**, **Warp**, **Holographic Layers**, **Circuit Flow** and **Magnetic Grid** icon effects;
- the full Tornado controls and presets.

It is for HCG Repo's candidate source, `https://repo.hakmicapitalgroup.com/repo/candidate/`, not the stable source.
Earlier builds keep their bytes and SHA-256:
- 0.1.0~beta1: `bb0af727…`
- 0.1.0~beta2: `a326759a…`
- 0.2.0~beta1: `c379266d…`

Candidate testers are offered 0.3.0~beta1 as the upgrade: `0.2.0~beta1 < 0.3.0~beta1 < 0.3.0`.

| File | What it is | Where it goes in HCG-repo |
|---|---|---|
| `com.hakmicapitalgroup.vortex_0.3.0~beta1_iphoneos-arm64.deb` | The Xcode-built package. **Prepare packages** fetches it from the pinned artifact; this copy is for review | not committed by hand |
| `imports/hcg-vortex-0.3.0-beta1-rootless.toml` | Import request with `channel = "candidate"`, pinned to the run, commit and SHA-256 | `imports/hcg-vortex-0.3.0-beta1-rootless.toml` |
| `CHANGELOG.md` | Changelog entry for this version | prepend to `packages/com.hakmicapitalgroup.vortex/CHANGELOG.md` |
| `DEVICE-TESTING.md` | Install: not attempted. Runtime: untested | read before adding any `device_tests` entry |
| `HCG-REPO-CHANGES.md` | `package.toml` edits for this version | `packages/com.hakmicapitalgroup.vortex/package.toml` |
| `COMPARISON.md` | Every file that changed from 0.2.0~beta1 (report mode: this version adds code) | reference |
| `FORMAT.txt`, `VALIDATE.txt` | gzip format and decompression exit statuses; `validate.sh --require-new-abi` output | reference |
| `PROVENANCE.md`, `provenance.json` | Commit, run, artifact ID, filename, size, SHA-256 and how each was checked | reference |
| `control.txt`, `contents.txt`, `LICENSE`, `SHA256SUMS` | Package fields and file list, licence, checksums | verify `SHA256SUMS` first |

## Verify

```sh
tar -xzf hcg-vortex-0.3.0-beta1-handoff.tar.gz
cd hcg-vortex-0.3.0-beta1-handoff
shasum -a 256 -c SHA256SUMS          # Linux: sha256sum -c SHA256SUMS
```

The `.deb` line must match the `sha256` in the import request: `@@SHA256@@`.

## Not claimed

- Installation, runtime behaviour, smoothness or battery impact on any device.
- Compatibility with HCG Halo or HCG Nexus.
- Publication. That is HCG-repo's manual **Publish** workflow.
