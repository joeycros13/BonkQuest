"""World 4, The Scorching Sands: where its decorations and gathering nodes go (2026-10-26).

Reads the ground from build_ground.py (the 2-stud height field, the road and doorway lanes,
the pyramid, its towers and doorway approaches, the oasis and the volcano), all in World 4's
own unturned coordinates, and places the templates set up in ServerStorage by the rules the
other worlds were dressed by (the build-world skill):

  * nothing touches anything: every model is a set of circles at its foot (and, for the palms,
    at its crown), and two models' circles keep `GAP` apart; a crown only clashes with another
    crown or with something tall enough to reach it;
  * a whole foot stands on one level of sand, dune or oasis grass (never on the road, the
    oasis bed, the volcano, the rim or the pyramid), so nothing hangs off a step, with no
    higher ground within a stud of it (a leaning trunk or a plinth's corner ran into a mound's
    next step up);
  * clearances: off the road by kind (palm trunks 4, a crown 1, structures 3, cacti 2, small
    things 1.5), 4 off the pyramid, out of its doorway approaches and the flat sand round its
    towers, 1 off the rim (crowns too), 1 off open water (lotus pads only on it), 3 off the
    volcano, and clear of the corridor and spawn and of the west arm's end (the World 5 gate);
  * landmarks are placed first, by hand rules: a sphinx either side of the east lane facing it,
    obelisk pairs flanking the east and west lanes, two tombs with their doors to the road;
  * the gathering nodes go right off the road like World 2's redwoods (a saguaro's foot 4-6
    off it, a dig pile's 2-3.5), spread along the loop farthest-first, 35+ apart, facing it;
  * the rest farthest-first from their own kind (best of `TRIES` random spots), so they spread
    evenly; the oasis set stays by the water.

Writes art/tools/w4/decor_plan.json: one entry per model (template, its ServerStorage folder,
the world folder it goes in, its name, local x / y / z and yaw in degrees). A Studio script
turns local into world with build_ground's `place` transform.

Usage: python place_decor.py
"""
import json
import math
import os
import random

import build_ground as G

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "decor_plan.json")
TRIES = 60
GAP = 1.0
rng = random.Random(20261026)

boxes, water, cells, borders, samples, vr = G.build()
X0, Z1, C = -646, -818, G.CELL
PX, PZ, PH = G.PYRAMID


def cell_at(x, z):
    return cells.get((int((x - X0) // C), int((Z1 - z) // C)))


# the road's cells (path) as points for the distance test, bucketed
path_cells = [((X0 + C * i + 1), (Z1 - C * j - 1)) for (i, j), v in cells.items() if v[3] == "Path"]
rim_cells = [((X0 + C * i + 1), (Z1 - C * j - 1)) for (i, j), v in cells.items() if v[2] == "Rim"]
water_cells = [((X0 + C * i + 1), (Z1 - C * j - 1)) for (i, j), v in cells.items() if v[2] == "Oasis" and v[3] == "Bed"]
volcano_cells = [((X0 + C * i + 1), (Z1 - C * j - 1)) for (i, j), v in cells.items() if v[2] == "Volcano"]


def bucket(points, size=8):
    b = {}
    for (x, z) in points:
        b.setdefault((int(x // size), int(z // size)), []).append((x, z))
    return b


PB, RB, WB, VB = bucket(path_cells), bucket(rim_cells), bucket(water_cells), bucket(volcano_cells)


def dist_cells(b, x, z, reach=24, size=8):
    """Distance from (x, z) to the nearest 2-stud cell in bucket b (to the cell's edge), or reach."""
    best = reach
    r = int(reach // size) + 1
    bx, bz = int(x // size), int(z // size)
    for i in range(bx - r, bx + r + 1):
        for j in range(bz - r, bz + r + 1):
            for (cx, cz) in b.get((i, j), ()):
                dx = max(abs(x - cx) - 1, 0)
                dz = max(abs(z - cz) - 1, 0)
                d = math.hypot(dx, dz)
                if d < best:
                    best = d
    return best


def nearest_path(x, z, reach=40):
    best, bp = 1e9, None
    for (cx, cz) in path_cells:
        d = (cx - x) ** 2 + (cz - z) ** 2
        if d < best:
            best, bp = d, (cx, cz)
    return bp


# keep-outs (local boxes x0, x1, z0, z1)
d0, d1, aw = PH - 1, PH + G.PYR_APPROACH, G.PYR_APPROACH_HALF
KEEP = [
    (PX + d0, PX + d1, PZ - aw, PZ + aw), (PX - d1, PX - d0, PZ - aw, PZ + aw),
    (PX - aw, PX + aw, PZ + d0, PZ + d1), (PX - aw, PX + aw, PZ - d1, PZ - d0),
    (-240, -170, -1020, -956),          # the corridor, the gate's mouth and the spawn
    (-575, -500, -1222, -1150),         # the west arm's end: the World 5 gate is to go here
]
for sx in (-1, 1):
    for sz in (-1, 1):
        tx, tz = PX + sx * G.TOWER_OUT, PZ + sz * G.TOWER_OUT
        KEEP.append((tx - G.TOWER_CLEAR, tx + G.TOWER_CLEAR, tz - G.TOWER_CLEAR, tz + G.TOWER_CLEAR))


def in_keep(x, z, r):
    for (a, b, c, d) in KEEP:
        if a - r < x < b + r and c - r < z < d + r:
            return True
    return False


def box_circles(x0, x1, z0, z1, pad=0.0):
    """Circles covering a box (model frame): along its long axis, radius half its short side."""
    w, d = x1 - x0, z1 - z0
    if w >= d:
        r = d / 2 + pad
        n = max(1, math.ceil((w - d) / r) + 1)
        return [(x0 + d / 2 + (w - d) * (k / (n - 1) if n > 1 else 0.5), (z0 + z1) / 2, r) for k in range(n)]
    r = w / 2 + pad
    n = max(1, math.ceil((d - w) / r) + 1)
    return [((x0 + x1) / 2, z0 + w / 2 + (d - w) * (k / (n - 1) if n > 1 else 0.5), r) for k in range(n)]


# each template: foot circles (model frame, studs), its height, crown circles and the crown's
# lowest y, the road gap, where its foot may stand, and its folders
T = {
    "PalmTall":  dict(foot=[(0, 0, 1.6), (1.3, 0, 1.4), (2.6, 0, 1.3)], h=24, crown=[(3.1, -1.0, 8.6)], crown_y=20, road=4.0),
    "PalmTwin":  dict(foot=[(0, 0, 2.2), (-2.4, 0, 1.3), (3.0, 0, 1.3)], h=20, crown=[(-4.5, 0, 7.0), (4.5, 0, 7.0)], crown_y=13, road=4.0),
    "DatePalm":  dict(foot=[(0, 0, 1.5)], h=17, crown=[(0.9, -0.3, 7.4)], crown_y=14, road=4.0),
    "BarrelCactus": dict(foot=[(0.2, 0, 2.1), (-2.7, 0, 1.4), (3.0, 0.2, 1.4)], h=3.5, road=2.0),
    "PillarDrums": dict(foot=box_circles(-8.8, 8.9, -2.2, 3.1), h=4.8, road=3.0),
    "PillarStump": dict(foot=box_circles(-9.0, 8.5, -2.7, 5.6), h=9.9, road=3.0),
    "PillarLeaning": dict(foot=box_circles(-7.8, 7.9, -2.7, 2.7), h=11.6, road=3.0),
    "PillarRubble": dict(foot=box_circles(-6.0, 7.1, -2.8, 2.7), h=4.0, road=3.0),
    "Obelisk": dict(foot=[(0, 0, 4.6)], h=26.5, road=3.0),   # the plinth is 6.4 square (half diagonal 4.53)
    "Sphinx": dict(foot=box_circles(-5.2, 5.2, -10.5, 13.5), h=12.9, road=3.0),
    "Tomb": dict(foot=box_circles(-10.4, 10.4, -11.4, 12.4) + box_circles(10.0, 13.3, 0.0, 6.8), h=15.3, road=3.0),
    "Papyrus": dict(foot=box_circles(-3.9, 3.6, -2.2, 2.1), h=8.8, road=1.5),
    "WaterJars": dict(foot=box_circles(-3.2, 3.6, -1.4, 1.5), h=3.9, road=1.5),
    "LotusPads": dict(foot=box_circles(-3.4, 3.9, -4.2, 2.4), h=0.5, road=1.5, on_water=True),
    "Saguaro": dict(foot=box_circles(-4.7, 4.4, -2.1, 2.1), h=12, road=(4.0, 6.0)),
    "DigPile": dict(foot=[(0, 0, 2.6)], h=1.0, road=(2.0, 3.5)),
}
SOURCE = {"Saguaro": "Gathering", "DigPile": "Gathering"}
FOLDER = {
    "PalmTall": "Decorations/Palms/PalmTall", "PalmTwin": "Decorations/Palms/PalmTwin", "DatePalm": "Decorations/Palms/DatePalm",
    "BarrelCactus": "Decorations/Cacti", "PillarDrums": "Decorations/Ruins/Pillars", "PillarStump": "Decorations/Ruins/Pillars",
    "PillarLeaning": "Decorations/Ruins/Pillars", "PillarRubble": "Decorations/Ruins/Pillars", "Obelisk": "Decorations/Ruins/Obelisks",
    "Sphinx": "Decorations/Ruins/Sphinxes", "Tomb": "Structures/Tombs", "Papyrus": "Decorations/Oasis/Papyrus",
    "WaterJars": "Decorations/Oasis/WaterJars", "LotusPads": "Decorations/Oasis/LotusPads",
    "Saguaro": "Gathering", "DigPile": "Gathering",
}
FOOT_OK = {("Sand", "Sand"), ("Dunes", "Dune"), ("Oasis", "Grass")}

placed = []   # (template, x, z, yaw, world circles foot, world circles crown, h, crown_y, top)


def world_circles(circles, x, z, yaw):
    c, s = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
    # Roblox CFrame.Angles(0, yaw, 0): local (lx, lz) -> (lx cos + lz sin, -lx sin + lz cos)
    return [(x + lx * c + lz * s, z - lx * s + lz * c, r) for (lx, lz, r) in circles]


def ring(cx, cz, r, n=10):
    pts = [(cx, cz)]
    for k in range(n):
        a = 2 * math.pi * k / n
        pts.append((cx + r * math.cos(a), cz + r * math.sin(a)))
    return pts


def check(name, x, z, yaw):
    """None if `name` can stand at (x, z) turned yaw, else a reason. Returns (top) on success."""
    t = T[name]
    foot = world_circles(t["foot"], x, z, yaw)
    crown = world_circles(t.get("crown", []), x, z, yaw)
    top = None
    for (cx, cz, r) in foot:
        for (px, pz) in ring(cx, cz, r):
            v = cell_at(px, pz)
            if v is None:
                return "off"
            if t.get("on_water"):
                if not (v[2] == "Oasis" and v[3] == "Bed"):
                    return "not water"
                continue
            if (v[2], v[3]) not in FOOT_OK:
                return "ground " + v[3]
            if top is None:
                top = v[0]
            elif v[0] != top:
                return "uneven"
        # no higher ground (a mound's next step up) within a stud of the foot: a leaning trunk or
        # a square plinth's corner would run into it
        if not t.get("on_water"):
            for (px, pz) in ring(cx, cz, r + 1.0, 14):
                v = cell_at(px, pz)
                if v is not None and v[0] > top:
                    return "step up"
        if in_keep(cx, cz, r + 1):
            return "keep"
        # the pyramid's footprint, 4 off
        if abs(cx - PX) < PH + r + 4 and abs(cz - PZ) < PH + r + 4:
            return "pyramid"
        road = t["road"]
        d = dist_cells(PB, cx, cz) - r
        lo = road[0] if isinstance(road, tuple) else road
        if d < lo:
            return "road"
        if dist_cells(RB, cx, cz) - r < 1:
            return "rim"
        if not t.get("on_water") and dist_cells(WB, cx, cz) - r < 1:
            return "water"
        if dist_cells(VB, cx, cz) - r < 3:
            return "volcano"
    if isinstance(t["road"], tuple):
        # a node's nearest foot circle sits in its band off the road
        dmin = min(dist_cells(PB, cx, cz) - r for (cx, cz, r) in foot)
        if not (t["road"][0] <= dmin <= t["road"][1]):
            return "band"
    for (cx, cz, r) in crown:
        if dist_cells(PB, cx, cz) - r < 1:
            return "crown road"
        if dist_cells(RB, cx, cz) - r < 1:
            return "crown rim"
        if in_keep(cx, cz, r - 4):
            return "crown keep"
        if abs(cx - PX) < PH + r and abs(cz - PZ) < PH + r:
            return "crown pyramid"
    # other models
    for p in placed:
        _, ox, oz, _, pf, pc, ph_, pcy, _ = p
        if math.hypot(ox - x, oz - z) > 60:
            continue
        for (ax, az, ar) in foot:
            for (bx, bz, br) in pf:
                if math.hypot(ax - bx, az - bz) < ar + br + GAP:
                    return "touch"
            if t["h"] > pcy:
                for (bx, bz, br) in pc:
                    if math.hypot(ax - bx, az - bz) < ar + br + GAP:
                        return "touch crown"
        for (ax, az, ar) in crown:
            for (bx, bz, br) in pc:
                if math.hypot(ax - bx, az - bz) < ar + br + GAP:
                    return "crowns"
            if ph_ > t["crown_y"]:
                for (bx, bz, br) in pf:
                    if math.hypot(ax - bx, az - bz) < ar + br + GAP:
                        return "touch crown"
    return ("ok", top if top is not None else water[5])


def put(name, x, z, yaw, res):
    t = T[name]
    placed.append((name, x, z, yaw, world_circles(t["foot"], x, z, yaw), world_circles(t.get("crown", []), x, z, yaw),
                   t["h"], t.get("crown_y", 1e9), res[1]))


def face_road(x, z):
    """Yaw (degrees) that turns a model's front (-Z) toward the nearest road cell."""
    q = nearest_path(x, z)
    dx, dz = q[0] - x, q[1] - z
    # front = (-sin yaw, -cos yaw) in Roblox terms after CFrame.Angles(0, yaw, 0): solve for yaw
    return math.degrees(math.atan2(-dx, -dz))


# the walkable area's bounds for sampling
XS = (-566, -216)
ZS = (-1288, -898)


def sample(near=None):
    if near:
        (cx, cz, r0, r1) = near
        a = rng.uniform(0, 2 * math.pi)
        r = rng.uniform(r0, r1)
        return cx + r * math.cos(a), cz + r * math.sin(a)
    return rng.uniform(*XS), rng.uniform(*ZS)


def spread(name, n, near=None, yaw_fn=None, against=None, min_sep=0):
    """Place n of name, each the best of TRIES valid spots: farthest from what's already placed
    of the kinds in `against` (default: its own kind)."""
    against = against or {name}
    got = 0
    for _ in range(n):
        best, bscore = None, -1
        for _t in range(TRIES * 6):
            x, z = sample(near)
            yaw = yaw_fn(x, z) if yaw_fn else rng.uniform(0, 360)
            res = check(name, x, z, yaw)
            if not isinstance(res, tuple):
                continue
            others = [math.hypot(p[1] - x, p[2] - z) for p in placed if p[0] in against]
            score = min(others) if others else 1e6
            if others and score < min_sep:
                continue
            if score > bscore:
                best, bscore = (x, z, yaw, res), score
            if bscore >= 1e6:
                break
        if best:
            put(name, best[0], best[1], best[2], best[3])
            got += 1
    return got


report = {}

# --- landmarks --------------------------------------------------------------------
# a mirrored pair either side of a doorway's lane: `lane` (dx, dz) is the way out from the
# pyramid; each pair is scanned outward from the approach's end and outward from the lane until
# both sides fit at the same spot (so the pair mirrors across the lane)
def pair(name, lane, across, yaw_fn, steps=160, offs=50):
    dx, dz = lane
    ux, uz = -dz, dx                      # across the lane
    start = PH + G.PYR_APPROACH
    for k in range(steps):
        t = start + 0.5 * k
        for m in range(offs):
            o = across + 0.5 * m
            spots = []
            for side in (1, -1):
                x = PX + dx * t + ux * o * side
                z = PZ + dz * t + uz * o * side
                yaw = yaw_fn(side)
                res = check(name, x, z, yaw)
                if not isinstance(res, tuple):
                    break
                spots.append((x, z, yaw, res))
            if len(spots) == 2:
                # the second must also clear the first
                put(name, *spots[0])
                res = check(name, spots[1][0], spots[1][1], spots[1][2])
                if isinstance(res, tuple):
                    put(name, spots[1][0], spots[1][1], spots[1][2], res)
                    return 2
                placed.pop()
    return 0


# a sphinx either side of the east lane (the one the road from the entry reaches first), lying
# along it and facing the road as guards at the doorway; across the lane they ran into the
# mounds beside it. Model front (-Z) turned to +X: yaw -90
report["Sphinx"] = pair("Sphinx", (1, 0), G.PYR_DOOR + 3 + 5.2, lambda side: -90)
# obelisk pairs flanking the other three lanes
report["Obelisk"] = 0
for lane in ((0, 1), (-1, 0), (0, -1)):
    report["Obelisk"] += pair("Obelisk", lane, G.PYR_DOOR + 3 + 4.5, lambda side: 0)

# two tombs, far apart, their doors to the road
report["Tomb"] = spread("Tomb", 2, yaw_fn=face_road, min_sep=120)

# --- gathering nodes --------------------------------------------------------------
report["Saguaro"] = spread("Saguaro", 8, yaw_fn=face_road, min_sep=35, against={"Saguaro"})
report["DigPile"] = spread("DigPile", 8, yaw_fn=face_road, min_sep=32, against={"DigPile", "Saguaro"})

# --- the oasis --------------------------------------------------------------------
ox, oz, orx, orz = G.OASIS
report["LotusPads"] = spread("LotusPads", 5, near=(ox, oz, 0, orx * 0.8))
report["Papyrus"] = spread("Papyrus", 10, near=(ox, oz, orz * 0.9, orx * 1.4))
report["DatePalm"] = spread("DatePalm", 6, near=(ox, oz, orz + 6, orx + 22), against={"DatePalm", "PalmTall", "PalmTwin"})
report["WaterJars"] = spread("WaterJars", 3, near=(ox, oz, orz + 2, orx + 10))

# --- ruins near the pyramid -------------------------------------------------------
for name in ("PillarDrums", "PillarStump", "PillarLeaning", "PillarRubble"):
    report[name] = spread(name, 2, near=(PX, PZ, PH + 18, PH + 70),
                          against={"PillarDrums", "PillarStump", "PillarLeaning", "PillarRubble", "Obelisk", "Sphinx"})

# --- palms and cacti over the whole map -------------------------------------------
PALMS = {"PalmTall", "PalmTwin", "DatePalm"}
for name, n in (("PalmTall", 16), ("PalmTwin", 9), ("DatePalm", 4)):
    report[name] = report.get(name, 0) + spread(name, n, against=PALMS)
report["BarrelCactus"] = spread("BarrelCactus", 24, against={"BarrelCactus", "Saguaro"})

# --- more round the oasis (2026-10-26, the user: more palms and papyrus by it); placed last, so
# everything above keeps its spot
OASIS_MORE = {"DatePalm": 6, "PalmTall": 4, "PalmTwin": 3}
for name, n in OASIS_MORE.items():
    report[name + " (oasis)"] = spread(name, n, near=(ox, oz, orz + 4, orx + 26), against=PALMS)
report["Papyrus (more)"] = spread("Papyrus", 12, near=(ox, oz, orz * 0.9, orx * 1.4))

counts = {}
plan = []
for (name, x, z, yaw, _, _, _, _, top) in placed:
    counts[name] = counts.get(name, 0) + 1
    plan.append(dict(template=name, source=SOURCE.get(name, "Decorations"), folder=FOLDER[name],
                     name=f"{name}_{counts[name]}", x=round(x, 2), z=round(z, 2), y=top, yaw=round(yaw % 360, 1)))
json.dump(dict(place=dict(frm=[G.EAST_LIMIT, G.CORRIDOR_Z], to=list(G.WORLD_END), turn=G.WORLD_TURN), items=plan),
          open(OUT, "w"), indent=1)
print("placed", counts)
print("asked vs got", report)
# spread check: halves and quarters of the map for the palms and cacti
for kinds in (PALMS, {"BarrelCactus"}):
    q = [0, 0, 0, 0]
    for p in placed:
        if p[0] in kinds:
            q[(p[1] > -391) * 1 + (p[2] > -1093) * 2] += 1
    print(sorted(kinds), "by quarter (SW, SE, NW, NE)", q)
