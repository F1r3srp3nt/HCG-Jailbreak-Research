#!/usr/bin/env python3
"""The C core keeps kit 1.0's code byte for byte; 1.1 only appends.

    python3 -I tests/test_core_compat.py

HCG Animation Center for Mac (F1r3srp3nt/animation-centre) vendors
HCGBackgroundCore.c / .h from kit 1.0 unmodified and checks their SHA-256
(Packages/HCGAnimationKit/Vendor/VENDORED.md). Removing the 1.1 section from
the files here must reproduce exactly those bytes, so every function the Mac
app (and the 0.1.0 tweak) calls behaves identically, and re-vendoring 1.1 is
a pure addition.
"""
import hashlib
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
KIT = os.path.join(ROOT, "HCGBackgroundKit", "Sources", "HCGBackgroundKit")
VENDORED_10 = {  # animation-centre Vendor/VENDORED.md (kit 1.0 = commit 35d9db7 / 2d642bd)
    "c": "ac415e5b5d2eb4fffd1cc21fcc4887cb37529dd890a014e00f206a6edca9dc68",
    "h": "3c98d1eae549ef5fbdd82e7bad21991fd839e165f693397915b408689cee862b",
}
C_MARK = "\n// ---- Orientation and transformation (kit 1.1) "
H_MARK = "// ---- Orientation and transformation (kit 1.1; format v1 minor addition) "
H_END = "#ifdef __cplusplus\n}\n#endif"

failures = []
c = open(os.path.join(KIT, "HCGBackgroundCore.c"), "rb").read().decode()
if C_MARK not in c:
    failures.append("HCGBackgroundCore.c: 1.1 section marker missing")
else:
    base = c[: c.index(C_MARK)]
    if hashlib.sha256(base.encode()).hexdigest() != VENDORED_10["c"]:
        failures.append("HCGBackgroundCore.c: the code before the 1.1 section is no longer kit 1.0's")
h = open(os.path.join(KIT, "include", "HCGBackgroundCore.h"), "rb").read().decode()
if H_MARK not in h or H_END not in h:
    failures.append("HCGBackgroundCore.h: 1.1 section markers missing")
else:
    start = h.index(H_MARK)
    end = h.rindex(H_END)
    base = h[:start] + h[end:]
    if hashlib.sha256(base.encode()).hexdigest() != VENDORED_10["h"]:
        failures.append("HCGBackgroundCore.h: outside the 1.1 section it is no longer kit 1.0's")
if failures:
    print("\n".join(failures))
    sys.exit(1)
print("C core: kit 1.0 code unchanged (matches the Mac app's vendored SHA-256s); 1.1 is additions only")
