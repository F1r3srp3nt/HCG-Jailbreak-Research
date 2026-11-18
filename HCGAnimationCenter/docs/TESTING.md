# Testing — what has and has not been verified (0.1.0~beta1)

Build validation, Simulator evidence and device testing are reported **separately**. Only the last one says anything
about SpringBoard on a phone, and **it has not happened yet.**

## 1. Build validation (package and source) — PASSED

| Check | Where | Result |
|---|---|---|
| C core: layout, crop, preset sanitising, GIF timing, playback policy (exhaustive over all 49,152 input combinations) | `tests/test_core.c`; Linux GCC + Clang (ASan/UBSan), macOS | **49,243 checks passed** |
| Preset schema ↔ examples ↔ C constants | `tests/test_schema.py` | **28 checks passed** |
| Packaging-format regression (gzip-only members) | `tests/test_deb_format.py` | **13 cases, 0 failures** |
| Canonical build, macOS 15 / Xcode, Theos `8167f59`, patched iPhoneOS16.5 SDK | run [44242604467](https://github.com/F1r3srp3nt/HCG-Jailbreak-Research/actions/runs/44242604467) | **success** |
| `validate.sh --require-new-abi` on that package: metadata, gzip format + full decompression, payload under `/var/jb`, permissions, `postrm` scope, version + build ID in both binaries, fat arm64/arm64e with signatures and iOS 15.0 minimum, **native arm64e ABI (0x80000002)**, SpringBoard-only filter, expected interfaces, **no API that changes the system wallpaper**, no networking / spawning / keychain / Photos-library APIs or URLs, `dpkg -i` + `dpkg -r` in a scratch root leaves nothing | same run | **0 failures, 0 warnings** |
| Independent re-check: artifact downloaded, SHA-256 recomputed, `validate.sh --require-new-abi` re-run from commit `2d642bd` outside CI | development container (Linux) | **same SHA-256; 0 failures, 0 warnings** |
| Linux test build (allemande-converted, never distributed) | development container | 0 failures, 2 expected warnings (dirty tree, converted ABI) |

Package: `com.hakmicapitalgroup.animationcenter_0.1.0~beta1_iphoneos-arm64.deb`, 360,342 bytes, SHA-256
`27a161b3cc323f09940211553b058873218697b49c995812f04e579f97429f60`.

## 2. iOS Simulator — runtime tests — PASSED

`scripts/run-simulator-tests.sh` (job *simulator-tests* of run 44242604467): **103 checks passed.** No SpringBoard.

- Preset format: valid document, dictionary and JSON round trips, property-list safety; refusals (newer major version,
  wrong format, `../` / absolute / hidden file names, missing media, impossible numbers, wrong kind, bad id, wrong
  types); repairs with warnings (speed, scaling, sound); a `.hcgbackground` folder loads.
- Preferences: defaults (off; Home on; Lock off; still for Reduce Motion / Low Power), stored presets, "same as Home",
  invalid placement → automatic, unsafe stored preset rejected with a reason.
- Importer on generated media: a video **with an audio track** is stored with **no audio track**; size, duration,
  checksum, still, thumbnail; a GIF with 0 / 50 / 200 ms delays becomes a 1.05 s H.264 video at even size; random
  bytes, a truncated MP4, a PNG, a one-frame GIF and an empty file are each refused with a reason and leave no files;
  staging cleaned; a corrupt library file is quarantined; export + re-import of a preset folder; a tampered export is
  refused by its checksum.
- Renderer: never interactive, hidden from accessibility; plays muted at 1× with `AVQueuePlayer + AVPlayerLooper`;
  no audio track in the played asset; still loaded below; layout equals the C core; scaling and speed changes keep the
  same decoder; a trim change reloads (1.0 s clip); paused → rate 0; still / none → decoder freed; play once holds
  the last frame; damaged media → exactly one failure report, decoder freed, no retry loop; missing file fails at once.
- AI interface: the shipped provider is *not connected* and refuses; request validation.
- Hierarchy probe: sections present, every placement tried, file written.

## 3. iOS Simulator — preview with a stand-in SpringBoard

`scripts/preview.sh`, workflow **HCG Animation Center preview**. Real tweak code (`HACController`, `HACHosts`,
`HCGBackgroundView`) and the real Settings bundle in an app whose classes are named like SpringBoard's, plus the
**real code** of HCG Halo 0.3.0~beta1 (controller), HCG Vortex 0.3.1~beta1 (engine) and HCG Nexus 0.3.1~beta1 (panel).
Not SpringBoard, not a device.

PREVIEW_RESULT_PLACEHOLDER

## 4. Device testing — NOT DONE

| | |
|---|---|
| Device installation | **Not attempted** |
| Runtime on a device (Home Screen, Lock Screen, coexistence, battery, memory) | **Not verified** |
| Test device | iPhone 11 Pro Max reported; iOS version and jailbreak **unconfirmed** (`SPRINGBOARD_RESEARCH.md` §1) |
| Plan | `DEVICE_TEST_CHECKLIST.md` (device report, install, probe, library, Home, Lock, coexistence, recovery) |
