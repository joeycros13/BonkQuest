"""Bonk Quest "Secret" rarity tile (2026-10-09): the Corn Cob's tier.

Same shape as the v3 rarity tiles (inventory_ui_v3.rarity_tile: 256 px, a
darker lip, a soft light spot, faint stripes, a dashed inner border, a light top
line), but the face is a diagonal rainbow and a few white sparkles sit on it.
Usage: python secret_tile.py [out_dir]     (default: ./inventory_v3)
"""
import math
import os
import sys

from PIL import Image

from artkit import Canvas
import inventory_ui_v3 as v3

OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "inventory_v3")
WHITE = (255, 255, 255, 255)
CLEAR = (0, 0, 0, 0)
LIP = (96, 46, 150, 255)
# rainbow bands, top-left to bottom-right
BANDS = [
    (255, 120, 170, 255),  # pink
    (255, 160, 80, 255),   # orange
    (255, 220, 80, 255),   # yellow
    (120, 214, 110, 255),  # green
    (80, 200, 240, 255),   # sky
    (170, 130, 255, 255),  # violet
]


def sparkle(c, cx, cy, r):
    """A four-point star."""
    k = r * 0.28
    return c.polygon([(cx, cy - r), (cx + k, cy - k), (cx + r, cy), (cx + k, cy + k),
                      (cx, cy + r), (cx - k, cy + k), (cx - r, cy), (cx - k, cy - k)])


def secret_tile():
    S = 256
    c = Canvas(S, 3)
    lip_h = 14
    c.fill(c.rrect((0, lip_h, S, S), 38), LIP)
    fb = (0, 0, S, S - lip_h)
    face = c.rrect(fb, 38)
    # diagonal rainbow from the top-left corner to the bottom-right: band i holds
    # the points with a <= x + y <= b (the first and last run past the corners)
    n = len(BANDS)
    span = 2 * S / n
    for i, col in enumerate(BANDS):
        a = i * span - (60 if i == 0 else 0)
        b = (i + 1) * span + (60 if i == n - 1 else 1)
        band = c.polygon([(a + S, -S), (b + S, -S), (b - 2 * S, 2 * S), (a - 2 * S, 2 * S)])
        c.fill(c.mask_and(band, face), col)
    c.radial(face, (70, 50), 190, (255, 255, 255, 120), CLEAR)
    stripes = c.blank()
    for x in range(-S, S * 2, 30):
        stripes = c.mask_or(stripes, c.polygon([(x, S), (x + 10, S), (x + 10 + S, 0), (x + S, 0)]))
    c.fill(c.mask_and(stripes, face), WHITE, 0.08)
    v3.dashed_rrect(c, (16, 16, S - 16, fb[3] - 16), 26, WHITE, 0.5, 12, 9, 3)
    c.fill(c.mask_and(c.mask_sub(face, c.shift(face, 0, 5)), c.rrect((0, 0, S, 60), 0)), WHITE, 0.45)
    # sparkles in the corners, clear of the middle where the weapon sits
    for (x, y, r) in ((44, 46, 15), (212, 54, 10), (206, 196, 14), (52, 200, 9)):
        c.fill(c.mask_and(sparkle(c, x, y, r), face), WHITE, 0.9)
    c.save(os.path.join(OUT, "tile_secret.png"))


def smooth_rainbow(c):
    """A full-canvas layer: the rainbow bands blended smoothly from the top-left
    corner (pink) to the bottom-right (violet), by x + y."""
    W, H = c.W, c.H
    n = len(BANDS)
    ramp = []
    for i in range(W + H - 1):
        t = i / (W + H - 2) * (n - 1)
        k = min(int(t), n - 2)
        f = t - k
        a, b = BANDS[k], BANDS[k + 1]
        ramp.append(tuple(round(a[j] + (b[j] - a[j]) * f) for j in range(3)) + (255,))
    layer = Image.new("RGBA", (W, H))
    layer.putdata([ramp[x + y] for y in range(H) for x in range(W)])
    return layer


def black_tile(name, border, sparkle_col, sparkle_alpha, rainbow_border=False):
    """Black-gradient options (2026-10-09, the user asked for black)."""
    S = 256
    c = Canvas(S, 3)
    lip_h = 14
    c.fill(c.rrect((0, lip_h, S, S), 38), (8, 8, 12, 255))
    fb = (0, 0, S, S - lip_h)
    face = c.rrect(fb, 38)
    c.vgrad(face, fb, (70, 70, 82, 255), (14, 14, 20, 255))
    c.radial(face, (70, 50), 190, (255, 255, 255, 60), CLEAR)
    stripes = c.blank()
    for x in range(-S, S * 2, 30):
        stripes = c.mask_or(stripes, c.polygon([(x, S), (x + 10, S), (x + 10 + S, 0), (x + S, 0)]))
    c.fill(c.mask_and(stripes, face), WHITE, 0.05)
    box = (16, 16, S - 16, fb[3] - 16)
    if rainbow_border:
        # a dashed ring, coloured in diagonal rainbow bands
        ring = c.ring(box, 26, 4)
        cuts = c.blank()
        x0, y0, x1, y1 = box
        cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        n = int(2 * ((x1 - x0) + (y1 - y0)) / 21)
        for i in range(n):
            a0 = 2 * math.pi * (i + 12 / 21) / n
            a1 = 2 * math.pi * (i + 1) / n
            far = (x1 - x0) + (y1 - y0)
            cuts = c.mask_or(cuts, c.polygon([(cx, cy), (cx + far * math.cos(a0), cy + far * math.sin(a0)),
                                              (cx + far * math.cos(a1), cy + far * math.sin(a1))]))
        dashes = c.mask_sub(ring, cuts)
        if rainbow_border == "smooth":
            # the user's pick (B), with each colour fading into the next along
            # the diagonal instead of switching at a hard line
            c._paint(smooth_rainbow(c), dashes)
            rainbow_border = None
        span = 2 * S / len(BANDS)
        for i, col in enumerate(BANDS if rainbow_border else []):
            a = i * span - (60 if i == 0 else 0)
            b = (i + 1) * span + (60 if i == len(BANDS) - 1 else 1)
            band = c.polygon([(a + S, -S), (b + S, -S), (b - 2 * S, 2 * S), (a - 2 * S, 2 * S)])
            c.fill(c.mask_and(band, dashes), col)
    else:
        v3.dashed_rrect(c, box, 26, border, 0.85, 12, 9, 3)
    c.fill(c.mask_and(c.mask_sub(face, c.shift(face, 0, 5)), c.rrect((0, 0, S, 60), 0)), WHITE, 0.25)
    for (x, y, r) in ((44, 46, 15), (212, 54, 10), (206, 196, 14), (52, 200, 9)):
        c.fill(c.mask_and(sparkle(c, x, y, r), face), sparkle_col, sparkle_alpha)
    c.save(os.path.join(OUT, f"tile_secret_{name}.png"))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    secret_tile()
    black_tile("a", (255, 255, 255, 255), (255, 255, 255, 255), 0.8)                 # Midnight
    black_tile("b", None, (255, 255, 255, 255), 0.9, rainbow_border=True)            # Black + rainbow rim
    black_tile("c", (255, 200, 70, 255), (255, 206, 84, 255), 0.95)                  # Black + gold
    # the user's pick (2026-10-09): B with the rim colours fading into each other
    black_tile("b_smooth", None, (255, 255, 255, 255), 0.9, rainbow_border="smooth")
    print("saved tile_secret.png and black options a/b/c, b_smooth")
