"""World 1 gathered material icons (2026-10-19): crop each raw render of w1_gather_icons.html (raw/mat_<Id>.png,
made by ../ui/svg_render.py) to its outline and fit the longer side to 464 px centred on 512, like the other
material icons (finish_materials.py), into art/icons/materials/, then build sheet_w1_gather.png with each icon on
its rarity tile for review.
Usage: py finish_w1_gather.py"""
import os
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(ART, "icons", "materials")
TILES = os.path.join(ART, "ui", "inventory")
ICONS = [("OakLog", "common"), ("Stone", "common"), ("Minnow", "common"), ("Sunfish", "uncommon"), ("GoldenCarp", "rare")]


def fit(src, dst, side=512, inner=464):
    im = Image.open(src).convert("RGBA")
    im = im.crop(im.getchannel("A").getbbox())
    k = inner / max(im.size)
    im = im.resize((round(im.width * k), round(im.height * k)), Image.LANCZOS)
    out = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    out.alpha_composite(im, ((side - im.width) // 2, (side - im.height) // 2))
    out.save(dst)
    return out


if __name__ == "__main__":
    cell, gap = 220, 16
    sheet = Image.new("RGBA", (len(ICONS) * (cell + gap) + gap, cell + 2 * gap), (196, 232, 238, 255))
    for i, (name, rarity) in enumerate(ICONS):
        icon = fit(os.path.join(HERE, "raw", "mat_%s.png" % name), os.path.join(OUT, name + ".png"))
        x = gap + i * (cell + gap)
        tile = os.path.join(TILES, "tile_%s.png" % rarity)
        if os.path.exists(tile):
            sheet.alpha_composite(Image.open(tile).convert("RGBA").resize((cell, cell), Image.LANCZOS), (x, gap))
        pad = cell // 9
        sheet.alpha_composite(icon.resize((cell - 2 * pad, cell - 2 * pad), Image.LANCZOS), (x + pad, gap + pad))
    sheet.save(os.path.join(HERE, "sheet_w1_gather.png"))
    print("saved", len(ICONS), "icons and sheet_w1_gather.png")
