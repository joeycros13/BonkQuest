"""World 2 weapon icons (2026-10-11): the finishing pass of art/weapon_icons.py (in the
roblox-studio-connection worktree), for the cel-shaded raw renders made by the Blender text
block "icon_render_w2". Crops to a square, adds the chunky ink outline and a soft shadow down
and to the right, saves 512 px icons here, and builds a review sheet on the rarity tiles.
Usage: python weapon_icons_w2.py
"""
import os
from PIL import Image, ImageFilter, ImageChops

HERE = os.path.dirname(os.path.abspath(__file__))
OTHER = r"C:\FirstRobloxGame\.claude\worktrees\roblox-studio-connection-d93d59\art"
RAW = os.path.join(OTHER, "icons", "weapons", "raw")
TILES = os.path.join(OTHER, "inventory_v3")
OUT = os.path.join(HERE, "icons", "weapons")
WEAPONS = ["Hatchet", "Cleaver", "Quarterstaff", "Mace", "WoodsmansAxe", "Greatclub", "HeartwoodStaff", "LanternFlail", "MarshmallowStick"]
RARITY = {"Hatchet": "common", "Cleaver": "uncommon", "Quarterstaff": "uncommon", "Mace": "rare", "WoodsmansAxe": "epic",
          "Greatclub": "epic", "HeartwoodStaff": "legendary", "LanternFlail": "legendary", "MarshmallowStick": "secret_b_smooth"}
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
    out.save(os.path.join(OUT, name + ".png"))
    return out


def sheet(icons):
    cell = 220
    img = Image.new("RGBA", (cell * len(icons) + 20, cell + 20), (196, 232, 238, 255))
    for i, (name, icon) in enumerate(icons):
        x = 10 + i * cell
        tp = os.path.join(TILES, "tile_%s.png" % RARITY[name])
        if os.path.exists(tp):
            img.alpha_composite(Image.open(tp).convert("RGBA").resize((cell - 12, cell - 12), Image.LANCZOS), (x + 6, 16))
        img.alpha_composite(icon.resize((cell - 30, cell - 30), Image.LANCZOS), (x + 15, 22))
    img.save(os.path.join(OUT, "sheet_w2.png"))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    done = [(w, finish(w)) for w in WEAPONS]
    sheet(done)
    print("saved", len(done), "icons and sheet_w2.png")
