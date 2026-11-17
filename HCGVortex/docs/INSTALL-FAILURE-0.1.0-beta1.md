# 0.1.0~beta1: observed unpacking failure

| Status | Result |
|---|---|
| Download | Worked |
| **Installation** | **Failed while unpacking.** dpkg-deb could not decompress the data member. Nothing was installed |
| **Runtime** | **Not tested.** The tweak never ran on any device |
| Cause | **Not confirmed.** Under investigation |

## Observed

These facts come from the user's screen recording of Zebra, 17 Nov 2026, and HCG-repo
`docs/device-tests/vortex-0.1.0-beta1.md`. The device facts there are iPhone 11 Pro Max, iOS 17.4, Dopamine
(rootless) and Zebra. They have not yet been confirmed with `scripts/device-info.sh`.

- Source: "HCG Repo Candidate" (`https://repo.hakmicapitalgroup.com/repo/candidate/`). The listing, queue and
  download worked. Zebra stored the file at `/var/mobile/Library/Application Support/xyz.willy.Zebra/debs/com.hakmicapitalgroup.vortex_0.1.0~beta1.deb`, shown as 81.7 kB.
- `Reading database ... 10769 files` and `Preparing to unpack` succeeded. So the ar container, `debian-binary` and
  `control.tar.gz` were read.
- Then:

  ```
  dpkg-deb: error: <decompress> subprocess was killed by signal (Bus error: 10)
  dpkg-deb --fsys-tarfile subprocess returned error exit status 2
  ```

## The artifact (unchanged and kept)

| | |
|---|---|
| File | `com.hakmicapitalgroup.vortex_0.1.0~beta1_iphoneos-arm64.deb`, 81,650 bytes |
| SHA-256 | `bb0af72745a36158d4022c1b97ebc9800847cf4b1fb42ca14d05b9fc07673eea` |
| Build | commit `7d5e5b9`, run 43970942708, artifact 14278312698 |
| Members | `debian-binary` (4 B), `control.tar.gz` (736 B), `data.tar.lzma` (80,722 B) |
| `data.tar.lzma` | lzma-alone, properties `0x5d`, **dictionary 67,108,864 B (64 MiB)**, size field unknown (streamed). It holds a 560,640-byte tar. These are Theos's defaults (lzma, level 9) |
| Off-device | Decodes completely with liblzma (`xz --format=lzma -t`) and lists 9 files. Decoding it needs about 65 MiB of memory: with a 32 MiB limit, xz refuses it |

## Possible causes still open

None of these is confirmed. The read-only phone checks will decide between them.

1. **The downloaded file is corrupt or different.** Ruled out only once Zebra's copy is hashed on the phone.
2. **The phone's decompressor fails on this format or dictionary size**, in the environment where Zebra runs
   dpkg-deb. Note that many Theos packages ship with the same defaults and install normally.
3. **The phone's decompressor or dpkg is broken**, so other packages would fail too.

## Response

- beta1 is kept as it is: same bytes, same version, same SHA-256. It is never rebuilt or relabelled.
- **0.1.0~beta2** is a packaging-only rebuild with gzip members (`CHANGELOG.md`). It is labelled
  "Packaging compatibility candidate — installation fix not yet device-verified" until it installs on a phone.
