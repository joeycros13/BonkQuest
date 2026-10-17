"""Cartoon backpack icon for DiceBattles, v3: a three-quarter view.

The pack is turned a little so the front AND its right side panel show. Every
outline is a smooth curve (artkit.blob / stroke), and the shapes bulge: a
sagging flap, a puffy front pocket, padded shoulder straps curving round the
side, creases where the fabric bunches, a darker base panel and a side pocket.
Usage: python backpack_icon.py [out.png]     (v1 / v2 PNGs are kept beside it)
"""
import sys
from artkit import Canvas, spline

OUT = sys.argv[1] if len(sys.argv) > 1 else "backpack_icon.png"
c = Canvas(512, 3)

INK = (62, 34, 12, 255)
WHITE = (255, 255, 255, 255)
SHADOW = (60, 26, 4, 255)
BODY_L, BODY_D = (252, 176, 86, 255), (214, 116, 38, 255)
SIDE_L, SIDE_D = (214, 120, 42, 255), (164, 80, 22, 255)
BASE = (150, 74, 24, 255)
FLAP_L, FLAP_D = (238, 146, 60, 255), (190, 94, 28, 255)
STRAP_L, STRAP_D = (182, 102, 42, 255), (122, 60, 20, 255)
PAD = (210, 136, 70, 255)
TEAL_L, TEAL_D = (110, 222, 206, 255), (34, 146, 138, 255)
GOLD_L, GOLD_D = (255, 228, 118, 255), (210, 146, 28, 255)
STITCH = (255, 226, 176, 255)
OW = 9  # outline width


def outlined(mask, width=OW):
    c.fill(c.dilate(mask, width), INK)


def dashes(points, length=9, gap=8, width=4, color=STITCH, opacity=0.85, offset=(0, 0)):
    """Stitching: short dashes along a curve."""
    pts = spline(points, False, 24)
    acc, on, run = 0.0, True, [pts[0]]
    for a, b in zip(pts, pts[1:]):
        seg = ((b[0] - a[0]) ** 2 + (b[1] - a[1]) ** 2) ** 0.5
        acc += seg
        run.append(b)
        if acc >= (length if on else gap):
            if on and len(run) > 1:
                shifted = [(x + offset[0], y + offset[1]) for x, y in run]
                c.fill(c.stroke(shifted, width, smooth=False), color, opacity)
            on, acc, run = not on, 0.0, [b]


def crease(points, width=4, dark=0.35, light=0.25):
    """A fabric fold: a dark line with a light line just above it."""
    c.glow(c.stroke(points, width), SHADOW, 1.5, dark)
    c.glow(c.stroke([(x - 2, y - 3) for x, y in points], width - 1), WHITE, 1.5, light)


# ---------------- shapes ----------------
front_pts = [(250, 104), (334, 116), (362, 196), (370, 320), (358, 418), (302, 446), (250, 450),
             (196, 446), (144, 424), (130, 320), (134, 198), (160, 120)]
side_pts = [(334, 116), (374, 130), (410, 190), (424, 300), (416, 404), (392, 436), (358, 430),
            (370, 320), (362, 196)]
front = c.blob(front_pts)
side = c.blob(side_pts)
body = c.mask_or(front, side)

right_strap_line = [(368, 140), (440, 196), (458, 300), (444, 388), (404, 438)]
left_strap_line = [(166, 132), (124, 204), (112, 306), (122, 396), (150, 436)]
handle_line = [(212, 120), (218, 72), (250, 54), (282, 70), (290, 118)]

flap_pts = [(146, 176), (162, 126), (250, 106), (338, 120), (360, 174), (358, 236), (306, 264),
            (250, 272), (196, 264), (142, 238)]
flap = c.blob(flap_pts)
flap_edge = [(150, 232), (198, 258), (250, 264), (304, 258), (354, 230)]

pocket_pts = [(170, 330), (250, 318), (340, 326), (354, 372), (346, 420), (250, 434), (158, 420), (148, 372)]
pocket = c.blob(pocket_pts)
side_pocket = c.blob([(380, 334), (412, 324), (424, 380), (414, 426), (386, 432), (372, 384)])

# ---------------- ground shadow ----------------
c.glow(c.ellipse((132, 432, 440, 478)), SHADOW, 14, 0.35)

# ---------------- straps and handle (behind the body) ----------------
for line, width in ((right_strap_line, 34), (left_strap_line, 28)):
    strap = c.stroke(line, width)
    outlined(strap)
    c.hgrad(strap, (100, 0, 470, 512), STRAP_L, STRAP_D)
    # padding: a lighter centre stripe with stitching either side
    c.fill(c.stroke(line, width * 0.42), PAD, 0.55)
    dashes(line, 7, 7, 3, opacity=0.6)
handle = c.stroke(handle_line, 22)
outlined(handle)
c.vgrad(handle, (200, 46, 300, 130), STRAP_L, STRAP_D)
c.glow(c.stroke([(220, 80), (250, 62), (276, 74)], 6), WHITE, 2, 0.35)

# ---------------- body: side panel then front ----------------
outlined(body)
c.vgrad(side, (330, 110, 430, 450), SIDE_L, SIDE_D)
c.hgrad(side, (340, 0, 430, 512), (0, 0, 0, 0), (110, 50, 10, 255), 0.35)
# the seam where the front meets the side, and a crease down the side
c.fill(c.stroke([(336, 118), (362, 198), (370, 320), (358, 420)], 5), INK, 0.8)
crease([(398, 206), (408, 262), (410, 316)], 4, 0.30, 0.18)

c.vgrad(front, (130, 104, 370, 450), BODY_L, BODY_D)
c.hgrad(front, (230, 0, 372, 512), (0, 0, 0, 0), (170, 76, 20, 255), 0.40)
c.glow(c.blob([(150, 250), (178, 236), (190, 330), (176, 410), (152, 404), (144, 320)]), WHITE, 12, 0.30, clip=front)

# a darker base panel along the bottom, curving with the bag
base = c.mask_and(body, c.blob([(110, 410), (250, 428), (430, 398), (430, 500), (110, 500)]))
c.vgrad(base, (110, 400, 430, 460), BASE, (110, 50, 14, 255))
c.fill(c.stroke([(140, 418), (200, 432), (250, 436), (304, 432), (360, 412), (392, 422), (414, 404)], 4), INK, 0.6)
dashes([(150, 426), (200, 440), (250, 443), (300, 440), (352, 424)], 8, 8, 3, opacity=0.55)

# baggy creases on the front
crease([(150, 300), (166, 290), (184, 296)])
crease([(334, 296), (350, 304), (360, 318)])
crease([(176, 438), (196, 424), (214, 420)], 4, 0.3, 0.15)

# side pocket
c.glow(c.shift(side_pocket, -3, 6), SHADOW, 5, 0.4, clip=side)
outlined(side_pocket, 7)
c.vgrad(side_pocket, (370, 320, 426, 434), TEAL_L, TEAL_D)
c.glow(c.blob([(386, 344), (400, 340), (402, 396), (390, 404)]), WHITE, 4, 0.35, clip=side_pocket)
c.fill(c.stroke([(380, 340), (412, 330)], 5), (24, 96, 92, 255))

# ---------------- flap ----------------
c.glow(c.shift(flap, 0, 14), SHADOW, 8, 0.5, clip=body)
outlined(flap)
c.vgrad(flap, (140, 104, 362, 272), FLAP_L, FLAP_D)
c.hgrad(flap, (240, 0, 362, 512), (0, 0, 0, 0), (140, 60, 14, 255), 0.35)
c.glow(c.blob([(176, 140), (250, 122), (326, 136), (316, 154), (250, 144), (184, 158)]), WHITE, 5, 0.45, clip=flap)
dashes(flap_edge, offset=(0, -12))
crease([(190, 200), (214, 214), (236, 218)], 3, 0.25, 0.18)
crease([(290, 216), (312, 206), (330, 190)], 3, 0.25, 0.18)

# centre strap and buckle
strap_mid = c.stroke([(250, 236), (251, 266), (252, 300)], 34)
c.glow(c.shift(strap_mid, 0, 8), SHADOW, 4, 0.4, clip=body)
outlined(strap_mid, 7)
c.hgrad(strap_mid, (232, 0, 270, 512), STRAP_L, STRAP_D)
dashes([(240, 244), (241, 288)], 6, 6, 3, opacity=0.6)
dashes([(262, 244), (263, 288)], 6, 6, 3, opacity=0.6)
buckle = c.rrect((219, 276, 287, 326), 15)
c.glow(c.shift(buckle, 0, 7), SHADOW, 4, 0.45, clip=body)
outlined(buckle, 7)
c.vgrad(buckle, (219, 276, 287, 326), GOLD_L, GOLD_D)
c.glow(c.rrect((226, 280, 280, 292), 6), WHITE, 2, 0.6, clip=buckle)
c.fill(c.rrect((244, 290, 262, 314), 5), INK)
c.fill(c.rrect((250, 284, 256, 320), 3), (150, 96, 20, 255))

# ---------------- front pocket ----------------
c.glow(c.shift(pocket, 0, 12), SHADOW, 8, 0.5, clip=body)
outlined(pocket)
c.vgrad(pocket, (148, 318, 354, 434), TEAL_L, TEAL_D)
c.hgrad(pocket, (250, 0, 356, 512), (0, 0, 0, 0), (16, 84, 80, 255), 0.40)
c.glow(c.blob([(170, 362), (190, 352), (196, 400), (178, 412), (166, 396)]), WHITE, 7, 0.45, clip=pocket)
# zip across the puffy top, with teeth
zip_line = [(172, 344), (250, 334), (334, 340)]
c.fill(c.stroke(zip_line, 11), (22, 92, 88, 255))
dashes(zip_line, 3, 4, 6, color=(150, 222, 212, 255), opacity=0.9)
dashes([(172, 414), (250, 424), (332, 414)], 9, 8, 4, color=(206, 255, 248, 255), opacity=0.7)
crease([(196, 404), (220, 398), (240, 402)], 3, 0.25, 0.15)
# zip pull hanging from a short tab
pull = c.rrect((310, 344, 330, 380), 7)
c.fill(c.stroke([(318, 338), (320, 350)], 6), (120, 84, 20, 255))
outlined(pull, 6)
c.vgrad(pull, (310, 344, 330, 380), GOLD_L, GOLD_D)
c.glow(c.rrect((314, 348, 326, 356), 3), WHITE, 1.5, 0.6, clip=pull)

c.save(OUT)
print("saved", OUT)
