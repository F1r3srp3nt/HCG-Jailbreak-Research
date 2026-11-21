# Remaining decisions before release

The guide is prepared and validated but **not published**. Nothing in HCG Repo was changed: the integration exists only
as a patch in `integration/hcg-repo/`, and even after it is applied the guide stays off until `[academy] enabled = true`.

## Owner decisions (required)

| # | Decision | Options / recommendation |
|---|---|---|
| 1 | **Approve publication** of “Why & How to Jailbreak Your iPhone”. | Review the preview (`docs/preview/`, or build it, see README). |
| 2 | **Apply the integration patch** to `F1r3srp3nt/HCG-repo` (review branch → PR → merge). | The patch adds the `[academy]` switch (off), the build step, the nav link, a mobile header fix and 6 tests. HCG Repo's 167 tests pass with it. |
| 3 | **Turn it on**: set `[academy] enabled = true` and run *Publish repository*. | Do this as a separate, deliberate change after 2. |
| 4 | **Search indexing.** The page carries `noindex, nofollow` so a preview cannot be indexed. | Remove the meta tag when you want search engines to list it. |
| 5 | **The “Academy” navigation link** appears on every HCG Repo page (home, product pages, package pages) once enabled. | Keep (recommended), or ask for the link only on the home page. |
| 6 | **Chapter 15 wording and statuses.** It states, as of 21 Nov 2026 08:43 UTC: no HCG product released; Nexus 0.3.3~beta1, Portal 0.1.0~beta4, Animation Center 0.1.0~beta1 in Candidate, all not device-tested; Terminal Unleashed unavailable; Animation Center “Coming Soon” at the announced US$1.99. | Confirm, and re-check on the day you publish (statuses changed twice while this guide was written). |
| 7 | **HCG Repo's unsigned Release** is mentioned in chapter 15 (“Release metadata is not yet signed”). | Keep the honest statement, or set up the archive key first (`docs/SIGNING.md` in HCG Repo). |
| 8 | **Legal/compliance review** of the jailbreaking content for the markets HCG serves. The guide quotes ios.cfw.guide on US legality and Apple's licence/service position; it is not legal advice. | Recommended before release. |

## Content decisions made on your behalf (reversible)

- **TrollStore installation is not re-written step by step.** The guide names the correct installer for the reader's
  device and links to the matching tab of the official page. TrollStore installers change often and four of them need
  a computer and third-party tools; copying their steps would go stale fastest. Dopamine's own install, run, setup and
  removal steps *are* written out in full.
- **No jailbreak-detection bypass instructions.** Chapter 4 explains detection, quotes ios.cfw.guide's advice to use a
  separate device for banking, and states that the guide does not cover defeating app security checks.
- **Update blocking** is explained with its cost (no security updates, a third-party profile) and linked, not embedded.
- **Illustrations** are original schematic drawings labelled “Illustration”, using Dopamine's own interface wording.
  No screenshots of Dopamine, TrollStore, Sileo or iOS were used, because none were available under a licence that
  clearly permits it and none were taken on a device.
- **HCG Halo, HCG Vortex and HCG Sentinel** are not in chapter 15 because the brief listed five products.

## Maintenance (after release)

- **Re-review whenever Dopamine releases** (watch `opa334/Dopamine` tags) or ios.cfw.guide changes its Dopamine pages.
  Update `RANGES` in `academy/assets/compat.js`, `LAST_REVIEWED`, the chapter 6/7 text and the date in the hero.
- **Refresh device data** when Apple ships new devices or iOS versions:
  `python3 tools/build_compat_data.py --appledb <appledb checkout>`, then `node --test tests/*.test.mjs` (the AppleDB
  cross-check must stay at 0 disagreements).
- Suggested review interval: monthly, and on every Dopamine release.

## Not verifiable from here

- **No physical device was used.** The guide's steps come from the official documentation and Dopamine's source code,
  not from a jailbreak performed by HCG. A walkthrough on a real supported device before release would let HCG add
  real-world notes (timings, screens). That needs a device and is the owner's call.
- **Screen-reader testing** was automated (axe-core) plus keyboard checks; a manual VoiceOver pass on iPhone and
  macOS is still recommended (see `docs/ACCESSIBILITY.md`).
