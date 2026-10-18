"""Bonk Quest Inventory theme v2: modern cartoon.

Warm cream panels, a teal header, chunky dark outlines (the HUD's ink), flat
colours with a solid darker "lip" under buttons and cards instead of gloss,
and a faint diagonal stripe pattern. Colours come from the HUD and the
backpack (teal, orange, cream), muted rather than bright.

Same files and aspect ratios as v1 (inventory_ui.py), so the Studio
instances only need their image ids swapped:
  window_bg, window_shadow, item_card, socket, btn_green / red / gold / blue,
  btn_close, search, dropdown, option
Usage: python inventory_ui_v2.py [out_dir]     (default: ./inventory_v2)
"""
import os
import sys

from artkit import Canvas

OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "inventory_v2")
os.makedirs(OUT, exist_ok=True)

INK = (34, 30, 40, 255)
CREAM = (255, 248, 236, 255)
CREAM_2 = (246, 236, 220, 255)
CREAM_3 = (234, 220, 200, 255)
TEAL_L, TEAL, TEAL_D = (96, 206, 192, 255), (64, 184, 170, 255), (36, 132, 124, 255)
WHITE = (255, 255, 255, 255)
CLEAR = (0, 0, 0, 0)


def path(name):
    return os.path.join(OUT, name)


def stripes(c, clip, box, colour, opacity, spacing=34, width=12):
    """Faint diagonal stripes inside `clip`."""
    x0, y0, x1, y1 = box
    m = c.blank()
    span = (x1 - x0) + (y1 - y0)
    x = x0 - (y1 - y0)
    while x < x1:
        m = c.mask_or(m, c.polygon([(x, y1), (x + width, y1), (x + width + (y1 - y0), y0), (x + (y1 - y0), y0)]))
        x += spacing
    c.fill(c.mask_and(m, clip), colour, opacity)


def dots(c, clip, box, colour, opacity, spacing=30, r=3.2):
    x0, y0, x1, y1 = box
    m = c.blank()
    row = 0
    y = y0 + spacing / 2
    while y < y1:
        x = x0 + (spacing / 2 if row % 2 else 0)
        while x < x1:
            m = c.mask_or(m, c.ellipse((x - r, y - r, x + r, y + r)))
            x += spacing
        y += spacing * 0.866
        row += 1
    c.fill(c.mask_and(m, clip), colour, opacity)


def inner_shadow(c, mask, box, r, depth=10, opacity=0.18):
    """A soft shadow along the inside top edge: the panel looks set in."""
    c.glow(c.mask_sub(c.rrect(box, r, 20), c.shift(mask, 0, depth)), INK, depth * 0.6, opacity, clip=mask)


# ==================== window ====================

def window():
    W, H = 1368, 800
    c = Canvas(W, 2, h=H)
    R = 44
    OW = 6
    body = c.rrect((OW, OW, W - OW, H - OW), R - OW)
    c.fill(c.rrect((0, 0, W, H), R), INK)
    c.vgrad(body, (0, 0, W, H), CREAM, CREAM_2)
    stripes(c, body, (0, 0, W, H), CREAM_3, 0.35)

    # header: teal band with a dotted pattern, an ink line under it
    header = c.mask_and(body, c.rrect((0, 0, W, 100), 0))
    c.vgrad(header, (0, 0, W, 100), TEAL_L, TEAL)
    dots(c, header, (0, 0, W, 100), WHITE, 0.14, 28, 3.5)
    c.fill(c.mask_and(body, c.rrect((0, 6, W, 16), 0)), WHITE, 0.18)  # soft top light
    c.fill(c.mask_and(body, c.rrect((0, 100, W, 106), 0)), INK)
    c.fill(c.mask_and(body, c.rrect((0, 106, W, 116), 0)), INK, 0.10)

    # footer: a slightly deeper cream strip with an ink line over it
    footer = c.mask_and(body, c.rrect((0, 704, W, H), 0))
    c.vgrad(footer, (0, 704, W, H), CREAM_2, CREAM_3)
    c.fill(c.mask_and(body, c.rrect((0, 700, W, 705), 0)), INK, 0.85)

    # character stage: a soft teal scene with a podium
    sb = (146, 124, 548, 688)
    stage = c.rrect(sb, 30)
    c.fill(c.rrect(sb, 30, 4), INK)
    c.vgrad(stage, sb, (208, 240, 234, 255), (156, 216, 206, 255))
    c.radial(stage, (347, 330), 230, (255, 255, 255, 170), CLEAR)
    dots(c, stage, sb, WHITE, 0.30, 34, 3)
    inner_shadow(c, stage, sb, 30, 12, 0.22)
    # podium: a side band and a top ellipse
    top = (196, 616, 498, 662)
    side = c.mask_or(c.rrect((196, 640, 498, 674), 6), c.ellipse((196, 652, 498, 696)))
    c.fill(c.dilate(c.mask_or(side, c.ellipse(top)), 4), INK)
    c.vgrad(side, (196, 640, 498, 696), TEAL, TEAL_D)
    c.vgrad(c.ellipse(top), top, (255, 255, 255, 255), (222, 244, 240, 255))
    c.fill(c.mask_sub(c.ellipse(top), c.ellipse(top, -4)), TEAL_D, 0.5)
    c.fill(c.mask_and(c.mask_sub(c.ellipse(top, 4), c.ellipse(top)), stage), INK)

    # items well: an inset cream tray
    wb = (560, 124, 1348, 688)
    well = c.rrect(wb, 30)
    c.fill(c.rrect(wb, 30, 4), INK, 0.9)
    c.fill(well, (240, 230, 214, 255))
    inner_shadow(c, well, wb, 30, 12, 0.18)

    c.save(path("window_bg.png"))


def window_shadow():
    # a chunky solid drop shadow (drawn the window's size, offset down in Studio)
    W, H = 1368, 800
    c = Canvas(W, 1, h=H)
    c.fill(c.rrect((0, 0, W, H), 44), INK, 0.45)
    c.save(path("window_shadow.png"))


# ==================== pieces ====================

def item_card():
    S = 256
    c = Canvas(S, 3)
    R = 38
    lip = c.rrect((0, 10, S, S), R)
    face_box = (0, 0, S, S - 12)
    face = c.rrect(face_box, R)
    c.fill(lip, CREAM_3)
    c.vgrad(face, face_box, (255, 255, 255, 255), (246, 240, 230, 255))
    c.radial(face, (128, 104), 112, (196, 236, 228, 255), CLEAR)
    stripes(c, face, face_box, (230, 220, 204, 255), 0.25, 30, 10)
    # stat area along the bottom of the face
    band = c.mask_and(face, c.rrect((0, 178, S, S), 0))
    c.fill(band, (236, 226, 210, 255), 0.85)
    c.fill(c.mask_and(face, c.rrect((0, 176, S, 180), 0)), INK, 0.12)
    # a crisp light line along the top inside edge
    c.fill(c.mask_and(c.mask_sub(face, c.shift(face, 0, 5)), c.rrect((0, 0, S, 60), 0)), WHITE, 0.8)
    c.save(path("item_card.png"))


def socket():
    S = 160
    c = Canvas(S, 3)
    R = 32
    c.fill(c.rrect((0, 0, S, S), R), INK)
    body = c.rrect((5, 5, S - 5, S - 5), R - 5)
    c.vgrad(body, (0, 0, S, S), CREAM_3, CREAM_2)
    stripes(c, body, (0, 0, S, S), (222, 206, 184, 255), 0.4, 24, 8)
    inner_shadow(c, body, (5, 5, S - 5, S - 5), R - 5, 9, 0.28)
    c.save(path("socket.png"))


def chunky_button(name, top, base, lip, w=468, h=120, r=34):
    """Flat cartoon button: ink outline, solid darker lip, flat face, thin highlight."""
    c = Canvas(w, 3, h=h)
    OW = 5
    c.fill(c.rrect((0, 0, w, h), r + 2), INK)
    c.fill(c.rrect((OW, OW + 8, w - OW, h - OW), r - 3), lip)
    face_box = (OW, OW, w - OW, h - OW - 12)
    face = c.rrect(face_box, r - 3)
    c.vgrad(face, face_box, top, base)
    # thin highlight just inside the top edge, and a soft one at the left
    c.fill(c.mask_and(c.mask_sub(face, c.shift(face, 0, 6)), c.rrect((0, 0, w, h * 0.5), 0)), WHITE, 0.45)
    c.save(path(name))


def close_button():
    S = 128
    c = Canvas(S, 3)
    c.fill(c.ellipse((0, 0, S, S)), INK)
    c.fill(c.ellipse((5, 13, S - 5, S - 5)), (158, 40, 52, 255))
    face_box = (5, 5, S - 5, S - 15)
    face = c.ellipse(face_box)
    c.vgrad(face, face_box, (255, 120, 118, 255), (232, 76, 84, 255))
    c.fill(c.mask_and(c.mask_sub(face, c.shift(face, 0, 6)), c.rrect((0, 0, S, 60), 0)), WHITE, 0.5)
    c.save(path("btn_close.png"))


def search_field():
    w, h, r = 600, 100, 46
    c = Canvas(w, 3, h=h)
    c.fill(c.rrect((0, 0, w, h), r), INK)
    box = (5, 5, w - 5, h - 5)
    body = c.rrect(box, r - 5)
    c.fill(body, WHITE)
    inner_shadow(c, body, box, r - 5, 8, 0.20)
    c.save(path("search.png"))


def dropdown():
    w, h, r = 336, 400, 30
    c = Canvas(w, 3, h=h)
    c.fill(c.rrect((0, 0, w, h), r), INK)
    body = c.rrect((5, 5, w - 5, h - 5), r - 5)
    c.vgrad(body, (0, 0, w, h), CREAM, CREAM_2)
    stripes(c, body, (0, 0, w, h), CREAM_3, 0.35, 28, 10)
    c.save(path("dropdown.png"))


def option_row():
    w, h, r = 456, 100, 30
    c = Canvas(w, 3, h=h)
    c.fill(c.rrect((0, 0, w, h), r), INK)
    c.fill(c.rrect((4, 12, w - 4, h - 4), r - 3), TEAL_D)
    face_box = (4, 4, w - 4, h - 14)
    face = c.rrect(face_box, r - 3)
    c.vgrad(face, face_box, TEAL_L, TEAL)
    c.fill(c.mask_and(c.mask_sub(face, c.shift(face, 0, 5)), c.rrect((0, 0, w, h * 0.5), 0)), WHITE, 0.4)
    c.save(path("option.png"))


window()
window_shadow()
item_card()
socket()
chunky_button("btn_green.png", (132, 220, 100, 255), (96, 190, 72, 255), (52, 124, 40, 255))
chunky_button("btn_red.png", (255, 120, 118, 255), (232, 76, 84, 255), (158, 40, 52, 255))
chunky_button("btn_gold.png", (255, 204, 92, 255), (246, 168, 48, 255), (176, 104, 20, 255))
chunky_button("btn_blue.png", TEAL_L, TEAL, TEAL_D)
close_button()
search_field()
dropdown()
option_row()
print("saved to", OUT)
