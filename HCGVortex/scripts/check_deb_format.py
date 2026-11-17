#!/usr/bin/env python3
"""Check the on-disk format of an HCG Vortex .deb (packaging regression check).

    python3 -I scripts/check_deb_format.py path/to/package.deb

From 0.1.0~beta2 every member must be gzip: debian-binary, control.tar.gz,
data.tar.gz, in that order, and nothing else. Each .gz member must decompress
completely with its CRC-32 and length checked, and contain a readable tar.

Why: 0.1.0~beta1 shipped Theos's default data.tar.lzma (lzma-alone, 64 MiB
dictionary). On one phone, dpkg-deb's <decompress> subprocess died with a Bus
error while unpacking it. The cause is not confirmed. This check only stops a
build that no longer uses the gzip packaging selected for beta2.

Prints PASS/FAIL/INFO lines and exits 1 on any FAIL. Standard library only,
so it runs the same on macOS and Linux.
"""
import gzip
import io
import lzma
import struct
import sys
import tarfile
import zlib

EXPECTED_MEMBERS = ["debian-binary", "control.tar.gz", "data.tar.gz"]


def read_ar(blob):
    """Return [(name, bytes)] for a System V / GNU ar archive, or raise ValueError."""
    if blob[:8] != b"!<arch>\n":
        raise ValueError("not an ar archive (bad global header)")
    pos, out = 8, []
    while pos < len(blob):
        if pos + 60 > len(blob):
            raise ValueError(f"truncated ar member header at offset {pos}")
        hdr = blob[pos:pos + 60]
        if hdr[58:60] != b"`\n":
            raise ValueError(f"bad ar member header magic at offset {pos}")
        name = hdr[0:16].decode("ascii", "replace").rstrip(" ").rstrip("/")
        size = int(hdr[48:58].decode("ascii").strip())
        start = pos + 60
        if start + size > len(blob):
            raise ValueError(f"member {name!r} is truncated ({size} bytes declared)")
        out.append((name, blob[start:start + size]))
        pos = start + size + (size & 1)  # members are 2-byte aligned
    return out


def describe(data):
    """Name the compression format of a member from its magic bytes (diagnostic only)."""
    if data[:2] == b"\x1f\x8b":
        return "gzip"
    if data[:6] == b"\xfd7zXZ\x00":
        return "xz"
    if data[:4] == b"\x28\xb5\x2f\xfd":
        return "zstd"
    if data[:3] == b"BZh":
        return "bzip2"
    if len(data) >= 13 and data[0] < 225:
        dict_size = struct.unpack("<I", data[1:5])[0]
        return f"lzma-alone? (props 0x{data[0]:02x}, dictionary {dict_size} bytes)"
    return "unknown"


def gunzip_exact(data):
    """Decompress a single gzip member completely. Raises on CRC/length errors,
    truncation or trailing bytes."""
    if data[:3] != b"\x1f\x8b\x08":
        raise ValueError(f"not gzip/deflate: {describe(data)}")
    d = zlib.decompressobj(wbits=16 + zlib.MAX_WBITS)  # checks CRC-32 and ISIZE
    out = d.decompress(data) + d.flush()
    if not d.eof:
        raise ValueError("gzip stream is truncated (no end of stream)")
    if d.unused_data:
        raise ValueError(f"{len(d.unused_data)} bytes after the gzip stream")
    # Cross-check with the gzip module as well (independent trailer parsing).
    if gzip.decompress(data) != out:
        raise ValueError("zlib and gzip module disagree")
    return out


def check(path):
    """Return (results, info): results is [(ok, message)], info a dict for callers."""
    results, info = [], {}
    blob = open(path, "rb").read()
    try:
        members = read_ar(blob)
    except ValueError as e:
        return [(False, f"ar container: {e}")], info
    names = [n for n, _ in members]
    if names == EXPECTED_MEMBERS:
        results.append((True, "ar members: " + ", ".join(names)))
    else:
        detail = ", ".join(f"{n} ({describe(d) if n != 'debian-binary' else 'text'})" for n, d in members)
        results.append((False, f"ar members are [{detail}], expected {', '.join(EXPECTED_MEMBERS)}"))
    by_name = dict(members)

    if by_name.get("debian-binary") == b"2.0\n":
        results.append((True, "debian-binary is 2.0"))
    else:
        results.append((False, f"debian-binary is {by_name.get('debian-binary')!r}"))

    for name in ("control.tar.gz", "data.tar.gz"):
        data = by_name.get(name)
        if data is None:
            continue
        try:
            raw = gunzip_exact(data)
            with tarfile.open(fileobj=io.BytesIO(raw), mode="r:") as tf:
                entries = tf.getmembers()
            files = sum(1 for e in entries if e.isfile())
            info[name] = {"compressed": len(data), "uncompressed": len(raw), "entries": len(entries), "files": files}
            results.append((True, f"{name}: gzip, fully decompressed {len(data)} -> {len(raw)} bytes, "
                                  f"CRC-32 and length OK, tar of {len(entries)} entries ({files} files)"))
        except (ValueError, OSError, EOFError, zlib.error, tarfile.TarError, lzma.LZMAError) as e:
            results.append((False, f"{name}: {e}"))
    return results, info


def main(argv):
    if len(argv) != 2:
        print("usage: check_deb_format.py package.deb", file=sys.stderr)
        return 2
    results, info = check(argv[1])
    for ok, msg in results:
        print(("PASS " if ok else "FAIL ") + msg)
    if "data.tar.gz" in info:
        print(f"INFO data_uncompressed_bytes={info['data.tar.gz']['uncompressed']}")
    return 0 if all(ok for ok, _ in results) else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
