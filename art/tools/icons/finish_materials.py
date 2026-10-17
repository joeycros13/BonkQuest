"""World 2 material icons v2 (2026-10-17): crop each raw SVG render (raw/mat_<Id>_v2.png from mat_w2_v2.html via
svg_render.py) to its outline and fit the longer side to 464 px centred on 512, like the uploaded material icons,
then build before_after.png: every World 2 icon that was checked, current (left) and new (right)."""
import os
from PIL import Image, ImageDraw
HERE = os.path.dirname(os.path.abspath(__file__))
WT = r"C:\FirstRobloxGame\.claude\worktrees"
LL = os.path.join(WT, "laughing-lovelace-33026c", "art", "icons")
INV = os.path.join(WT, "roblox-studio-connection-d93d59", "art", "inventory_v3")

def fit(src, dst, side=512, inner=464):
    im = Image.open(src).convert("RGBA")
    im = im.crop(im.getchannel("A").getbbox())
    k = inner / max(im.size)
    im = im.resize((round(im.width * k), round(im.height * k)), Image.LANCZOS)
    out = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    out.alpha_composite(im, ((side - im.width) // 2, (side - im.height) // 2))
    out.save(dst)
    return out

for n in ("FoxFur", "BearClaw"):
    fit(os.path.join(HERE, "raw", "mat_%s_v2.png" % n), os.path.join(HERE, "%s.png" % n))

ROWS = [  # name, tile (None = plain), before, after, verdict
    ("Greatclub", "tile_epic.png", os.path.join(LL, "weapons", "Greatclub.png"), "Greatclub.png", "re-render"),
    ("Fox Fur", None, os.path.join(LL, "materials", "FoxFur.png"), "FoxFur.png", "redraw"),
    ("Bear Claw", None, os.path.join(LL, "materials", "BearClaw.png"), "BearClaw.png", "redraw"),
    ("Hatchet", "tile_common.png", os.path.join(LL, "weapons", "Hatchet.png"), "Hatchet.png", "optional"),
    ("Woodsman's Axe", "tile_epic.png", os.path.join(LL, "weapons", "WoodsmansAxe.png"), "WoodsmansAxe.png", "optional"),
    ("Cleaver", "tile_uncommon.png", os.path.join(LL, "weapons", "Cleaver.png"), "Cleaver.png", "same"),
    ("Quarterstaff", "tile_uncommon.png", os.path.join(LL, "weapons", "Quarterstaff.png"), "Quarterstaff.png", "same"),
    ("Mace", "tile_rare.png", os.path.join(LL, "weapons", "Mace.png"), "Mace.png", "same"),
    ("Heartwood Staff", "tile_legendary.png", os.path.join(LL, "weapons", "HeartwoodStaff.png"), "HeartwoodStaff.png", "same"),
    ("Lantern Flail", "tile_legendary.png", os.path.join(LL, "weapons", "LanternFlail.png"), "LanternFlail.png", "same"),
    ("Marshmallow Stick", "tile_secret_b_smooth.png", os.path.join(LL, "weapons", "MarshmallowStick.png"), "MarshmallowStick.png", "same"),
]
CELL, GAP, COLS = 220, 16, 3
pair_w = CELL * 2 + GAP * 3
W = COLS * pair_w + GAP
H = ((len(ROWS) + COLS - 1) // COLS) * (CELL + 40 + GAP) + GAP
sheet = Image.new("RGBA", (W, H), (38, 40, 48, 255))
d = ImageDraw.Draw(sheet)
for i, (name, tile, before, after, verdict) in enumerate(ROWS):
    x = GAP + (i % COLS) * pair_w; y = GAP + (i // COLS) * (CELL + 40 + GAP)
    d.text((x, y), "%s  -  %s   (left: now, right: new)" % (name, verdict), fill=(235, 235, 240, 255))
    for j, p in enumerate((before, os.path.join(HERE, after))):
        cx = x + j * (CELL + GAP)
        cell = Image.new("RGBA", (CELL, CELL), (60, 64, 76, 255) if not tile else (0, 0, 0, 0))
        if tile: cell.alpha_composite(Image.open(os.path.join(INV, tile)).convert("RGBA").resize((CELL, CELL), Image.LANCZOS))
        pad = CELL // 14
        cell.alpha_composite(Image.open(p).convert("RGBA").resize((CELL - 2 * pad, CELL - 2 * pad), Image.LANCZOS), (pad, pad))
        sheet.alpha_composite(cell, (cx, y + 20))
sheet.save(os.path.join(HERE, "before_after.png"))
print("saved before_after.png")
