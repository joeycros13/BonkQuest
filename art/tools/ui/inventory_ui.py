"""Bonk Quest Inventory theme: midnight indigo, gold trim, scattered-dice pattern.

Draws every skin the Inventory window uses, each at its element's on-screen
aspect ratio (so they are used with ScaleType.Stretch and nothing distorts):

  window_bg.png     the whole window: glass body, dice pattern, header and
                    footer bands, character stage with spotlight and pedestal,
                    items well, gold rim
  window_shadow.png soft drop shadow drawn behind the window
  item_card.png     one item tile (square)
  socket.png        an equipment slot (helmet / chest / legs)
  btn_green / btn_red / btn_gold / btn_blue.png   3D candy buttons (3.9 : 1)
  btn_close.png     the round close button
  search.png        the inset search field (6 : 1)
  dropdown.png      the filter dropdown panel (0.84 : 1)
  option.png        one dropdown row (4.56 : 1)

Usage: python inventory_ui.py [out_dir]     (default: ./inventory)
"""
import os
import random
import sys

from artkit import Canvas, die_mask

OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "inventory")
os.makedirs(OUT, exist_ok=True)

# ---- palette ----
INK = (12, 10, 22, 255)
INDIGO_TOP = (46, 38, 92, 255)
INDIGO_BOT = (22, 18, 46, 255)
BAND_TOP = (70, 58, 132, 255)
BAND_BOT = (44, 36, 90, 255)
WELL = (12, 10, 28, 255)
GOLD_LIGHT = (255, 222, 120, 255)
GOLD = (236, 176, 58, 255)
GOLD_DARK = (168, 108, 30, 255)
SPOT = (140, 116, 255, 255)
WHITE = (255, 255, 255, 255)
CLEAR = (0, 0, 0, 0)


def path(name):
    return os.path.join(OUT, name)


def gold_ring(c, box, r, width, opacity=1.0):
    ring = c.ring(box, r, width)
    c.vgrad(ring, box, GOLD_LIGHT, GOLD_DARK, opacity)
    # a bright glint along the top of the ring
    x0, y0, x1, y1 = box
    c.glow(c.mask_and(ring, c.rrect((x0, y0, x1, y0 + (y1 - y0) * 0.35), r)), WHITE, 1, 0.35 * opacity)
    return ring


def dice_pattern(c, clip, box, count, seed, opacity_line=0.05, opacity_pip=0.07, sizes=(30, 64)):
    rnd = random.Random(seed)
    x0, y0, x1, y1 = box
    lines, pips = c.blank(), c.blank()
    for _ in range(count):
        size = rnd.uniform(*sizes)
        cx, cy = rnd.uniform(x0, x1), rnd.uniform(y0, y1)
        outline, spots = die_mask(c, cx, cy, size, rnd.uniform(0, 90), rnd.randint(1, 6))
        lines = c.mask_or(lines, outline)
        pips = c.mask_or(pips, spots)
    c.fill(c.mask_and(lines, clip), WHITE, opacity_line)
    c.fill(c.mask_and(pips, clip), WHITE, opacity_pip)


# ==================== window ====================

def window():
    W, H = 1368, 800
    c = Canvas(W, 2, h=H)
    R = 40
    body = c.rrect((0, 0, W, H), R)
    # glass body (a little see-through)
    c.vgrad(body, (0, 0, W, H), (INDIGO_TOP[0], INDIGO_TOP[1], INDIGO_TOP[2], 236), (INDIGO_BOT[0], INDIGO_BOT[1], INDIGO_BOT[2], 244))
    dice_pattern(c, body, (0, 0, W, H), 70, seed=7)

    # header and footer bands
    header = c.mask_and(body, c.rrect((0, 0, W, 100), 0))
    c.vgrad(header, (0, 0, W, 100), (BAND_TOP[0], BAND_TOP[1], BAND_TOP[2], 235), (BAND_BOT[0], BAND_BOT[1], BAND_BOT[2], 225))
    dice_pattern(c, header, (0, 0, W, 100), 14, seed=3, opacity_line=0.06, opacity_pip=0.08, sizes=(26, 44))
    c.glow(c.rrect((30, 6, W - 30, 30), 12), WHITE, 6, 0.10, clip=header)
    footer = c.mask_and(body, c.rrect((0, 704, W, H), 0))
    c.vgrad(footer, (0, 704, W, H), (BAND_BOT[0], BAND_BOT[1], BAND_BOT[2], 225), (30, 24, 62, 240))
    # gold divider lines under the header and over the footer
    for y in (100, 702):
        line = c.rrect((18, y - 1, W - 18, y + 3), 2)
        c.fill(c.shift(line, 0, 3), INK, 0.6)
        c.hgrad(line, (18, y, W - 18, y + 3), GOLD_DARK, GOLD_DARK)
        c.hgrad(c.rrect((W * 0.2, y - 1, W * 0.8, y + 3), 2), (0, 0, W, H), GOLD, GOLD)
        c.glow(c.rrect((W * 0.3, y - 1, W * 0.7, y + 2), 2), GOLD_LIGHT, 2, 0.6)

    # character stage (left, right of the gear sockets): a recessed panel, a
    # spotlight and a pedestal
    stage_box = (146, 114, 548, 690)
    stage = c.rrect(stage_box, 26)
    c.vgrad(stage, stage_box, (14, 12, 32, 170), (20, 16, 44, 210))
    c.radial(stage, (340, 360), 300, (SPOT[0], SPOT[1], SPOT[2], 150), CLEAR)
    c.radial(stage, (340, 250), 150, (220, 210, 255, 50), CLEAR)
    # inner shadow along the top edge, soft light along the bottom
    c.glow(c.mask_sub(c.rrect(stage_box, 26, 20), c.shift(stage, 0, 10)), INK, 8, 0.8, clip=stage)
    gold_ring(c, stage_box, 26, 3, 0.85)
    # pedestal under the character's feet
    ped = (190, 618, 490, 676)
    c.glow(c.ellipse((176, 630, 504, 690)), INK, 10, 0.7, clip=stage)
    c.vgrad(c.ellipse(ped), ped, (92, 76, 170, 255), (40, 32, 84, 255))
    c.vgrad(c.mask_sub(c.ellipse(ped), c.ellipse(ped, -5)), ped, GOLD_LIGHT, GOLD_DARK)
    c.glow(c.ellipse((236, 624, 444, 642)), WHITE, 4, 0.25, clip=c.ellipse(ped))

    # items well (right)
    well_box = (558, 114, 1352, 690)
    well = c.rrect(well_box, 26)
    c.fill(well, WELL, 0.45)
    c.glow(c.mask_sub(c.rrect(well_box, 26, 20), c.shift(well, 0, 10)), INK, 8, 0.7, clip=well)
    c.fill(c.ring(well_box, 26, 2), (140, 128, 220, 255), 0.35)

    # the frame: dark outline, gold rim, a thin inner light line
    c.fill(c.ring((0, 0, W, H), R, 4), INK)
    gold_ring(c, (4, 4, W - 4, H - 4), R - 4, 6)
    c.fill(c.ring((10, 10, W - 10, H - 10), R - 10, 2), (255, 240, 200, 255), 0.25)
    c.save(path("window_bg.png"))


def window_shadow():
    W, H = 760, 444  # drawn 1.1x the window; the window covers its middle
    c = Canvas(W, 2, h=H)
    inner = c.rrect((34, 30, W - 34, H - 22), 30)
    c.glow(inner, (6, 4, 14, 255), 16, 0.7)
    c.save(path("window_shadow.png"))


# ==================== pieces ====================

def item_card():
    S = 256
    c = Canvas(S, 3)
    box = (0, 0, S, S)
    R = 36
    body = c.rrect(box, R)
    c.vgrad(body, box, (84, 70, 160, 255), (40, 32, 90, 255))
    c.radial(body, (128, 104), 128, (170, 150, 255, 150), CLEAR)
    # diagonal sheen across the upper-left
    sheen = c.polygon([(-20, 120), (120, -20), (190, -20), (-20, 190)])
    c.glow(sheen, WHITE, 6, 0.10, clip=body)
    # a faint die tucked in the corner
    outline, pips = die_mask(c, 210, 46, 52, 18, 5)
    c.fill(c.mask_and(outline, body), WHITE, 0.10)
    c.fill(c.mask_and(pips, body), WHITE, 0.12)
    # stat band along the bottom
    band = c.mask_and(body, c.rrect((0, 184, S, S), 0))
    c.vgrad(band, (0, 184, S, S), (16, 12, 40, 120), (10, 8, 26, 190))
    c.fill(c.mask_and(body, c.rrect((14, 183, S - 14, 186), 1)), (200, 190, 255, 255), 0.25)
    # bevel: bright top edge, darker bottom edge
    c.glow(c.mask_sub(body, c.shift(body, 0, 6)), WHITE, 1.5, 0.35, clip=body)
    c.glow(c.mask_sub(body, c.shift(body, 0, -6)), INK, 2, 0.5, clip=body)
    c.save(path("item_card.png"))


def socket():
    S = 160
    c = Canvas(S, 3)
    box = (0, 0, S, S)
    R = 28
    body = c.rrect(box, R)
    c.vgrad(body, box, (16, 12, 36, 235), (34, 28, 70, 235))
    c.radial(body, (80, 86), 70, (120, 100, 230, 70), CLEAR)
    c.glow(c.mask_sub(c.rrect(box, R, 16), c.shift(body, 0, 8)), INK, 6, 0.9, clip=body)
    gold_ring(c, (2, 2, S - 2, S - 2), R - 2, 5)
    c.fill(c.ring((10, 10, S - 10, S - 10), R - 10, 2), (170, 156, 255, 255), 0.25)
    c.save(path("socket.png"))


def candy_button(name, light, base, lip, w=468, h=120, r=32):
    c = Canvas(w, 3, h=h)
    face_box = (5, 5, w - 5, h - 15)
    lip_box = (5, 15, w - 5, h - 5)
    # dark outline around the whole button, then the lip, then the face
    c.fill(c.rrect((0, 0, w, h), r + 5), INK)
    c.fill(c.rrect(lip_box, r), lip)
    face = c.rrect(face_box, r)
    c.vgrad(face, face_box, light, base)
    # gloss across the top half, a soft glow at the bottom of the face
    gloss = c.rrect((18, 11, w - 18, (h - 15) * 0.5), r * 0.6)
    c.vgrad(gloss, (18, 11, w - 18, (h - 15) * 0.5), (255, 255, 255, 255), (255, 255, 255, 0), 0.55)
    c.fill(c.ring(face_box, r, 3), (255, 255, 255, 255), 0.18)
    # tiny sparkles of pattern: two faint pips in the corners
    for x in (26, w - 26):
        c.fill(c.ellipse((x - 5, h * 0.55 - 5, x + 5, h * 0.55 + 5)), WHITE, 0.25)
    c.save(path(name))


def close_button():
    S = 128
    c = Canvas(S, 3)
    c.fill(c.ellipse((0, 0, S, S)), INK)
    c.fill(c.ellipse((5, 11, S - 5, S - 5)), (128, 22, 36, 255))
    face_box = (5, 5, S - 5, S - 11)
    face = c.ellipse(face_box)
    c.vgrad(face, face_box, (255, 120, 120, 255), (214, 46, 60, 255))
    gloss = c.ellipse((24, 12, S - 24, 56))
    c.vgrad(gloss, (24, 12, S - 24, 56), WHITE, (255, 255, 255, 0), 0.6)
    c.fill(c.mask_sub(face, c.ellipse(face_box, -3)), WHITE, 0.2)
    c.save(path("btn_close.png"))


def search_field():
    w, h, r = 600, 100, 44
    c = Canvas(w, 3, h=h)
    box = (0, 0, w, h)
    body = c.rrect(box, r)
    c.vgrad(body, box, (8, 6, 20, 235), (20, 16, 44, 235))
    c.glow(c.mask_sub(c.rrect(box, r, 16), c.shift(body, 0, 9)), (0, 0, 0, 255), 6, 0.9, clip=body)
    c.fill(c.ring(box, r, 3), (120, 108, 210, 255), 0.55)
    c.glow(c.mask_and(c.ring(box, r, 3), c.rrect((0, h * 0.6, w, h), 0)), WHITE, 1, 0.25)
    c.save(path("search.png"))


def dropdown():
    w, h, r = 336, 400, 28
    c = Canvas(w, 3, h=h)
    box = (0, 0, w, h)
    body = c.rrect(box, r)
    c.vgrad(body, box, (40, 34, 84, 245), (20, 16, 44, 248))
    dice_pattern(c, body, box, 8, seed=11, sizes=(30, 50))
    c.fill(c.ring(box, r, 3), INK)
    gold_ring(c, (3, 3, w - 3, h - 3), r - 3, 4)
    c.save(path("dropdown.png"))


def option_row():
    w, h, r = 456, 100, 30
    c = Canvas(w, 3, h=h)
    box = (0, 0, w, h)
    body = c.rrect(box, r)
    c.vgrad(body, box, (74, 62, 140, 255), (44, 36, 92, 255))
    c.glow(c.rrect((16, 6, w - 16, 34), 12), WHITE, 4, 0.18, clip=body)
    c.fill(c.ring(box, r, 3), INK, 0.8)
    c.save(path("option.png"))


window()
window_shadow()
item_card()
socket()
candy_button("btn_green.png", (140, 236, 110, 255), (46, 166, 62, 255), (24, 98, 36, 255))
candy_button("btn_red.png", (255, 128, 120, 255), (212, 50, 62, 255), (124, 22, 34, 255))
candy_button("btn_gold.png", (255, 228, 120, 255), (226, 148, 30, 255), (144, 84, 12, 255))
candy_button("btn_blue.png", (120, 204, 255, 255), (44, 116, 230, 255), (22, 62, 146, 255))
close_button()
search_field()
dropdown()
option_row()
print("saved to", OUT, sorted(os.listdir(OUT)))
