# Bonk Quest logo, style A "Bonk Burst" (the user's pick, 2026-10-17, canvas
# https://claude.ai/artifact/DWZCVc43EFz3tDedSAnJ9d): a white "BONK!" over an orange/yellow comic
# starburst, "QUEST" on a teal ribbon, cartoon clouds on sky blue, ink 2b1b3d outlines.
# Draws the Roblox game icon (512x512) and thumbnail (1920x1080) with PIL in Luckiest Guy (the font
# Roblox installs with Studio), supersampled 2x for smooth edges.
#   python bonk_logo.py <out_dir> [path to LuckiestGuy-Regular.ttf]
# Logo geometry is in the canvas artboard's units (900x560); `scale` maps it to pixels.
import glob, math, os, sys
from PIL import Image, ImageDraw, ImageFont

OUT = sys.argv[1]
FONT = sys.argv[2] if len(sys.argv) > 2 else sorted(glob.glob(os.path.expandvars(
    r"%LOCALAPPDATA%\Roblox\Versions\*\content\fonts\LuckiestGuy-Regular.ttf")))[-1]
SS = 2  # supersampling

INK = (43, 27, 61, 255)
SKY = (142, 216, 255, 255)
WHITE = (255, 255, 255, 255)
CREAM = (255, 244, 214, 255)
ORANGE = (255, 138, 43, 255)
YELLOW = (255, 201, 60, 255)
TEAL = (38, 181, 166, 255)
TEAL_DARK = (23, 138, 126, 255)
GRASS = (108, 194, 74, 255)
GRASS_DARK = (79, 154, 51, 255)

BURST_OUT = [(0, -205), (52, -120), (152, -160), (118, -68), (232, -52), (140, 6), (214, 96), (104, 92), (92, 190),
             (22, 118), (-46, 196), (-66, 98), (-184, 128), (-128, 36), (-234, -22), (-126, -64), (-168, -160), (-64, -122)]
BURST_IN = [(0, -150), (38, -90), (112, -118), (88, -50), (172, -38), (104, 4), (158, 70), (76, 68), (68, 140),
            (16, 86), (-34, 144), (-48, 72), (-136, 94), (-94, 26), (-172, -16), (-92, -48), (-124, -118), (-48, -90)]


def rot(pts, deg):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    return [(x * c - y * s, x * s + y * c) for x, y in pts]


def outlined_polygon(d, pts, fill, width):
    d.polygon(pts, fill=fill)
    d.line(pts + [pts[0]], fill=INK, width=max(1, int(width)), joint="curve")
    r = width / 2
    for x, y in pts:  # round the corners
        d.ellipse((x - r, y - r, x + r, y + r), fill=INK)


def cloud(d, cx, base, w, t):
    shapes = [("e", cx - 0.25 * w, base - 0.22 * w, 0.22 * w), ("e", cx, base - 0.32 * w, 0.3 * w),
              ("e", cx + 0.25 * w, base - 0.24 * w, 0.24 * w)]
    box = (cx - 0.46 * w, base - 0.26 * w, cx + 0.46 * w, base)
    for grow, col in ((t, INK), (0, WHITE)):
        for _, x, y, r in shapes:
            d.ellipse((x - r - grow, y - r - grow, x + r + grow, y + r + grow), fill=col)
        d.rounded_rectangle((box[0] - grow, box[1] - grow, box[2] + grow, box[3] + grow), radius=0.12 * w + grow, fill=col)


def spaced_text(size, text, font_px, spacing, fill, stroke, shadow):
    """RGBA image of `text` with letter spacing, an outer ink stroke and a hard ink drop shadow."""
    font = ImageFont.truetype(FONT, int(font_px))
    widths = [font.getlength(ch) for ch in text]
    total = sum(widths) + spacing * (len(text) - 1)
    pad = int(stroke * 2 + shadow + 10)
    asc, desc = font.getmetrics()
    img = Image.new("RGBA", (int(total + pad * 2), int(asc + desc + pad * 2)), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for dy, col in ((shadow, INK), (0, fill)):
        x = pad
        for ch, w in zip(text, widths):
            d.text((x, pad + dy), ch, font=font, fill=col, stroke_width=int(stroke), stroke_fill=INK)
            x += w + spacing
    return img.crop(img.getbbox())


def paste_center(base, img, cx, cy):
    base.alpha_composite(img, (int(cx - img.width / 2), int(cy - img.height / 2)))


def logo(base, cx, cy, k):
    """Draw the logo with its visual centre at (cx, cy); k = pixels per artboard unit."""
    d = ImageDraw.Draw(base)
    # starburst (artboard centre 450,225 -> here cx, cy - 55k)
    bx, by = cx, cy - 55 * k
    outer = [(bx + x * k, by + y * k) for x, y in rot(BURST_OUT, -8)]
    inner = [(bx + x * k, by + y * k) for x, y in rot(BURST_IN, -8)]
    outlined_polygon(d, outer, ORANGE, 10 * k)
    d.polygon(inner, fill=YELLOW)
    # BONK! (white, stroke 8 out, shadow 12, spacing 6, rotated 4 deg counter-clockwise)
    bonk = spaced_text(None, "BONK!", 188 * k, 6 * k, WHITE, 8 * k, 12 * k)
    bonk = bonk.rotate(4, resample=Image.BICUBIC, expand=True)
    paste_center(base, bonk, cx, cy - 92 * k)
    # QUEST ribbon (470x112 box centred 92k below the logo centre)
    rx, ry = cx - 235 * k, cy + 82 * k
    P = lambda pts: [(rx + x * k, ry + y * k) for x, y in pts]
    outlined_polygon(d, P([(0, 30), (60, 30), (60, 104), (0, 104), (26, 67)]), TEAL_DARK, 6 * k)
    outlined_polygon(d, P([(470, 30), (410, 30), (410, 104), (470, 104), (444, 67)]), TEAL_DARK, 6 * k)
    d.rounded_rectangle((rx + 44 * k, ry + 8 * k, rx + 426 * k, ry + 96 * k), radius=14 * k, fill=TEAL, outline=INK,
                        width=int(7 * k))
    quest = spaced_text(None, "QUEST", 76 * k, 8 * k, CREAM, 5 * k, 6 * k)
    paste_center(base, quest, cx, ry + 50 * k)


def icon(px=512):
    S = px * SS
    im = Image.new("RGBA", (S, S), SKY)
    d = ImageDraw.Draw(im)
    cloud(d, S * 0.16, S * 0.2, S * 0.26, S * 0.008)
    cloud(d, S * 0.86, S * 0.93, S * 0.28, S * 0.008)
    k = S * 0.92 / 560  # "BONK!" is about 560 artboard units wide: keep it inside the square
    logo(im, S / 2, S * 0.56, k)
    return im.resize((px, px), Image.LANCZOS)


def thumbnail(w=1920, h=1080):
    W, H = w * SS, h * SS
    im = Image.new("RGBA", (W, H), SKY)
    d = ImageDraw.Draw(im)
    t = H * 0.006
    for cx, base, cw in ((0.12, 0.30, 0.16), (0.87, 0.24, 0.17), (0.14, 0.64, 0.09), (0.86, 0.6, 0.1)):
        cloud(d, W * cx, H * base, W * cw, t)
    # rolling meadow hills along the bottom
    for x0, y0, x1, y1, col in ((-0.15, 0.80, 0.55, 1.35, GRASS_DARK), (0.40, 0.84, 1.20, 1.40, GRASS),
                                (-0.10, 0.88, 0.70, 1.45, GRASS)):
        box = (W * x0, H * y0, W * x1, H * y1)
        d.ellipse((box[0] - t * 1.4, box[1] - t * 1.4, box[2] + t * 1.4, box[3] + t * 1.4), fill=INK)
        d.ellipse(box, fill=col)
    k = H * 0.70 / 430  # whole logo (burst tip to ribbon) about 430 units tall
    logo(im, W / 2, H * 0.47, k)
    return im.resize((w, h), Image.LANCZOS)


os.makedirs(OUT, exist_ok=True)
icon().convert("RGB").save(os.path.join(OUT, "bonkquest_icon_512.png"))
thumbnail().convert("RGB").save(os.path.join(OUT, "bonkquest_thumbnail_1920x1080.png"))
print("font:", FONT)
print("wrote", os.listdir(OUT))
