"""Paw icon for the Index world-card creature count chip (2026-10-13).
Flat white pads with a chunky warm-brown outline, matching the white-and-blue shield
icon on the armour chip. Renders at 4x and downsamples to 512."""
from PIL import Image, ImageDraw, ImageFilter

SS = 4
S = 512 * SS
OUT = (122, 59, 28, 255)       # 7a3b1c, the Index's warm brown
FILL = (255, 255, 255, 255)
SHINE = (232, 222, 210, 255)   # a soft lower shade inside each pad

def ell(d, cx, cy, rx, ry, fill, rot=0):
    # rotated ellipse as a polygon
    import math
    pts = []
    for i in range(96):
        t = 2 * math.pi * i / 96
        x, y = rx * math.cos(t), ry * math.sin(t)
        c, s = math.cos(math.radians(rot)), math.sin(math.radians(rot))
        pts.append(((cx + x * c - y * s) * SS, (cy + x * s + y * c) * SS))
    d.polygon(pts, fill=fill)

# toes: (cx, cy, rx, ry, rot); main pad drawn as a rounded trapezoid-ish blob
TOES = [(104, 222, 46, 60, -28), (194, 126, 48, 64, -10), (318, 126, 48, 64, 10), (408, 222, 46, 60, 28)]

def shapes(d, grow, fill):
    for cx, cy, rx, ry, rot in TOES:
        ell(d, cx, cy, rx + grow, ry + grow, fill, rot)
    # main pad: three overlapping ellipses for a soft heart-ish bean
    ell(d, 256, 352, 118 + grow, 92 + grow, fill)
    ell(d, 196, 318, 76 + grow, 70 + grow, fill)
    ell(d, 316, 318, 76 + grow, 70 + grow, fill)

img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
d = ImageDraw.Draw(img)
shapes(d, 22, OUT)
shapes(d, 0, FILL)
# flat white pads, like the shield icon (shading read as smudges at chip size)
img = img.resize((512, 512), Image.LANCZOS)
img.save(__file__.replace("paw_icon.py", "paw_icon.png"))
