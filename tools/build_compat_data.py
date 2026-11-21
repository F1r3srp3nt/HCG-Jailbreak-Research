#!/usr/bin/env python3
"""Build the device/firmware dataset used by the HCG Jailbreak Academy compatibility checker.

Inputs (read-only):
  --appledb PATH   a checkout of https://github.com/littlebyteorg/appledb (the database ellekit.space links
                   to for "a more detailed breakdown of device and version support"). Needs deviceFiles/iPhone,
                   deviceFiles/iPad, osFiles/iOS, osFiles/iPadOS and jailbreakFiles/dopamine.json.

Output:
  academy/assets/compat-data.js    window.HCG_COMPAT_DATA = {...}  (loaded by the page)
  academy/data/compat-data.json    the same object                 (used by tests and reviewers)

What this script does NOT decide: which iOS versions Dopamine supports. Those ranges are written by hand in
academy/assets/compat.js from Dopamine's own README and website (see docs/SOURCES.md). This script only supplies
facts about Apple hardware and releases (model -> chip, which versions each model actually received), plus
AppleDB's own Dopamine entry, which tests/compat.test.mjs uses as an independent cross-check.

Standard library only. Run:  python3 tools/build_compat_data.py --appledb /path/to/appledb
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MIN_MAJOR, MAX_MAJOR = 15, 27          # iOS/iPadOS versions considered (Dopamine's floor is 15.0)
KEEP_RC_BUILDS = {"20H18"}             # 16.7 RC is named by Dopamine/TrollStore documentation; other RCs are not
VARIANT_RE = re.compile(
    r"\s*\((?:GSM|CDMA|Global|China|Japan|VZ)\)|\s+Wi-Fi \+ Cellular|\s+Wi-Fi"
    r"|\s+\((?:1TB|1 or 2 TB|Cellular|VZ)\)",
)


def norm_name(name: str) -> str:
    """'iPad Pro 11-inch (3rd generation) Wi-Fi + Cellular (1 or 2 TB)' -> 'iPad Pro 11-inch (3rd generation)'."""
    out = VARIANT_RE.sub("", name)
    return re.sub(r"\s{2,}", " ", out).strip()


def vkey(v: str) -> tuple:
    nums = [int(x) for x in re.findall(r"\d+", v.split(" ")[0])]
    return tuple(nums + [0] * (3 - len(nums))) + ((0,) if "RC" in v else (1,))


def git_head(path: Path) -> dict:
    try:
        sha = subprocess.check_output(["git", "-C", str(path), "rev-parse", "HEAD"], text=True).strip()
        date = subprocess.check_output(["git", "-C", str(path), "log", "-1", "--format=%cs"], text=True).strip()
        return {"commit": sha, "date": date}
    except (subprocess.CalledProcessError, FileNotFoundError):
        return {"commit": "unknown", "date": "unknown"}


def load(path: str) -> dict:
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--appledb", required=True, type=Path)
    args = ap.parse_args()
    db: Path = args.appledb

    # 1. Releases: every shipped iOS / iPadOS build from 15.0 up (betas excluded; 16.7 RC kept).
    releases: dict[str, set[str]] = {}       # version label -> identifiers
    builds: dict[str, set[str]] = {}         # version label -> builds
    for os_dir in ("iOS", "iPadOS"):
        for f in glob.glob(str(db / "osFiles" / os_dir / "*" / "*.json")):
            d = load(f)
            ver, build = str(d.get("version", "")), str(d.get("build", ""))
            if d.get("beta") or d.get("internal") or re.search(r"beta", ver, re.I):
                continue   # betas and Apple-internal builds (e.g. 17.5.2 21F101) never shipped to the public
            if d.get("rc") or " RC" in ver:
                if build not in KEEP_RC_BUILDS:
                    continue
                ver = ver.replace(" RC", "") + " RC"
            m = re.match(r"^(\d+)\.(\d+)(?:\.(\d+))?( RC)?$", ver)
            if not m or not (MIN_MAJOR <= int(m.group(1)) <= MAX_MAJOR):
                continue
            ids = {x for x in d.get("deviceMap", []) if x.startswith(("iPhone", "iPad"))}
            if not ids:
                continue
            releases.setdefault(ver, set()).update(ids)
            builds.setdefault(ver, set()).add(build)

    shipped_ids = set().union(*releases.values())

    # 2. Devices that received at least one of those releases, grouped by marketing name.
    groups: dict[str, dict] = {}
    for f in sorted(glob.glob(str(db / "deviceFiles" / "iPhone" / "*.json")) +
                    glob.glob(str(db / "deviceFiles" / "iPad" / "*.json"))):
        d = load(f)
        ident = d.get("identifier")
        idents = ident if isinstance(ident, list) else [ident]
        idents = [i for i in idents if i in shipped_ids]
        if not idents:
            continue
        name = norm_name(d["name"])
        models = d.get("model", [])
        models = models if isinstance(models, list) else [models]
        g = groups.setdefault(name, {"name": name, "type": d.get("type", ""), "soc": d.get("soc"),
                                     "arch": d.get("arch"), "ids": [], "models": [], "released": d.get("released")})
        if g["soc"] != d.get("soc") or g["arch"] != d.get("arch"):
            raise SystemExit(f"variants of {name!r} disagree on chip: {g['soc']} vs {d.get('soc')}")
        g["ids"] += [i for i in idents if i not in g["ids"]]
        g["models"] += [m for m in models if m and m not in g["models"]]
        rel = d.get("released")
        if isinstance(rel, list):
            rel = rel[0]
        if rel and (not g["released"] or str(rel) < str(g["released"])):
            g["released"] = rel

    versions = sorted(releases, key=vkey)
    vindex = {v: i for i, v in enumerate(versions)}
    devices = []
    for g in groups.values():
        idset = set(g["ids"])
        got = [vindex[v] for v in versions if releases[v] & idset]
        family = "iPhone" if g["ids"][0].startswith("iPhone") else "iPad"
        devices.append({
            "key": re.sub(r"[^a-z0-9]+", "-", g["name"].lower()).strip("-"),
            "name": g["name"], "family": family, "soc": g["soc"], "arch": g["arch"],
            "ids": sorted(g["ids"]), "models": sorted(g["models"]),
            "released": str(g["released"] or ""), "versions": got,
        })
    devices.sort(key=lambda x: (x["family"], x["released"], x["name"]))

    # 3. AppleDB's own Dopamine entry (used only as a cross-check in tests).
    dop = load(str(db / "jailbreakFiles" / "dopamine.json"))
    cross = {
        "latestVer": dop.get("info", {}).get("latestVer"),
        "notes": dop.get("info", {}).get("notes"),
        "groups": [{"devices": c.get("devices", []), "builds": c.get("firmwares", [])}
                   for c in dop.get("compatibility", [])],
    }

    out = {
        "schema": 1,
        "source": {"name": "AppleDB", "url": "https://github.com/littlebyteorg/appledb", **git_head(db)},
        "note": "Hardware and release facts only. Dopamine's supported ranges live in compat.js.",
        "versions": versions,
        "builds": {v: sorted(builds[v]) for v in versions},
        "devices": devices,
        "appledbDopamine": cross,
    }
    data_dir = ROOT / "academy" / "data"
    data_dir.mkdir(parents=True, exist_ok=True)
    (data_dir / "compat-data.json").write_text(json.dumps(out, indent=1) + "\n", encoding="utf-8")
    slim = {k: v for k, v in out.items() if k != "appledbDopamine"}
    js = ("/* Generated by tools/build_compat_data.py from AppleDB " + out["source"]["commit"][:12] + " ("
          + out["source"]["date"] + "). Do not edit by hand. */\n"
          "window.HCG_COMPAT_DATA = " + json.dumps(slim, separators=(",", ":")) + ";\n")
    (ROOT / "academy" / "assets" / "compat-data.js").write_text(js, encoding="utf-8")
    print(f"{len(devices)} device models, {len(versions)} releases ({versions[0]} .. {versions[-1]}), "
          f"AppleDB {out['source']['commit'][:12]} {out['source']['date']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
