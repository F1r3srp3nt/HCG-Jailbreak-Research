# HCG Repo distribution kit: HCG Halo

**Nothing here publishes anything, and HCG Repo has not been changed.** This session can read HCG-repo but cannot
write to it.

| | |
|---|---|
| Target source | **HCG Repo Candidate**: `https://repo.hakmicapitalgroup.com/repo/candidate/` (HCG-repo `docs/CANDIDATE.md`) |
| Access | Free public beta demo: no sign-in, no payment, candidate channel only (HCG-repo `docs/ACCESS.md`, free-demo policy) |
| Source repository | [`F1r3srp3nt/HCG-repo`](https://github.com/F1r3srp3nt/HCG-repo), schema read at `6ff63fd` (17 Nov 2026) |

## Files: one copy of each

| File (here) | Destination in HCG-repo | Notes |
|---|---|---|
| `hcg-repo/imports/hcg-halo-0.1.0-beta1-rootless.toml` | `imports/hcg-halo-0.1.0-beta1-rootless.toml` | **The only import manifest.** `channel = "candidate"`, pinned to the CI run, commit and SHA-256 |
| `hcg-repo/packages/com.hakmicapitalgroup.halo/package.toml` | `packages/com.hakmicapitalgroup.halo/package.toml` | listing, access exception, known issues, version entry |
| `hcg-repo/packages/com.hakmicapitalgroup.halo/CHANGELOG.md` | `packages/com.hakmicapitalgroup.halo/CHANGELOG.md` | **the** changelog for this version |
| `hcg-repo/packages/com.hakmicapitalgroup.halo/icon.png` | `packages/com.hakmicapitalgroup.halo/icon.png` | 180 px, **provisional** |
| `hcg-repo/packages/com.hakmicapitalgroup.halo/README.md` | `packages/com.hakmicapitalgroup.halo/README.md` | asset provenance |
| `handoff/0.1.0-beta1/` | — | handoff notes, proposed HCG-repo edits, and known issues |
| `icon-512.png` | — | provisional source icon (`scripts/make_icon.py`) |

The device-test checklist is `../docs/DEVICE_TEST_CHECKLIST.md`. The handoff archive includes a copy as
`DEVICE-TEST-CHECKLIST.md`.

## Handoff archive

The **HCG Halo handoff archive** workflow (`.github/workflows/hcg-halo-handoff.yml`) does the following:

1. Checks the pinned build run through the GitHub API: the workflow file, `success`, the head commit and the artifact ID.
2. Downloads the artifact on a separate runner, recomputes the SHA-256 and refuses any other value.
3. Re-runs `validate.sh --require-new-abi` from the source commit.
4. Records the archive format and decompression exit statuses.
5. Bundles the `.deb` with the manifest, listing files, changelog, known issues, checklist, licence, icon,
   provenance and `SHA256SUMS`.
6. Extracts the archive again and verifies it.

It publishes nothing.

### 0.1.0~beta1 handoff (done)

| | |
|---|---|
| Build | run [44062061609](https://github.com/F1r3srp3nt/HCG-Jailbreak-Research/actions/runs/44062061609), commit `ab439f8bd0990500ba373616073a1d9b108686e6`, `validate.sh --require-new-abi` 0 failures / 0 warnings, 310 simulator runtime checks passed |
| Package | `com.hakmicapitalgroup.halo_0.1.0~beta1_iphoneos-arm64.deb`, 264,782 bytes, SHA-256 `c0a3301c9b38cdac812d439fb919c3a77bfcb7999c52ea174d799e88ba24c9af` (artifact `hcg-halo-rootless-deb`, ID 14317739735, kept until 2027-02-15) |
| Handoff | run [44063187804](https://github.com/F1r3srp3nt/HCG-Jailbreak-Research/actions/runs/44063187804): API provenance checked, SHA-256 recomputed from a fresh download, re-validated from the source commit, archive re-extracted and `SHA256SUMS` verified. Archive artifact `hcg-halo-0.1.0-beta1-handoff` (ID 14318997915, kept until 2027-02-15) |

## Dry run with HCG-repo's own tools

The dry run used a scratch copy of HCG-repo at `6ff63fd`, the proposed `packages/com.hakmicapitalgroup.halo/`, and
a **Linux test build** of the same source (not the distributable artifact):

| Command | Result |
|---|---|
| `bin/hcgrepo inspect` | OK. Entitlements null on both binaries; links only system frameworks and CydiaSubstrate; arm64 + arm64e signed; `postrm` only. 1 warning, `path-not-root-owned`, which is specific to the Linux build: the Xcode artifact is `root/wheel`, as recorded for Vortex |
| import with `channel = "candidate"` (the `import_deb` path that **Prepare packages** uses), then `bin/hcgrepo validate` | `OK: 4 packages in pool, repository valid` |
| `bin/hcgrepo channel com.hakmicapitalgroup.halo 0.1.0~beta1 iphoneos-arm64 stable` | **Refused**: "free demos stay in the candidate channel". The free demo cannot reach stable |
| `bin/hcgrepo build --target production` | OK. Halo is in `repo/candidate/Packages` with a depiction, Sileo depiction and icon; stable `Packages` does not list it |
| `bin/hcgrepo smoke` | `SMOKE OK`, 0 errors, 0 warnings, on both base URLs |
| `bin/hcgrepo verify --channel candidate --source-only` | 35 URLs, 4 packages (every `.deb` downloaded and re-checked), 0 errors, 0 warnings |

The real import must use the CI artifact named in the manifest. **Prepare packages** fetches it on HCG-repo's side.
