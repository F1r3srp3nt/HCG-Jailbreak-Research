# Test results

Run on 21 Nov 2026 in the development container (Linux, Node 22, Python 3.13, Chromium via Playwright).

| Suite | Command | Result |
|---|---|---|
| Compatibility logic (unit + AppleDB cross-check) | `node --test tests/*.test.mjs` | **18 / 18 passed**; cross-check: 5,149 model × release pairs, 0 disagreements |
| Browser end-to-end + accessibility | `AXE_PATH=… node tests/e2e.mjs` | **22 / 22 passed** (`docs/test-results/e2e.json`) |
| HCG Repo's own suite with the integration patch | `python3 -m unittest discover -s tests` (in HCG-repo) | **167 / 167 passed** (161 existing + 6 new `test_academy.py`); baseline without the patch: 161 / 161 |
| Patch applies to HCG Repo `main` | `git apply --check` on `4aa36a0` | clean |
| Full site build with the Academy enabled | `python3 tools/build_preview.py …` (runs `hcgrepo build`) | built; 0 packages in stable index (as live), Candidate built |
| Local links in the built guide | link check against `_preview/` | 31 references, 0 broken |
| External links | HTTP / `git ls-remote` | 19 links, all reachable after replacing `ios.cfw.guide/resigning-apps/` (client-side alias, 404 over HTTP) with `/sideloading-apps/` |
| HTML structure | parser check | no unclosed or mismatched tags, no duplicate ids, every `#anchor` and ARIA reference resolves |
| SVG illustrations | XML parse | 15 / 15 valid |

## End-to-end checks (tests/e2e.mjs)

1–4. axe WCAG 2.2 AA + best practice: desktop dark/light, iPhone 13 dark/light: 0 violations each.
5. No horizontal overflow at 320 px and iPhone 13 on the guide, HCG home, a product page and the Candidate page.
6. All assets load; 85 models available.
7. 15 chapters, each with a completion button.
8. Checker “Supported”: iPhone 12, 15.4.1, backup → TrollHelperOTA, focus moves to the result.
9. Checker “Supported with specific requirements”: iPhone 15 Pro, 17.3.1 → sideload tab selected.
10. Checker “Unsupported”: iPhone 12, 17.4.
11. Checker “cannot yet be verified”: iPhone X, 17.0 (never released for it).
12. 16.7 shows the build-number question.
13. Search by model number A2161 selects iPhone 11 Pro Max.
14. Progress: mark complete, persists after reload, reset.
15. Preparation checklist updates its status and the install warning.
16. Route tabs switch with the arrow keys.
17. Glossary search filters terms.
18. Troubleshooting expand all / collapse all (12 items).
19. Copy button puts `uicache -a` on the clipboard.
20. Appearance toggle cycles auto → light → dark → auto.
21. Skip link moves focus to main.
22. No console errors, failed requests or HTTP errors.

## Problems found by the tests and fixed

- Apple-internal build 17.5.2 counted as a release (AppleDB cross-check) → excluded internal builds.
- Keyboard-inaccessible scroll regions on phones (axe) → focusable, labelled table regions; wrapping commands.
- **HCG Repo top bar overflowed at 320 px even before this work** (“Help” partly cut off, hidden by `overflow-x`); a
  fourth link would have hidden “Academy” entirely → `site.css` now wraps the navigation onto a second row below 520 px.
- A long link in chapter 9 overflowed at 320 px → links and code in chapters may break anywhere.
- Broken external link (`resigning-apps`) → canonical URL.

## Preview screenshots

`docs/preview/`: desktop dark/light hero, checker and result, install chapter, ecosystem chapter, iPhone 13 hero,
running chapter, troubleshooting, and the HCG Repo home page showing the new Academy link. Taken from the real built
site at 2× scale.
