"""The Gathering upgrade's icon (2026-10-28, the user: built like the pickaxe and axe icons): the
Wooden Pickaxe's and Wooden Axe's own drawn icons (art/icons/tools/, cel-shaded mesh renders) crossed,
the pickaxe mirrored behind and the axe in front, trimmed to 464 px in 512 like the other upgrade icons.
Usage: py gathering_icon.py [preview.png]
"""
import os, sys
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.dirname(os.path.dirname(HERE))
TOOLS = os.path.join(ART, "icons", "tools")
OUT = os.path.join(ART, "icons", "upgrades", "Gathering.png")

axe = Image.open(os.path.join(TOOLS, "WoodenAxe.png")).convert("RGBA")
pick = Image.open(os.path.join(TOOLS, "WoodenPickaxe.png")).convert("RGBA").transpose(Image.FLIP_LEFT_RIGHT)
S, k = 1024, 0.82
canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))
for icon, dx in ((pick, -60), (axe, 60)):
    big = icon.resize((int(S * k), int(S * k)), Image.LANCZOS)
    canvas.alpha_composite(big, ((S - big.width) // 2 + dx, (S - big.height) // 2))
canvas = canvas.crop(canvas.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox())
f = 464 / max(canvas.size)
canvas = canvas.resize((round(canvas.width * f), round(canvas.height * f)), Image.LANCZOS)
out = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
out.alpha_composite(canvas, ((512 - canvas.width) // 2, (512 - canvas.height) // 2))
out.save(OUT)
if len(sys.argv) > 1:
    bg = Image.new("RGBA", (330, 120), (255, 247, 233, 255))
    for i, s in enumerate((110, 64, 40)):
        bg.alpha_composite(out.resize((s, s), Image.LANCZOS), (8 + i * 120, (120 - s) // 2))
    bg.save(sys.argv[1])
print("wrote", OUT)
