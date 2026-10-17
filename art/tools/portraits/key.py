import sys
from PIL import Image
src, dst = sys.argv[1], sys.argv[2]
im = Image.open(src).convert("RGBA")
w, h = im.size
px = im.load()
minx, miny, maxx, maxy = w, h, -1, -1
for y in range(h):
    for x in range(w):
        r, g, b, a = px[x, y]
        d = g - max(r, b)
        if d > 90:
            px[x, y] = (0, 0, 0, 0)
            continue
        if d > 25:
            t = (d - 25) / 65.0
            g2 = max(r, b)
            px[x, y] = (r, g2, b, int(255 * (1 - t)))
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
