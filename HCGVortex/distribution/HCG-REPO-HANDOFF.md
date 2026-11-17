# HCG-repo handoff — HCG Vortex 0.1.0~beta1 (free experimental beta)

For whoever maintains [`F1r3srp3nt/HCG-repo`](https://github.com/F1r3srp3nt/HCG-repo). Nothing here has been applied to HCG-repo.

## What this adds

One **free, public** package, as an explicit per-package exception to the paid / HCG Connect flow. Nothing else changes:
- HCG Nexus and HCG Terminal Unleashed keep `[access] level = "paid"` / `"connect"`;
- no authentication, ownership or payment code changes;
- `payment_endpoint` stays as it is.

| | |
|---|---|
| Package | `com.hakmicapitalgroup.vortex` · **HCG Vortex (Beta)** · `0.1.0~beta1` · `iphoneos-arm64` (rootless) |
| Source commit | `F1r3srp3nt/HCG-Jailbreak-Research@7d5e5b9153e9e7246d87e6f3bf4f7c6927d42ad4` |
| Build | macOS CI run [43970942708](https://github.com/F1r3srp3nt/HCG-Jailbreak-Research/actions/runs/43970942708), Xcode 16.4, `validate.sh --require-new-abi`: 0 failures, 0 warnings |
| Artifact | `hcg-vortex-rootless-deb` (ID 14278312698), kept until 2027-02-14 |
| `.deb` SHA-256 (CI-reported) | `bb0af72745a36158d4022c1b97ebc9800847cf4b1fb42ca14d05b9fc07673eea` |
| Access | `public` (free) |
| Licence | Proprietary freeware (`HCGVortex/LICENSE`) |

## Files to add (review branch)

| From this repo | To HCG-repo |
|---|---|
| `HCGVortex/distribution/hcg-repo/packages/com.hakmicapitalgroup.vortex/package.toml` | `packages/com.hakmicapitalgroup.vortex/package.toml` |
| `…/CHANGELOG.md` | `packages/com.hakmicapitalgroup.vortex/CHANGELOG.md` |
| `…/icon.png` (180 px) | `packages/com.hakmicapitalgroup.vortex/icon.png` |
| `…/header.jpg` (1200×400, BETA badge) | `packages/com.hakmicapitalgroup.vortex/header.jpg` |
| `HCGVortex/distribution/hcg-repo/imports/hcg-vortex-0.1.0-beta1-rootless.toml` | `imports/hcg-vortex-0.1.0-beta1-rootless.toml` |

Pushing the branch runs **Prepare packages**. It fetches the pinned artifact, checks package, version, architecture and SHA-256, and commits `pool/`, provenance and lock back to the branch.

## Dry run already done (scratch copy, Linux build of the same source)

With HCG-repo at `dbb3e01` plus the files above:
- `bin/hcgrepo inspect`: OK. Entitlements null; links only system frameworks and CydiaSubstrate; arm64 and arm64e signed; `postrm` only.
- `bin/hcgrepo import-deb --built-from …@7d5e5b9`, then `validate`: `OK: 1 packages in pool, repository valid`.
- `bin/hcgrepo import-plan` (manifest only): the request is listed as pending, so the format is accepted.
- `bin/hcgrepo build --target production`: one public package. Neither protected product appears in the public index.
- `bin/hcgrepo smoke`: `SMOKE OK`, 24 URLs, 0 errors, 0 warnings on both base URLs.
- Generated depiction: BETA summary, status **Experimental**, "iOS 15.0 or later, declared by the package. Not yet tested on a physical device."

One warning, `path-not-root-owned`, is specific to the Linux build. The Xcode artifact's file list in CI shows `root/wheel` ownership.

## After the device test (only if it passes)

Add to `packages/com.hakmicapitalgroup.vortex/package.toml`, using the real values from the test record:

```toml
[versions."0.1.0~beta1"]
status = "device-tested"
device_tests = [
  { device = "<model + identifier>", ios = "<version (build)>", jailbreak = "<jailbreak + version, rootless, injector>", date = "<YYYY-MM-DD>", result = "pass", evidence = "<link to the test record>" },
]
```

If Engine Status was **Incompatible** (missing hooks), that configuration is **unsupported**. Record it as `result = "fail"` and don't use the label. HCG-repo refuses `device-tested` without a passing entry.

## Before running "Publish repository" (HCG's decision)

- [ ] Device smoke test passed on a confirmed device, with the record linked above
- [ ] HCG Repo's suspected Sileo crash resolved or ruled out (`docs/SILEO_STABILITY.md`)
- [ ] Licence wording reviewed by whoever handles HCG's legal terms (the model is decided: proprietary freeware)
- [ ] Prepare packages imported the Xcode artifact with SHA-256 `bb0af727…07673eea`
