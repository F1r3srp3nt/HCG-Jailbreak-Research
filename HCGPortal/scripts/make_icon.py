#!/usr/bin/env python3
"""Draws the PROVISIONAL HCG Portal icon (no official artwork exists yet).

    python3 scripts/make_icon.py

Original artwork: a dark translucent portal core with a cyan-to-violet energy
ring, a dashed inner ring and a soft glow, on the dark HCG background (the same
look as the portal itself). Replace with official artwork when HCG provides it;
the listing and docs label this icon as provisional.

Writes (deterministic; requires Pillow):
  distribution/icon-512.png                                          source, 512 px
  distribution/hcg-repo/packages/com.hakmicapitalgroup.portal/icon.png  180 px (HCG Repo listing)
  preferences/Resources/icon.png, icon@2x.png, icon@3x.png            29 / 58 / 87 px (Settings)
"""
import math
import os

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
S = 2048  # supersampled canvas
BG = (0x05, 0x07, 0x0F)
CYAN = (0x33, 0xE6, 0xFF)
VIOLET = (0x94, 0x5C, 0xFF)


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def ring(draw, cx, cy, r, width, segments, colour_at, dash=None):
    for i in range(segments):
        if dash and (i % dash[0]) >= dash[1]:
            continue
        a0 = 2 * math.pi * i / segments - math.pi / 2
        a1 = 2 * math.pi * (i + 1.15) / segments - math.pi / 2
        p0 = (cx + r * math.cos(a0), cy + r * math.sin(a0))
        p1 = (cx + r * math.cos(a1), cy + r * math.sin(a1))
        draw.line([p0, p1], fill=colour_at(i / segments), width=width)


def draw():
    img = Image.new("RGB", (S, S), BG)
    cx = cy = S // 2
    # Glow.
    glow = Image.new("RGB", (S, S), (0, 0, 0))
    gd = ImageDraw.Draw(glow)
    for k in range(40, 0, -1):
        r = S * 0.30 + k * S * 0.006
        c = lerp(BG, lerp(CYAN, VIOLET, 0.5), (40 - k) / 40 * 0.55)
        gd.ellipse((cx - r, cy - r, cx + r, cy + r), fill=c)
    glow = glow.filter(ImageFilter.GaussianBlur(S * 0.03))
    img = Image.blend(img, glow, 0.9)
    d = ImageDraw.Draw(img)
    # Dark core.
    core = S * 0.27
    for k in range(60):
        t = k / 59
        r = core * (1 - t)
        d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=lerp((0x14, 0x1E, 0x46), (0x02, 0x04, 0x0C), t))

    def conic(t):
        # cyan -> violet -> faint -> violet -> cyan around the ring
        if t < 0.25:
            return lerp(CYAN, VIOLET, t / 0.25)
        if t < 0.5:
            return lerp(VIOLET, (0x20, 0x3A, 0x50), (t - 0.25) / 0.25)
        if t < 0.75:
            return lerp((0x20, 0x3A, 0x50), VIOLET, (t - 0.5) / 0.25)
        return lerp(VIOLET, CYAN, (t - 0.75) / 0.25)

    ring(d, cx, cy, S * 0.36, int(S * 0.030), 720, conic)
    ring(d, cx, cy, S * 0.315, int(S * 0.012), 360, lambda t: VIOLET, dash=(40, 27))
    ring(d, cx, cy, S * 0.285, int(S * 0.008), 360, lambda t: CYAN if t < 0.72 else BG)
    # Glass highlight.
    r = core - S * 0.01
    d.arc((cx - r, cy - r, cx + r, cy + r), start=200, end=260, fill=(0xC8, 0xD8, 0xFF), width=int(S * 0.010))
    return img


def main():
    img = draw()
    targets = [
        ("distribution/icon-512.png", 512),
        ("distribution/hcg-repo/packages/com.hakmicapitalgroup.portal/icon.png", 180),
        ("preferences/Resources/icon.png", 29),
        ("preferences/Resources/icon@2x.png", 58),
        ("preferences/Resources/icon@3x.png", 87),
    ]
    for rel, size in targets:
        path = os.path.join(ROOT, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        img.resize((size, size), Image.LANCZOS).save(path, optimize=True)
        print("wrote", rel, size)


if __name__ == "__main__":
    main()
