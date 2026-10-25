"""World 4 (the desert) ground: option B "Pinwheel" (the user's pick, 2026-10-25,
https://claude.ai/artifact/8oMag1XSAEpsEBeXGLVNyy).

Lays the world out as a height field on a 2-stud grid, then merges cells of the same
top height and colour into world-aligned columns (each from y 2 up to its top), so
terraces read as steps and nothing is stacked or buried. Writes them to
src/shared/DevData/W4Ground.luau (a temporary Rojo module, never committed), which a
one-off execute_luau turns into parts under Workspace.Worlds.W04_Desert/Ground.

The pieces:
  * the walkable sand: a square with one end of every wall pushed out (POLY);
  * the rim: sand dunes rising in 2-stud steps from the walkable edge to a crest of
    44-62 (World 2's hedges top 36-56), the crest height, slope and foot wobbling with
    smooth noise so no stretch repeats; the east rim stops at x -176, where World 2's
    hedges begin, and opens for the corridor at z -912..-878;
  * the ring road and the canyon shortcut, flush with the sand (12 wide, 4-stud blocks);
  * a sandstone mesa in the middle (three 8-stud tiers) with the canyon cut through it;
  * interior dunes in 1-stud steps (8-10 tall);
  * the oasis: a shallow and a deep bed under one water part, a green ring round it;
  * a dormant volcano in the west arm (2-stud steps, a crater on top).

Usage: python build_ground.py   (prints the counts; writes the Luau module)
"""
import math
import os
import random

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
OUT = os.path.join(REPO, "src", "shared", "DevData", "W4Ground.luau")

CELL = 2
FLOOR = 8          # walkable top
BASE = 2           # every column's bottom
EAST_LIMIT = -176  # World 2's hedges start at x -175
CORRIDOR = (-912, -878)

# the walkable outline, clockwise from the north arm's north-west corner
POLY = [(-526, -700), (-386, -700), (-386, -740), (-216, -740), (-216, -1050), (-246, -1050),
        (-246, -1090), (-354, -1090), (-354, -1050), (-566, -1050), (-566, -910), (-526, -910)]

ROUTES = [
    [(-176, -894), (-262, -894), (-262, -790), (-470, -790), (-490, -830), (-490, -1000), (-300, -1000), (-300, -1050)],
    [(-262, -894), (-490, -894)],  # the canyon shortcut through the mesa
]
PATH_HALF = 6

MESA = (-374, -894, 78, 70)          # centre x, z, radius x, z
MESA_TIERS = [(1.00, 8, "B8743F"), (0.80, 16, "C98A55"), (0.62, 24, "D69A63")]
OASIS = (-454, -734, 48, 22)
VOLCANO = (-532, -1006, 22)
DUNES = [(-300, -760, 30, 14, 8), (-548, -940, 12, 22, 10), (-252, -1020, 22, 22, 9), (-420, -1030, 40, 14, 8)]

SAND = "E8C98E"
PATH = "C99A5B"
OASIS_GRASS = "8DB650"
BED_SHALLOW = "6FA9A0"
BED_DEEP = "2F7F9A"
BASALT = ["5A4A48", "52423F", "4A3C3A"]
CRATER = "3A2E2C"


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


def seg_dist(px, pz, a, b):
    ax, az = a
    bx, bz = b
    dx, dz = bx - ax, bz - az
    L = dx * dx + dz * dz
    t = 0 if L == 0 else max(0, min(1, ((px - ax) * dx + (pz - az) * dz) / L))
    return math.hypot(px - (ax + t * dx), pz - (az + t * dz))


def edge_dist(x, z):
    n = len(POLY)
    return min(seg_dist(x, z, POLY[i], POLY[(i + 1) % n]) for i in range(n))


def cheb_to_route(x, z):
    """Chebyshev distance from a point to the routes (a square brush along each leg)."""
    best = 1e9
    for r in ROUTES:
        for a, b in zip(r, r[1:]):
            steps = max(1, int(math.dist(a, b) / 2))
            for s in range(steps + 1):
                t = s / steps
                qx, qz = a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t
                best = min(best, max(abs(x - qx), abs(z - qz)))
    return best


def wob(x, z, cx, cz, rx, rz, seed, amp=0.08):
    """Normalised radius of (x, z) in a wobbly ellipse (1 = its edge)."""
    a = math.atan2((z - cz) / rz, (x - cx) / rx)
    k = 1 + amp * math.sin(3 * a + seed) + amp * 0.6 * math.sin(5 * a + seed * 1.7) + amp * 0.4 * math.sin(2 * a + seed * 0.3)
    return math.hypot((x - cx) / rx, (z - cz) / rz) / k


def edge_runs():
    """Each wall split into straight stretches of 24-48 studs, each with its own crest
    (44-62) and foot (0-6 studs out from the walkable edge), so the rim varies along its
    length while every step stays a straight block (few parts)."""
    rnd = random.Random(40)
    runs = []
    n = len(POLY)
    for e in range(n):
        a, b = POLY[e], POLY[(e + 1) % n]
        length = abs(b[0] - a[0]) + abs(b[1] - a[1])
        cuts, t = [], 0
        while t < length:
            step = rnd.choice((24, 28, 32, 36, 40, 44, 48))
            cuts.append((t, min(length, t + step), rnd.choice((44, 46, 48, 50, 52, 54, 56, 58, 60, 62)), rnd.choice((0, 2, 4, 6))))
            t += step
        runs.append(cuts)
    return runs


RUNS = None


def rim_at(x, z):
    """(rectilinear distance to the walkable edge, crest, foot) for a cell outside it."""
    best = None
    n = len(POLY)
    for e in range(n):
        (ax, az), (bx, bz) = POLY[e], POLY[(e + 1) % n]
        if az == bz:  # a wall running east-west
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
    for (t0, t1, crest, foot) in RUNS[e]:
        if t0 <= t <= t1:
            return d, crest, foot
    t0, t1, crest, foot = RUNS[e][-1]
    return d, crest, foot


def build():
    global RUNS
    RUNS = edge_runs()
    x0, x1 = -646, -176
    z1, z0 = -620, -1170   # north, south
    nx = (x1 - x0) // CELL
    nz = (z1 - z0) // CELL
    cells = {}  # (i, j) -> (top, colour, folder, name)
    route_cache = {}

    def on_path(x, z):
        # 4-stud blocks: decide per 4x4 block from its centre, so path edges step by 4
        bx = x0 + 4 * math.floor((x - x0) / 4) + 2
        bz = z1 - 4 * math.floor((z1 - z) / 4) - 2
        key = (bx, bz)
        if key not in route_cache:
            route_cache[key] = cheb_to_route(bx, bz) <= PATH_HALF
        return route_cache[key]

    water_cells = []
    for i in range(nx):
        x = x0 + CELL * i + CELL / 2
        for j in range(nz):
            z = z1 - CELL * j - CELL / 2
            corridor = x > -216 and CORRIDOR[0] <= z <= CORRIDOR[1]
            if inside(x, z) or corridor:
                top, colour, folder, name = FLOOR, SAND, "Sand", "Sand"
                if on_path(x, z):
                    top, colour, folder, name = FLOOR, PATH, "Paths", "Path"
                else:
                    # the mesa, with the canyon cut through it
                    mr = wob(x, z, *MESA, seed=4.0, amp=0.06)
                    for frac, h, col in MESA_TIERS:
                        if mr < frac:
                            top, colour, folder, name = FLOOR + h, col, "Mesa", "Sandstone"
                    # the oasis
                    orr = wob(x, z, *OASIS, seed=1.2, amp=0.07)
                    if orr < 0.55:
                        top, colour, folder, name = 4, BED_DEEP, "Oasis", "Bed"
                        water_cells.append((x, z))
                    elif orr < 1.0:
                        top, colour, folder, name = 5.5, BED_SHALLOW, "Oasis", "Bed"
                        water_cells.append((x, z))
                    elif orr < 1.25:
                        top, colour, folder, name = FLOOR, OASIS_GRASS, "Oasis", "Grass"
                    # interior dunes, 1-stud steps
                    for n_, (cx, cz, rx, rz, H) in enumerate(DUNES):
                        dr = wob(x, z, cx, cz, rx, rz, seed=2.0 + n_, amp=0.09)
                        if dr < 1 and folder == "Sand":
                            h = math.floor(H * (1 - dr * dr) ** 0.7 + 0.5)
                            if h > 0:
                                top, colour, folder, name = FLOOR + h, dune_colour(FLOOR + h), "Dunes", "Dune"
                    # the volcano: 2-stud steps up to a crater rim
                    vx, vz, vr = VOLCANO
                    vd = math.hypot(x - vx, z - vz) / vr
                    if vd < 1 and folder == "Sand":
                        if vd < 0.3:
                            top, colour = FLOOR + 24, CRATER
                        else:
                            top = FLOOR + 2 * math.floor((1 - vd) / 0.7 * 15)
                            colour = BASALT[min(2, int((1 - vd) * 3))]
                        folder, name = "Volcano", "Basalt"
                cells[(i, j)] = (top, colour, folder, name)
            else:
                if x > EAST_LIMIT:
                    continue
                d, crest, foot = rim_at(x, z)
                reach = foot + (crest - FLOOR) + 6
                if d > reach:
                    continue
                rise = d - foot  # 45 degrees: a 2-stud step every 2 studs
                top = FLOOR if rise < 2 else min(crest, FLOOR + 2 * math.floor(rise / 2))
                if top == FLOOR:
                    cells[(i, j)] = (FLOOR, SAND, "Sand", "Sand")
                else:
                    cells[(i, j)] = (top, dune_colour(top), "Rim", "Dune")

    # greedy merge per (top, colour, folder, name)
    boxes = []
    used = set()
    keys = sorted(cells)
    for (i, j) in keys:
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

    # one water part over the oasis, its top under the banks
    wx = [c[0] for c in water_cells]
    wz = [c[1] for c in water_cells]
    water = (min(wx) - 1 - 1, max(wx) + 1 + 1, min(wz) - 1 - 1, max(wz) + 1 + 1, 5.5, 7.2)

    # invisible borders: a 1-stud wall just outside every outer edge of the world, from
    # y 2 to 600 (the rim's 2-stud steps can be jumped up), open only where the corridor
    # meets World 2
    edges = {"x": {}, "z": {}}  # x-walls keyed by x (runs along z), z-walls keyed by z
    for (i, j) in cells:
        cx0 = x0 + CELL * i
        cz_n = z1 - CELL * j
        if (i - 1, j) not in cells:
            edges["x"].setdefault((cx0, -1), []).append(cz_n)
        if (i + 1, j) not in cells:
            if not (cx0 + CELL == EAST_LIMIT and CORRIDOR[0] <= cz_n - 1 <= CORRIDOR[1]):
                edges["x"].setdefault((cx0 + CELL, 1), []).append(cz_n)
        if (i, j - 1) not in cells:
            edges["z"].setdefault((cz_n, 1), []).append(cx0)
        if (i, j + 1) not in cells:
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
    return boxes, water, cells, borders


def area_walkable(cells):
    return sum(CELL * CELL for v in cells.values() if v[3] in ("Sand", "Path", "Grass", "Bed") and v[2] != "Rim")


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
    lines.append("}")
    open(OUT, "w", encoding="utf-8", newline="\n").write("\n".join(lines) + "\n")


if __name__ == "__main__":
    boxes, water, cells, borders = build()
    write(boxes, water, borders)
    print("borders", len(borders))
    by = {}
    for b in boxes:
        by[b[7]] = by.get(b[7], 0) + 1
    tops = [b[5] for b in boxes if b[7] == "Rim"]
    print("boxes", len(boxes), by)
    print("walkable area", area_walkable(cells), "rim crest max", max(tops), "min top", min(tops))
    print("water", water)
