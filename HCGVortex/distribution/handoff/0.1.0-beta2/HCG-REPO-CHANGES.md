# HCG-repo changes for 0.1.0~beta2 (proposed, not applied)

These are edits for `packages/com.hakmicapitalgroup.vortex/package.toml` on HCG-repo `main` (as of `fb3a01e`).
This session cannot write to HCG-repo.

## 1. Access: needs the owner's approval

The current exception allows `exception_versions = ["0.1.0~beta1"]` **only**. A comment says any other version is
refused until it is approved and listed. beta2 therefore needs an explicit owner decision. This handoff does not make
it:

```toml
exception_versions = ["0.1.0~beta1", "0.1.0~beta2"]
```

Nothing else in `[access]` changes. No other product's access, sign-in or ownership protection is touched.

## 2. Version entry (no device results yet)

```toml
[versions."0.1.0~beta2"]
status = "experimental"
# Packaging compatibility candidate — installation fix not yet device-verified.
# No device_tests entry until a phone has attempted the install. Install and runtime are recorded separately.
```

Keep `[versions."0.1.0~beta1"]` and its `stage = "install"`, `result = "fail"` entry exactly as they are.

## 3. Known issues (replace the first bullet)

```
- **0.1.0~beta1 failed to install** on iPhone 11 Pro Max, iOS 17.4, Dopamine 2.x (rootless), Zebra 1.1.x (17 Nov 2026): the download worked, then unpacking stopped with `dpkg-deb: error: <decompress> subprocess was killed by signal (Bus error: 10)`. Nothing was installed. The cause is still under investigation.
- **0.1.0~beta2 is a packaging compatibility candidate. The installation fix is not yet device-verified.** It is the same tweak repackaged with gzip, and has not yet been installed on any device.
```

## 4. Changelog

Prepend this handoff's `CHANGELOG.md` to `packages/com.hakmicapitalgroup.vortex/CHANGELOG.md`.

## 5. Import

Add `imports/hcg-vortex-0.1.0-beta2-rootless.toml` (with `channel = "candidate"`) on a branch. **Prepare packages**
then fetches and checks it. Then merge, and run Publish when HCG decides to. The candidate index then lists both
versions. Zebra offers the highest, `0.1.0~beta2`, as the upgrade, because `0.1.0~beta1 < 0.1.0~beta2 < 0.1.0`.
