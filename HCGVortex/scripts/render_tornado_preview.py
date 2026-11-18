#!/usr/bin/env python3
"""Render the REAL Tornado geometry (tests/build/tornado_frames JSON) to images.

    make -C tests tornado-frames
    tests/build/tornado_frames 61 > /tmp/frames.json
    python3 -I scripts/render_tornado_preview.py /tmp/frames.json OUTDIR

Writes OUTDIR/tornado-sheet.png (frames at several progress values) and
OUTDIR/tornado-swipe.gif (a swipe forwards, a pause, then a reversal back).

Each square is an icon at the position, scale, rotation, depth order and
opacity that vortex_tornado_icon() returned. Pages are drawn in page order
(outgoing below incoming) and icons are depth-sorted within each page, which
is how SpringBoard composites sibling icon list views. This shows the
geometry only; it is NOT a capture of SpringBoard on a device.
"""
import json
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFont

SCALE = 0.6
OUT_PALETTE = [(64, 156, 255), (52, 199, 89), (90, 200, 250), (88, 86, 214), (48, 176, 199), (0, 122, 255)]
IN_PALETTE = [(255, 149, 0), (255, 59, 48), (255, 204, 0), (255, 45, 85), (242, 130, 60), (230, 90, 140)]
ICON = 60.0  # pt


def background(w, h):
    img = Image.new("RGB", (w, h))
    px = img.load()
    for y in range(h):
        t = y / max(h - 1, 1)
        c = (int(18 + 20 * t), int(22 + 10 * t), int(40 + 30 * t))
        for x in range(w):
            px[x, y] = c
    return img


def icon_tile(color, label, size, rotation, alpha):
    s = max(int(size), 4)
    tile = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(tile)
    d.rounded_rectangle([0, 0, s - 1, s - 1], radius=s * 0.23, fill=color + (255,))
    d.rounded_rectangle([s * 0.12, s * 0.10, s * 0.88, s * 0.42], radius=s * 0.12, fill=(255, 255, 255, 60))
    try:
        font = ImageFont.load_default(size=max(int(s * 0.42), 8))
    except TypeError:
        font = ImageFont.load_default()
    d.text((s / 2, s / 2 + s * 0.05), label, fill=(255, 255, 255, 235), font=font, anchor="mm")
    if rotation:
        tile = tile.rotate(-math.degrees(rotation), resample=Image.BICUBIC, expand=True)
    if alpha < 1.0:
        a = tile.getchannel("A").point(lambda v: int(v * alpha))
        tile.putalpha(a)
    return tile


def render(frame, page, scale=SCALE):
    w, h = int(page[0] * scale), int(page[1] * scale)
    img = background(w, h).convert("RGBA")
    for pg in (0, 1):
        page_alpha = frame["pageOpacity"][pg]
        icons = sorted((ic for ic in frame["icons"] if ic["page"] == pg), key=lambda ic: ic["z"])
        for ic in icons:
            alpha = max(0.0, min(1.0, ic["o"] * page_alpha))
            if alpha <= 0.003:
                continue
            palette = OUT_PALETTE if pg == 0 else IN_PALETTE
            label = ("ABCDEFGHIJKLMNOPQRSTUVWX" if pg == 0 else "abcdefghijklmnopqrstuvwx")[ic["i"]]
            tile = icon_tile(palette[ic["i"] % len(palette)], label, ICON * ic["s"] * scale, ic["r"], alpha)
            cx = (page[0] / 2 + ic["x"]) * scale
            cy = (page[1] / 2 + ic["y"]) * scale
            img.alpha_composite(tile, (int(round(cx - tile.width / 2)), int(round(cy - tile.height / 2))))
    return img


def main():
    data = json.load(open(sys.argv[1]))
    out = sys.argv[2]
    os.makedirs(out, exist_ok=True)
    page, frames = data["page"], data["frames"]

    wanted = [0.0, 0.2, 0.35, 0.5, 0.65, 0.8, 1.0]
    picks = [min(frames, key=lambda f: abs(f["p"] - p)) for p in wanted]
    tiles = [render(f, page) for f in picks]
    pad, top = 12, 46
    tw, th = tiles[0].size
    sheet = Image.new("RGB", (pad + len(tiles) * (tw + pad), th + top + pad + 30), (245, 245, 247))
    d = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.load_default(size=16)
        small = ImageFont.load_default(size=13)
    except TypeError:
        font = small = ImageFont.load_default()
    pr = data["params"]
    d.text((pad, 10), "HCG Vortex Tornado: real vortex_tornado_icon() geometry, finger swipes left "
           f"(intensity {pr['intensity']}, radius {pr['radius']}, turns {pr['rotations']}, "
           f"depth {'on' if pr['depth'] else 'off'}, icon spin {'on' if pr['iconSpin'] else 'off'}). "
           "Geometry preview, not a device capture.", fill=(20, 20, 20), font=small)
    for k, (f, t) in enumerate(zip(picks, tiles)):
        x = pad + k * (tw + pad)
        sheet.paste(t.convert("RGB"), (x, top))
        d.text((x + tw / 2, top + th + 16), f"progress {f['p']:.2f}", fill=(20, 20, 20), font=font, anchor="mm")
    sheet.save(os.path.join(out, "tornado-sheet.png"))

    # Swipe forward, hold mid-swipe, then reverse (cancel) back to the start.
    seq = frames + [frames[len(frames) // 2]] * 0
    mid = len(frames) // 2
    order = list(range(0, mid + 1)) + [mid] * 10 + list(range(mid, -1, -1)) + [0] * 6 + list(range(0, len(frames))) + [len(frames) - 1] * 8
    gif_frames = [render(frames[i], page, 0.45).convert("P", palette=Image.ADAPTIVE) for i in order]
    gif_frames[0].save(os.path.join(out, "tornado-swipe.gif"), save_all=True, append_images=gif_frames[1:],
                       duration=40, loop=0, optimize=True)
    print("wrote", os.path.join(out, "tornado-sheet.png"), "and", os.path.join(out, "tornado-swipe.gif"))


if __name__ == "__main__":
    main()
