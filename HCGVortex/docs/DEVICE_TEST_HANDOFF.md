# Device test handoff — HCG Vortex 0.1.0-alpha

Two statuses are tracked separately:

| | Status |
|---|---|
| **Build validation** | Passed in CI for the PR head: Xcode build, `validate.sh --require-new-abi`, 0 failures. The exact artifact, run and SHA-256 are listed in PR #1's description. |
| **Device compatibility** | **Unknown.** Nothing has been installed. The target device has not been confirmed. |

## Ground rules for the first test

- **Use only the Xcode-built CI artifact** (`hcg-vortex-rootless-deb`). Never the Linux package: its arm64e code is converted, not native.
- **Keep it independent of HCG Repo and Sileo.** HCG Repo is under investigation for a suspected Sileo crash (HCG-repo `docs/SILEO_STABILITY.md`). Do not add the source. Install and remove with `dpkg` over SSH.
- **Confirm the device first.** The Vortex brief names an iPhone 11 Pro Max on iOS 17.4. HCG-repo's HCG Nexus listing names an iPhone 13 Pro on iOS 16.5. Neither is assumed: step 0 decides.
- **One change at a time.** Wait at least **30 seconds** after every respring before the next one (see "Launch guard").
- **Record evidence** for every step: screen recording or screenshot, plus the terminal output.

## 0. Confirm the device (read-only)

Copy `scripts/device-info.sh` to the phone and run it over SSH as `mobile`:

```sh
scp HCGVortex/scripts/device-info.sh mobile@<iphone-ip>:/var/mobile/Documents/
ssh mobile@<iphone-ip> 'sh /var/mobile/Documents/device-info.sh' | tee vortex-device-report.txt
```

It changes nothing. Send `vortex-device-report.txt` for review. Also note the Dopamine version from the Dopamine app if the script can't read it.

**Go only if all of these hold:**
- arm64e CPU (A12 or newer);
- iOS 15.0 or later, with the exact version and build recorded;
- rootless jailbreak (`/var/jb`), with the jailbreak and its version recorded;
- `dpkg` architecture `iphoneos-arm64`;
- a `mobilesubstrate` provider (ElleKit) and PreferenceLoader installed;
- no other page-transition tweak injected into SpringBoard;
- SSH access works, and you know the recovery steps in §7.

iOS versions other than 17.x are **untested**. The compatibility gate decides at runtime, but treat the result as exploratory.

## 1. Get and verify the package (on your Mac)

1. Download artifact `hcg-vortex-rootless-deb` from the macOS run linked in PR #1, and unzip it.
2. Check the hash against the one in the PR, which matches the run's *Package listing* step:
   ```sh
   shasum -a 256 com.hakmicapitalgroup.vortex_0.1.0~alpha_iphoneos-arm64.deb
   dpkg-deb -f com.hakmicapitalgroup.vortex_0.1.0~alpha_iphoneos-arm64.deb Package Version Architecture Depends
   ```
3. Copy it to the phone and check the hash there too:
   ```sh
   scp com.hakmicapitalgroup.vortex_0.1.0~alpha_iphoneos-arm64.deb mobile@<iphone-ip>:/var/mobile/Documents/
   ssh mobile@<iphone-ip> 'shasum -a 256 /var/mobile/Documents/com.hakmicapitalgroup.vortex_*.deb || sha256sum /var/mobile/Documents/com.hakmicapitalgroup.vortex_*.deb'
   ```

## 2. Test sequence

Run these over SSH. `sudo` needs the mobile password you set for the jailbreak (`passwd`). Use `sbreload`, or your jailbreak's respring action, to respring.

### A. Install with the kill switch on (nothing hooks)

```sh
touch /var/mobile/Library/Preferences/com.hakmicapitalgroup.vortex.disabled
sudo dpkg -i /var/mobile/Documents/com.hakmicapitalgroup.vortex_0.1.0~alpha_iphoneos-arm64.deb
sbreload
```

Expected:
- `dpkg` succeeds with no dependency errors;
- the Home Screen pages exactly as before;
- **Settings → HCG Vortex** opens (this proves the Settings bundle loads);
- *Engine Status* reads **Kill switch on**.

### B. Disabled baseline (code loaded, effects off)

1. In Settings → HCG Vortex, turn **Enable Vortex off**.
2. Remove the kill switch, respring, and wait 30 s:
   ```sh
   rm /var/mobile/Library/Preferences/com.hakmicapitalgroup.vortex.disabled
   sbreload
   ```
3. *Engine Status* should read **Loaded, disabled**. That means the hooks are installed and verified, and effects are off. Page through every Home Screen page, Today View and App Library: all stock.
4. If it reads **Incompatible — stock**, record *Engine Detail* and **stop**. This is the safe outcome: this iOS build lacks something Vortex needs, so no hooks were installed.

### C. One effect at a time

Turn **Enable Vortex on**. Changes apply live, with no respring. For each preset, in this order:
1. **Reverse Slide**
2. **Vertical Rise**
3. **Vertical Fall**

For each one, check:
- swipe left and right across three pages: the page dots show the correct page, and the motion matches the effect;
- drag half way and release; reverse a drag past the start page; flick, then grab mid-motion;
- tap an icon right after a transition: the icon under your finger opens;
- swipe to Today View and App Library and back: those transitions stay stock;
- open a folder and page inside it: stock.

The full list is in `docs/TESTING.md` (F1–F11, R1–R13).

### D. Preferences persistence

1. Set non-default values: preset **Vertical Fall**, Duration **0.4**, Easing **Ease In-Out**.
2. Respring and wait 30 s.
3. Settings should show the same values and the behaviour should match.
4. Check the preferences file exists: `ls -l /var/mobile/Library/Preferences/com.hakmicapitalgroup.vortex.plist`.

### E. Enable / disable

- Turn **Enable Vortex off**: stock immediately, no respring.
- Turn it back on: the effect returns immediately.
- **Restore Default Behavior** switches to the stock animation and keeps your other settings.

### F. Respring stability

Respring three times, **waiting at least 30 s between them**. *Engine Status* should read **Active** each time. Afterwards, check Settings → Privacy & Security → Analytics & Improvements → Analytics Data. There should be no `SpringBoard-*.ips` entries mentioning `HCGVortex`.

### G. Uninstall

```sh
sudo dpkg -r com.hakmicapitalgroup.vortex
sbreload
dpkg -L com.hakmicapitalgroup.vortex 2>&1 | head -2      # should say: not installed
ls /var/jb/Library/MobileSubstrate/DynamicLibraries/HCGVortex.* 2>&1   # should say: No such file
```

The Home Screen should be stock and Settings should no longer list HCG Vortex. Your preferences file stays (that's expected with `-r`). To delete it too, use `sudo dpkg -P com.hakmicapitalgroup.vortex`.

## 3. Stop conditions

Stop, collect evidence, and recover (§7) on any of these:
- SpringBoard crashes, or Safe Mode appears;
- *Engine Status* reads **Fault** or **Auto-disabled**;
- a page is left offset or stuck after a transition;
- a tap opens the wrong icon;
- an icon or widget is missing or moved.

## 4. Logs

Enable **Diagnostic Logging** in Settings → HCG Vortex, then on a Mac connected to the phone:
```sh
log stream --device --predicate 'subsystem == "com.hakmicapitalgroup.vortex"'
```

## 5. What the safety layer does (for interpreting results)

| Situation | What Vortex does | Engine Status |
|---|---|---|
| Kill switch file present | Installs no hooks | Kill switch on |
| A required SpringBoard class or method is missing, or only inherited | Installs no hooks | Incompatible — stock (*Engine Detail* names it) |
| Hook engine didn't replace both methods | Treats as failed and doesn't report active | Fault — stock |
| 3 consecutive SpringBoard launches that each ended within 30 s | Installs no hooks until **Enable Vortex** is toggled | Auto-disabled — stock |
| Objective-C exception in a hook | Restores every page, then stays inert until settings change or respring | Fault — stock |

What it **cannot** catch: a hard crash (bad memory access) inside SpringBoard. ElleKit's safe mode and the launch guard limit repeats; §7 covers recovery.

## 6. Reporting

Use the template in `docs/TESTING.md`, plus:
- the device report from step 0;
- the artifact SHA-256 you installed;
- the result of each step A–G;
- any crash logs.

Only after this is the device-compatibility status updated.

## 7. Recovery (rootless Dopamine + ElleKit)

These steps assume step 0 confirmed Dopamine with ElleKit. If it reports a different jailbreak, use that jailbreak's equivalents and confirm them before testing.

1. **Settings still works:** turn **Enable Vortex** off (instant), or **Restore Default Behavior**.
2. **Safe Mode appeared** (SpringBoard restarted without tweaks after a crash): don't respring back into tweaks yet. Over SSH, run either:
   ```sh
   touch /var/mobile/Library/Preferences/com.hakmicapitalgroup.vortex.disabled   # keep installed, load nothing
   # or remove it:
   sudo dpkg -r com.hakmicapitalgroup.vortex
   ```
   Then respring.
3. **SpringBoard keeps crashing, or there's no SSH:** reboot the phone. Dopamine is semi-untethered, so the phone starts as stock iOS with no tweaks. Then:
   - before re-jailbreaking, turn off tweak injection in the Dopamine app (its setting name varies by version: check the version recorded in step 0);
   - jailbreak, remove HCG Vortex over SSH (`sudo dpkg -r com.hakmicapitalgroup.vortex`);
   - turn tweak injection back on and use the Dopamine app's userspace reboot.
4. **Engine Status: Auto-disabled:** Vortex has already stopped itself. Collect logs and crash reports before toggling **Enable Vortex**, since toggling re-arms it.

Nothing in HCG Vortex changes system files, layout data, passcode or security settings. Removing the package and its preferences file returns the phone to its previous state.
