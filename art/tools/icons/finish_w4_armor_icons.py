"""World 4's armour icons (2026-10-29): trims each raw render of w4_armor_icons.html (armor_<Id>.png, made by
../ui/svg_render.py) to its outline and centres it in a 512 square with a 6% margin, into art/icons/armor/<Id>.png,
the same finish as the coin sets' icons.
Usage: py finish_w4_armor_icons.py <raw dir>"""
import os
import sys
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "icons", "armor")
IDS = ["NomadWraps", "BoneWarden", "SunKing"]

if __name__ == "__main__":
    raw = sys.argv[1]
    for i in IDS:
        im = Image.open(os.path.join(raw, "armor_%s.png" % i)).convert("RGBA")
        im = im.crop(im.getbbox())
        side = int(max(im.size) / 0.88)
        sq = Image.new("RGBA", (side, side), (0, 0, 0, 0))
        sq.alpha_composite(im, ((side - im.width) // 2, (side - im.height) // 2))
        sq.resize((512, 512), Image.LANCZOS).save(os.path.join(OUT, i + ".png"))
        print("saved", i)
