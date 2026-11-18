#!/usr/bin/env python3
"""Draws the PROVISIONAL HCG Animation Center icon (no official artwork exists yet).

    python3 scripts/make_icon.py

Original artwork: a phone-screen outline filled with flowing violet / cyan
waves (an animated background) and a small play mark, on the dark HCG
background. Replace with official artwork when HCG provides it; the listing
and docs label this icon as provisional.

Writes (deterministic; requires Pillow):
  distribution/icon-512.png                                                   source, 512 px
  distribution/hcg-repo/packages/com.hakmicapitalgroup.animationcenter/icon.png  180 px (HCG Repo listing)
  preferences/Resources/icon.png, icon@2x.png, icon@3x.png                     29 / 58 / 87 px (Settings)
"""
import math
import os

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
S = 2048  # supersampled canvas
BG = (0x0B, 0x0B, 0x14)
VIOLET = (0x87, 0x6B, 0xFF)
CYAN = (0x00, 0xE5, 0xFF)
MAGENTA = (0xC0, 0x26, 0xFF)


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def draw():
    img = Image.new("RGB", (S, S), BG)
    # Phone screen.
    pw, ph = int(S * 0.46), int(S * 0.80)
    px, py = (S - pw) // 2, (S - ph) // 2
    radius = int(pw * 0.17)
    screen = Image.new("RGB", (pw, ph), (0, 0, 0))
    sd = ImageDraw.Draw(screen)
    # Flowing waves: bands of colour, each a sine curve.
    bands = 7
    for b in range(bands):
        t = b / (bands - 1)
        colour = lerp(lerp(MAGENTA, VIOLET, min(1, t * 2)), CYAN, max(0, t * 2 - 1))
        pts = []
        base = ph * (0.18 + 0.12 * b)
        for x in range(0, pw + 1, 8):
            y = base + math.sin(x / pw * math.pi * 2 + b * 0.7) * ph * 0.045
            pts.append((x, y))
        poly = pts + [(pw, ph), (0, ph)]
        sd.polygon(poly, fill=lerp(colour, (0, 0, 0), 0.15 + 0.08 * b))
    screen = screen.filter(ImageFilter.GaussianBlur(6))
    mask = Image.new("L", (pw, ph), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, pw - 1, ph - 1), radius=radius, fill=255)
    img.paste(screen, (px, py), mask)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((px, py, px + pw, py + ph), radius=radius, outline=(0xE8, 0xE6, 0xFF), width=int(S * 0.018))
    # Play mark.
    cx, cy, r = S // 2, int(S * 0.56), int(S * 0.085)
    d.polygon([(cx - r * 0.6, cy - r), (cx - r * 0.6, cy + r), (cx + r, cy)], fill=(255, 255, 255))
    return img


def main():
    img = draw()
    targets = [
        ("distribution/icon-512.png", 512),
        ("distribution/hcg-repo/packages/com.hakmicapitalgroup.animationcenter/icon.png", 180),
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
