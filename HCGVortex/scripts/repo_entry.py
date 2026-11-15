#!/usr/bin/env python3
"""Prints the HCG Repo `Packages` stanza for a built HCG Vortex .deb.

    python3 scripts/repo_entry.py packages/com.hakmicapitalgroup.vortex_0.1.0~alpha_iphoneos-arm64.deb

Read-only: it does not touch, upload to, or regenerate any repository. The
HCG Repo maintainer pastes the output into the repo's own tooling after
review. Depiction/Icon URLs are placeholders until the repo URL is confirmed.
"""
import hashlib
import os
import subprocess
import sys

REPO_BASE = os.environ.get("HCG_REPO_BASE", "https://REPLACE-WITH-HCG-REPO-URL")


def main(path: str) -> None:
    control = subprocess.run(["dpkg-deb", "-f", path], check=True, capture_output=True, text=True).stdout.strip()
    data = open(path, "rb").read()
    name = os.path.basename(path)
    extra = {
        "Filename": f"debs/{name}",
        "Size": str(len(data)),
        "MD5sum": hashlib.md5(data).hexdigest(),
        "SHA1": hashlib.sha1(data).hexdigest(),
        "SHA256": hashlib.sha256(data).hexdigest(),
        "Depiction": f"{REPO_BASE}/depictions/com.hakmicapitalgroup.vortex/",
        "SileoDepiction": f"{REPO_BASE}/depictions/com.hakmicapitalgroup.vortex/depiction.json",
        "Icon": f"{REPO_BASE}/depictions/com.hakmicapitalgroup.vortex/icon-512.png",
    }
    print(control)
    for key, value in extra.items():
        print(f"{key}: {value}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
