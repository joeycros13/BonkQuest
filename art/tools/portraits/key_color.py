# Keys a portrait capture shot on a flat green, blue or magenta screen to a transparent 512 px square.
#   python key_color.py <capture> <out.png> green|blue|magenta
# Pick the screen colour the model doesn't use (2026-10-17): the Corn Wraith's leaves are green (magenta
# screen), the Fairy has pink and green (blue screen), the Gem Mole has pink gems (green screen).
# Same thresholds as key.py: screen dominance > 90 -> transparent, 25..90 -> fade with the spill pulled out;
# trimmed to the model with a 12% margin.
import sys
from PIL import Image

src, dst, screen = sys.argv[1], sys.argv[2], sys.argv[3]

def dominance(r, g, b):
    if screen == "green":
        return g - max(r, b)
    if screen == "blue":
        return b - max(r, g)
    if screen == "magenta":
        return min(r, b) - g
    raise SystemExit("screen must be green, blue or magenta")

def despill(r, g, b):
    if screen == "green":
        return r, min(g, max(r, b)), b
    if screen == "blue":
        return r, g, min(b, max(r, g))
    cap = g + 40  # magenta spills into red and blue together
    return min(r, cap), g, min(b, cap)

im = Image.open(src).convert("RGBA")
w, h = im.size
px = im.load()
minx, miny, maxx, maxy = w, h, -1, -1
for y in range(h):
    for x in range(w):
        r, g, b, a = px[x, y]
        d = dominance(r, g, b)
        if d > 90:
            px[x, y] = (0, 0, 0, 0)
            continue
        if d > 25:
            t = (d - 25) / 65.0
            r2, g2, b2 = despill(r, g, b)
            px[x, y] = (r2, g2, b2, int(255 * (1 - t)))
        if px[x, y][3] > 40:
            minx, miny = min(minx, x), min(miny, y)
            maxx, maxy = max(maxx, x), max(maxy, y)
im = im.crop((minx, miny, maxx + 1, maxy + 1))
cw, ch = im.size
side = int(max(cw, ch) * 1.12)
out = Image.new("RGBA", (side, side), (0, 0, 0, 0))
out.paste(im, ((side - cw) // 2, (side - ch) // 2))
out = out.resize((512, 512), Image.LANCZOS)
out.save(dst)
print(dst, (minx, miny, maxx, maxy))
