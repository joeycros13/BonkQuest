"""DiceBattles World 3 weapon icon re-render (2026-10-17; copied from the 2026-10-16 W1 version): the finishing pass for the raw renders made by the Blender
text blocks "w1_icons_rerender" (the nine World 1 weapons, the Rusty Blade, the three Worldheart tiers)
and "shared_secretcores_icons" (the three cores), after the World 1 skill pass.
Same recipe as art/weapon_icons.py (roblox-studio-connection worktree): crop to a square, a chunky ink
outline round the silhouette and a soft shadow down and to the right. Saves 512 px icons next to this
script and compare.png: each item's current icon (top) over the new one (bottom), on its rarity tile,
with a hotbar-size copy of each beside it.
Usage: python finish_icons.py
"""
import os

from PIL import Image, ImageChops, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.join(HERE, "raw")
WT = r"C:\FirstRobloxGame\.claude\worktrees"
INV = os.path.join(WT, r"roblox-studio-connection-d93d59\art\inventory_v3")
OLD_W = os.path.join(WT, r"roblox-studio-connection-d93d59\art\icons\weapons")
OLD_C = os.path.join(WT, r"determined-cohen-dc5f35\art\cores")
LL = os.path.join(WT, r"laughing-lovelace-33026c\art")

OLD_W3 = os.path.join(WT, "roblox-studio-connection-d93d59", "art", "icons", "weapons")
ITEMS = [  # id, rarity tile, current (uploaded 2026-10-13) icon
    ("BatwingBlade", os.path.join(INV, "tile_common.png"), os.path.join(OLD_W3, "BatwingBlade.png")),
    ("IronPickaxe", os.path.join(INV, "tile_uncommon.png"), os.path.join(OLD_W3, "IronPickaxe.png")),
    ("PebbleMallet", os.path.join(INV, "tile_uncommon.png"), os.path.join(OLD_W3, "PebbleMallet.png")),
    ("GoldGauntlets", os.path.join(INV, "tile_rare.png"), os.path.join(OLD_W3, "GoldGauntlets.png")),
    ("GeodeGlaive", os.path.join(INV, "tile_epic.png"), os.path.join(OLD_W3, "GeodeGlaive.png")),
    ("EmberCoalMaul", os.path.join(INV, "tile_epic.png"), os.path.join(OLD_W3, "EmberCoalMaul.png")),
    ("QueensFang", os.path.join(INV, "tile_legendary.png"), os.path.join(OLD_W3, "QueensFang.png")),
    ("DiamondPickaxe", os.path.join(INV, "tile_legendary.png"), os.path.join(OLD_W3, "DiamondPickaxe.png")),
    ("RockCandyClub", os.path.join(INV, "tile_secret_b_smooth.png"), os.path.join(OLD_W3, "RockCandyClub.png")),
]
INK = (22, 18, 28)
WORK, FINAL, OUTLINE, SHADOW, MARGIN = 1024, 512, 22, (14, 20), 0.06


def dilate(mask, px):
    out, left = mask, px
    while left > 0:
        step = min(left, 6)
        out = out.filter(ImageFilter.MaxFilter(step * 2 + 1))
        left -= step
    out = out.filter(ImageFilter.GaussianBlur(1.5))
    return out.point(lambda v: 255 if v > 100 else int(v * 2.55))


def finish(name):
    img = Image.open(os.path.join(RAW, name + ".png")).convert("RGBA")
    img = img.crop(img.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox())
    side = int(max(img.size) / (1 - 2 * MARGIN - 2 * OUTLINE / WORK))
    sq = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    sq.paste(img, ((side - img.width) // 2, (side - img.height) // 2))
    sq = sq.resize((WORK, WORK), Image.LANCZOS)
    ring = dilate(sq.getchannel("A"), OUTLINE)
    out = Image.new("RGBA", (WORK, WORK), (0, 0, 0, 0))
    shadow = Image.new("RGBA", (WORK, WORK), INK + (0,))
    shadow.putalpha(ring.point(lambda v: int(v * 0.45)))
    out.alpha_composite(ImageChops.offset(shadow, *SHADOW).filter(ImageFilter.GaussianBlur(6)))
    ink = Image.new("RGBA", (WORK, WORK), INK + (0,))
    ink.putalpha(ring)
    out.alpha_composite(ink)
    out.alpha_composite(sq)
    out = out.resize((FINAL, FINAL), Image.LANCZOS)
    out.save(os.path.join(HERE, name + ".png"))
    return out


def on_tile(tile_path, icon, size):
    cell = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    if os.path.exists(tile_path):
        cell.alpha_composite(Image.open(tile_path).convert("RGBA").resize((size, size), Image.LANCZOS))
    pad = size // 14
    cell.alpha_composite(icon.resize((size - 2 * pad, size - 2 * pad), Image.LANCZOS), (pad, pad))
    return cell


def compare(rows):
    big, small, gap = 200, 64, 12
    col = big + small + 3 * gap
    per_row = 8
    lines = (len(rows) + per_row - 1) // per_row
    img = Image.new("RGBA", (per_row * col + gap, lines * (2 * big + 3 * gap + 26) + gap), (38, 40, 48, 255))
    d = ImageDraw.Draw(img)
    for i, (name, tile, old, new) in enumerate(rows):
        x = gap + (i % per_row) * col
        y = gap + (i // per_row) * (2 * big + 3 * gap + 26)
        d.text((x, y), name, fill=(235, 235, 240, 255))
        y += 16
        for j, icon in enumerate((old, new)):
            if icon is None:
                continue
            yy = y + j * (big + gap)
            img.alpha_composite(on_tile(tile, icon, big), (x, yy))
            img.alpha_composite(on_tile(tile, icon, small), (x + big + gap, yy + big - small))
    img.save(os.path.join(HERE, "compare.png"))


if __name__ == "__main__":
    rows = []
    for name, tile, old_path in ITEMS:
        new = finish(name)
        old = Image.open(old_path).convert("RGBA") if os.path.exists(old_path) else None
        rows.append((name, tile, old, new))
    compare(rows)
    print("saved", len(rows), "icons and compare.png (top: current, bottom: new)")
