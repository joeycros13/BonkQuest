"""World 3 (Crystal Caverns) top-down layout sketch for the user's approval, 2026-10-13.
World coordinates: x east, z (north = less negative). 1 stud = S px."""
from PIL import Image, ImageDraw, ImageFont
import math
S = 2.2
X0, X1, Z0, Z1 = 60, 640, -760, -410
W, H = int((X1 - X0) * S), int((Z1 - Z0) * S)
img = Image.new("RGB", (W, H + 70), (32, 30, 40))
d = ImageDraw.Draw(img)
try:
    F = ImageFont.truetype("arialbd.ttf", 22); f = ImageFont.truetype("arial.ttf", 16)
except Exception:
    F = f = None
def P(x, z): return ((x - X0) * S, (Z1 - z) * S)
def rect(x0, z0, x1, z1, fill, outline=None):
    a, b = P(x0, z1), P(x1, z0); d.rectangle([a, b], fill=fill, outline=outline, width=3)
def blob(cx, cz, rx, rz, fill):
    a, b = P(cx - rx, cz + rz), P(cx + rx, cz - rz); d.ellipse([a, b], fill=fill)
ROCK, FLOOR, PATH = (74, 70, 88), (112, 104, 128), (196, 178, 140)
# World 2 east edge + corridor
rect(60, -672, 138, -440, (46, 94, 43)); rect(97, -601, 138, -567, (70, 140, 60))
d.text(P(64, -450), "World 2", fill=(220, 240, 210), font=F)
blob(52 + 30, -584, 26, 26, (120, 120, 110))
d.text(P(64, -700), "boss arena", fill=(230, 230, 220), font=f)
# whole cave: rock mass under one ceiling
rect(138, -720, 620, -448, ROCK)
# entrance tunnel + mouth
rect(130, -598, 166, -570, FLOOR)
# halls
blob(210, -584, 48, 46, FLOOR)   # entry hall
blob(392, -584, 32, 34, FLOOR)   # middle hall
blob(568, -584, 44, 44, FLOOR)   # boss hall
# loop lanes (fork 1: x 250..360, fork 2: x 420..528)
def lane(xa, xb, bulge, sign):
    pts = []
    for i in range(161):
        t = i / 160
        x = xa + (xb - xa) * t
        z = -584 + sign * (34 + bulge * math.sin(math.pi * t))
        pts.append(P(x, z))
    r = 20 * S
    for (px, pz) in pts:
        d.ellipse([px - r, pz - r, px + r, pz + r], fill=FLOOR)
for xa, xb, bul in ((236, 376, 18), (408, 544, 18)):
    lane(xa, xb, bul, +1); lane(xa, xb, bul, -1)
# labels
def lab(x, z, t, font=f, c=(255, 255, 255)):
    tw = d.textlength(t, font=font); px, pz = P(x, z); d.text((px - tw / 2, pz - 9), t, fill=c, font=font)
lab(150, -560, "cave mouth", f, (255, 230, 140)); lab(150, -548, "(rock arch, W3 gate)", f, (255, 230, 140))
lab(210, -584, "ENTRY HALL", F); lab(210, -604, "spawn, stalls, altar", f)
lab(306, -584, "rock", f, (190, 185, 205)); lab(475, -584, "rock", f, (190, 185, 205))
lab(306, -540, "fork 1 north lane", f); lab(306, -628, "fork 1 south lane", f)
lab(392, -584, "MIDDLE HALL", F)
lab(475, -540, "fork 2 north lane", f); lab(475, -628, "fork 2 south lane", f)
lab(568, -584, "BOSS HALL", F); lab(568, -604, "boss arena", f)
# scale bar + note
d.line([(20, H + 30), (20 + 100 * S, H + 30)], fill=(255, 255, 255), width=4)
d.text((24, H + 38), "100 studs", fill=(255, 255, 255), font=f)
d.text((300, H + 18), "Lanes 40 wide, gentle curves, no paths. Rock ceiling ~28 above the floor over everything. East is right.", fill=(230, 230, 230), font=f)
img.save(__file__.replace(".py", ".png"))
