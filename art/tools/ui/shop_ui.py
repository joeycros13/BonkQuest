"""DiceBattles Weapons Shop skins (the "Counter list" layout picked on the
Claude Design canvas, 2026-10-07), in the Inventory v3 style.

  shop_bg.png      the window (1280x720): aqua glass, diamonds, cyan header,
                   the list panel
  shop_row.png     one row's background: white glass with a soft lip
  btn_locked.png   grey lip button (can't afford it yet)
  btn_owned.png    flat pale button (already owned)
  icon_speed.png   white lightning (speed chip)
  icon_reach.png   white double arrow (reach chip)
The rarity tiles, green Buy button, close button, coin and sword are reused
from the Inventory.
Usage: python shop_ui.py [out_dir]     (default: ./shop)
"""
import os
import sys

from artkit import Canvas
from inventory_ui_v3 import (HEADER_BOT, HEADER_TOP, PANEL_EDGE, RIM, WHITE, AQUA_BOT, AQUA_TOP,
                             lip_tile, pattern_diamonds)

OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "shop")
os.makedirs(OUT, exist_ok=True)
CLEAR = (0, 0, 0, 0)


def path(name):
    return os.path.join(OUT, name)


def shop_bg():
    W, H = 1280, 720
    c = Canvas(W, 2, h=H)
    R = 40
    c.fill(c.rrect((0, 0, W, H), R), RIM, 0.95)
    body_box = (5, 5, W - 5, H - 14)
    body = c.rrect(body_box, R - 5)
    c.vgrad(body, body_box, AQUA_TOP, AQUA_BOT)
    c.radial(body, (220, 240), 480, (255, 255, 255, 120), CLEAR)
    pattern_diamonds(c, body, (0, 0, W, H), WHITE, 0.45, 44, 5)
    header = c.mask_and(body, c.rrect((0, 0, W, 96), 0))
    c.vgrad(header, (0, 0, W, 96), HEADER_TOP, HEADER_BOT)
    pattern_diamonds(c, header, (0, 0, W, 96), WHITE, 0.10, 36, 5)
    c.radial(header, (280, 18), 340, (255, 255, 255, 70), CLEAR)
    c.fill(c.mask_and(body, c.rrect((0, 90, W, 100), 0)), (6, 124, 146, 255))
    lb = (28, 120, 1252, 692)
    c.fill(c.rrect(lb, 28), PANEL_EDGE)
    inner = c.rrect((32, 124, 1248, 688), 25)
    c.vgrad(inner, lb, (186, 234, 240, 220), (168, 224, 232, 230))
    c.save(path("shop_bg.png"))


def shop_row():
    w, h = 1184, 88
    c = Canvas(w, 2, h=h)
    c.fill(c.rrect((0, 6, w, h), 22), (166, 216, 223, 255))
    face = c.rrect((0, 0, w, h - 6), 22)
    c.vgrad(face, (0, 0, w, h - 6), (255, 255, 255, 235), (240, 250, 252, 225))
    c.fill(c.mask_and(c.mask_sub(face, c.shift(face, 0, 4)), c.rrect((0, 0, w, 30), 0)), WHITE, 0.8)
    c.save(path("shop_row.png"))


def btn_locked():
    w, h = 348, 120
    c = Canvas(w, 3, h=h)
    face, fb = lip_tile(c, (0, 0, w, h), 32, (190, 198, 208, 255), (150, 160, 172, 255), (106, 116, 128, 255), 14)
    c.fill(c.mask_and(c.mask_sub(face, c.shift(face, 0, 5)), c.rrect((0, 0, w, h * 0.45), 0)), WHITE, 0.4)
    c.save(path("btn_locked.png"))


def btn_owned():
    w, h = 348, 120
    c = Canvas(w, 3, h=h)
    c.fill(c.rrect((0, 6, w, h), 32), (184, 216, 222, 255))
    c.fill(c.rrect((0, 0, w, h - 6), 32), (204, 230, 235, 255))
    c.save(path("btn_owned.png"))


def icon_speed():
    S = 128
    c = Canvas(S, 4)
    bolt = c.polygon([(72, 8), (24, 74), (58, 74), (50, 120), (104, 50), (70, 50)])
    c.fill(bolt, WHITE)
    c.save(path("icon_speed.png"))


def icon_reach():
    S = 128
    c = Canvas(S, 4)
    shaft = c.stroke([(18, 64), (110, 64)], 14, smooth=False)
    left = c.stroke([(42, 38), (16, 64), (42, 90)], 14, smooth=False)
    right = c.stroke([(86, 38), (112, 64), (86, 90)], 14, smooth=False)
    c.fill(c.mask_or(c.mask_or(shaft, left), right), WHITE)
    c.save(path("icon_reach.png"))


shop_bg()
shop_row()
btn_locked()
btn_owned()
icon_speed()
icon_reach()
print("saved", sorted(os.listdir(OUT)))
