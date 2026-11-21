# Integration with HCG Repo (not applied)

`0001-HCG-Jailbreak-Academy-publish-academy-behind-academy.patch` is a `git format-patch` against
`F1r3srp3nt/HCG-repo` `main` at `4aa36a0`. **It has not been pushed or opened as a pull request.** Applying it does not
publish anything: the guide stays off until `[academy] enabled = true`.

What it changes:

| File | Change |
|---|---|
| `config/repo.toml` | New `[academy]` section, `enabled = false` |
| `tools/hcgrepo/config.py` | `RepoConfig.academy_enabled`; a non-boolean value is a configuration error |
| `tools/hcgrepo/site.py` | `copy_academy()` publishes `academy/` to `<site>/academy/` (stable build only, static files only, fails if required files are missing); optional “Academy” link in `page()` navigation, passed at all 7 call sites |
| `tools/hcgrepo/assets/site.css` | Below 520 px the navigation wraps onto its own row (fixes an existing 320 px overflow) |
| `academy/` | The guide (copied from this repository) and a README |
| `tests/test_academy.py` | 6 tests: off by default; disabled build has no academy/link; enabled build publishes and links it, resolves every local reference, still passes `verify`; missing files fail; non-boolean fails |

Not touched: authentication, HCG Store/Connect access checks, signing, package import, the publish workflow.

## Applying it (owner decision)

```bash
git checkout -b academy-integration origin/main
```

```bash
git am /path/to/HCG-Jailbreak-Research/integration/hcg-repo/0001-*.patch
```

```bash
python3 -m unittest discover -s tests
```

Then open a pull request for review. Publishing is a separate step: set `[academy] enabled = true`, merge, and run
*Publish repository*. See `docs/RELEASE_DECISIONS.md`.

## Keeping the copy in sync

The guide's source of truth is `academy/` in this repository. After editing it, copy `academy/jailbreak/` and
`academy/assets/` into HCG Repo's `academy/` (the `data/` folder is for review and tests only and is not published).
