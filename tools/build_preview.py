#!/usr/bin/env python3
"""Build a local publication preview: the real HCG Repo site with the Academy switched on.

Nothing is published. The script copies an HCG Repo checkout (one that already has the integration patch from
integration/hcg-repo/ applied) into a temporary folder, replaces its academy/ with this repository's academy/,
sets [academy] enabled = true in that COPY ONLY, and runs HCG Repo's own `hcgrepo build`. The original checkout and
its config are not modified.

  python3 tools/build_preview.py --hcg-repo /path/to/HCG-repo --out _preview
  python3 -m http.server -d _preview 8000      # then open http://127.0.0.1:8000/academy/jailbreak/

The built pages use the production base URL in canonical links only; all navigation is relative.
"""
from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--hcg-repo", required=True, type=Path, help="HCG Repo checkout with the integration patch applied")
    ap.add_argument("--out", default=ROOT / "_preview", type=Path)
    args = ap.parse_args()
    src = args.hcg_repo.resolve()
    if not (src / "tools" / "hcgrepo" / "site.py").is_file() or "copy_academy" not in (src / "tools" / "hcgrepo" / "site.py").read_text():
        print("error: --hcg-repo must be an HCG Repo checkout with integration/hcg-repo/*.patch applied", file=sys.stderr)
        return 2
    out = args.out.resolve()
    with tempfile.TemporaryDirectory(prefix="hcg-academy-preview-") as tmp:
        work = Path(tmp) / "hcg-repo"
        shutil.copytree(src, work, ignore=shutil.ignore_patterns("_site", "_preview", "__pycache__"))
        shutil.rmtree(work / "academy", ignore_errors=True)
        shutil.copytree(ROOT / "academy", work / "academy")
        cfgp = work / "config" / "repo.toml"
        text, n = re.subn(r"(?m)^(\[academy\][^\[]*?)^enabled = false$", r"\1enabled = true", cfgp.read_text())
        if n != 1:
            print("error: could not find '[academy] enabled = false' in the copy's config/repo.toml", file=sys.stderr)
            return 2
        cfgp.write_text(text)
        if out.exists():
            shutil.rmtree(out)
        subprocess.run([sys.executable, str(work / "bin" / "hcgrepo"), "build", "--target", "production", "--out", str(out)],
                       cwd=work, check=True)
    print(f"preview built in {out}\nserve it: python3 -m http.server -d {out} 8000  ->  http://127.0.0.1:8000/academy/jailbreak/")
    return 0


if __name__ == "__main__":
    sys.exit(main())
