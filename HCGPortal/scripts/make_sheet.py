#!/usr/bin/env python3
"""Makes a labelled contact sheet from preview screenshots.

    python3 scripts/make_sheet.py <shots-dir> <out.jpg>

Screenshots are taken by scripts/preview.sh at each PORTAL-PREVIEW-SHOT marker and
named <order>-<state>.png. Requires Pillow. Preview evidence, not a device result.
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont


def main(folder, out):
    names = sorted(f for f in os.listdir(folder) if f.endswith(".png"))
    if not names:
        sys.exit("no screenshots")
    thumbs = []
    for name in names:
        im = Image.open(os.path.join(folder, name)).convert("RGB")
        w = 300
        im = im.resize((w, int(im.height * w / im.width)), Image.LANCZOS)
        thumbs.append((name[:-4], im))
    cols = min(5, len(thumbs))
    rows = (len(thumbs) + cols - 1) // cols
    tw, th = thumbs[0][1].size
    pad, label = 14, 34
    sheet = Image.new("RGB", (cols * (tw + pad) + pad, rows * (th + label + pad) + pad + 40), (18, 18, 24))
    draw = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 15)
        title = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 18)
    except OSError:
        font = title = ImageFont.load_default()
    draw.text((pad, 12), "HCG Portal — PREVIEW (iOS Simulator, stand-in SpringBoard; not a device result)",
              fill=(255, 182, 72), font=title)
    for i, (name, im) in enumerate(thumbs):
        x = pad + (i % cols) * (tw + pad)
        y = 40 + pad + (i // cols) * (th + label + pad)
        sheet.paste(im, (x, y))
        draw.text((x, y + th + 6), name, fill=(230, 230, 240), font=font)
    sheet.save(out, quality=88)
    print("wrote", out, len(thumbs), "screenshots")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
