# Device testing: HCG Vortex 0.2.0~beta1

| | |
|---|---|
| **Installation** | **Not yet attempted** |
| **Runtime** | **Not tested**, including Tornado |
| With HCG Halo / HCG Nexus | **Not tested.** No compatibility is claimed |
| Off-device | Xcode build; `validate.sh --require-new-abi`, including the Tornado geometry tests; gzip format and decompression checks. See VALIDATE.txt and FORMAT.txt |

History: 0.1.0~beta1 failed to unpack on one phone (cause unconfirmed). 0.1.0~beta2 (gzip) has not been installed yet.
This build uses the same gzip packaging.

## What a device test must show (Tornado)

Follow `HCGVortex/docs/DEVICE_TEST_HANDOFF.md` section C, including:
- the funnel forms at mid-swipe and follows the finger;
- pause holds, reverse unwinds, cancel restores every icon exactly;
- taps open the intended app after a completed **and** after a cancelled swipe;
- widgets fade in place;
- Reduce Motion gives the stock animation;
- disabling restores everything;
- a smoothness impression on the actual hardware.

## Recording results (HCG-repo `package.toml`)

Record installation and runtime as separate entries. A successful install is not a runtime pass.

```toml
[versions."0.2.0~beta1"]
status = "experimental"

[[versions."0.2.0~beta1".device_tests]]
device = "<model> (<identifier>)"
ios = "<version> (<build>)"
jailbreak = "<jailbreak> <version>, rootless, <package manager> <version>"
date = "<YYYY-MM-DD>"
stage = "install"            # then a second entry with stage = "runtime"
result = "<pass|fail|partial>"
evidence = "<link to the record>"
```
