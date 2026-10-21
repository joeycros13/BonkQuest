"""The Weaponsmith's upgrade-path arrow (2026-10-20, Tool Upgrade Recipes option C): a chunky teal arrow
with round caps (0c7084), drawn at 8x and scaled down for clean edges. Writes art/ui/shop/upgrade_arrow.png.
Usage: py upgrade_arrow.py"""
import os
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(os.path.dirname(HERE)), "ui", "shop", "upgrade_arrow.png")
S = 8
W, H = 136, 112
TEAL = (12, 112, 132, 255)
im = Image.new("RGBA", (W * S, H * S), (0, 0, 0, 0))
d = ImageDraw.Draw(im)
w = 20 * S
def line(a, b):
    d.line([(a[0] * S, a[1] * S), (b[0] * S, b[1] * S)], fill=TEAL, width=w)
    for p in (a, b):
        d.ellipse([p[0] * S - w / 2, p[1] * S - w / 2, p[0] * S + w / 2, p[1] * S + w / 2], fill=TEAL)
line((14, 56), (100, 56))
line((72, 20), (112, 56))
line((72, 92), (112, 56))
im = im.resize((W, H), Image.LANCZOS)
os.makedirs(os.path.dirname(OUT), exist_ok=True)
im.save(OUT)
print("saved", OUT)
