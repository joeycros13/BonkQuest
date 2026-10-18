"""Bonk Quest "Transcendent" rarity tile (2026-10-12): the Worldheart Blade's tier.

Same shape as the v3 rarity tiles (inventory_ui_v3: 256 px, a darker lip, a soft light
spot, faint stripes, a dashed inner border, a light top line). The user's pick: a dark
purple gradient, plum #6B2FA8 at the top to deep violet #2A0F4A at the bottom, with a
thin gold dashed rim and a scatter of tiny gold star sparkles in the corners, clear of
the middle where the weapon sits.
Usage: python transcendent_tile.py [out_dir]     (default: this folder)
"""
import math
import os
import sys

ART = r"C:\FirstRobloxGame\.claude\worktrees\roblox-studio-connection-d93d59\art"
sys.path.insert(0, ART)
from artkit import Canvas  # noqa: E402
import inventory_ui_v3 as v3  # noqa: E402

OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.abspath(__file__))
WHITE = (255, 255, 255, 255)
CLEAR = (0, 0, 0, 0)
TOP = (107, 47, 168, 255)      # 6B2FA8
BASE = (42, 15, 74, 255)       # 2A0F4A
LIP = (23, 7, 38, 255)
GOLD = (242, 193, 78, 255)


def star(cx, cy, r):
    pts = []
    for i in range(8):
        rr = r if i % 2 == 0 else r * 0.32
        a = math.pi / 4 * i - math.pi / 2
        pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
    return pts


def transcendent_tile():
    S = 256
    c = Canvas(S, 3)
    lip_h = 14
    c.fill(c.rrect((0, lip_h, S, S), 38), LIP)
    fb = (0, 0, S, S - lip_h)
    face = c.rrect(fb, 38)
    c.vgrad(face, fb, TOP, BASE)
    c.radial(face, (70, 50), 190, (255, 255, 255, 70), CLEAR)
    stripes = c.blank()
    for x in range(-S, S * 2, 30):
        stripes = c.mask_or(stripes, c.polygon([(x, S), (x + 10, S), (x + 10 + S, 0), (x + S, 0)]))
    c.fill(c.mask_and(stripes, face), WHITE, 0.05)
    # tiny gold sparkles in the corners
    for (x, y, r, a) in ((44, 200, 9, 0.8), (64, 214, 5, 0.6), (210, 42, 8, 0.8), (194, 30, 4, 0.6), (218, 196, 5, 0.6), (40, 46, 4, 0.5)):
        c.fill(c.mask_and(c.polygon(star(x, y, r)), face), GOLD, a)
    v3.dashed_rrect(c, (16, 16, S - 16, fb[3] - 16), 26, GOLD, 0.95, 12, 9, 3)
    c.fill(c.mask_and(c.mask_sub(face, c.shift(face, 0, 5)), c.rrect((0, 0, S, 60), 0)), WHITE, 0.3)
    path = os.path.join(OUT, "tile_transcendent.png")
    c.save(path)
    return path


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    print(transcendent_tile())
