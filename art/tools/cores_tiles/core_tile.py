"""DiceBattles "Core" rarity tile (2026-10-12): the tier for the secret-weapon cores
(Farm Core, Forest Core...). Same shape as the v3 rarity tiles (inventory_ui_v3: 256 px,
a darker lip, a soft light spot, faint stripes, a dashed inner border, a light top line),
plus a faint octagon socket ring behind the item, echoing the blade's sockets.

Three looks to choose from, all built so any core colour stands out:
  vault  - dark slate face, gold rim and socket ring
  soil   - deep earth-brown face, gold rim (freshly dug up)
  ivory  - pale stone face, gold rim, a darker socket ring

Usage: python core_tile.py [out_dir]     (default: this folder)
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

LOOKS = {
    "vault": dict(top=(74, 80, 96, 255), base=(34, 37, 46, 255), lip=(18, 19, 25, 255),
                  rim=(242, 193, 78, 255), ring=(242, 193, 78, 255), ring_a=0.22, spot=60, stripes=0.05),
    "soil": dict(top=(122, 84, 56, 255), base=(68, 44, 30, 255), lip=(38, 24, 16, 255),
                 rim=(242, 193, 78, 255), ring=(242, 193, 78, 255), ring_a=0.2, spot=70, stripes=0.05),
    "ivory": dict(top=(246, 238, 220, 255), base=(214, 198, 166, 255), lip=(160, 140, 104, 255),
                  rim=(214, 156, 40, 255), ring=(150, 120, 80, 255), ring_a=0.25, spot=110, stripes=0.08),
}


def octagon(cx, cy, r, rot=math.pi / 8):
    return [(cx + r * math.cos(rot + i * math.pi / 4), cy + r * math.sin(rot + i * math.pi / 4)) for i in range(8)]


def core_tile(name):
    k = LOOKS[name]
    S = 256
    c = Canvas(S, 3)
    lip_h = 14
    c.fill(c.rrect((0, lip_h, S, S), 38), k["lip"])
    fb = (0, 0, S, S - lip_h)
    face = c.rrect(fb, 38)
    c.vgrad(face, fb, k["top"], k["base"])
    c.radial(face, (70, 50), 190, (255, 255, 255, k["spot"]), CLEAR)
    stripes = c.blank()
    for x in range(-S, S * 2, 30):
        stripes = c.mask_or(stripes, c.polygon([(x, S), (x + 10, S), (x + 10 + S, 0), (x + S, 0)]))
    c.fill(c.mask_and(stripes, face), WHITE, k["stripes"])
    # the socket: a faint octagon ring behind where the core sits
    cx, cy = S / 2, (fb[3]) / 2
    ring = c.mask_sub(c.polygon(octagon(cx, cy, 86)), c.polygon(octagon(cx, cy, 74)))
    c.fill(c.mask_and(ring, face), k["ring"], k["ring_a"])
    v3.dashed_rrect(c, (16, 16, S - 16, fb[3] - 16), 26, k["rim"], 0.95, 12, 9, 3)
    c.fill(c.mask_and(c.mask_sub(face, c.shift(face, 0, 5)), c.rrect((0, 0, S, 60), 0)), WHITE, 0.35)
    path = os.path.join(OUT, "tile_core_%s.png" % name)
    c.save(path)
    return path


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for n in LOOKS:
        print(core_tile(n))
