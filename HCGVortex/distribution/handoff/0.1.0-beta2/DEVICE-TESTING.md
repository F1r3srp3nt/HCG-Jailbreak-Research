# Device testing: HCG Vortex 0.1.0~beta2

**Packaging compatibility candidate — installation fix not yet device-verified.**

| | |
|---|---|
| **Installation** | **Not yet attempted.** No phone has installed this build |
| **Runtime** | **Not tested** |
| Off-device | Format and decompression verified in CI: gzip members; `dpkg-deb --fsys-tarfile` exit 0. Validation and the comparison with beta1 passed. See FORMAT.txt, VALIDATE.txt and COMPARISON.md |

## Why this build exists

0.1.0~beta1 **failed to unpack** on one phone. See `HCGVortex/docs/INSTALL-FAILURE-0.1.0-beta1.md` in
HCG-Jailbreak-Research. beta2 repackages the same build inputs with gzip. Its own install result is needed before
anyone can say the problem is fixed. Two things remain open:
- **beta1's cause is unconfirmed.** It is not established that the lzma format or its 64 MiB dictionary caused the
  failure, or that the phone's dpkg is at fault.
- **gzip is not yet proven to install on that phone.**

## Recording results (HCG-repo `package.toml`)

Keep the install attempt and runtime testing as **separate** entries. An install result says nothing about runtime.

```toml
[versions."0.1.0~beta2"]
status = "experimental"

[[versions."0.1.0~beta2".device_tests]]          # install attempt
device = "<model> (<identifier>)"
ios = "<version> (<build>)"
jailbreak = "<jailbreak> <version>, rootless, <package manager> <version>"
date = "<YYYY-MM-DD>"
stage = "install"
result = "<pass|fail>"
evidence = "<link to the record>"
```

A runtime entry (`result = "pass"`, so `status = "device-tested"`) needs everything below. A successful install
alone is not a runtime pass.
- *Engine Status: Active*.
- One effect visibly working in both swipe directions.
- Correct icon taps after a transition.
- Stock behaviour after disabling and after a respring.
- A clean uninstall.

"Incompatible", "Fault", "Auto-disabled", a SpringBoard crash, a stuck page or a wrong icon tap is `fail` (or
`partial`) and goes in `known_issues`. Procedure: `HCGVortex/docs/DEVICE_TEST_HANDOFF.md` and
`HCGVortex/docs/RECOVERY.md`.
