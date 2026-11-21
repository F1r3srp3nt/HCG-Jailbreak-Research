# Sources and verification record

Last reviewed: **21 November 2026**. Every factual statement in the guide traces to one of these sources. Pages were
read directly (not from memory); git-hosted sources are pinned to commits so the review can be repeated.

| # | Source | Pin / date | Used for |
|---|---|---|---|
| 1 | [opa334/Dopamine](https://github.com/opa334/Dopamine) README, default branch `3.x` | tag **3.0.13**, commit `5b1d2c1`, 3 Nov 2026 | Supported ranges: “iOS 15.0 - 17.3.1 (arm64e), iOS 15.0 - 18.7.1, 26.0 - 26.0.1 (A12/A13) and iOS 15.0 - 18.7.1 (arm64)”; “rootless semi-untethered”. Note: the `main` branch README is stale (“iOS 15.0 - 15.4.1”) and was **not** used. |
| 2 | Dopamine source at 3.0.13: `Application/Dopamine/en.lproj/Localizable.strings`, `LICENSE.md` | same | Every interface label quoted (Jailbreak, Settings, Tweak Injection, Remove/Hide Jailbreak, Select Package Manager(s), Apply Workaround, …), the Remove Jailbreak warning text, MIT licence (© Lars Fröder, opa334). |
| 3 | Dopamine source: `DOEnvironmentManager.m`, `DOJailbreaker.m`, `BaseBin/launchdhook/src/jbserver/jbdomain_watchdog.c`, `BaseBin/systemhook/src/main.c` | same | Safe Mode mechanics: Tweak Injection off writes `basebin/.safe_mode`; a userspace panic is turned into a userspace reboot, logged as “userspace-panic”, and sets the same marker. |
| 4 | [ellekit.space/dopamine](https://ellekit.space/dopamine/) (official site) | read 21 Nov 2026 | “Supported on iOS 15.0 - 17.3.1 (A14 - A17 / M1 - M2)”, “15.0 - 18.7.1 and 26.0 - 26.0.1 (A8 - A13)”, chips, package managers (Sileo, Zebra), rootless explanation, credits, Apple's warning text, official download links. |
| 5 | ios.cfw.guide [Installing Dopamine](https://ios.cfw.guide/installing-dopamine/) | page source `095ca91f`, 7 Aug 2026 | Sideload route, 7-day re-signing, factory-firmware limitation, conflicting jailbreaks, PlumeImpactor steps, trust and Developer Mode, running Dopamine, ElleKit + PreferenceLoader setup, Next Steps (TrollStore Helper). jailbreaks.app note (signing Dopamine 2.5b4 at review time). |
| 6 | ios.cfw.guide [Installing Dopamine (TrollStore)](https://ios.cfw.guide/installing-dopamine-trollstore/) | `06367d2c`, 7 Aug 2026 | TrollStore route; the four installer tabs and their version/chip ranges; Find My warning; additional steps for A12+ 16.6–16.6.1 and A15/A16/M2 16.5.1. |
| 7 | ios.cfw.guide [Removing Dopamine](https://ios.cfw.guide/removing-dopamine/) | `210b9d10`, 23 Aug 2026 | Removal steps; palera1n rootless intercompatibility. |
| 8 | ios.cfw.guide [Troubleshooting](https://ios.cfw.guide/troubleshooting/), [FAQ](https://ios.cfw.guide/faq/), [Types of Jailbreak](https://ios.cfw.guide/types-of-jailbreak/), [Blocking Updates](https://ios.cfw.guide/blocking-updates/), [Blocking Jailbreak Detection](https://ios.cfw.guide/blocking-jailbreak-detection/), [Sideloading Apps](https://ios.cfw.guide/sideloading-apps/) | site source `71cce3f`, 20 Nov 2026 | Respring loops, bootloops, DFU/Recovery; legality, warranty, backups; semi-untethered definition; update-blocking profile and its risk; banking advice; 7/365-day signing. |
| 9 | [opa334/TrollStore](https://github.com/opa334/TrollStore) README | read 21 Nov 2026 | “Supported versions: 14.0 beta 2 - 16.6.1, 16.7 RC (20H18), 17.0”; persistence helper; uninstalling TrollStore apps. |
| 10 | [AppleDB](https://github.com/littlebyteorg/appledb) (linked by ellekit.space for “a more detailed breakdown”) | commit `b1ba172`, 20 Nov 2026 | Model → chip, architecture, model numbers; which iOS/iPadOS releases each model received; AppleDB's own Dopamine compatibility list (independent cross-check). |
| 11 | [F1r3srp3nt/HCG-repo](https://github.com/F1r3srp3nt/HCG-repo) `config/products.toml`, `packages/*/package.toml`, `docs/ROOTLESS_ROOTFUL.md`; live site and Candidate index | commits `ade4a55` / `4aa36a0`; live read 21 Nov 2026 08:43 UTC | HCG product statuses and requirements; rootless/rootful table; Theos/libroot guidance; HCG Repo URLs. |

## Discrepancies found and how they were resolved

- **Dopamine README on `main`** says 15.0–15.4.1. It is the old 1.x branch; the default branch is `3.x`. Used `3.x`.
- **Official website vs README for 26.0–26.0.1**: the website says “A8 – A13”, the README “A12/A13”. Both are true in
  practice: A8–A11 devices never received iOS 26 (AppleDB). The guide says so.
- **AppleDB lists 17.5.2 (21F101)**: marked `internal` in AppleDB, never released publicly. Excluded; the cross-check
  test found it.
- **AppleDB's Dopamine entry lists some betas (17.4 betas, 26.1 betas)**. The checker only accepts shipped releases and
  follows the developer's own ranges; betas return “cannot yet be verified”.
- **AppleDB `latestVer` = 3.0.12**, one release behind the 3.0.13 tag. The guide uses the tag.
- **HCG Repo README** says HTTPS is not working; the live site serves HTTPS correctly (checked). The guide uses HTTPS.
- **`ios.cfw.guide/resigning-apps`** is a client-side alias that returns 404 to plain HTTP clients; the guide links the
  canonical `/sideloading-apps/` page.

## What was not used

No forum posts, videos, mirrors or third-party compatibility sites. Statements about how iOS works in general (sandbox,
code signing, force-restart buttons, what a restore installs) are standard platform facts, written conservatively.
