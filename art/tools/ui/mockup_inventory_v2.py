"""Compose a rough mock-up of the themed Inventory (for review only)."""
import os, sys
from PIL import Image, ImageDraw, ImageFont
D = os.path.join(os.path.dirname(os.path.abspath(__file__)), "inventory_v2")
W, H = 1368, 800
scene = Image.new("RGBA", (W + 160, H + 160), (110, 170, 90, 255))
ImageDraw.Draw(scene).rectangle([0, (H + 160) // 2, W + 160, H + 160], fill=(200, 196, 190, 255))
def put(name, box):
    x0, y0, x1, y1 = [int(v) for v in box]
    im = Image.open(os.path.join(D, name)).resize((x1 - x0, y1 - y0), Image.LANCZOS)
    scene.alpha_composite(im, (x0 + 80, y0 + 80))
put("window_shadow.png", (0, 14, W, H + 14))
put("window_bg.png", (0, 0, W, H))
# top bar
put("btn_blue.png", (W * 0.405, 100 * 0.17, W * 0.595, 100 * 0.83))
put("search.png", (W * 0.615, 100 * 0.17, W * 0.905, 100 * 0.83))
put("btn_close.png", (W * 0.985 - 62, 19, W * 0.985, 81))
# sockets
for y in (0.07, 0.37, 0.67):
    x0, y0 = 547 * 0.035, 100 + 604 * y
    put("socket.png", (x0, y0, x0 + 122, y0 + 122))
# items: 5 per row
for i in range(6):
    col, row = i % 5, i // 5
    x0 = 556 + 14 + col * 158
    y0 = 100 + 18 + row * 168
    put("item_card.png", (x0, y0, x0 + 148, y0 + 148))
# bottom
put("btn_gold.png", (W * 0.415, 704 + 96 * 0.18, W * 0.595, 704 + 96 * 0.84))
put("btn_green.png", (W * 0.605, 704 + 96 * 0.18, W * 0.785, 704 + 96 * 0.84))
put("btn_red.png", (W * 0.795, 704 + 96 * 0.18, W * 0.975, 704 + 96 * 0.84))
scene.save(sys.argv[1])
print("ok")
