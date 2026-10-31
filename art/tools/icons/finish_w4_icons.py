"""World 4 material, quest item and fish icons (2026-10-29): the same finishing as finish_w3_gather.py for the raw
renders of w4_icons.html and w4_gather_icons.html (raw/mat_<Id>.png, made by ../ui/svg_render.py): crop to the
outline, fit the longer side to 464 px centred on 512, into art/icons/materials/. A review sheet on the rarity tiles
only when asked (--sheet=<path>; art/ keeps live art only). The Desert Core is a Blender render, finished by
core_icons.py.
Usage: py finish_w4_icons.py [--sheet=<path>]"""
import os
import sys
from PIL import Image

from finish_w1_gather import fit, OUT, TILES, HERE

ICONS = [("JackalFang", "common"), ("MummyLinen", "uncommon"), ("GuardianBronze", "rare"), ("PharaohsGold", "epic"),
         ("SunstoneAmulet", "legendary"), ("CactusRib", "common"), ("Fossil", "common"), ("OldCoin", "uncommon"),
         ("GoldenScarab", "rare"), ("Pupfish", "common"), ("OasisKoi", "uncommon"), ("SandShark", "rare")]

if __name__ == "__main__":
    done = [(name, rarity, fit(os.path.join(HERE, "raw", "mat_%s.png" % name), os.path.join(OUT, name + ".png"))) for name, rarity in ICONS]
    for a in sys.argv[1:]:
        if a.startswith("--sheet="):
            cell, gap, cols = 220, 16, 6
            rows = (len(done) + cols - 1) // cols
            sheet = Image.new("RGBA", (cols * (cell + gap) + gap, rows * (cell + gap) + gap), (196, 232, 238, 255))
            for i, (name, rarity, icon) in enumerate(done):
                x, y = gap + (i % cols) * (cell + gap), gap + (i // cols) * (cell + gap)
                tile = os.path.join(TILES, "tile_%s.png" % rarity)
                if os.path.exists(tile):
                    sheet.alpha_composite(Image.open(tile).convert("RGBA").resize((cell, cell), Image.LANCZOS), (x, y))
                pad = cell // 9
                sheet.alpha_composite(icon.resize((cell - 2 * pad, cell - 2 * pad), Image.LANCZOS), (x + pad, y + pad))
            sheet.save(a.split("=", 1)[1])
    print("saved", len(done), "icons")
