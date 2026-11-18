# HCG-repo changes for HCG Halo 0.1.0~beta1 (applied on a review branch, not merged)

These are written against HCG-repo `main` at `6ff63fd` (17 Nov 2026). They are **applied on the review branch
[`candidate/hcg-halo-0.1.0-beta1`](https://github.com/F1r3srp3nt/HCG-repo/tree/candidate/hcg-halo-0.1.0-beta1)**
(§1, §2, plus an access-decision row in `docs/ACCESS.md` and an inventory row in `docs/CANDIDATE.md`). Nothing is
merged or published.

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

## 3. No website product entry (yet)

Do **not** add a `config/products.toml` entry for Halo now. HCG-repo's validator requires a `store_slug` for
`connect`/`paid` products ("access is granted by HCG Store"), and HCG Halo has no HCG Store page. Inventing a slug
would point at a page that does not exist. The indexed candidate package is listed on its own. Add a product entry
with a real `store_slug` when a Store page exists. (An earlier draft of this file proposed an entry; HCG-repo's own
`validate` rejected it, so it was dropped.)

## 4. Before running Publish (HCG's decision)

- [ ] Access level confirmed (§1)
- [ ] Prepare packages imported the artifact with the SHA-256 pinned in the manifest
- [ ] Licence: the Vortex freeware licence with the name changed (`LICENSE`), confirmed for Halo
- [ ] The provisional icon is acceptable for a candidate listing
- [ ] Optional: wait for the first device install result
