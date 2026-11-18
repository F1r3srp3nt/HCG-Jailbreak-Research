#!/usr/bin/env python3
"""Render the REAL per-icon effect geometry (tests/build/effect_frames JSON) to images.

    make -C tests effect-frames
    tests/build/effect_frames tornado 61 > /tmp/frames.json
    python3 -I scripts/render_effect_preview.py /tmp/frames.json OUTDIR

Writes OUTDIR/<effect>-sheet.png (frames at several progress values) and
OUTDIR/<effect>-swipe.gif (a swipe forwards, a pause, a reversal back, then a
completed swipe).

Each square is an icon at the position, scale, rotation, 3-D tilt (drawn as a
foreshortening), depth order and opacity that vortex_icon_effect_visual()
returned; Circuit Flow traces are vortex_icon_effect_trace(). Pages are drawn in page order
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


def icon_tile(color, label, size, rotation, alpha, sx=1.0, sy=1.0):
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
    if sx < 0.999 or sy < 0.999:
        tile = tile.resize((max(int(s * sx), 2), max(int(s * sy), 2)), resample=Image.BICUBIC)
    if rotation:
        tile = tile.rotate(-math.degrees(rotation), resample=Image.BICUBIC, expand=True)
    if alpha < 1.0:
        a = tile.getchannel("A").point(lambda v: int(v * alpha))
        tile.putalpha(a)
    return tile


TRACE = (0, 229, 255)


def render(frame, page, scale=SCALE):
    w, h = int(page[0] * scale), int(page[1] * scale)
    img = background(w, h).convert("RGBA")
    for pg in (0, 1):
        pv = frame["pages"][pg]
        page_alpha = pv["o"]
        ox, oy = pv["dx"] * page[0], pv["dy"] * page[1]
        icons = [ic for ic in frame["icons"] if ic["page"] == pg]
        # Circuit Flow traces: behind the icons of their page.
        glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        gd = ImageDraw.Draw(glow)
        for ic in icons:
            pts = ic["trace"]["pts"]
            if len(pts) < 2:
                continue
            a = ic["trace"]["a"] * page_alpha
            xy = [((page[0] / 2 + ox + x) * scale, (page[1] / 2 + oy + y) * scale) for x, y in pts]
            gd.line(xy, fill=TRACE + (int(90 * a),), width=max(int(7 * scale), 2), joint="curve")
            gd.line(xy, fill=(200, 250, 255, int(235 * a)), width=max(int(2 * scale), 1))
        img.alpha_composite(glow)
        for ic in sorted(icons, key=lambda ic: ic["z"]):
            alpha = max(0.0, min(1.0, ic["o"] * page_alpha))
            if alpha <= 0.003:
                continue
            palette = OUT_PALETTE if pg == 0 else IN_PALETTE
            label = ("ABCDEFGHIJKLMNOPQRSTUVWX" if pg == 0 else "abcdefghijklmnopqrstuvwx")[ic["i"]]
            tile = icon_tile(palette[ic["i"] % len(palette)], label, ICON * ic["s"] * scale, ic["r"], alpha,
                             abs(math.cos(ic["ty"])), abs(math.cos(ic["tx"])))
            cx = (page[0] / 2 + ox + ic["x"]) * scale
            cy = (page[1] / 2 + oy + ic["y"]) * scale
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
    name = data["effect"]
    d.text((pad, 10), f"HCG Vortex {name}: real vortex_icon_effect_visual() geometry, default settings, finger "
           "swipes left. Mock icons. Geometry preview, not a device capture.", fill=(20, 20, 20), font=small)
    for k, (f, t) in enumerate(zip(picks, tiles)):
        x = pad + k * (tw + pad)
        sheet.paste(t.convert("RGB"), (x, top))
        d.text((x + tw / 2, top + th + 16), f"progress {f['p']:.2f}", fill=(20, 20, 20), font=font, anchor="mm")
    sheet.save(os.path.join(out, f"{name}-sheet.png"))

    # Swipe forward, hold mid-swipe, then reverse (cancel) back to the start.
    mid = len(frames) // 2
    order = list(range(0, mid + 1)) + [mid] * 10 + list(range(mid, -1, -1)) + [0] * 6 + list(range(0, len(frames))) + [len(frames) - 1] * 8
    gif_frames = [render(frames[i], page, 0.45).convert("P", palette=Image.ADAPTIVE) for i in order]
    gif_frames[0].save(os.path.join(out, f"{name}-swipe.gif"), save_all=True, append_images=gif_frames[1:],
                       duration=40, loop=0, optimize=True)
    print("wrote", os.path.join(out, f"{name}-sheet.png"), "and", os.path.join(out, f"{name}-swipe.gif"))


if __name__ == "__main__":
    main()
