"""Bonk Quest Inventory theme v3: bright aqua cartoon, after the user's reference.

A light aqua window (a touch see-through) with soft gradients and a faint
pattern, a cyan header, rounded inset panels, rarity-coloured item tiles with a
solid darker lip and a dashed inner border, a green "equipped" check badge,
Damage / Health stat cards, and chunky lip buttons with no outlines or gloss.

Layout (window fractions, matching the Studio frames):
  header 0-0.135 | character panel x .025-.335 y .17-.73 | stat cards y .755-.86
  items panel x .355-.975 y .17-.835 | buttons in the bottom bar
Usage: python inventory_ui_v3.py [out_dir]     (default: ./inventory_v3)
"""
import math
import os
import sys

from artkit import Canvas

OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "inventory_v3")
os.makedirs(OUT, exist_ok=True)

WHITE = (255, 255, 255, 255)
CLEAR = (0, 0, 0, 0)
RIM = (12, 112, 132, 255)
AQUA_TOP, AQUA_BOT = (236, 251, 252, 236), (206, 240, 244, 240)
PANEL = (178, 228, 234, 255)
PANEL_EDGE = (150, 212, 220, 255)
HEADER_TOP, HEADER_BOT = (30, 206, 222, 255), (8, 160, 186, 255)
TEAL = (14, 150, 166, 255)

RARITIES = {
    "Common": ((206, 212, 222, 255), (150, 160, 176, 255), (106, 116, 134, 255)),
    "Uncommon": ((132, 222, 112, 255), (70, 180, 72, 255), (38, 124, 46, 255)),
    "Rare": ((104, 178, 255, 255), (44, 118, 232, 255), (24, 74, 168, 255)),
    "Epic": ((204, 142, 255, 255), (146, 82, 226, 255), (96, 46, 166, 255)),
    "Legendary": ((255, 204, 84, 255), (246, 150, 30, 255), (182, 96, 12, 255)),
}


def path(name):
    return os.path.join(OUT, name)


def pattern_diamonds(c, clip, box, colour, opacity, spacing=40, r=5):
    x0, y0, x1, y1 = box
    m = c.blank()
    row = 0
    y = y0
    while y < y1 + spacing:
        x = x0 + (spacing / 2 if row % 2 else 0)
        while x < x1 + spacing:
            m = c.mask_or(m, c.polygon([(x, y - r), (x + r, y), (x, y + r), (x - r, y)]))
            x += spacing
        y += spacing / 2
        row += 1
    c.fill(c.mask_and(m, clip), colour, opacity)


def dashed_rrect(c, box, r, colour, opacity, dash=14, gap=10, width=3):
    """A dashed rounded-rectangle outline."""
    x0, y0, x1, y1 = box
    ring = c.ring(box, r, width)
    # cut the ring into dashes with a pattern of spokes running round the box
    cuts = c.blank()
    perim = 2 * ((x1 - x0) + (y1 - y0))
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    n = int(perim / (dash + gap))
    for i in range(n):
        a0 = 2 * math.pi * (i + dash / (dash + gap)) / n
        a1 = 2 * math.pi * (i + 1) / n
        far = (x1 - x0) + (y1 - y0)
        cuts = c.mask_or(cuts, c.polygon([(cx, cy), (cx + far * math.cos(a0), cy + far * math.sin(a0)),
                                          (cx + far * math.cos(a1), cy + far * math.sin(a1))]))
    c.fill(c.mask_sub(ring, cuts), colour, opacity)


def lip_tile(c, box, r, top, base, lip, lip_h=12):
    """A face with a solid darker lip under it; returns the face mask."""
    x0, y0, x1, y1 = box
    c.fill(c.rrect((x0, y0 + lip_h, x1, y1), r), lip)
    face_box = (x0, y0, x1, y1 - lip_h)
    face = c.rrect(face_box, r)
    c.vgrad(face, face_box, top, base)
    return face, face_box


# ==================== window ====================

def window():
    W, H = 1368, 800
    c = Canvas(W, 2, h=H)
    R = 42
    c.fill(c.rrect((0, 0, W, H), R), RIM, 0.95)
    body_box = (5, 5, W - 5, H - 14)
    body = c.rrect(body_box, R - 5)
    c.vgrad(body, body_box, AQUA_TOP, AQUA_BOT)
    c.radial(body, (240, 260), 520, (255, 255, 255, 120), CLEAR)
    pattern_diamonds(c, body, (0, 0, W, H), WHITE, 0.45, 44, 5)

    # header
    header = c.mask_and(body, c.rrect((0, 0, W, 108), 0))
    c.vgrad(header, (0, 0, W, 108), HEADER_TOP, HEADER_BOT)
    pattern_diamonds(c, header, (0, 0, W, 108), WHITE, 0.10, 36, 5)
    c.radial(header, (300, 20), 360, (255, 255, 255, 70), CLEAR)
    c.fill(c.mask_and(body, c.rrect((0, 100, W, 110), 0)), (6, 124, 146, 255))

    # character panel, with a dashed stage and a podium
    pb = (34, 136, 458, 584)
    c.fill(c.rrect(pb, 30), PANEL_EDGE)
    inner = c.rrect((38, 140, 454, 580), 27)
    c.vgrad(inner, pb, (186, 234, 240, 225), (164, 222, 230, 235))
    c.radial(inner, (320, 300), 230, (255, 255, 255, 120), CLEAR)
    stage = (166, 152, 444, 570)
    dashed_rrect(c, stage, 22, (90, 168, 178, 255), 0.6)
    top = (194, 520, 418, 552)
    c.fill(c.ellipse((194, 528, 418, 566)), (10, 128, 148, 255))
    c.vgrad(c.ellipse(top), top, (40, 190, 200, 255), (16, 156, 172, 255))
    c.fill(c.mask_and(c.ellipse(top), c.ellipse((214, 516, 398, 540))), WHITE, 0.25)

    # items panel
    ib = (486, 136, 1334, 668)
    c.fill(c.rrect(ib, 30), PANEL_EDGE)
    well = c.rrect((490, 140, 1330, 664), 27)
    c.vgrad(well, ib, (190, 236, 242, 215), (170, 226, 234, 225))
    c.save(path("window_bg.png"))


def window_shadow():
    W, H = 1368, 800
    c = Canvas(W, 1, h=H)
    c.fill(c.rrect((0, 0, W, H), 42), (8, 60, 72, 255), 0.35)
    c.save(path("window_shadow.png"))


# ==================== tiles ====================

def rarity_tile(name, top, base, lip):
    S = 256
    c = Canvas(S, 3)
    face, fb = lip_tile(c, (0, 0, S, S), 38, top, base, lip, 14)
    c.radial(face, (70, 50), 190, (255, 255, 255, 110), CLEAR)
    # faint diagonal stripes
    stripes = c.blank()
    for x in range(-S, S * 2, 30):
        stripes = c.mask_or(stripes, c.polygon([(x, S), (x + 10, S), (x + 10 + S, 0), (x + S, 0)]))
    c.fill(c.mask_and(stripes, face), WHITE, 0.07)
    dashed_rrect(c, (16, 16, S - 16, fb[3] - 16), 26, WHITE, 0.4, 12, 9, 3)
    # thin light line along the top edge
    c.fill(c.mask_and(c.mask_sub(face, c.shift(face, 0, 5)), c.rrect((0, 0, S, 60), 0)), WHITE, 0.45)
    c.save(path(f"tile_{name.lower()}.png"))


def empty_tile():
    S = 256
    c = Canvas(S, 3)
    c.fill(c.rrect((0, 0, S, S), 38), (176, 222, 230, 255), 0.75)
    c.fill(c.rrect((4, 4, S - 4, S - 4), 35), (198, 236, 242, 255), 0.75)
    c.save(path("tile_empty.png"))


def check_badge():
    S = 96
    c = Canvas(S, 4)
    c.fill(c.ellipse((0, 4, S, S)), (22, 120, 40, 255))
    c.fill(c.ellipse((0, 0, S, S - 4)), WHITE)
    face = c.ellipse((8, 8, S - 8, S - 12))
    c.vgrad(face, (8, 8, S - 8, S - 12), (110, 220, 96, 255), (56, 176, 64, 255))
    c.fill(c.stroke([(30, 47), (42, 59), (66, 35)], 9, smooth=False), WHITE)
    c.save(path("check_badge.png"))


def socket():
    S = 160
    c = Canvas(S, 3)
    face, fb = lip_tile(c, (0, 0, S, S), 30, (244, 252, 253, 255), (212, 240, 244, 255), (144, 200, 210, 255), 10)
    dashed_rrect(c, (12, 12, S - 12, fb[3] - 12), 20, (110, 184, 194, 255), 0.6, 10, 8, 3)
    c.save(path("socket.png"))


# ==================== stat cards ====================

def sword_icon(c, cx, cy, s):
    """A sword pointing up-right: blade with a tip, crossguard, grip, pommel."""
    d = (0.7071, -0.7071)   # along the blade
    p = (0.7071, 0.7071)    # across it

    def at(base, along, across):
        return (base[0] + d[0] * along + p[0] * across, base[1] + d[1] * along + p[1] * across)

    base = (cx - s * 0.16, cy + s * 0.16)
    w = s * 0.17
    blade = c.polygon([at(base, 0, -w / 2), at(base, s * 0.62, -w / 2), at(base, s * 0.78, 0),
                       at(base, s * 0.62, w / 2), at(base, 0, w / 2)])
    guard = c.stroke([at(base, 0, -s * 0.26), at(base, 0, s * 0.26)], s * 0.12, smooth=False)
    grip = c.stroke([at(base, 0, 0), at(base, -s * 0.22, 0)], s * 0.1, smooth=False)
    pc = at(base, -s * 0.28, 0)
    pommel = c.ellipse((pc[0] - s * 0.08, pc[1] - s * 0.08, pc[0] + s * 0.08, pc[1] + s * 0.08))
    return c.mask_or(c.mask_or(c.mask_or(blade, guard), grip), pommel)


def heart_icon(c, cx, cy, s):
    r = s * 0.26
    left = c.ellipse((cx - 2 * r + s * 0.02, cy - s * 0.32, cx + s * 0.02, cy - s * 0.32 + 2 * r))
    right = c.ellipse((cx - s * 0.02, cy - s * 0.32, cx + 2 * r - s * 0.02, cy - s * 0.32 + 2 * r))
    point = c.polygon([(cx - 2 * r + s * 0.04, cy - s * 0.02), (cx + 2 * r - s * 0.04, cy - s * 0.02), (cx, cy + s * 0.44)])
    return c.mask_or(c.mask_or(left, right), point)


def stat_card(name, top, base, lip, icon):
    w, h = 366, 150
    c = Canvas(w, 3, h=h)
    face, fb = lip_tile(c, (0, 0, w, h), 30, top, base, lip, 12)
    c.radial(face, (60, 20), 220, (255, 255, 255, 90), CLEAR)
    c.fill(c.mask_and(c.mask_sub(face, c.shift(face, 0, 5)), c.rrect((0, 0, w, 50), 0)), WHITE, 0.4)
    if icon is not None:  # (the game now overlays the HUD-design icons instead)
        m = icon(c, 76, 68, 92)
        c.fill(c.shift(m, 0, 4), lip, 0.6)
        c.fill(m, WHITE)
    c.save(path(name))


# ==================== buttons ====================

def lip_button(name, top, base, lip, w=348, h=120, r=32):
    c = Canvas(w, 3, h=h)
    face, fb = lip_tile(c, (0, 0, w, h), r, top, base, lip, 14)
    c.fill(c.mask_and(c.mask_sub(face, c.shift(face, 0, 5)), c.rrect((0, 0, w, h * 0.45), 0)), WHITE, 0.45)
    c.radial(face, (w * 0.3, 10), w * 0.6, (255, 255, 255, 60), CLEAR)
    c.save(path(name))


def close_button():
    S = 128
    c = Canvas(S, 3)
    face, fb = lip_tile(c, (0, 0, S, S), 30, (255, 112, 104, 255), (232, 62, 66, 255), (166, 30, 42, 255), 12)
    c.fill(c.mask_and(c.mask_sub(face, c.shift(face, 0, 5)), c.rrect((0, 0, S, 50), 0)), WHITE, 0.45)
    c.save(path("btn_close.png"))


def search_field():
    w, h, r = 600, 100, 34
    c = Canvas(w, 3, h=h)
    c.fill(c.rrect((0, 8, w, h), r), (178, 218, 226, 255))
    c.fill(c.rrect((0, 0, w, h - 8), r), WHITE)
    c.save(path("search.png"))


def dropdown():
    w, h, r = 336, 400, 30
    c = Canvas(w, 3, h=h)
    c.fill(c.rrect((0, 0, w, h), r), RIM)
    body = c.rrect((5, 5, w - 5, h - 10), r - 5)
    c.vgrad(body, (0, 0, w, h), (240, 252, 253, 255), (210, 240, 244, 255))
    pattern_diamonds(c, body, (0, 0, w, h), WHITE, 0.5, 40, 5)
    c.save(path("dropdown.png"))


def option_row():
    w, h, r = 456, 100, 30
    c = Canvas(w, 3, h=h)
    face, fb = lip_tile(c, (0, 0, w, h), r, (24, 150, 172, 255), (10, 116, 140, 255), (6, 78, 98, 255), 12)
    c.fill(c.mask_and(c.mask_sub(face, c.shift(face, 0, 4)), c.rrect((0, 0, w, 40), 0)), WHITE, 0.3)
    c.save(path("option.png"))


if __name__ == "__main__":
    window()
    window_shadow()
    for rarity, (top, base, lip) in RARITIES.items():
        rarity_tile(rarity, top, base, lip)
    empty_tile()
    check_badge()
    socket()
    stat_card("stat_damage.png", (255, 122, 110, 255), (234, 72, 74, 255), (176, 38, 50, 255), None)
    stat_card("stat_health.png", (126, 222, 104, 255), (66, 184, 76, 255), (34, 126, 50, 255), None)
    lip_button("btn_red.png", (255, 116, 106, 255), (234, 70, 72, 255), (172, 34, 46, 255))
    lip_button("btn_green.png", (124, 222, 102, 255), (70, 186, 72, 255), (36, 128, 46, 255))
    lip_button("btn_gold.png", (255, 224, 90, 255), (250, 184, 40, 255), (196, 120, 16, 255))
    close_button()
    search_field()
    dropdown()
    option_row()
    print("saved", sorted(os.listdir(OUT)))
