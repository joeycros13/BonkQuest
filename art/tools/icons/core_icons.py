"""Bonk Quest secret-core icons (2026-10-13): the finishing pass for the raw renders made by the
Blender text block "shared_secretcores_icons" (the three mirrored quad cores, rendered to raw/).
Same recipe as art/weapon_icons.py in the roblox-studio-connection worktree: crop to a square, add
the chunky ink outline round the silhouette and a soft shadow down and to the right. Saves 512 px
icons as icon_<Id>.png here and a review sheet (core_icons_sheet.png) with every core on the Core
rarity's soil tile, at full size and at hotbar size.
Usage: python core_icons.py
"""
import os

from PIL import Image, ImageChops, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.join(HERE, "raw")
TILE = r"C:\FirstRobloxGame\.claude\worktrees\laughing-lovelace-33026c\art\cores\tile_core_soil.png"
CORES = ["FarmCore", "ForestCore", "CaveCore"]
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
    out.save(os.path.join(HERE, "icon_%s.png" % name))
    return out


def sheet(icons):
    cell, small = 220, 72
    img = Image.new("RGBA", (cell * len(icons) + 20 + len(icons) * small, cell + 20), (38, 40, 48, 255))
    tile = Image.open(TILE).convert("RGBA") if os.path.exists(TILE) else None
    for i, (_, icon) in enumerate(icons):
        x = 10 + i * cell
        if tile:
            img.alpha_composite(tile.resize((cell - 12, cell - 12), Image.LANCZOS), (x + 6, 16))
        img.alpha_composite(icon.resize((cell - 30, cell - 30), Image.LANCZOS), (x + 15, 22))
    # the same icons at hotbar size, to check they still read small
    for i, (_, icon) in enumerate(icons):
        x = 10 + len(icons) * cell + i * small
        if tile:
            img.alpha_composite(tile.resize((64, 64), Image.LANCZOS), (x, 90))
        img.alpha_composite(icon.resize((56, 56), Image.LANCZOS), (x + 4, 94))
    img.save(os.path.join(HERE, "core_icons_sheet.png"))


BLADES = ["WorldheartBlade", "WorldheartBlade2", "WorldheartBlade3"]   # tiers 1..3, re-rendered with the new gems
BLADE_TILE = r"C:\FirstRobloxGame\.claude\worktrees\laughing-lovelace-33026c\art\worldheart\tile_transcendent.png"


if __name__ == "__main__":
    done = [(c, finish(c)) for c in CORES]
    sheet(done)
    blades = [(b, finish(b)) for b in BLADES]
    TILE, keep = BLADE_TILE, os.path.join(HERE, "core_icons_sheet.png")
    os.replace(keep, keep + ".tmp")
    sheet(blades)
    os.replace(keep, os.path.join(HERE, "worldheart_icons_sheet.png"))
    os.replace(keep + ".tmp", keep)
    print("saved", len(done), "core icons,", len(blades), "blade icons and the two review sheets")
