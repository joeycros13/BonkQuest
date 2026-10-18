"""Bonk Quest "Relic" rarity tile (2026-10-12): the Rusty Blade's tier.

Same shape as the v3 rarity tiles (inventory_ui_v3.rarity_tile: 256 px, a darker
lip, a soft light spot, faint stripes, a dashed inner border, a light top line).
The face is a rusty copper gradient (#C46A3A at the top to #8A4B2A at the bottom,
the user's pick) with a teal verdigris dashed rim, like old copper gone green,
and a few faint verdigris patina spots in the corners, clear of the middle where
the weapon sits.
Usage: python relic_tile.py [out_dir]     (default: this folder)
"""
import os
import sys

ART = r"C:\FirstRobloxGame\.claude\worktrees\roblox-studio-connection-d93d59\art"
sys.path.insert(0, ART)
from artkit import Canvas  # noqa: E402
import inventory_ui_v3 as v3  # noqa: E402

OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.abspath(__file__))
WHITE = (255, 255, 255, 255)
CLEAR = (0, 0, 0, 0)
TOP = (196, 106, 58, 255)      # C46A3A
BASE = (138, 75, 42, 255)      # 8A4B2A
LIP = (84, 42, 20, 255)
VERDIGRIS = (79, 179, 163, 255)


def relic_tile():
    S = 256
    c = Canvas(S, 3)
    lip_h = 14
    c.fill(c.rrect((0, lip_h, S, S), 38), LIP)
    fb = (0, 0, S, S - lip_h)
    face = c.rrect(fb, 38)
    c.vgrad(face, fb, TOP, BASE)
    c.radial(face, (70, 50), 190, (255, 255, 255, 90), CLEAR)
    stripes = c.blank()
    for x in range(-S, S * 2, 30):
        stripes = c.mask_or(stripes, c.polygon([(x, S), (x + 10, S), (x + 10 + S, 0), (x + S, 0)]))
    c.fill(c.mask_and(stripes, face), WHITE, 0.06)
    # verdigris patina: soft blotches in the corners
    for (x, y, r) in ((40, 196, 26), (58, 214, 14), (214, 44, 20), (200, 30, 11), (222, 200, 12)):
        c.fill(c.mask_and(c.ellipse((x - r, y - r * 0.8, x + r, y + r * 0.8)), face), VERDIGRIS, 0.35)
    v3.dashed_rrect(c, (16, 16, S - 16, fb[3] - 16), 26, VERDIGRIS, 0.95, 12, 9, 3)
    c.fill(c.mask_and(c.mask_sub(face, c.shift(face, 0, 5)), c.rrect((0, 0, S, 60), 0)), WHITE, 0.35)
    c.save(os.path.join(OUT, "tile_relic.png"))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    relic_tile()
