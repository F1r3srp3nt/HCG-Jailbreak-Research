# HCG Animation Center 0.2.0~alpha1 — development build (awaiting manual approval)

**Not published.** Not a candidate, not imported into HCG Repo, no existing release changed. Installing it on a phone
is a manual decision; it has **not** been device-tested (`docs/DEVICE_TEST_CHECKLIST.md`, rows O1–O10 for this build).

| | |
|---|---|
| Package | `com.hakmicapitalgroup.animationcenter_0.2.0~alpha1_iphoneos-arm64.deb` |
| Size | 417,674 bytes |
| SHA-256 | `d9bb375e78ee728a84ea93d7350562da309cc7b9ddef1c7b7dbae4f29f762e20` |
| SHA-512 | `120043591a6cbf06cadd80c1475f323b2880365aa05c4395f3b24f8c6a0e2202f34dc7128ab3a40968daed9b674b4d86bc9a744ee2e8a741a53a5f9ba62beeca` |
| Source commit | `4fbebd2e89ce3462cc6e00368470222a42e2b2af` (branch `claude/stoic-gates-07elp7`); build ID `4fbebd2e89ce` in both binaries |
| Built by | workflow *HCG Animation Center build*, run [44885278113](https://github.com/F1r3srp3nt/HCG-Jailbreak-Research/actions/runs/44885278113) (macOS 15 / Xcode, Theos `8167f59`, patched iPhoneOS16.5 SDK) |
| Artifact | `hcg-animationcenter-rootless-deb`, id 14700296221, zip digest `sha256:071d605d7d63a1b415a3c04a06de763280ea3bf8e1b2553595bd6fc4cf43a6de`, expires 2027-02-19 |
| Validation | `validate.sh --require-new-abi`: 0 failures, 0 warnings in CI, and again outside CI from a clean worktree of the source commit (same SHA-256) |
| Format | gzip members, rootless `/var/jb`, fat arm64 + arm64e (native 0x80000002 ABI), iOS 15.0 minimum |
| Debian ordering | `0.2.0~alpha1` > `0.1.0~beta1` (upgrade from the candidate) and < a later `0.2.0~beta1` / `0.2.0` |
| Tests at this commit | host core 137,986 checks; schema 59; Simulator 236 checks; Mac readers OK (`docs/TESTING.md`) |

Downloading: GitHub › Actions › run 44885278113 › artifact *hcg-animationcenter-rootless-deb*; check the SHA-256 above
before installing.
