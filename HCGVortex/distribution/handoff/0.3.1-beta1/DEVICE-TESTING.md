# Device testing: HCG Vortex 0.3.1~beta1

| | |
|---|---|
| **0.3.1~beta1 itself** | **Not yet installed or run on a device** |
| **Previous build** | **Partial device test** (`HCGVortex/docs/device-tests/2026-11-18-recording-0.3.0.md`). One camera recording on an iPhone 11 Pro Max (per the wallpaper), with HCG Halo enabled. Orbital, Tornado and Magnetic Grid were seen running; restoration after completed, reversed and cancelled swipes looked correct. **Installed version, iOS and jailbreak are not yet confirmed**: the evidence points to 0.3.0~beta1 |
| Not shown | Tap targets, performance, battery, Warp, Holographic Layers, Circuit Flow, Reduce Motion, widgets |
| With HCG Halo | Running together in the recording; no artefact attributable to Halo. Not ruled out |
| Off-device | Xcode build; `validate.sh --require-new-abi` (host tests, including device-layout regression tests); gzip format and decompression checks |

## Before recording a device test for 0.3.1~beta1

Confirm all of these first:
- the device: `scripts/device-info.sh`;
- the installed version: Settings › HCG Vortex › Reset & Diagnostics › Version, or `dpkg-query -W com.hakmicapitalgroup.vortex`;
- the SHA-256 of the installed `.deb`.

Then repeat the recorded swipes with Orbital and Tornado to check fixes F1–F3:
- no flash at the start of a swipe;
- the funnel has width at every height;
- the rings are legible;
- labels are hidden in formations and back afterwards.

Also tap an app after a completed and after a cancelled swipe. To isolate coexistence, repeat two swipes per effect
with HCG Halo turned off.

## Recording results (HCG-repo `package.toml`)

Keep installation and runtime separate, and mark partial evidence as `partial`.

```toml
[[versions."0.3.0~beta1".device_tests]]          # the recording, once the version is confirmed
device = "iPhone 11 Pro Max (<identifier>)"
ios = "<version> (<build>)"
jailbreak = "<jailbreak> <version>, rootless, <package manager>"
date = "2026-11-18"
stage = "runtime"
result = "partial"
evidence = "HCGVortex/docs/device-tests/2026-11-18-recording-0.3.0.md"
```
