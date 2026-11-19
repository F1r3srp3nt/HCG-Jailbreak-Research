#!/usr/bin/env python3
"""Draws the PROVISIONAL HCG Halo icon (no official artwork exists yet).

    python3 scripts/make_icon.py

Original artwork: the Halo border itself (a rounded phone-screen outline with
a notch) lit by a cyan -> violet -> magenta neon gradient with glow, on the
dark HCG background. Replace with official artwork when HCG provides it; the
listing and docs label this icon as provisional.

Writes (deterministic; requires Pillow):
  distribution/icon-512.png                                      source, 512 px
  distribution/hcg-repo/packages/com.hakmicapitalgroup.halo/icon.png   180 px (HCG Repo listing)
  preferences/Resources/icon.png, icon@2x.png, icon@3x.png             29 / 58 / 87 px (Settings)
"""
import math
import os

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
S = 2048  # supersampled canvas

STOPS = [(0.00, (0x00, 0xE5, 0xFF)), (0.33, (0x7B, 0x61, 0xFF)), (0.66, (0xC0, 0x26, 0xFF)), (1.00, (0x00, 0xE5, 0xFF))]


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def palette(t):
    t %= 1.0
    for (t0, c0), (t1, c1) in zip(STOPS, STOPS[1:]):
        if t0 <= t <= t1:
            return lerp(c0, c1, (t - t0) / (t1 - t0))
    return STOPS[-1][1]


def conic(size, rotation=-0.25):
    """Conic gradient image (angle 0 at the top, clockwise)."""
    small = 256
    img = Image.new("RGB", (small, small))
    px = img.load()
    c = (small - 1) / 2
    for y in range(small):
        for x in range(small):
            a = math.atan2(y - c, x - c) / (2 * math.pi) - rotation
            px[x, y] = palette(a)
    return img.resize((size, size), Image.BILINEAR)


def ring_mask(width):
    """The Halo border: phone outline (414 x 896 proportions) with a notch."""
    m = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(m)
    h = S * 0.74
    w = h * 414 / 896
    x0, y0 = (S - w) / 2, (S - h) / 2
    x1, y1 = x0 + w, y0 + h
    r = w * 39 / 414
    d.rounded_rectangle([x0, y0, x1, y1], radius=r, outline=255, width=width)
    # Notch: cut the top edge, then draw the U-shaped dip.
    nw, nh = w * 209 / 414, h * 30 / 896 * 1.35
    nx0, nx1 = S / 2 - nw / 2, S / 2 + nw / 2
    d.rectangle([nx0 + width, y0 - 2, nx1 - width, y0 + width + 2], fill=0)
    u = Image.new("L", (S, S), 0)
    ud = ImageDraw.Draw(u)
    ud.rounded_rectangle([nx0, y0 - nh, nx1, y0 + nh], radius=nh * 0.75, outline=255, width=width)
    ud.rectangle([0, 0, S, y0 - 1], fill=0)
    return ImageChops.lighter(m, u)


def make():
    bg = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    # Background: deep navy with a violet bloom, rounded like an app icon.
    base = Image.new("RGB", (S, S), (5, 7, 15))
    bloom = Image.new("L", (S, S), 0)
    ImageDraw.Draw(bloom).ellipse([S * 0.18, S * 0.12, S * 0.82, S * 0.88], fill=110)
    bloom = bloom.filter(ImageFilter.GaussianBlur(S * 0.12))
    base = Image.composite(Image.new("RGB", (S, S), (34, 18, 84)), base, bloom)
    shape = Image.new("L", (S, S), 0)
    ImageDraw.Draw(shape).rounded_rectangle([0, 0, S - 1, S - 1], radius=int(S * 0.2237), fill=255)
    bg.paste(base, (0, 0), shape)

    colours = conic(S)
    stroke = int(S * 0.038)
    core = ring_mask(stroke)
    for blur, strength in ((S * 0.06, 0.55), (S * 0.025, 0.8), (S * 0.008, 1.0)):
        glow = core.filter(ImageFilter.GaussianBlur(blur)).point(lambda v, k=strength: min(255, int(v * k * 2.2)))
        bg = Image.composite(Image.alpha_composite(bg, Image.merge("RGBA", (*colours.split(), glow))), bg, shape)
    bg = Image.alpha_composite(bg, Image.merge("RGBA", (*colours.split(), core)))
    hot = ring_mask(max(2, int(stroke * 0.35))).filter(ImageFilter.GaussianBlur(S * 0.002))
    white = Image.new("RGBA", (S, S), (255, 255, 255, 0))
    white.putalpha(hot.point(lambda v: int(v * 0.75)))
    bg = Image.alpha_composite(bg, white)
    out = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    out.paste(bg, (0, 0), shape)
    return out


def save(img, rel, size):
    path = os.path.join(ROOT, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.resize((size, size), Image.LANCZOS).save(path, optimize=True)
    print(f"wrote {rel} ({size} px)")


def main():
    img = make()
    save(img, "distribution/icon-512.png", 512)
    save(img, "distribution/hcg-repo/packages/com.hakmicapitalgroup.halo/icon.png", 180)
    save(img, "preferences/Resources/icon.png", 29)
    save(img, "preferences/Resources/icon@2x.png", 58)
    save(img, "preferences/Resources/icon@3x.png", 87)


if __name__ == "__main__":
    main()
