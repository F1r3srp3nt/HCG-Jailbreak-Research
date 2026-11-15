# HCG Repo distribution kit — HCG Vortex

Prepared for the existing HCG Repo. **Nothing here publishes anything**, and no
HCG Repo infrastructure has been changed. A maintainer applies these by hand
after review and after on-device verification.

| Item | File / source |
|---|---|
| Package | `packages/com.hakmicapitalgroup.vortex_0.1.0~alpha_iphoneos-arm64.deb` from the **macOS CI artifact** (native arm64e ABI) |
| `Packages` stanza | `python3 scripts/repo_entry.py <deb>` (set `HCG_REPO_BASE` to the repo URL) |
| Sileo native depiction | `depiction.json` (replace `REPLACE-WITH-HCG-REPO-URL`) |
| Icon | `icon-512.png` |
| Header image | to be created (`header.png`, 1500×500 recommended) |
| Screenshots | `screenshots/` — placeholder until device capture |
| Changelog | `../CHANGELOG.md` |
| Install / recovery | `../docs/RECOVERY.md` |
| Compatibility | `../docs/COMPATIBILITY.md` |

## Listing metadata

| Field | Value |
|---|---|
| Package | `com.hakmicapitalgroup.vortex` |
| Name | HCG Vortex |
| Section / Category | Tweaks |
| Price | Free (no payment integration) |
| Author / Maintainer | Hakmi Capital Group |
| Architecture | `iphoneos-arm64` (rootless) |
| Description | HCG Vortex is an advanced Home Screen animation engine featuring directional overrides, customizable transitions, and modular animation effects. |

## Release checklist

- [ ] macOS CI build green; `validate.sh --require-new-abi` passed
- [ ] Device tests in `docs/TESTING.md` executed and recorded
- [ ] Screenshots captured on device
- [ ] LICENSE terms confirmed by Hakmi Capital Group
- [ ] Repo URL substituted in `depiction.json` / `repo_entry.py` output
- [ ] Maintainer adds the `.deb` + stanza with the repo's own tooling
