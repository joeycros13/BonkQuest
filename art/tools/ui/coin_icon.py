"""Cartoon gold coin icon for DiceBattles (transparent PNG).

Drawn at 4x and downsampled for clean anti-aliased edges. Style matches the
HUD icons: chunky warm-dark outline, flat cel shading, one glossy highlight.
"""
import math
import sys
from PIL import Image, ImageDraw, ImageFilter

OUT = sys.argv[1] if len(sys.argv) > 1 else "coin.png"
SIZE = 512
SS = 4  # supersampling
S = SIZE * SS
c = S / 2

OUTLINE = (74, 44, 14, 255)
SIDE = (196, 124, 18, 255)       # coin edge (thickness)
SIDE_DARK = (160, 96, 12, 255)   # reeding grooves on the edge
RIM = (250, 184, 40, 255)
RIM_LIGHT = (255, 226, 120, 255)
GROOVE = (214, 140, 20, 255)
FACE = (255, 206, 58, 255)
FACE_SHADE = (246, 182, 36, 255)
STAR = (255, 230, 110, 255)
STAR_EDGE = (190, 118, 14, 255)
STAR_SHADOW = (214, 140, 20, 255)
WHITE = (255, 255, 255, 255)

R = S * 0.40          # face radius
T = S * 0.055         # coin thickness (how far the edge shows below)
OW = S * 0.022        # outline width
cy = c - T / 2        # face centre, nudged up so face + edge are centred

img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
d = ImageDraw.Draw(img)


def disc(cx, cy, r, fill):
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=fill)


def star_points(cx, cy, r_out, r_in, rot=-90):
    pts = []
    for i in range(10):
        r = r_out if i % 2 == 0 else r_in
        a = math.radians(rot + i * 36)
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


# 1. outline around the face and the edge below it
disc(c, cy + T, R + OW, OUTLINE)
disc(c, cy, R + OW, OUTLINE)
# 2. the edge (thickness), with reeding grooves on the visible lower part
disc(c, cy + T, R, SIDE)
edge = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ed = ImageDraw.Draw(edge)
for i in range(64):
    a = math.radians(i * (360 / 64))
    x = c + R * math.cos(a)
    if math.sin(a) <= 0.15:   # only the lower half shows below the face
        continue
    ed.line([(x, cy + T * 0.2), (x, cy + T + R)], fill=SIDE_DARK, width=int(S * 0.006))
mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).ellipse([c - R, cy + T - R, c + R, cy + T + R], fill=255)
img.paste(edge, (0, 0), Image.composite(edge, Image.new("RGBA", (S, S)), mask).split()[3])
d = ImageDraw.Draw(img)
# 3. the face: rim, then a thin dark line where the face meets the edge
disc(c, cy, R, RIM)
# rim highlight along the upper-left
d.arc([c - R * 0.94, cy - R * 0.94, c + R * 0.94, cy + R * 0.94], start=150, end=280, fill=RIM_LIGHT, width=int(R * 0.07))
# 4. inset face: groove ring, then the face with a lower-right shade
disc(c, cy, R * 0.80, OUTLINE)
disc(c, cy, R * 0.775, GROOVE)
disc(c, cy, R * 0.74, FACE_SHADE)
# lighter upper-left of the face (a big offset disc clipped to the face)
face = Image.new("RGBA", (S, S), (0, 0, 0, 0))
fd = ImageDraw.Draw(face)
fd.ellipse([c - R * 0.74 - R * 0.10, cy - R * 0.74 - R * 0.10, c + R * 0.74 - R * 0.10, cy + R * 0.74 - R * 0.10], fill=FACE)
fmask = Image.new("L", (S, S), 0)
ImageDraw.Draw(fmask).ellipse([c - R * 0.74, cy - R * 0.74, c + R * 0.74, cy + R * 0.74], fill=255)
img.paste(face, (0, 0), Image.composite(face, Image.new("RGBA", (S, S)), fmask).split()[3])
d = ImageDraw.Draw(img)
# 5. raised star: drop shadow, outline, body, then a lit top-left half
sr_out, sr_in = R * 0.48, R * 0.21
off = R * 0.045
d.polygon(star_points(c + off, cy + off * 1.4, sr_out, sr_in), fill=STAR_SHADOW)
d.polygon(star_points(c, cy, sr_out + OW * 0.9, sr_in + OW * 0.5), fill=STAR_EDGE)
d.polygon(star_points(c, cy, sr_out, sr_in), fill=STAR)
# bevel: every point is two facets (either side of its ridge), shaded by how
# much each faces the light from the upper left
pts = star_points(c, cy, sr_out, sr_in)
light = (-0.6, -0.8)
STAR_LIT = (255, 240, 150, 255)
STAR_MID = (255, 216, 84, 255)
STAR_DARK = (238, 172, 40, 255)
for i in range(0, 10, 2):
    tip = pts[i]
    for inner in (pts[(i - 1) % 10], pts[(i + 1) % 10]):
        mx, my = (tip[0] + inner[0]) / 2 - c, (tip[1] + inner[1]) / 2 - cy
        length = math.hypot(mx, my)
        facing = (mx * light[0] + my * light[1]) / length
        fill = STAR_LIT if facing > 0.35 else (STAR_MID if facing > -0.35 else STAR_DARK)
        d.polygon([(c, cy), tip, inner], fill=fill)
# 6. gloss streak on the upper-left of the coin
gloss = Image.new("RGBA", (S, S), (0, 0, 0, 0))
gd = ImageDraw.Draw(gloss)
gd.ellipse([c - R * 0.80, cy - R * 0.86, c - R * 0.12, cy - R * 0.50], fill=(255, 255, 255, 120))
gloss = gloss.rotate(28, center=(c - R * 0.46, cy - R * 0.68), resample=Image.BICUBIC)
gmask = Image.new("L", (S, S), 0)
ImageDraw.Draw(gmask).ellipse([c - R, cy - R, c + R, cy + R], fill=255)
img = Image.alpha_composite(img, Image.composite(gloss, Image.new("RGBA", (S, S)), gmask))
d = ImageDraw.Draw(img)
# 7. sparkle on the upper-right of the face (fully on the coin, not on the outline)
sx, sy, sl = c + R * 0.50, cy - R * 0.50, R * 0.19
d.polygon([(sx, sy - sl), (sx + sl * 0.18, sy - sl * 0.18), (sx + sl, sy), (sx + sl * 0.18, sy + sl * 0.18),
           (sx, sy + sl), (sx - sl * 0.18, sy + sl * 0.18), (sx - sl, sy), (sx - sl * 0.18, sy - sl * 0.18)], fill=WHITE)

img = img.resize((SIZE, SIZE), Image.LANCZOS)
img.save(OUT)
print("saved", OUT, img.size)
