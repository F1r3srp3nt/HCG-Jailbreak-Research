"""Builds the HCG Vortex beta header (1200x400) from existing HCG assets.

  - chrome "HCG" mark: top of HCG-repo's HCG Terminal header (the approved style)
  - spiral icon: HCGVortex/distribution/icon-512.png
Usage: python3 make_header.py <terminal-header.jpg> <icon-512.png> <out.jpg>
"""
import sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

term_header, icon_path, out = sys.argv[1:4]
W, H = 1200, 400
CYAN = (0, 229, 255)

base = Image.new("RGB", (W, H), (0, 0, 0))

# HCG chrome mark: rows above the "TERMINAL" wordmark, scaled to leave room.
src = Image.open(term_header).convert("RGB")
mark = src.crop((150, 0, 1050, 300))           # drop ">_TERMINAL"
mark = mark.resize((630, 210), Image.LANCZOS)
# The source background is near-black, not black: lift the black point so the
# crop edges disappear against the pure-black canvas.
mark = mark.point(lambda v: 0 if v < 24 else int((v - 24) * 255 / 231))
from PIL import ImageChops
layer = Image.new("RGB", (W, H), (0, 0, 0))
layer.paste(mark, (300, 18))
base = ImageChops.lighter(base, layer)   # lighten blend: no visible crop box

# Spiral icon on the left, with a soft cyan glow.
icon = Image.open(icon_path).convert("RGBA").resize((200, 200), Image.LANCZOS)
glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
ImageDraw.Draw(glow).ellipse((40, 90, 300, 350), fill=CYAN + (70,))
glow = glow.filter(ImageFilter.GaussianBlur(40))
base = Image.alpha_composite(base.convert("RGBA"), glow)
base.alpha_composite(icon, (70, 120))

d = ImageDraw.Draw(base)
bold = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
regular = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"


def spaced(text, font, x, y, spacing, fill):
    for ch in text:
        d.text((x, y), ch, font=font, fill=fill)
        x += d.textlength(ch, font=font) + spacing
    return x


# "VORTEX" in the Terminal header's spaced style.
word = ImageFont.truetype(regular, 40)
spaced("VORTEX", word, 420, 250, 30, (225, 232, 240))

# Prominent BETA badge.
badge_font = ImageFont.truetype(bold, 34)
bx, by = 900, 246
bw = d.textlength("BETA", font=badge_font) + 44
d.rounded_rectangle((bx, by, bx + bw, by + 56), radius=12, fill=CYAN)
d.text((bx + 22, by + 8), "BETA", font=badge_font, fill=(0, 0, 0))

# Tagline.
tag = ImageFont.truetype(regular, 20)
spaced("FREE EXPERIMENTAL BETA  ·  HOME SCREEN PAGE TRANSITIONS", tag, 300, 340, 3, (150, 165, 185))

base.convert("RGB").save(out, quality=90)
print("wrote", out)
