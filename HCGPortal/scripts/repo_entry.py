#!/usr/bin/env python3
"""Prints the control fields and hashes of a built HCG Portal .deb.

    python3 scripts/repo_entry.py packages/com.hakmicapitalgroup.portal_0.1.0~beta1_iphoneos-arm64.deb

Read-only. For cross-checking what HCG-repo's importer records. HCG-repo
(https://repo.hakmicapitalgroup.com/repo/) adds Filename, Depiction,
SileoDepiction, Icon and Header itself, so they are not printed here. See
distribution/README.md.
"""
import hashlib
import subprocess
import sys


def main(path: str) -> None:
    control = subprocess.run(["dpkg-deb", "-f", path], check=True, capture_output=True, text=True).stdout.strip()
    data = open(path, "rb").read()
    print(control)
    print(f"Size: {len(data)}")
    print(f"MD5sum: {hashlib.md5(data).hexdigest()}")
    print(f"SHA1: {hashlib.sha1(data).hexdigest()}")
    print(f"SHA256: {hashlib.sha256(data).hexdigest()}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
