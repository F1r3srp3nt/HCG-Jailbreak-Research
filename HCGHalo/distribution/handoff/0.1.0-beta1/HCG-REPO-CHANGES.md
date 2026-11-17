# HCG-repo changes for HCG Halo 0.1.0~beta1 (proposed, not applied)

These are written against HCG-repo `main` at `6ff63fd` (17 Nov 2026). This session can read HCG-repo but not write
to it.

## 1. New package: `packages/com.hakmicapitalgroup.halo/`

Copy these files from `hcg-repo/packages/com.hakmicapitalgroup.halo/` in the handoff archive:

- `package.toml`
- `CHANGELOG.md`
- `icon.png` (provisional)
- `README.md`

### Access decision (owner, please confirm)

```toml
[access]
level = "connect"
exception = "Free public beta demo … for the versions in exception_versions only …"
exception_versions = ["0.1.0~beta1"]
```

- **The exception follows the owner's instruction.** HCG Halo candidate builds are authorised as free public beta
  demos: no account and no payment.
- **`level = "connect"` is HCG's default** for its packages. It does not decide Halo's production pricing or
  access; the owner should set the real level (`connect` or `paid`) before any release. With a non-public level,
  HCG-repo's free-demo policy keeps this version in the candidate source. The dry run confirmed that
  `bin/hcgrepo channel … stable` refuses it.
- **If the owner wants HCG Halo fully public** (as HCG Vortex is), set `level = "public"` instead. The exception
  lines can stay, documenting the approval.
- No other package's access changes, and no sign-in, ownership or payment code changes.

### Version entry

```toml
[versions."0.1.0~beta1"]
status = "experimental"
label = "Free public beta demo — not yet device-tested."
```

Add no `device_tests` entry until a phone has attempted the install. Record install and runtime separately
(`DEVICE-TEST-CHECKLIST.md`, section *Recording*).

## 2. Import request: `imports/hcg-halo-0.1.0-beta1-rootless.toml`

Copy it from `hcg-repo/imports/` in the handoff archive. It is the only manifest for this version. It has
`channel = "candidate"` and is pinned to the macOS CI run, the commit, the artifact name and the SHA-256 (see
`PROVENANCE.md`). Push it on a branch: **Prepare packages** fetches the artifact, checks it and commits the `.deb`,
provenance and lock entry for review. Then merge, and run **Publish** when HCG decides to.

## 3. Optional: website product entry (`config/products.toml`)

```toml
[[products]]
key = "hcg-halo"
name = "HCG Halo"
package_ids = ["com.hakmicapitalgroup.halo"]
layouts = ["iphoneos-arm64"]
kind = "Jailbreak tweak"
access = "connect"   # match [access] level above
status = "Free public beta demo in testing: not yet device-tested"
summary = "Animated neon light border around the Home Screen edges: Static, Breathing, Colour Flow, Orbit and Sci-Fi Circuit."
detail = "Free public beta demo in the HCG Repo Candidate testing channel, no sign-in. Rootless (iphoneos-arm64). Not yet installed on any device."
```

There is no `store_slug`, because no HCG Store page exists for Halo. Add one when it does.

## 4. Before running Publish (HCG's decision)

- [ ] Access level confirmed (§1)
- [ ] Prepare packages imported the artifact with the SHA-256 pinned in the manifest
- [ ] Licence: the Vortex freeware licence with the name changed (`LICENSE`), confirmed for Halo
- [ ] The provisional icon is acceptable for a candidate listing
- [ ] Optional: wait for the first device install result
