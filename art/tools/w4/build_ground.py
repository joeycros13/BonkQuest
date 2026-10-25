"""World 4, The Scorching Sands: the ground. Option B "Pinwheel" (the user's pick,
2026-10-25, https://claude.ai/artifact/8oMag1XSAEpsEBeXGLVNyy), then the user's changes the
same day: a pyramid in the middle, much bigger mounds, curvy paths like Worlds 1 and 2, no
path through the middle, and outer dunes too steep to climb.

Lays the world out as a height field on a 2-stud grid, then merges cells of the same top
height and colour into world-aligned columns (each from y 2 up to its top), so terraces
read as steps and nothing is stacked or buried. The pyramid is stacked square slabs instead
(one part a step). Writes src/shared/DevData/W4Ground.luau (a temporary Rojo module, never
committed), which a one-off execute_luau turns into parts under
Workspace.Worlds.W04_ScorchingSands/Ground and /Borders.

The pieces:
  * the walkable sand: a square with one end of every wall pushed out (POLY);
  * the rim: sand dunes in 11-stud terraces (measured in a playtest: a player jumps onto a
    9-stud ledge but not a 10), each wall in straight stretches of 24-48 studs with their
    own crest (41 / 52 / 63), ledge width (2 or 4) and
    foot (0-4 out); the east rim stops at x -176, where World 2's hedges begin, and opens
    for the corridor at z -912..-878;
  * the road: a curvy loop round the pyramid, forking at the entry and meeting again by the
    boss in the west arm, rasterised like World 2's (Catmull-Rom curves, a 12-stud square
    brush on 4-stud blocks, so every bend steps sideways by 4), flush with the sand;
  * the pyramid: a stepped pyramid (2 in, 2.5 up a step, about Giza's 51 degrees) with a
    gold capstone;
  * mounds: big dunes in 2-stud steps (10-20 tall), rounded squares like World 1's
    stepped mounds, lowered near the road so each one slopes down to its edge instead of
    walling it in;
  * the oasis in the north arm (a shallow and a deep bed under one water part, a green
    ring), and a dormant volcano in the south arm (World 6's way in, later).

Usage: python build_ground.py   (prints the counts; writes the Luau module)
"""
import math
import os
import random
from collections import deque

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
OUT = os.path.join(REPO, "src", "shared", "DevData", "W4Ground.luau")

CELL = 2
FLOOR = 8          # walkable top
BASE = 2           # every column's bottom
EAST_LIMIT = -176  # World 2's hedges start at x -175
CORRIDOR = (-912, -878)
TERRACE = 11       # rim step height: measured, a player gets onto 9 but not 10

# the walkable outline, clockwise from the north arm's north-west corner
POLY = [(-526, -700), (-386, -700), (-386, -740), (-216, -740), (-216, -1050), (-246, -1050),
        (-246, -1090), (-354, -1090), (-354, -1050), (-566, -1050), (-566, -910), (-526, -910)]

# the road's centre lines (control points of Catmull-Rom curves)
FORK = (-258, -894)
JOIN = (-500, -1004)
ROUTES = [
    # in from the corridor to the fork
    [(-176, -894), (-196, -894), (-222, -890), (-240, -896), FORK],
    # the north way round: up the east side, along the north past the oasis, down the west
    [FORK, (-270, -852), (-262, -806), (-306, -784), (-366, -794), (-426, -778), (-482, -794),
     (-498, -848), (-480, -906), (-496, -962), JOIN],
    # the south way round: down the east side, along the south
    [FORK, (-270, -938), (-262, -988), (-312, -1010), (-372, -996), (-432, -1014), JOIN],
    # on to the boss in the west arm
    [JOIN, (-516, -996), (-530, -988)],
]
PATH_HALF = 6

PYRAMID = (-375, -900, 60)      # centre x, z, half base
PYR_RISE = 2.5                  # up a step (each step is 2 in)
OASIS = (-454, -734, 48, 22)
VOLCANO = (-300, -1066, 22)
BOSS = (-534, -988, 22)
# mounds: centre x, z, radius x, z, height (they slope down to the road by themselves)
DUNES = [
    (-300, -752, 44, 16, 16), (-232, -804, 18, 30, 18), (-232, -1000, 18, 38, 20),
    (-405, -1036, 46, 14, 16), (-292, -846, 14, 30, 14), (-292, -956, 14, 30, 14),
    (-458, -870, 14, 34, 16), (-458, -950, 12, 26, 12), (-375, -816, 46, 12, 12),
    (-375, -984, 46, 11, 12), (-512, -760, 14, 22, 16), (-470, -1036, 20, 12, 10),
    (-546, -1032, 16, 12, 10), (-396, -716, 10, 14, 10),
]

SAND = "E8C98E"
PATH = "C99A5B"
OASIS_GRASS = "8DB650"
BED_SHALLOW = "6FA9A0"
BED_DEEP = "2F7F9A"
BASALT = ["5A4A48", "52423F", "4A3C3A"]
CRATER = "3A2E2C"
SANDSTONE = "E0BC78"
SANDSTONE_BAND = "CFA865"
GOLD = "F2C14E"


def lerp_hex(a, b, t):
    ca = [int(a[i:i + 2], 16) for i in (0, 2, 4)]
    cb = [int(b[i:i + 2], 16) for i in (0, 2, 4)]
    return "".join(f"{round(x + (y - x) * t):02X}" for x, y in zip(ca, cb))


def dune_colour(top):
    """Sand gets a touch lighter the higher it is, so steps read."""
    t = max(0.0, min(1.0, (top - FLOOR) / 54))
    return lerp_hex("DFBC7C", "F3DFB2", t)


def inside(x, z):
    hit = False
    n = len(POLY)
    for i in range(n):
        x1, z1 = POLY[i]
        x2, z2 = POLY[(i + 1) % n]
        if (z1 > z) != (z2 > z):
            xc = x1 + (z - z1) * (x2 - x1) / (z2 - z1)
            if x < xc:
                hit = not hit
    return hit


def catmull(points, step=1.0):
    """Points along a Catmull-Rom curve through `points`, about `step` studs apart."""
    pts = [points[0]] + list(points) + [points[-1]]
    out = []
    for k in range(1, len(pts) - 2):
        p0, p1, p2, p3 = pts[k - 1], pts[k], pts[k + 1], pts[k + 2]
        n = max(1, int(math.dist(p1, p2) / step))
        for s in range(n):
            t = s / n
            t2, t3 = t * t, t * t * t
            out.append(tuple(0.5 * ((2 * p1[i]) + (-p0[i] + p2[i]) * t + (2 * p0[i] - 5 * p1[i] + 4 * p2[i] - p3[i]) * t2
                                    + (-p0[i] + 3 * p1[i] - 3 * p2[i] + p3[i]) * t3) for i in (0, 1)))
    out.append(points[-1])
    return out


def wob(x, z, cx, cz, rx, rz, seed, amp=0.07):
    """Normalised radius of (x, z) in a wobbly ellipse (1 = its edge)."""
    a = math.atan2((z - cz) / rz, (x - cx) / rx)
    k = 1 + amp * math.sin(3 * a + seed) + amp * 0.6 * math.sin(5 * a + seed * 1.7) + amp * 0.4 * math.sin(2 * a + seed * 0.3)
    return math.hypot((x - cx) / rx, (z - cz) / rz) / k


def mound_r(x, z, cx, cz, rx, rz, seed):
    """Normalised radius in a rounded square (a superellipse, exponent 3) with a slight
    wobble: blockier than an ellipse, so a mound's steps are long straight runs (few parts),
    like World 1's stepped mounds."""
    a = math.atan2((z - cz) / rz, (x - cx) / rx)
    k = 1 + 0.04 * math.sin(3 * a + seed) + 0.03 * math.sin(2 * a + seed * 0.7)
    u, w = abs(x - cx) / rx, abs(z - cz) / rz
    return (u ** 3 + w ** 3) ** (1 / 3) / k


def edge_runs():
    """Each wall split into straight stretches of 24-48 studs, each with its own crest,
    ledge width and foot, so the rim varies along its length while every terrace stays a
    straight block (few parts)."""
    rnd = random.Random(41)
    runs = []
    n = len(POLY)
    for e in range(n):
        a, b = POLY[e], POLY[(e + 1) % n]
        length = abs(b[0] - a[0]) + abs(b[1] - a[1])
        cuts, t = [], 0
        while t < length:
            step = rnd.choice((24, 28, 32, 36, 40, 44, 48))
            cuts.append((t, min(length, t + step), rnd.choice((41, 52, 52, 63)), rnd.choice((2, 4, 4)), rnd.choice((0, 2, 4))))
            t += step
        runs.append(cuts)
    return runs


RUNS = None


def rim_at(x, z):
    """(rectilinear distance to the walkable edge, crest, ledge, foot) for a cell outside it."""
    best = None
    n = len(POLY)
    for e in range(n):
        (ax, az), (bx, bz) = POLY[e], POLY[(e + 1) % n]
        if az == bz:
            lo, hi = min(ax, bx), max(ax, bx)
            d = max(lo - x, 0, x - hi, abs(z - az))
            t = min(max(x, lo), hi) - lo if ax < bx else hi - min(max(x, lo), hi)
        else:
            lo, hi = min(az, bz), max(az, bz)
            d = max(lo - z, 0, z - hi, abs(x - ax))
            t = min(max(z, lo), hi) - lo if az < bz else hi - min(max(z, lo), hi)
        if best is None or d < best[0]:
            best = (d, e, t)
    d, e, t = best
    for run in RUNS[e]:
        if run[0] <= t <= run[1]:
            return (d,) + run[2:]
    return (d,) + RUNS[e][-1][2:]


def build():
    global RUNS
    RUNS = edge_runs()
    x0, x1 = -646, -176
    z1, z0 = -620, -1170   # north, south
    nx = (x1 - x0) // CELL
    nz = (z1 - z0) // CELL

    def cell_of(x, z):
        return int((x - x0) // CELL), int((z1 - z) // CELL)

    # the road: 4-stud blocks within a 12-stud square brush of the curves
    samples = [p for r in ROUTES for p in catmull(r)]
    path_blocks = set()
    for (px, pz) in samples:
        for bx in range(int((px - PATH_HALF - x0) // 4), int((px + PATH_HALF - x0) // 4) + 1):
            for bz in range(int((z1 - (pz + PATH_HALF)) // 4), int((z1 - (pz - PATH_HALF)) // 4) + 1):
                cx = x0 + 4 * bx + 2
                cz = z1 - 4 * bz - 2
                if max(abs(cx - px), abs(cz - pz)) <= PATH_HALF:
                    path_blocks.add((bx, bz))
    path_cells = set()
    for (bx, bz) in path_blocks:
        for a in (0, 1):
            for b in (0, 1):
                path_cells.add((2 * bx + a, 2 * bz + b))

    # distance (studs) from every cell to the road, so mounds slope down to it
    dist = {c: 0 for c in path_cells}
    q = deque(path_cells)
    while q:
        c = q.popleft()
        d = dist[c]
        if d >= 40:
            continue
        for di in (-1, 0, 1):
            for dj in (-1, 0, 1):
                nb = (c[0] + di, c[1] + dj)
                if 0 <= nb[0] < nx and 0 <= nb[1] < nz and nb not in dist:
                    dist[nb] = d + CELL
                    q.append(nb)

    px_, pz_, ph = PYRAMID
    cells = {}
    water_cells = []
    for i in range(nx):
        x = x0 + CELL * i + CELL / 2
        for j in range(nz):
            z = z1 - CELL * j - CELL / 2
            corridor = x > -216 and CORRIDOR[0] <= z <= CORRIDOR[1]
            if inside(x, z) or corridor:
                v = (FLOOR, SAND, "Sand", "Sand")
                if (i, j) in path_cells:
                    v = (FLOOR, PATH, "Paths", "Path")
                elif abs(x - px_) < ph and abs(z - pz_) < ph:
                    v = None  # under the pyramid (its own slabs)
                else:
                    orr = wob(x, z, *OASIS, seed=1.2)
                    vx, vz, vr = VOLCANO
                    vd = math.hypot(x - vx, z - vz) / vr
                    if orr < 0.55:
                        v = (4, BED_DEEP, "Oasis", "Bed")
                        water_cells.append((x, z))
                    elif orr < 1.0:
                        v = (5.5, BED_SHALLOW, "Oasis", "Bed")
                        water_cells.append((x, z))
                    elif orr < 1.25:
                        v = (FLOOR, OASIS_GRASS, "Oasis", "Grass")
                    elif vd < 1:
                        if vd < 0.3:
                            v = (FLOOR + 24, CRATER, "Volcano", "Basalt")
                        else:
                            v = (FLOOR + 2 * math.floor((1 - vd) / 0.7 * 15), BASALT[min(2, int((1 - vd) * 3))], "Volcano", "Basalt")
                    else:
                        h = 0
                        for n_, (cx, cz, rx, rz, H) in enumerate(DUNES):
                            dr = mound_r(x, z, cx, cz, rx, rz, seed=2.0 + n_)
                            if dr < 1:
                                h = max(h, 2 * math.floor(H * (1 - dr ** 2.2) ** 0.8 / 2 + 0.5))
                        # slope down to the road (and keep 2 studs of flat sand beside it)
                        h = min(h, max(0, int(dist.get((i, j), 99) - 2)))
                        # and down to the pyramid's foot
                        gap = max(abs(x - px_), abs(z - pz_)) - ph
                        h = min(h, max(0, int(gap - 2)))
                        h -= h % 2  # 2-stud steps
                        if h > 0:
                            v = (FLOOR + h, dune_colour(FLOOR + h), "Dunes", "Dune")
                if v:
                    cells[(i, j)] = v
            else:
                if x > EAST_LIMIT:
                    continue
                d, crest, ledge, foot = rim_at(x, z)
                levels = (crest - FLOOR) // TERRACE
                reach = foot + levels * ledge + 8
                if d > reach:
                    continue
                if d < foot:
                    cells[(i, j)] = (FLOOR, SAND, "Sand", "Sand")
                else:
                    lv = min(levels, 1 + int((d - foot) // ledge))
                    top = FLOOR + TERRACE * lv
                    cells[(i, j)] = (top, dune_colour(top), "Rim", "Dune")

    # greedy merge per (top, colour, folder, name)
    boxes = []
    used = set()
    for (i, j) in sorted(cells):
        if (i, j) in used:
            continue
        v = cells[(i, j)]
        w = 1
        while (i + w, j) in cells and cells[(i + w, j)] == v and (i + w, j) not in used:
            w += 1
        h = 1
        while True:
            row = [(i + a, j + h) for a in range(w)]
            if all(c in cells and cells[c] == v and c not in used for c in row):
                h += 1
            else:
                break
        for a in range(w):
            for b in range(h):
                used.add((i + a, j + b))
        top, colour, folder, name = v
        bx0 = x0 + CELL * i
        bz_north = z1 - CELL * j
        boxes.append((bx0, bx0 + CELL * w, bz_north - CELL * h, bz_north, BASE, top, colour, folder, name))

    # the pyramid: one square slab a step, from the sand up
    half, y, k = ph, BASE, 0
    while half >= 2:
        top = FLOOR + PYR_RISE * (k + 1) if k > 0 else FLOOR + PYR_RISE
        bottom = BASE if k == 0 else FLOOR + PYR_RISE * k
        colour = GOLD if half <= 4 else (SANDSTONE_BAND if k % 4 == 3 else SANDSTONE)
        boxes.append((px_ - half, px_ + half, pz_ - half, pz_ + half, bottom, top, colour, "Pyramid", "Gold" if colour == GOLD else "Sandstone"))
        half -= 2
        k += 1

    wx = [c[0] for c in water_cells]
    wz = [c[1] for c in water_cells]
    water = (min(wx) - 2, max(wx) + 2, min(wz) - 2, max(wz) + 2, 5.5, 7.2)

    # invisible borders: a 1-stud wall just outside every outer edge of the world, from
    # y 2 to 600, open only where the corridor meets World 2
    footprint = set(cells)
    for i in range(cell_of(px_ - ph + 1, 0)[0], cell_of(px_ + ph - 1, 0)[0] + 1):
        for j in range(cell_of(0, pz_ + ph - 1)[1], cell_of(0, pz_ - ph + 1)[1] + 1):
            footprint.add((i, j))
    edges = {"x": {}, "z": {}}
    for (i, j) in footprint:
        cx0 = x0 + CELL * i
        cz_n = z1 - CELL * j
        if (i - 1, j) not in footprint:
            edges["x"].setdefault((cx0, -1), []).append(cz_n)
        if (i + 1, j) not in footprint:
            if not (cx0 + CELL == EAST_LIMIT and CORRIDOR[0] <= cz_n - 1 <= CORRIDOR[1]):
                edges["x"].setdefault((cx0 + CELL, 1), []).append(cz_n)
        if (i, j - 1) not in footprint:
            edges["z"].setdefault((cz_n, 1), []).append(cx0)
        if (i, j + 1) not in footprint:
            edges["z"].setdefault((cz_n - CELL, -1), []).append(cx0)
    borders = []
    for (x, side), zs in edges["x"].items():
        zs.sort()
        start = prev = zs[0]
        for z in zs[1:] + [None]:
            if z is not None and z == prev + CELL:
                prev = z
                continue
            wx0 = x if side > 0 else x - 1
            borders.append((wx0, wx0 + 1, start - CELL, prev, BASE, 600))
            if z is not None:
                start = prev = z
    for (z, side), xs in edges["z"].items():
        xs.sort()
        start = prev = xs[0]
        for x in xs[1:] + [None]:
            if x is not None and x == prev + CELL:
                prev = x
                continue
            wz0 = z if side > 0 else z - 1
            borders.append((start, prev + CELL, wz0, wz0 + 1, BASE, 600))
            if x is not None:
                start = prev = x
    # and walls along the rim's inner face, from the sand up: a player can't jump onto an
    # 11-stud terrace from the floor, but a running jump off a mound (sprint reaches 40+
    # studs a jump) could land on the first one; these keep everyone off the rim entirely
    inner = {"x": {}, "z": {}}
    for (i, j), v in cells.items():
        if v[2] != "Rim":
            continue
        cx0 = x0 + CELL * i
        cz_n = z1 - CELL * j
        for (di, dj) in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            nb = cells.get((i + di, j + dj))
            if nb is None or nb[2] == "Rim":
                continue
            if di == -1:
                inner["x"].setdefault((cx0, 1), []).append(cz_n)        # wall in the cell's west stud
            elif di == 1:
                inner["x"].setdefault((cx0 + CELL, -1), []).append(cz_n)  # in its east stud
            elif dj == -1:
                inner["z"].setdefault((cz_n, -1), []).append(cx0)       # in its north stud
            else:
                inner["z"].setdefault((cz_n - CELL, 1), []).append(cx0)  # in its south stud
    for (x, side), zs in inner["x"].items():
        zs.sort()
        start = prev = zs[0]
        for z in zs[1:] + [None]:
            if z is not None and z == prev + CELL:
                prev = z
                continue
            wx0 = x if side > 0 else x - 1
            borders.append((wx0, wx0 + 1, start - CELL, prev, FLOOR, 600))
            if z is not None:
                start = prev = z
    for (z, side), xs in inner["z"].items():
        xs.sort()
        start = prev = xs[0]
        for x in xs[1:] + [None]:
            if x is not None and x == prev + CELL:
                prev = x
                continue
            wz0 = z if side > 0 else z - 1
            borders.append((start, prev + CELL, wz0, wz0 + 1, FLOOR, 600))
            if x is not None:
                start = prev = x
    return boxes, water, cells, borders, samples


def write(boxes, water, borders):
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    lines = ["-- Generated by art/tools/w4/build_ground.py. Temporary: never commit; delete once World 4's ground is built.",
             "return {", "\tboxes = {"]
    for b in boxes:
        x0, x1, z0, z1, y0, y1, col, folder, name = b
        lines.append(f'\t\t{{{x0}, {x1}, {z0}, {z1}, {y0}, {y1}, "{col}", "{folder}", "{name}"}},')
    lines.append("\t},")
    lines.append("\tborders = {")
    for b in borders:
        lines.append("\t\t{" + ", ".join(str(v) for v in b) + "},")
    lines.append("\t},")
    lines.append(f"\twater = {{{', '.join(str(v) for v in water)}}},")
    lines.append(f"\tboss = {{{', '.join(str(v) for v in BOSS)}}},")
    lines.append("}")
    open(OUT, "w", encoding="utf-8", newline="\n").write("\n".join(lines) + "\n")


def route_length(points):
    c = catmull(points)
    return sum(math.dist(c[k], c[k + 1]) for k in range(len(c) - 1))


if __name__ == "__main__":
    boxes, water, cells, borders, samples = build()
    write(boxes, water, borders)
    by = {}
    for b in boxes:
        by[b[7]] = by.get(b[7], 0) + 1
    print("boxes", len(boxes), by, "borders", len(borders))
    lens = [round(route_length(r)) for r in ROUTES]
    print("road lengths (entry, north way, south way, boss spur)", lens,
          "entry to boss: north", lens[0] + lens[1] + lens[3], "south", lens[0] + lens[2] + lens[3])
    tall = max(b[5] for b in boxes if b[7] == "Dunes")
    print("tallest mound top", tall, "pyramid top", max(b[5] for b in boxes if b[7] == "Pyramid"))
