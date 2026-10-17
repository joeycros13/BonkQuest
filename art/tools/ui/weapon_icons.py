"""DiceBattles weapon icons (2026-10-09): the hotbar and Inventory pictures.

The raw pictures are cel-shaded renders of the real weapon meshes from Blender
(art/meshes/plants.blend, scene "Icons", text block "icon_render": toon
materials per colour, Freestyle ink lines, an orthographic camera laying each
weapon diagonally, tip to the top right). This script finishes them:
  * crops each to a square with a small margin,
  * adds a chunky ink outline around the whole silhouette,
  * adds a soft shadow down and to the right, so the weapon lifts off the tile.
It also makes a review sheet with every icon on its rarity tile.
Usage: python weapon_icons.py
"""
import os

from PIL import Image, ImageFilter, ImageChops

HERE = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.join(HERE, "icons", "weapons", "raw")
OUT = os.path.join(HERE, "icons", "weapons")
TILES = os.path.join(HERE, "inventory_v3")
WEAPONS = ["Dagger", "Sickle", "Machete", "Shovel", "Pitchfork", "Scythe", "CornCob", "WeathervaneSpear", "PumpkinMace"]
RARITY = {"Dagger": "common", "Sickle": "common", "Machete": "uncommon", "Shovel": "rare",
          "Pitchfork": "uncommon", "Scythe": "epic", "CornCob": "secret_b_smooth",
          "WeathervaneSpear": "legendary", "PumpkinMace": "legendary"}
INK = (22, 18, 28)
WORK = 1024
FINAL = 512
OUTLINE = 22       # px at WORK size
SHADOW = (14, 20)  # offset at WORK size
MARGIN = 0.06


def dilate(mask, px):
    # MaxFilter in a few passes (it needs odd sizes); round the corners with a blur
    out = mask
    left = px
    while left > 0:
        step = min(left, 6)
        out = out.filter(ImageFilter.MaxFilter(step * 2 + 1))
        left -= step
    out = out.filter(ImageFilter.GaussianBlur(1.5))
    return out.point(lambda v: 255 if v > 100 else int(v * 2.55))


def finish(name):
    img = Image.open(os.path.join(RAW, name + ".png")).convert("RGBA")
    box = img.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox()
    img = img.crop(box)
    side = int(max(img.size) / (1 - 2 * MARGIN - 2 * OUTLINE / WORK))
    sq = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    sq.paste(img, ((side - img.width) // 2, (side - img.height) // 2))
    sq = sq.resize((WORK, WORK), Image.LANCZOS)

    alpha = sq.getchannel("A")
    ring = dilate(alpha, OUTLINE)
    out = Image.new("RGBA", (WORK, WORK), (0, 0, 0, 0))
    # soft shadow under everything, down and to the right
    shadow = Image.new("RGBA", (WORK, WORK), INK + (0,))
    shadow.putalpha(ring.point(lambda v: int(v * 0.45)))
    shadow = ImageChops.offset(shadow, *SHADOW).filter(ImageFilter.GaussianBlur(6))
    out.alpha_composite(shadow)
    ink = Image.new("RGBA", (WORK, WORK), INK + (0,))
    ink.putalpha(ring)
    out.alpha_composite(ink)
    out.alpha_composite(sq)
    out = out.resize((FINAL, FINAL), Image.LANCZOS)
    out.save(os.path.join(OUT, name + ".png"))
    return out


def sheet(icons):
    cell = 220
    img = Image.new("RGBA", (cell * len(icons) + 20, cell + 20), (196, 232, 238, 255))
    for i, (name, icon) in enumerate(icons):
        tile_path = os.path.join(TILES, "tile_%s.png" % RARITY[name])
        x = 10 + i * cell
        if os.path.exists(tile_path):
            tile = Image.open(tile_path).convert("RGBA").resize((cell - 12, cell - 12), Image.LANCZOS)
            img.alpha_composite(tile, (x + 6, 16))
        ic = icon.resize((cell - 30, cell - 30), Image.LANCZOS)
        img.alpha_composite(ic, (x + 15, 22))
    img.save(os.path.join(OUT, "sheet.png"))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    done = [(w, finish(w)) for w in WEAPONS]
    sheet(done)
    print("saved", len(done), "icons and sheet.png")
