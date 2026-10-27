"""Weapon icon finishing pass (2026-10-27): the same finish as tool_icons.py for cel-shaded weapon renders from the
Blender icon scripts (w1_icons_rerender / w2_icons_rerender / w3_icons_rerender, render(id)). Crops each raw render
to a square, adds the chunky ink outline and a soft shadow down and to the right, saves 512 px icons to
art/icons/weapons, and writes a review sheet: each icon on its rarity tile, with the current icon above it when one
exists (raws and sheets stay out of art/: pass their folders).
Usage: py weapon_icons_finish.py RAW_DIR SHEET_PATH Id[:rarity] ...
"""
import os, sys
from PIL import Image, ImageFilter, ImageChops

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.dirname(os.path.dirname(HERE))
TILES = os.path.join(ART, "ui", "inventory")
OUT = os.path.join(ART, "icons", "weapons")
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


def finish(raw):
    img = Image.open(raw).convert("RGBA")
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
    return out.resize((FINAL, FINAL), Image.LANCZOS)


def on_tile(icon, rarity, cell):
    tile = Image.open(os.path.join(TILES, "tile_%s.png" % rarity)).convert("RGBA").resize((cell, cell), Image.LANCZOS)
    tile.alpha_composite(icon.resize((int(cell * 0.92), int(cell * 0.92)), Image.LANCZOS), (int(cell * 0.04), int(cell * 0.04)))
    return tile


def main(raw_dir, sheet_path, specs):
    cell, pad = 200, 12
    rows = []
    for spec in specs:
        wid, rarity = (spec.split(":") + ["common"])[:2]
        old = os.path.join(OUT, wid + ".png")
        before = Image.open(old).convert("RGBA") if os.path.exists(old) else None
        icon = finish(os.path.join(raw_dir, wid + ".png"))
        icon.save(os.path.join(OUT, wid + ".png"))
        rows.append((wid, rarity, before, icon))
    sheet = Image.new("RGBA", (pad + len(rows) * (cell + pad), pad * 3 + cell * 2), (196, 232, 238, 255))
    for i, (wid, rarity, before, icon) in enumerate(rows):
        x = pad + i * (cell + pad)
        if before is not None:
            sheet.alpha_composite(on_tile(before, rarity, cell), (x, pad))
        sheet.alpha_composite(on_tile(icon, rarity, cell), (x, pad * 2 + cell))
    sheet.save(sheet_path)
    print("wrote", len(rows), "icons; sheet", sheet_path)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], sys.argv[3:])
