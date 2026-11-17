# Device testing: HCG Vortex 0.1.0~beta1

## Status

| | |
|---|---|
| **Installation** | **FAILED: observed unpacking failure** (17 Nov 2026). Zebra downloaded the package, then `dpkg-deb: error: <decompress> subprocess was killed by signal (Bus error: 10)`. Nothing was installed. Record: `HCGVortex/docs/INSTALL-FAILURE-0.1.0-beta1.md` |
| **Runtime** | **NOT TESTED.** The tweak never ran on any device |
| Cause | Not confirmed (under investigation) |

The phone was recorded in HCG-repo as iPhone 11 Pro Max, iOS 17.4, Dopamine 2.x (rootless), Zebra 1.1.x. Those
details have not been confirmed with `scripts/device-info.sh`.

Note: this file was updated after the beta1 handoff archive was produced. The archive's copy, written before the
install attempt, says "NOT TESTED".

So HCG-repo should record the install attempt with `stage = "install"` and `result = "fail"`, and must not record
any runtime result. beta1's bytes and SHA-256 (`bb0af727…07673eea`) stay unchanged. The packaging-only follow-up is
0.1.0~beta2.

What has been verified for beta1 is limited to the build:
- Xcode CI compile and link;
- package validation (`validate.sh --require-new-abi`);
- host unit tests;
- compatibility-gate tests against fake runtime classes;
- an HCG-repo dry run in a scratch copy.

None of these shows that the tweak works on a device.

## Recording a test later (HCG-repo `package.toml`)

Use HCG-repo's schema. Required fields: device, ios, jailbreak, date, result, evidence. `result` is one of
`pass`, `fail`, `partial`.

```toml
[versions."0.1.0~beta1"]
status = "device-tested"           # only with at least one result = "pass"
device_tests = [
  { device = "<model> (<identifier>)", ios = "<version> (<build>)", jailbreak = "<jailbreak> <version>, rootless, <injector> <version>", date = "<YYYY-MM-DD>", result = "<pass|fail|partial>", evidence = "<link to the test record>" },
]
```

Rules for this beta:
- **Engine Status "Incompatible"** (required SpringBoard methods missing): that configuration is unsupported. Record
  `result = "fail"` and describe it in `[display] known_issues`. It is never a pass.
- **Engine Status "Fault" or "Auto-disabled"**, a SpringBoard crash, a stuck page or a wrong icon tap: `fail`, or
  `partial` if the effects otherwise worked. Describe it in `known_issues`.
- `pass` needs:
  - *Engine Status: Active*;
  - one effect visibly working in both swipe directions;
  - correct icon taps after a transition;
  - stock behaviour after disabling and after a respring;
  - a clean uninstall.

The test procedure is in HCG-Jailbreak-Research `HCGVortex/docs/DEVICE_TEST_HANDOFF.md`. It confirms the device
with `scripts/device-info.sh` first.
