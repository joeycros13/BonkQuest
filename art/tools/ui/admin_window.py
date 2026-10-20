"""The admin panel's window, in the Inventory's look (2026-10-20, the user: "remodel the
admin panel to have the same look as the inventory").

Same 1368 x 800 aqua glass window, cyan header and diamond pattern as inventory_ui_v3's
window(), with the admin's own inset panels: a tall one for the tab column on the left
and a big one for the page content on the right.

Layout (window fractions, matching the Studio frames):
  header 0-0.135 | tabs panel x .0249-.1944 y .17-.94 | content panel x .2120-.9751 y .17-.94
Usage: py admin_window.py   ->  art/ui/admin/admin_window.png (+ the Inventory's shadow is reused)
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from artkit import Canvas  # noqa: E402
from inventory_ui_v3 import (AQUA_BOT, AQUA_TOP, CLEAR, HEADER_BOT, HEADER_TOP,  # noqa: E402
                             PANEL_EDGE, RIM, WHITE, pattern_diamonds)

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "ui", "admin")
os.makedirs(OUT, exist_ok=True)

W, H = 1368, 800
TABS = (34, 136, 266, 752)
CONTENT = (290, 136, 1334, 752)


def panel(c, box):
    """A rounded inset panel with a lighter edge, like the Inventory's items panel."""
    x0, y0, x1, y1 = box
    c.fill(c.rrect(box, 30), PANEL_EDGE)
    well = c.rrect((x0 + 4, y0 + 4, x1 - 4, y1 - 4), 27)
    c.vgrad(well, box, (190, 236, 242, 215), (170, 226, 234, 225))
    return well


def window():
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

    # the tab column, with a soft light on its top like the character panel
    tabs = panel(c, TABS)
    c.radial(tabs, (150, 260), 260, (255, 255, 255, 90), CLEAR)
    panel(c, CONTENT)
    c.save(os.path.join(OUT, "admin_window.png"))


if __name__ == "__main__":
    window()
    for name, box in (("tabs", TABS), ("content", CONTENT)):
        x0, y0, x1, y1 = box
        print(f"{name}: x {x0 / W:.4f}-{x1 / W:.4f}  y {y0 / H:.4f}-{y1 / H:.4f}")
    print("saved", OUT)
