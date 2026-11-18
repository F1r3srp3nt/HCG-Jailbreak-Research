# Device testing: HCG Vortex 0.3.0~beta1

| | |
|---|---|
| **Installation** | **Not yet attempted** |
| **Runtime** | **Not tested**, for any of the six icon effects |
| Performance / battery | **Not measured** |
| With HCG Halo / HCG Nexus | **Not tested.** No compatibility is claimed |
| Off-device | Xcode build; `validate.sh --require-new-abi`, including all geometry tests and every Settings page; gzip format and decompression checks. See VALIDATE.txt and FORMAT.txt |

History:
- 0.1.0~beta1 failed to unpack on one phone; the cause is unconfirmed.
- 0.1.0~beta2 and 0.2.0~beta1 have not been installed.

## What a device test must show

Follow `HCGVortex/docs/DEVICE_TEST_HANDOFF.md` section C, for each icon effect:
- the formation is recognisable mid-swipe and follows the finger;
- pause holds, reverse unwinds, cancel restores every icon exactly;
- taps open the intended app after a completed **and** after a cancelled swipe;
- widgets fade in place;
- Reduce Motion gives the stock animation;
- disabling restores everything;
- Circuit Flow traces vanish once the page settles;
- Magnetic Grid snaps once and then stops;
- a smoothness impression per effect.

## Recording results (HCG-repo `package.toml`)

Record installation and runtime as separate entries, with the effect named in `evidence`. A successful install is not
a runtime pass.

```toml
[versions."0.3.0~beta1"]
status = "experimental"

[[versions."0.3.0~beta1".device_tests]]
device = "<model> (<identifier>)"
ios = "<version> (<build>)"
jailbreak = "<jailbreak> <version>, rootless, <package manager> <version>"
date = "<YYYY-MM-DD>"
stage = "install"            # then one entry per runtime check, stage = "runtime"
result = "<pass|fail|partial>"
evidence = "<link to the record>"
```
