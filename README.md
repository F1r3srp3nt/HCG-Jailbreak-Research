# HCG-Jailbreak-Research
The portal to the new world

## HCG Jailbreak Academy: “Why & How to Jailbreak Your iPhone”

An interactive, beginner-friendly educational guide from Hakmi Capital Group, using **Dopamine** as the example
jailbreak. It is built for the HCG Repo website (“HCG Futuristic” design) and is **prepared, validated and awaiting
owner approval. It is not published.**

- 15 chapters: what jailbreaking is → risks → rootless vs rootful → Dopamine → compatibility → preparation → install →
  run → Sileo/Zebra → repositories → Safe Mode and recovery → removal → HCG software (optional).
- Compatibility checker: exact model, iOS version, existing jailbreak, TrollStore, backup → *Supported*, *Supported
  with specific requirements*, *Unsupported* or *Compatibility cannot yet be verified*, plus the verified route.
- Progress tracking, chapter navigation, searchable glossary, expandable troubleshooting, copyable commands, light and
  dark appearance, responsive down to 320 px, WCAG 2.2 AA (axe: 0 violations).
- Installs nothing, runs nothing, hosts no jailbreak files. Every download points to the official source.

Last reviewed **21 November 2026** against Dopamine 3.0.13. See [docs/SOURCES.md](docs/SOURCES.md).

## Layout

```
academy/jailbreak/index.html     the guide (published at <HCG Repo site>/academy/jailbreak/)
academy/assets/                  academy.css, academy.js, compat.js (logic), compat-data.js (generated), img/*.svg
academy/data/compat-data.json    full dataset incl. AppleDB's Dopamine list (tests and review only; not published)
tools/build_compat_data.py       regenerates the device/release data from an AppleDB checkout
tools/make_illustrations.py      regenerates the original SVG illustrations
tools/build_preview.py           builds the real HCG Repo site with the Academy enabled, locally (publication preview)
tests/compat.test.mjs            compatibility unit tests + cross-check against AppleDB
tests/e2e.mjs                    browser, accessibility (axe-core) and screenshot run
integration/hcg-repo/            patch for F1r3srp3nt/HCG-repo (not applied) and how to apply it
docs/                            sources, compatibility logic, accessibility, test results, release decisions, preview/
```

## Running the checks

```bash
node --test tests/*.test.mjs
```

```bash
python3 tools/build_preview.py --hcg-repo /path/to/HCG-repo-with-patch --out _preview
```

```bash
npm i --prefix /tmp/axe axe-core@4.10.2 && AXE_PATH=/tmp/axe/node_modules/axe-core/axe.min.js node tests/e2e.mjs
```

```bash
python3 -m http.server -d _preview 8000
```

Then open `http://127.0.0.1:8000/academy/jailbreak/`.

## Before release

Read [docs/RELEASE_DECISIONS.md](docs/RELEASE_DECISIONS.md). In short: approve the content, apply the HCG Repo patch,
then set `[academy] enabled = true` and publish, re-checking Dopamine's ranges and HCG product statuses that day.
