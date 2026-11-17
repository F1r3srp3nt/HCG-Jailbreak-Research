# HCG Vortex 0.1.0~beta1: HCG Repo import handoff

This archive supplies the four inputs F1r3srp3nt/HCG-repo `docs/VORTEX.md` asks for (branch
`claude/hcg-apt-sileo-repo-unxxqg`). HCG-repo's own Vortex listing (`package.toml`, icon) stays as it is.

| File | What it is | Where it goes in HCG-repo |
|---|---|---|
| `com.hakmicapitalgroup.vortex_0.1.0~beta1_iphoneos-arm64.deb` | The Xcode-built package (input 1). Normally fetched by **Prepare packages** from the pinned artifact. This copy is for review and local `bin/hcgrepo inspect` | not committed by hand |
| `imports/hcg-vortex-0.1.0~beta1.toml` | Import request (input 2), pinned to run, commit and SHA-256 | `imports/hcg-vortex-0.1.0~beta1.toml` |
| `CHANGELOG.md` | Changelog entry for exactly this version (input 3) | `packages/com.hakmicapitalgroup.vortex/CHANGELOG.md` |
| `DEVICE-TESTING.md` | Device-test evidence (input 4). **States that no testing has occurred** | read before setting any `[versions]` status |
| `LICENSE` | Proprietary freeware terms for HCG Vortex | reference; link it from the listing if wanted |
| `PROVENANCE.md`, `provenance.json` | Source commit, CI run, artifact ID, filename, size, SHA-256 and how each was verified | reference |
| `control.txt`, `contents.txt` | `dpkg-deb -f` / `dpkg-deb -c` of the package | reference |
| `SHA256SUMS` | SHA-256 of every file above | verify first |

## Verify

```sh
tar -xzf hcg-vortex-0.1.0-beta1-handoff.tar.gz
cd hcg-vortex-0.1.0-beta1-handoff
shasum -a 256 -c SHA256SUMS          # Linux: sha256sum -c SHA256SUMS
```

Every line must end in `OK`. The `.deb` line must also match the `sha256` in the import request.

## Not claimed

- **Device compatibility.** None. See `DEVICE-TESTING.md`.
- **Publication.** None. Publishing stays HCG-repo's manual **Publish** workflow, after the Sileo source check
  and the device test that `docs/VORTEX.md` describes.
