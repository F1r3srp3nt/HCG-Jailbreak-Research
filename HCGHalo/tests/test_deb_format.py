#!/usr/bin/env python3
"""Regression tests for scripts/check_deb_format.py (gzip-only packaging check).

Adapted from HCG Vortex (HCGVortex/tests/test_deb_format.py).

    python3 -I tests/test_deb_format.py [real.deb:expect ...]

Builds small synthetic .debs in memory and checks the format check accepts
only the gzip layout. One case reproduces HCG Vortex beta1's data member exactly: an
lzma-alone stream with a 64 MiB dictionary and unknown size. Optional
arguments check real packages, e.g. `beta1.deb:fail beta2.deb:pass`.
"""
import gzip
import importlib.util
import io
import lzma
import os
import sys
import tarfile
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("check_deb_format", os.path.join(HERE, "..", "scripts", "check_deb_format.py"))
cdf = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cdf)


def tar_of(files):
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w", format=tarfile.GNU_FORMAT) as tf:
        for name, data in files.items():
            ti = tarfile.TarInfo(name)
            ti.size = len(data)
            tf.addfile(ti, io.BytesIO(data))
    return buf.getvalue()


def ar_of(members):
    out = [b"!<arch>\n"]
    for name, data in members:
        hdr = f"{name:<16}{0:<12}{0:<6}{0:<6}{0o100644:<8o}{len(data):<10}`\n".encode()
        assert len(hdr) == 60
        out += [hdr, data, b"\n" if len(data) & 1 else b""]
    return b"".join(out)


CONTROL = tar_of({"./control": b"Package: test\nVersion: 1\nArchitecture: iphoneos-arm64\n"})
DATA = tar_of({"./var/jb/Library/test.dylib": os.urandom(40000) + b"\0" * 200000})


def gz(b):
    return gzip.compress(b, compresslevel=9, mtime=0)


def lzma_alone_64m(b):
    # beta1's shape: props 0x5d, dictionary 64 MiB, size unknown (streamed)
    return lzma.compress(b, format=lzma.FORMAT_ALONE, filters=[{"id": lzma.FILTER_LZMA1, "preset": 9}])


CASES = []


def case(name, expect_ok, members=None, blob=None, must_mention=None):
    CASES.append((name, expect_ok, blob if blob is not None else ar_of(members), must_mention))


good = [("debian-binary", b"2.0\n"), ("control.tar.gz", gz(CONTROL)), ("data.tar.gz", gz(DATA))]
case("gzip control + gzip data (beta2 layout)", True, good)
case("lzma-alone data, 64 MiB dictionary (beta1 layout)", False,
     [good[0], good[1], ("data.tar.lzma", lzma_alone_64m(DATA))], must_mention="dictionary 67108864")
case("xz data", False, [good[0], good[1], ("data.tar.xz", lzma.compress(DATA, preset=6))])
case("data.tar.gz that is really xz", False, [good[0], good[1], ("data.tar.gz", lzma.compress(DATA))])
case("truncated gzip data", False, [good[0], good[1], ("data.tar.gz", gz(DATA)[:-9])])
bad_crc = bytearray(gz(DATA)); bad_crc[-6] ^= 0xFF
case("gzip data with a wrong CRC-32", False, [good[0], good[1], ("data.tar.gz", bytes(bad_crc))])
case("gzip data with trailing bytes", False, [good[0], good[1], ("data.tar.gz", gz(DATA) + b"junk")])
case("gzip that is not a tar", False, [good[0], good[1], ("data.tar.gz", gz(b"x" * 1000))])
case("extra member", False, good + [("extra", b"x")])
case("wrong member order", False, [good[0], good[2], good[1]])
case("debian-binary 3.0", False, [("debian-binary", b"3.0\n")] + good[1:])
case("truncated ar container", False, blob=ar_of(good)[:-500])
case("not an ar archive", False, blob=b"PK\x03\x04 not a deb")


def run(path):
    results, _ = cdf.check(path)
    return all(ok for ok, _ in results), results


failures = 0
with tempfile.TemporaryDirectory() as tmp:
    for i, (name, expect_ok, blob, must_mention) in enumerate(CASES):
        p = os.path.join(tmp, f"case{i}.deb")
        open(p, "wb").write(blob)
        ok, results = run(p)
        good_result = ok == expect_ok
        text = " | ".join(m for _, m in results)
        if must_mention and must_mention not in text:
            good_result = False
        print(("PASS " if good_result else "FAIL ") + f"{name}: check {'accepted' if ok else 'rejected'}"
              + ("" if expect_ok else f" ({text[:160]})"))
        failures += not good_result

for arg in sys.argv[1:]:
    path, _, expect = arg.rpartition(":")
    ok, results = run(path)
    good_result = ok == (expect == "pass")
    print(("PASS " if good_result else "FAIL ") + f"{os.path.basename(path)}: expected {expect}, check {'accepted' if ok else 'rejected'}")
    for r_ok, msg in results:
        print(f"       {'ok ' if r_ok else 'bad'} {msg}")
    failures += not good_result

print(f"{len(CASES) + len(sys.argv) - 1} cases, {failures} failures")
sys.exit(1 if failures else 0)
