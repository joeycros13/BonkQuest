"""The glow behind the hotbar slot that holds what's in hand (issue 19, 2026-10-24: option A on
https://claude.ai/artifact/FuTgGJkyhMp9VuoZTzsyBW, the user: "more of a glow effect instead of a rim, like a
strong glow effect that comes from the edges").

A gold halo hugging a rounded square the shape of the slot's rarity tile, brightest right at the tile's
edge and fading out, with nothing inside (the tile covers it). In Studio it is each slot's
Content/Glow, GLOW_SCALE (2.4) x the slot, behind the Skin; HotbarUI shows and pulses it.

  py art/tools/ui/hotbar_glow.py      -> art/ui/hud/hotbar_glow.png (512)
"""
from PIL import Image, ImageDraw, ImageFilter, ImageChops
import os

SS = 1024                 # drawn at 2x, saved at 512
GLOW_SCALE = 2.4          # the image is this many slots wide (Content/Glow's Size)
TILE = 1.08               # the Skin is 1.08 of the slot
INNER = TILE / GLOW_SCALE # the tile's share of the image
RADIUS = 0.17             # the tile's corner radius, a share of its side

HALO = (255, 190, 30)     # wide outer haze
WARM = (255, 214, 70)     # the middle of the glow
EDGE = (255, 244, 180)    # the bright line right at the tile's edge


def rounded(side_share, grow=0):
    side = SS * side_share + 2 * grow
    r = SS * side_share * RADIUS + grow
    m = Image.new("L", (SS, SS), 0)
    x0 = (SS - side) / 2
    ImageDraw.Draw(m).rounded_rectangle((x0, x0, x0 + side, x0 + side), radius=r, fill=255)
    return m


def boosted(mask, blur, gain):
    soft = mask.filter(ImageFilter.GaussianBlur(blur))
    return soft.point(lambda v: min(255, int(v * gain)))


def layer(colour, alpha):
    out = Image.new("RGBA", (SS, SS), colour + (0,))
    out.putalpha(alpha)
    return out


tile = rounded(INNER)
img = Image.new("RGBA", (SS, SS), (0, 0, 0, 0))
img.alpha_composite(layer(HALO, boosted(rounded(INNER, 52), 105, 3.4)))
img.alpha_composite(layer(WARM, boosted(rounded(INNER, 26), 52, 3.0)))
img.alpha_composite(layer(EDGE, boosted(rounded(INNER, 10), 18, 2.6)))
# nothing inside the tile: keep only what lies outside a hair inside its edge
inside = rounded(INNER, -6)
a = ImageChops.subtract(img.getchannel("A"), inside)
img.putalpha(a)

out = os.path.join(os.path.dirname(__file__), "..", "..", "ui", "hud", "hotbar_glow.png")
img.resize((512, 512), Image.LANCZOS).save(os.path.normpath(out))
print("saved", os.path.normpath(out))
