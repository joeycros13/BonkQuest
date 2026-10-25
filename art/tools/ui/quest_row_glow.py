"""The gold glow round a Weaponsmith tool row that a quest needs (issue 21, 2026-10-25; the user:
"the glow border should be the same shape as the entire tile").

The hotbar glow's look (hotbar_glow.py: a wide gold haze, a warm middle and a bright line right at
the edge, nothing inside), but cut from the row card's own outline (art/ui/shop/shop_row.png), so
its rim follows the card's rounded corners exactly. The card is stretched to the row (ScaleType
Stretch), and the upgrade rows are twice as tall, so their corners are taller ovals: one image per
row height, each drawn at the row's real proportions and shown Stretch in the row's `QuestGlow`
(sized GLOW_X x GLOW_Y of the row, printed below).

  py art/tools/ui/quest_row_glow.py   -> art/ui/shop/quest_glow_short.png, quest_glow_tall.png
"""
from PIL import Image, ImageChops, ImageFilter
import os

HERE = os.path.dirname(__file__)
CARD = os.path.normpath(os.path.join(HERE, "..", "..", "ui", "shop", "shop_row.png"))
OUT = os.path.normpath(os.path.join(HERE, "..", "..", "ui", "shop"))

ROW_W = 1641.0                  # a row's drawn size in Studio (any screen: the window keeps its shape)
ROWS = {"short": 112.8, "tall": 223.1}
MARGIN = 0.3 * ROWS["short"]    # the glow reaches this far past the card, the same on every row
SS = 2                          # drawn at 2x
SAVE_W = 1024                   # Roblox keeps images at most 1024 across

HALO = (255, 190, 30)
WARM = (255, 214, 70)
EDGE = (255, 244, 180)
# the hotbar glow's grow / blur amounts, scaled from its 296-px haze to this one's margin
K = MARGIN / 296.0


def card_mask(h):
    """The card's outline at the row's size, set in the glow image with MARGIN round it."""
    w_px, h_px = round(ROW_W * SS), round(h * SS)
    m = round(MARGIN * SS)
    card = Image.open(CARD).getchannel("A").resize((w_px, h_px), Image.LANCZOS)
    canvas = Image.new("L", (w_px + 2 * m, h_px + 2 * m), 0)
    canvas.paste(card, (m, m))
    return canvas


def grown(mask, px):
    px = max(1, round(px * SS))
    return mask.filter(ImageFilter.MaxFilter(px * 2 + 1)) if px > 0 else mask


def boosted(mask, blur, gain):
    soft = mask.filter(ImageFilter.GaussianBlur(blur * SS))
    return soft.point(lambda v: min(255, int(v * gain)))


def layer(size, colour, alpha):
    out = Image.new("RGBA", size, colour + (0,))
    out.putalpha(alpha)
    return out


for name, h in ROWS.items():
    card = card_mask(h)
    img = Image.new("RGBA", card.size, (0, 0, 0, 0))
    img.alpha_composite(layer(card.size, HALO, boosted(grown(card, 52 * K), 105 * K, 3.4)))
    img.alpha_composite(layer(card.size, WARM, boosted(grown(card, 26 * K), 52 * K, 3.0)))
    img.alpha_composite(layer(card.size, EDGE, boosted(grown(card, 10 * K), 18 * K, 2.6)))
    # nothing inside the card: keep only what lies outside a hair inside its edge
    inside = card.filter(ImageFilter.MinFilter(2 * SS + 1))
    img.putalpha(ImageChops.subtract(img.getchannel("A"), inside))
    w, hh = img.size
    save = img.resize((SAVE_W, round(hh * SAVE_W / w)), Image.LANCZOS)
    path = os.path.join(OUT, "quest_glow_%s.png" % name)
    save.save(path)
    print("saved", path, save.size, "GLOW_X %.4f GLOW_Y %.4f" % ((ROW_W + 2 * MARGIN) / ROW_W, (h + 2 * MARGIN) / h))
