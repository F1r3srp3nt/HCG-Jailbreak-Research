#!/usr/bin/env python3
"""Compare two HCG Vortex .debs and account for every difference.

    python3 -I scripts/compare_debs.py OLD.deb NEW.deb [--markdown OUT.md]

Written for 0.1.0~beta1 (data.tar.lzma) -> 0.1.0~beta2 (data.tar.gz), which
come from the same tweak source and differ, by design, only in packaging and
version. It reports:

  * the archive members and their compression;
  * control fields that changed;
  * every payload entry: added/removed, type, mode, owner, size, SHA-256, mtime;
  * for each changed Mach-O file, every differing byte, sorted into
      - version: inside an occurrence of the old display version string
        (UTF-8, or UTF-16LE as in CFStrings with non-ASCII text),
      - LC_UUID: the linker's build UUID,
      - code signature: the LC_CODE_SIGNATURE blob (ldid ad-hoc signature,
        which hashes the pages above, so it changes whenever they do),
      - unexplained: anything else;
  * property lists key by key (binary or XML); other text files as a line diff.

Exit status 1 if any difference is unexplained (an unexpected file, a mode or
owner change, or Mach-O bytes outside the three categories). Standard library
only. It never executes or installs anything from the packages.
"""
import argparse
import difflib
import gzip
import hashlib
import io
import lzma
import plistlib
import struct
import sys
import tarfile

LC_UUID, LC_CODE_SIGNATURE = 0x1B, 0x1D


def read_ar(blob):
    assert blob[:8] == b"!<arch>\n", "not an ar archive"
    pos, out = 8, []
    while pos < len(blob):
        hdr = blob[pos:pos + 60]
        name = hdr[0:16].decode().rstrip(" ").rstrip("/")
        size = int(hdr[48:58].decode().strip())
        out.append((name, blob[pos + 60:pos + 60 + size]))
        pos += 60 + size + (size & 1)
    return out


def decompress(name, data):
    if name.endswith(".gz"):
        return gzip.decompress(data), "gzip"
    if name.endswith(".lzma"):
        dict_size = struct.unpack("<I", data[1:5])[0]
        return lzma.decompress(data, format=lzma.FORMAT_ALONE), f"lzma-alone, dictionary {dict_size} bytes"
    if name.endswith(".xz"):
        return lzma.decompress(data, format=lzma.FORMAT_XZ), "xz"
    raise ValueError(f"unsupported member {name}")


def load(path):
    blob = open(path, "rb").read()
    members = read_ar(blob)
    pkg = {"path": path, "size": len(blob), "sha256": hashlib.sha256(blob).hexdigest(), "members": [], "entries": {}}
    for name, data in members:
        if name == "debian-binary":
            pkg["members"].append((name, len(data), "text " + data.decode().strip()))
            continue
        raw, kind = decompress(name, data)
        pkg["members"].append((name, len(data), f"{kind}, {len(raw)} bytes uncompressed"))
        with tarfile.open(fileobj=io.BytesIO(raw), mode="r:") as tf:
            for ti in tf.getmembers():
                content = tf.extractfile(ti).read() if ti.isfile() else None
                key = ("control:" if name.startswith("control") else "") + ti.name.lstrip("./")
                pkg["entries"][key] = (ti, content)
    control = pkg["entries"]["control:control"][1].decode()
    pkg["control"] = dict(line.split(": ", 1) for line in control.splitlines() if ": " in line)
    return pkg


def macho_regions(blob):
    """Return [(start, end, label)] of LC_UUID and code-signature ranges in a (fat) Mach-O."""
    slices = []
    magic = struct.unpack(">I", blob[:4])[0]
    if magic == 0xCAFEBABE:
        n = struct.unpack(">I", blob[4:8])[0]
        for i in range(n):
            _, _, off, size, _ = struct.unpack(">IIIII", blob[8 + 20 * i:28 + 20 * i])
            slices.append(off)
    elif struct.unpack("<I", blob[:4])[0] == 0xFEEDFACF:
        slices.append(0)
    else:
        return None
    regions = []
    for base in slices:
        ncmds = struct.unpack("<I", blob[base + 16:base + 20])[0]
        p = base + 32
        for _ in range(ncmds):
            cmd, cmdsize = struct.unpack("<II", blob[p:p + 8])
            if cmd == LC_UUID:
                regions.append((p + 8, p + 24, "LC_UUID"))
            elif cmd == LC_CODE_SIGNATURE:
                off, size = struct.unpack("<II", blob[p + 8:p + 16])
                regions.append((base + off, base + off + size, "code signature"))
            p += cmdsize
    return regions


def classify_macho(old, new, old_ver, new_ver):
    """Sort every differing byte of two same-size Mach-O files into categories."""
    regions = macho_regions(old)
    if regions is None or len(old) != len(new):
        return None
    if macho_regions(new) != regions:
        return {"unexplained": ["load-command layout differs"]}
    ver_ranges = []
    # The version is compiled in as UTF-8 C strings and, inside CFStrings that
    # contain non-ASCII text (the settings header's "·"), as UTF-16LE.
    for ov, nv in ((old_ver, new_ver),
                   (old_ver.decode().encode("utf-16-le"), new_ver.decode().encode("utf-16-le"))):
        i = old.find(ov)
        while i >= 0:
            if new[i:i + len(nv)] == nv:
                ver_ranges.append((i, i + len(ov), "version"))
            i = old.find(ov, i + 1)
    counts = {"version": 0, "LC_UUID": 0, "code signature": 0, "unexplained": 0}
    unexplained = []
    for off in range(len(old)):
        if old[off] == new[off]:
            continue
        label = next((lab for s, e, lab in ver_ranges + regions if s <= off < e), "unexplained")
        counts[label] += 1
        if label == "unexplained" and len(unexplained) < 20:
            unexplained.append(f"0x{off:x}: {old[off]:02x} -> {new[off]:02x}")
    return {"counts": counts, "version_sites": len(ver_ranges), "unexplained": unexplained,
            "signature_bytes": sum(e - s for s, e, lab in regions if lab == "code signature")}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("old")
    ap.add_argument("new")
    ap.add_argument("--markdown")
    a = ap.parse_args()
    old, new = load(a.old), load(a.new)
    old_ver = old["control"]["Version"].replace("~", "-").encode()
    new_ver = new["control"]["Version"].replace("~", "-").encode()
    lines, problems = [], []
    say = lines.append

    say(f"# Package comparison: {old['control']['Version']} -> {new['control']['Version']}")
    say("")
    say("| | old | new |")
    say("|---|---|---|")
    say(f"| file | `{a.old.rsplit('/', 1)[-1]}` | `{a.new.rsplit('/', 1)[-1]}` |")
    say(f"| size | {old['size']} | {new['size']} |")
    say(f"| SHA-256 | `{old['sha256']}` | `{new['sha256']}` |")
    for (on, osz, ok), (nn, nsz, nk) in zip(old["members"], new["members"]):
        say(f"| member | `{on}` {osz} B ({ok}) | `{nn}` {nsz} B ({nk}) |")
    say("")

    say("## Control fields")
    say("")
    changed = False
    for k in sorted(set(old["control"]) | set(new["control"])):
        ov, nv = old["control"].get(k), new["control"].get(k)
        if ov != nv:
            changed = True
            say(f"- **{k}**: `{ov}` -> `{nv}`")
            if k not in ("Version", "Description", "Installed-Size"):
                problems.append(f"control field {k} changed")
    if not changed:
        say("- none")
    say("")

    say("## Payload")
    say("")
    keys = sorted(set(old["entries"]) | set(new["entries"]))
    mtime_changes = 0
    for key in keys:
        if key in ("control:control", "control:"):
            continue
        if key not in old["entries"] or key not in new["entries"]:
            where = "added" if key not in old["entries"] else "removed"
            say(f"- `{key}`: **{where}**")
            problems.append(f"{key} {where}")
            continue
        (oti, oc), (nti, nc) = old["entries"][key], new["entries"][key]
        meta = [(f, getattr(oti, f), getattr(nti, f)) for f in ("type", "mode", "uid", "gid", "uname", "gname", "linkname")
                if getattr(oti, f) != getattr(nti, f)]
        if oti.mtime != nti.mtime:
            mtime_changes += 1
        for f, ov, nv in meta:
            problems.append(f"{key}: {f} {ov!r} -> {nv!r}")
            say(f"- `{key}`: **{f}** {ov!r} -> {nv!r}")
        if oc is None or oc == nc:
            continue
        osha, nsha = hashlib.sha256(oc).hexdigest()[:16], hashlib.sha256(nc).hexdigest()[:16]
        head = f"- `{key}`: {len(oc)} -> {len(nc)} bytes, SHA-256 `{osha}…` -> `{nsha}…`"
        result = classify_macho(oc, nc, old_ver, new_ver)
        if result is not None:
            if result["unexplained"]:
                problems.append(f"{key}: unexplained Mach-O differences")
                say(head + ". **Unexplained bytes:** " + ", ".join(result["unexplained"]))
            else:
                c = result["counts"]
                say(head + f". Same size and load commands; every differing byte accounted for: "
                    f"{c['version']} in {result['version_sites']} version string(s) "
                    f"(`{old_ver.decode()}` -> `{new_ver.decode()}`), {c['LC_UUID']} in LC_UUID, "
                    f"{c['code signature']} inside the code signatures ({result['signature_bytes']} bytes in total), 0 elsewhere")
            continue
        if oc[:8] == b"bplist00" or oc.lstrip()[:5] == b"<?xml":
            # Property lists (binary on macOS builds): compare key by key.
            try:
                op, np_ = plistlib.loads(oc), plistlib.loads(nc)
            except Exception as e:  # noqa: BLE001 - report any parse failure as a problem
                problems.append(f"{key}: plist does not parse ({e})")
                say(head + f". **Plist does not parse:** {e}")
                continue
            if isinstance(op, dict) and isinstance(np_, dict):
                changes = [(k, op.get(k), np_.get(k)) for k in sorted(set(op) | set(np_)) if op.get(k) != np_.get(k)]
                say(head + ". Plist keys changed: " + ("; ".join(f"`{k}` `{ov}` -> `{nv}`" for k, ov, nv in changes) or "none (encoding only)"))
                for k, ov, nv in changes:
                    if not (isinstance(ov, str) and isinstance(nv, str) and ov.replace(old_ver.decode(), new_ver.decode()) == nv):
                        problems.append(f"{key}: plist key {k} changed beyond the version")
                continue
        if b"\0" not in oc[:4096] and b"\0" not in nc[:4096]:
            diff = [d for d in difflib.unified_diff(oc.decode().splitlines(), nc.decode().splitlines(), lineterm="", n=0)
                    if d[:1] in "+-" and d[:3] not in ("+++", "---")]
            say(head + ". Text diff: " + "; ".join(f"`{d.strip()}`" for d in diff))
            if any(old_ver.decode() not in d and new_ver.decode() not in d for d in diff):
                problems.append(f"{key}: text change other than the version")
            continue
        say(head + ". **Binary change not classified**")
        problems.append(f"{key}: unclassified binary change")
    if mtime_changes:
        say(f"- Timestamps: {mtime_changes} entries have new mtimes (each build stamps the time it ran)")
    say("")
    say("## Result")
    say("")
    if problems:
        say("**Unexplained differences:**")
        for p in problems:
            say(f"- {p}")
    else:
        say("Every difference is accounted for. The only kinds of change allowed are: archive members and their "
            "compression; the control Version, Description and Installed-Size; the version string inside files; "
            "file timestamps; and the Mach-O build UUIDs and code signatures. Anything else fails this comparison.")
    text = "\n".join(lines) + "\n"
    print(text)
    if a.markdown:
        open(a.markdown, "w").write(text)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
