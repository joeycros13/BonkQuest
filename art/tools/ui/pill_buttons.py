"""Chunky-pill button skins (2026-10-20, the user's pick: style A on
https://claude.ai/artifact/LqroedjkDQQnsskNtjbaDh).

Each skin is a 9-slice image, 400 x 136: a dark ink outline round a rounded face, the
face's bottom a darker lip (the button's thickness), a flat light band across the top
and the ink thicker at the bottom like a drop. In Studio: ScaleType Slice,
SliceCenter (68, 67, 332, 69): the corners are the whole height, so each end is a
semicircle; SliceScale = the skin's height at 1080 / 134 (Responsive scales it with the screen).

    py art/tools/ui/pill_buttons.py   ->  art/ui/buttons/pill_<name>.png + sheet.png
"""
from pathlib import Path
from PIL import Image, ImageDraw

W, H, S = 400, 136, 4                      # size and supersampling
INK = (43, 27, 61, 255)
OUT = Path(__file__).resolve().parents[2] / "ui" / "buttons"

# name: (face, lip)
SKINS = {
    "green": ((79, 207, 92), (44, 154, 62)),
    "teal": ((51, 191, 211), (26, 135, 152)),
    "gold": ((255, 201, 61), (224, 150, 28)),
    "red": ((255, 100, 100), (204, 61, 61)),
    "grey": ((207, 200, 189), (170, 161, 150)),
    "white": ((255, 255, 255), (220, 212, 199)),   # text fields (the Daily Rewards code box)
}

OUTLINE, DROP = 8, 10       # ink round the face; extra ink under it (the drop)
LIP = 18                    # the darker band at the face's bottom
BAND_TOP, BAND_H = 10, 10   # the light band across the top of the face
RADIUS = H // 2              # semicircle ends: the user's rule (2026-10-20)


def skin(face, lip):
    img = Image.new("RGBA", (W * S, H * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    s = lambda v: int(round(v * S))
    d.rounded_rectangle((0, 0, s(W) - 1, s(H) - 1), radius=s(RADIUS), fill=INK)
    fx0, fy0, fx1, fy1 = OUTLINE, OUTLINE, W - OUTLINE, H - OUTLINE - DROP
    r = (fy1 - fy0) / 2         # the face is a stadium too: semicircle ends
    # the lip is the face minus the face moved up by LIP (like an inset shadow), so it
    # follows the round ends as a crescent and the face stays one smooth shape
    face_mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(face_mask).rounded_rectangle((s(fx0), s(fy0), s(fx1), s(fy1)), radius=s(r), fill=255)
    top_mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(top_mask).rounded_rectangle((s(fx0), s(fy0 - LIP), s(fx1), s(fy1 - LIP)), radius=s(r), fill=255)
    from PIL import ImageChops
    img.paste(Image.new("RGBA", img.size, lip + (255,)), (0, 0), face_mask)
    img.paste(Image.new("RGBA", img.size, face + (255,)), (0, 0), ImageChops.multiply(face_mask, top_mask))
    # the light band: a thin pill inside the face's top, clear of the round ends
    band = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(band).rounded_rectangle(
        (s(fx0 + r * 0.9), s(fy0 + BAND_TOP - 4), s(fx1 - r * 0.9), s(fy0 + BAND_TOP - 4 + BAND_H)),
        radius=s(BAND_H / 2), fill=(255, 255, 255, 97))
    img = Image.alpha_composite(img, band)
    return img.resize((W, H), Image.LANCZOS)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    sheet = Image.new("RGBA", (W + 40, (H + 20) * len(SKINS) + 20), (255, 248, 236, 255))
    for i, (name, (face, lip)) in enumerate(SKINS.items()):
        im = skin(face, lip)
        im.save(OUT / f"pill_{name}.png")
        sheet.alpha_composite(im, (20, 20 + i * (H + 20)))
    sheet.save(OUT / "sheet.png")
    print("wrote", len(SKINS), "skins to", OUT)


if __name__ == "__main__":
    main()
