#!/usr/bin/env python3
"""The README's banner (docs/images/banner.png, 1600x480): a glowing blade slash and the title, in Crema's layout.

Original art, drawn here: no game artwork or logo.

    python3 scripts/make-banner.py
"""
import math
import os
import random

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
W, H = 1600, 480
TEXT = (0xEE, 0xF2, 0xF6)
MUTED = (0x8F, 0xA3, 0xB4)


def font(names, size):
    for name in names:
        for d in ("C:/Windows/Fonts", "/mnt/c/Windows/Fonts", "/usr/share/fonts/truetype/dejavu"):
            path = os.path.join(d, name)
            if os.path.exists(path):
                return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def background():
    """Near black, a cold light behind the blade and a warm one low on the right"""
    img = Image.new("RGBA", (W, H), (0x07, 0x0A, 0x0E, 255))
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(glow)
    d.ellipse((60, -120, 820, 600), fill=(0x10, 0x2E, 0x44, 255))
    d.ellipse((1050, 300, 1750, 760), fill=(0x3A, 0x10, 0x10, 200))
    img = Image.alpha_composite(img, glow.filter(ImageFilter.GaussianBlur(170)))
    # Faint diagonal lines, as brushed steel
    lines = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ld = ImageDraw.Draw(lines)
    for x in range(-H, W, 22):
        ld.line([(x, H), (x + H, 0)], fill=(0x9F, 0xC8, 0xE8, 9), width=1)
    return Image.alpha_composite(img, lines)


def blade():
    """A long tapered blade on a slant, white-hot with a cyan glow and a red edge, drawn 2x for smooth edges"""
    K = 2
    layer = Image.new("RGBA", (W * K, H * K), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    angle = math.radians(-27)
    ux, uy = math.cos(angle), math.sin(angle)  # along the blade
    nx, ny = -uy, ux                           # across it
    x0, y0 = 110 * K, 418 * K                  # the hilt end
    length = 480 * K                           # the point stops short of the title

    def at(t, s):
        return (x0 + ux * length * t + nx * s, y0 + uy * length * t + ny * s)

    # The blade: wide at the guard, a curved back, the point at the far end
    spine = [at(t / 40, (14 - 9 * (t / 40) ** 2) * K) for t in range(41)]
    edge = [at(t / 40, -(10 - 10 * (t / 40) ** 3) * K) for t in range(40, -1, -1)]
    d.polygon(spine + edge, fill=(0xF4, 0xFB, 0xFF, 255))
    # The red edge line of a heated blade
    d.line(edge, fill=(0xFF, 0x3B, 0x3B, 255), width=3 * K)
    # The guard and the grip behind it
    g = [at(0, 30 * K), at(0.012, 30 * K), at(0.012, -26 * K), at(0, -26 * K)]
    d.polygon(g, fill=(0xB9, 0xC6, 0xD2, 255))
    grip = [at(-0.17, 8 * K), at(0, 9 * K), at(0, -8 * K), at(-0.17, -7 * K)]
    d.polygon(grip, fill=(0x2A, 0x33, 0x3D, 255))
    for i in range(1, 6):  # the grip's wrapping
        t = -0.17 * i / 6
        d.line([at(t, 9 * K), at(t - 0.012, -8 * K)], fill=(0x55, 0x66, 0x77, 255), width=2 * K)
    layer = layer.resize((W, H), Image.LANCZOS)

    glow = layer.filter(ImageFilter.GaussianBlur(26))
    tint = Image.new("RGBA", (W, H), (0x3C, 0xC8, 0xFF, 0))
    tint.putalpha(glow.getchannel("A").point(lambda a: a * 0.9))
    out = Image.alpha_composite(Image.new("RGBA", (W, H), (0, 0, 0, 0)), tint)

    # The slash: a thin streak of light past the point
    streak = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sd = ImageDraw.Draw(streak)
    p0 = (x0 / K + ux * 470, y0 / K + uy * 470)
    p1 = (x0 / K + ux * 545, y0 / K + uy * 545)
    sd.line([p0, p1], fill=(0xC8, 0xF0, 0xFF, 160), width=4)
    out = Image.alpha_composite(out, streak.filter(ImageFilter.GaussianBlur(3)))
    out = Image.alpha_composite(out, layer)

    # Sparks thrown off the edge
    sparks = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    spd = ImageDraw.Draw(sparks)
    rnd = random.Random(1347)
    for _ in range(70):
        t = rnd.uniform(0.3, 1.05)
        px, py = x0 / K + ux * 480 * t, y0 / K + uy * 480 * t
        a = angle + math.pi / 2 + rnd.uniform(-0.9, 0.9)
        r = rnd.uniform(8, 46)
        qx, qy = px + math.cos(a) * r, py + math.sin(a) * r
        c = rnd.choice([(0xFF, 0xD2, 0x7A), (0xFF, 0x8A, 0x4A), (0xD8, 0xF4, 0xFF)])
        spd.line([(px + (qx - px) * 0.6, py + (qy - py) * 0.6), (qx, qy)], fill=c + (230,), width=2)
    out = Image.alpha_composite(out, sparks.filter(ImageFilter.GaussianBlur(0.6)))
    return out


def gradient_text(img, x_right, y, text, f, left, right):
    """Right-aligned text filled with a left-to-right gradient, like Crema's title"""
    d = ImageDraw.Draw(img)
    bbox = d.textbbox((0, 0), text, font=f)
    tw = bbox[2] - bbox[0]
    x = x_right - tw
    mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(mask).text((x - bbox[0], y - bbox[1]), text, font=f, fill=255)
    grad = Image.new("RGBA", (W, H))
    gd = ImageDraw.Draw(grad)
    for i in range(tw + 1):
        t = i / max(tw, 1)
        c = tuple(round(left[k] + (right[k] - left[k]) * t) for k in range(3)) + (255,)
        gd.line([(x + i, 0), (x + i, H)], fill=c)
    grad.putalpha(ImageChops.multiply(mask, Image.new("L", (W, H), 255)))
    img.alpha_composite(grad)


def right_text(img, x_right, y, text, f, fill):
    d = ImageDraw.Draw(img)
    d.text((x_right - d.textlength(text, font=f), y), text, font=f, fill=fill)


def main():
    img = background()
    img.alpha_composite(blade())
    bold = font(("segoeuib.ttf", "DejaVuSans-Bold.ttf"), 112)
    light = font(("segoeuil.ttf", "segoeui.ttf", "DejaVuSans.ttf"), 58)
    small = font(("segoeuil.ttf", "segoeui.ttf", "DejaVuSans.ttf"), 34)
    gradient_text(img, 1530, 120, "Metal Gear Rising", bold, (0xE6, 0xF4, 0xFF), (0xFF, 0x4A, 0x45))
    right_text(img, 1530, 262, "REVENGEANCE", light, TEXT)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((1530 - 330, 350, 1530, 354), radius=2, fill=(0xFF, 0x4A, 0x45, 220))
    right_text(img, 1530, 372, "XBOX 360 RECOMP  ·  PS4", small, MUTED)
    out = os.path.join(ROOT, "docs", "images")
    os.makedirs(out, exist_ok=True)
    img.convert("RGB").save(os.path.join(out, "banner.png"))
    print("wrote docs/images/banner.png")


if __name__ == "__main__":
    main()
