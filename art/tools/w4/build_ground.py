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
  * the rim: sand dunes in four 11-stud terraces all the way round (measured in a playtest:
    a player jumps onto a 9-stud ledge but not a 10), every terrace the same 8 studs deep,
    so the walls are one height (top y 52) and built of thick blocks (the user: an earlier
    rim varied its height, ledge and foot every 24-48 studs, which left 2-stud slivers
    where stretches met), with a fifth step 5 tall on top along four long stretches
    (RIM_CAP_STRETCHES, 2026-10-26); the east rim stops at x -176, where World 2's hedges begin, and
    opens for the corridor (the user's pick for the gate, 2026-10-25: World 2's stepped
    south-west corner); the whole world is turned 45 degrees and moved so the corridor
    runs on from a diagonal cut through that corner (WORLD_END, WORLD_TURN);
  * the road: a curvy loop round the pyramid, forking at the entry and meeting again by the
    boss in the west arm, rasterised like World 2's (Catmull-Rom curves, a 12-stud square
    brush on 4-stud blocks, so every bend steps sideways by 4), flush with the sand;
  * the pyramid: a stepped pyramid (2 in, 2.5 up a step, about Giza's 51 degrees) with a
    gold capstone, hollow (the user, 2026-10-26; World 4's boss hall): an 80 x 80 hall with
    sheer walls to y 20.5, then a stepped vault following the pyramid's own steps up to a
    peak about 60 over the floor (the shell 12 thick all the way), and a doorway in the
    middle of every side, flush with the sand, framed by pillars and a lintel, with flat
    sand kept in front of each; and a sandstone tower (decoration) set into each of its corners,
    most of its foot inside the pyramid;
  * mounds: big dunes in 2-stud steps (10-20 tall), rounded squares like World 1's
    stepped mounds, lowered near the road so each one slopes down to its edge instead of
    walling it in;
  * the oasis in the north arm (a shallow and a deep bed under one water part, a green
    ring), and a dormant volcano in the south arm (World 6's way in, later), as wide as it can
    be with `VOLCANO_GAP` studs left before the road, in rings 4 studs wide and 6 up.

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
# the way in: the corridor, straight in from the east at the entry road's height, 34 wide,
# with walls the rim's full height either side
CORRIDOR_Z = -988
CORRIDOR_HALF = 17
CORRIDOR_WALL = 16
# World 4 is laid out in these coordinates, then turned 45 degrees and moved so its
# corridor runs on, south-west, from the diagonal cut through World 2's stepped
# south-west corner (the user, 2026-10-25): the corridor's east end (EAST_LIMIT,
# CORRIDOR_Z) lands on WORLD_END, and the world's east (+X) points north-east.
# The seam is the line x + z = -1160; World 2's floor blocks that it cuts are wedges, so the
# two worlds meet edge to edge at the same height (WORLD_DROP 0).
WORLD_END = (-142, -1018)   # on World 2's 4-stud grid, so its blocks meet the seam in whole wedges
WORLD_TURN = -45   # degrees about Y (Roblox's CFrame.Angles)
WORLD_DROP = 0


def corridor_d(x, z):
    """Distance across the corridor from its centre line."""
    return abs(z - CORRIDOR_Z)
TERRACE = 11       # rim step height: measured, a player gets onto 9 but not 10
RIM_LEVELS = 4     # terraces in every wall (top y 8 + 4 x 11 = 52)
RIM_LEDGE = 8      # how deep each terrace is
RIM_BACK = 12      # how far the top terrace runs on behind its edge
# a fifth, lower step on top of the wall along some stretches (the user, 2026-10-26: "one more step
# on top of some of the outer parts"), 8 studs back from the fourth terrace's edge, so the fourth
# keeps an 8-deep ledge and the step is 12 deep: thick blocks with straight ends. Boxes (x0, x1,
# z0, z1) of the stretches, each ending well short of a corner
RIM_CAP = 5
RIM_CAP_STRETCHES = [
    (-560, -396, -866, -800),     # the north arm's north wall
    (-372, -236, -906, -800),     # the north wall's east part
    (-660, -598, -1236, -1124),   # the west arm's west wall
    (-560, -372, -1340, -1280),   # the south wall west of the south arm
]

# the walkable outline, clockwise from the north arm's north-west corner
POLY = [(-526, -898), (-386, -898), (-386, -938), (-216, -938), (-216, -1248), (-246, -1248),
        (-246, -1288), (-354, -1288), (-354, -1248), (-566, -1248), (-566, -1108), (-526, -1108)]

# the road's centre lines (control points of Catmull-Rom curves)
FORK = (-262, -990)
JOIN = (-500, -1202)
ROUTES = [
    # in from the corridor at the east wall's left end (as you walk in from World 2; the
    # user, 2026-10-25) to the fork
    [(-176, -988), (-200, -988), (-226, -990), (-246, -988), FORK],
    # the north way round: along the north past the oasis, down the west
    [FORK, (-306, -982), (-366, -992), (-426, -976), (-482, -992), (-498, -1046), (-480, -1104),
     (-496, -1160), JOIN],
    # the south way round: down the east side, along the south
    [FORK, (-266, -1032), (-258, -1092), (-270, -1140), (-262, -1186), (-312, -1208), (-372, -1194),
     (-432, -1212), JOIN],
    # on to the west arm's end (the old boss spot, where the World 5 gate is to go)
    [JOIN, (-516, -1194), (-530, -1186)],
]
# and a straight path from the loop into each of the pyramid's four doorways (the boss hall;
# the user, 2026-10-26): a lane exactly the doorway's width (12) on its axis, from where the loop
# crosses that axis, through the doorway's tunnel as its floor, to the hall's edge (door_lanes)
PATH_HALF = 6

PYRAMID = (-376, -1098, 60)      # centre x, z, half base (x -376 since 2026-10-26, so every edge is on
                                # the 2-stud ground grid and the doorway paths meet it without seams)
PYR_RISE = 2.5                  # up a step (each step is 2 in)
PYR_HALL = 40                   # the hall's floor: 80 x 80 (the boss's room)
PYR_SHELL = 12                  # the shell's thickness: each slab keeps a 12-wide ring, so above the
                                # sheer walls (to y 20.5, out of jumping reach) the ceiling steps in
                                # 2 every 2.5 up, the pyramid's own steps, to a peak at y 68
PYR_DOOR = 6                    # each doorway is 12 wide
PYR_DOOR_TOP = 20.5             # and 12.5 tall, to the bottom of the slab over it
PYR_APPROACH = 16               # flat sand kept this far out in front of each doorway
PYR_APPROACH_HALF = 12          # and this far either side of its middle (the pillars stand out to 9.8)
TOWER_OUT = 54                  # each corner tower's centre, 6 in from the base's corner on each axis, so
                                # about 60% of its shaft's footprint is inside the pyramid at the foot; its
                                # inner corner stays 0.5 clear of the hall's walls (x, z 40)
TOWER_CLEAR = 20                # flat sand kept round a tower's middle
OASIS = (-454, -932, 48, 22)
VOLCANO = (-300, -1264)         # centre; its radius is set by the road (VOLCANO_GAP)
VOLCANO_GAP = 10                # studs of sand between the volcano's foot and the road
VOLCANO_MAX = 56
VOLCANO_STEP = 4                # each ring is 4 studs wide
VOLCANO_RISE = 6                # and 6 up (the user, 2026-10-25: 50% taller; it was 4)
BOSS = (-375, -1098, 30)         # the pyramid's hall (it was the west arm's end until 2026-10-26)
# mounds: centre x, z, radius x, z, height (they slope down to the road by themselves)
DUNES = [
    (-300, -950, 44, 16, 16), (-232, -1086, 18, 40, 18), (-232, -1194, 18, 40, 20),
    (-405, -1234, 46, 14, 16), (-292, -1044, 14, 30, 14), (-292, -1154, 14, 30, 14),
    # the north and south mounds were one long dune each across the doorway's path: split in two
    # (2026-10-26), and the west one cut back clear of the west path
    (-458, -1060, 14, 24, 16), (-458, -1148, 12, 26, 12), (-412, -1014, 20, 12, 12),
    (-338, -1014, 20, 12, 12), (-412, -1182, 20, 11, 12), (-338, -1182, 20, 11, 12), (-512, -958, 14, 22, 16), (-470, -1234, 20, 12, 10),
    (-546, -1230, 16, 12, 10), (-396, -914, 10, 14, 10),
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


def door_lanes():
    """One straight lane per doorway, as a box (x0, x1, z0, z1): the doorway's width, from
    the loop's centre line where it crosses the doorway's axis to the hall's edge."""
    px_, pz_, ph = PYRAMID
    north, south = catmull(ROUTES[1]), catmull(ROUTES[2])
    lanes = []
    for (dx, dz, curve) in ((1, 0, south), (-1, 0, north), (0, 1, north), (0, -1, south)):
        if dx:
            # the curve point nearest the axis z = pz_, on this side of the pyramid
            q = min((c for c in curve if (c[0] - px_) * dx > ph), key=lambda c: abs(c[1] - pz_))
            a, b = sorted((q[0], px_ + dx * PYR_HALL))
            lanes.append((a, b, pz_ - PYR_DOOR, pz_ + PYR_DOOR))
        else:
            q = min((c for c in curve if (c[1] - pz_) * dz > ph), key=lambda c: abs(c[0] - px_))
            a, b = sorted((q[1], pz_ + dz * PYR_HALL))
            lanes.append((px_ - PYR_DOOR, px_ + PYR_DOOR, a, b))
    return lanes


def all_routes():
    return ROUTES


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


def rim_dist(x, z):
    """Rectilinear distance from a cell outside the walkable outline to its nearest edge."""
    best = None
    n = len(POLY)
    for e in range(n):
        (ax, az), (bx, bz) = POLY[e], POLY[(e + 1) % n]
        if az == bz:
            lo, hi = min(ax, bx), max(ax, bx)
            d = max(lo - x, 0, x - hi, abs(z - az))
        else:
            lo, hi = min(az, bz), max(az, bz)
            d = max(lo - z, 0, z - hi, abs(x - ax))
        if best is None or d < best:
            best = d
    return best


def subtract(box, hole):
    """The parts of box (x0, x1, z0, z1, y0, y1) outside hole: at most six boxes."""
    x0, x1, z0, z1, y0, y1 = box
    hx0, hx1, hz0, hz1, hy0, hy1 = hole
    if hx0 >= x1 or hx1 <= x0 or hz0 >= z1 or hz1 <= z0 or hy0 >= y1 or hy1 <= y0:
        return [box]
    out = []
    if hx0 > x0:
        out.append((x0, hx0, z0, z1, y0, y1))
    if hx1 < x1:
        out.append((hx1, x1, z0, z1, y0, y1))
    mx0, mx1 = max(x0, hx0), min(x1, hx1)
    if hz0 > z0:
        out.append((mx0, mx1, z0, hz0, y0, y1))
    if hz1 < z1:
        out.append((mx0, mx1, hz1, z1, y0, y1))
    mz0, mz1 = max(z0, hz0), min(z1, hz1)
    if hy0 > y0:
        out.append((mx0, mx1, mz0, mz1, y0, hy0))
    if hy1 < y1:
        out.append((mx0, mx1, mz0, mz1, hy1, y1))
    return out


TOWER_SLIT = "6B4A2B"


def tower_boxes(cx, cz):
    """One sandstone tower (a decoration): a stepped plinth, a square shaft with two bands
    and a window slit on every face, a cap, eight merlons round the top and a small gold
    stepped point in the middle (the pyramid's capstone, small). (x0, x1, z0, z1, y0, y1,
    colour, part name) in world terms."""
    out = []

    def sq(half, y0, y1, colour, name, dx=0.0, dz=0.0, hz=None):
        hz = half if hz is None else hz
        out.append((cx + dx - half, cx + dx + half, cz + dz - hz, cz + dz + hz, y0, y1, colour, name))

    # heights kept off the pyramid's slab tops (8 + 2.5k) and sides off its slab edges
    # (even halves), so no face of a tower lies in a face of the pyramid where they meet
    # 50% thicker (the user, 2026-10-26): a 22.5-wide shaft
    sq(13.5, FLOOR, 11.2, SANDSTONE_BAND, "Plinth")
    sq(12.6, 11.2, 12.4, SANDSTONE, "Step")
    sq(11.25, 12.4, 60, SANDSTONE, "Shaft")
    sq(11.9, 26.2, 27.8, SANDSTONE_BAND, "Band")
    sq(11.9, 44.2, 45.8, SANDSTONE_BAND, "Band")
    # two slits on each face, 0.1 proud of the shaft
    for (y0, y1) in ((32, 38.4), (49.2, 54.4)):
        sq(1.2, y0, y1, TOWER_SLIT, "Slit", dz=-11.3, hz=0.05)
        sq(1.2, y0, y1, TOWER_SLIT, "Slit", dz=11.3, hz=0.05)
        sq(0.05, y0, y1, TOWER_SLIT, "Slit", dx=-11.3, hz=1.2)
        sq(0.05, y0, y1, TOWER_SLIT, "Slit", dx=11.3, hz=1.2)
    sq(12.9, 60, 62.6, SANDSTONE_BAND, "Cap")
    for mx in (-11.15, 0, 11.15):
        for mz in (-11.15, 0, 11.15):
            if mx == 0 and mz == 0:
                continue
            sq(1.6, 62.6, 66.2, SANDSTONE, "Merlon", dx=mx, dz=mz)
    sq(4.5, 62.6, 64.4, GOLD, "Gold")
    sq(2.4, 64.4, 67.2, GOLD, "Gold")
    return out


PORTAL_LIGHT = "EAD3A0"


def portal_boxes(side):
    """The frame round one doorway, in the pyramid's terms: d out from its centre along
    `side` (E, W, N or S), t across. Two pillars (a pale base, a band-coloured shaft, a gold
    capital) set into the pyramid's face and standing 1.6 proud of its foot, a lintel across
    them hanging 0.4 under the doorway's top, a gold strip and a pale cap. Heights and sides
    keep off the pyramid's slab faces. (x0, x1, z0, z1, y0, y1, colour, part name)."""
    px_, pz_, _ = PYRAMID
    out = []

    def box(d0, d1, t0, t1, y0, y1, colour, name):
        if side in ("E", "W"):
            sx = 1 if side == "E" else -1
            xa, xb = sorted((px_ + sx * d0, px_ + sx * d1))
            out.append((xa, xb, pz_ + t0, pz_ + t1, y0, y1, colour, name))
        else:
            sz = 1 if side == "N" else -1
            za, zb = sorted((pz_ + sz * d0, pz_ + sz * d1))
            out.append((px_ + t0, px_ + t1, za, zb, y0, y1, colour, name))

    for s_ in (-1, 1):
        t0, t1 = sorted((s_ * 5.8, s_ * 9.4))
        b0, b1 = sorted((s_ * 5.6, s_ * 9.8))
        box(47, 62, b0, b1, FLOOR, 9.6, PORTAL_LIGHT, "PillarBase")
        box(47.2, 61.6, t0, t1, 9.6, 18.7, SANDSTONE_BAND, "Pillar")
        box(47, 62, b0, b1, 18.7, 20.1, GOLD, "Capital")
    box(45.8, 62.2, -10.4, 10.4, 20.1, 23.2, SANDSTONE_BAND, "Lintel")
    box(45.6, 62.6, -10.8, 10.8, 23.2, 23.9, GOLD, "Trim")
    box(45.6, 61.8, -9, 9, 23.9, 25.2, PORTAL_LIGHT, "Cap")
    return out


def portals():
    out = []
    for side in ("E", "W", "N", "S"):
        for b in portal_boxes(side):
            out.append(("Entrance_" + side, *b))
    return out


def towers():
    px_, pz_, _ = PYRAMID
    out = []
    for name, sx, sz in (("Tower_NE", 1, 1), ("Tower_NW", -1, 1), ("Tower_SE", 1, -1), ("Tower_SW", -1, -1)):
        for b in tower_boxes(px_ + sx * TOWER_OUT, pz_ + sz * TOWER_OUT):
            out.append((name, *b))
    return out


def build():
    x0, x1 = -646, -176
    z1, z0 = -818, -1368   # north, south
    nx = (x1 - x0) // CELL
    nz = (z1 - z0) // CELL

    def cell_of(x, z):
        return int((x - x0) // CELL), int((z1 - z) // CELL)

    # the road: 4-stud blocks within a 12-stud square brush of the curves
    samples = [p for r in all_routes() for p in catmull(r)]
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
    # the doorway lanes, cell by cell (exactly their width, so each fills its tunnel)
    for (lx0, lx1, lz0, lz1) in door_lanes():
        for i in range(int((lx0 - x0) // CELL), int((lx1 - x0) // CELL) + 1):
            for j in range(int((z1 - lz1) // CELL), int((z1 - lz0) // CELL) + 1):
                cx, cz = x0 + CELL * i + CELL / 2, z1 - CELL * j - CELL / 2
                if lx0 < cx < lx1 and lz0 < cz < lz1:
                    path_cells.add((i, j))

    # the volcano: as wide as it can be with VOLCANO_GAP studs of sand before the road
    vx, vz = VOLCANO
    vr = VOLCANO_MAX
    for (ci, cj) in path_cells:
        qx = min(max(vx, x0 + CELL * ci), x0 + CELL * ci + CELL)
        qz = min(max(vz, z1 - CELL * cj - CELL), z1 - CELL * cj)
        vr = min(vr, math.hypot(qx - vx, qz - vz) - VOLCANO_GAP)
    vr = VOLCANO_STEP * math.floor(vr / VOLCANO_STEP)
    crater = 0.3 * vr
    rings = int((vr - crater) // VOLCANO_STEP)

    def volcano_top(x, z):
        """(top, colour) of the volcano at a cell, or None off it."""
        r = math.hypot(x - vx, z - vz)
        if r >= vr:
            return None
        if r < crater:
            return FLOOR + VOLCANO_RISE * (rings - 2), CRATER
        k = min(rings - 1, int((vr - r) // VOLCANO_STEP))
        return FLOOR + VOLCANO_RISE * (k + 1), BASALT[min(2, 3 * k // rings)]

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
    d0, d1 = ph - 1, ph + PYR_APPROACH
    aw = PYR_APPROACH_HALF
    keep_flat = [
        (px_ + d0, px_ + d1, pz_ - aw, pz_ + aw),
        (px_ - d1, px_ - d0, pz_ - aw, pz_ + aw),
        (px_ - aw, px_ + aw, pz_ + d0, pz_ + d1),
        (px_ - aw, px_ + aw, pz_ - d1, pz_ - d0),
    ]
    for sx in (-1, 1):
        for sz in (-1, 1):
            tx, tz = px_ + sx * TOWER_OUT, pz_ + sz * TOWER_OUT
            keep_flat.append((tx - TOWER_CLEAR, tx + TOWER_CLEAR, tz - TOWER_CLEAR, tz + TOWER_CLEAR))
    cells = {}
    water_cells = []
    for i in range(nx):
        x = x0 + CELL * i + CELL / 2
        for j in range(nz):
            z = z1 - CELL * j - CELL / 2
            corridor = -216 < x < EAST_LIMIT and corridor_d(x, z) <= CORRIDOR_HALF
            if inside(x, z) or corridor:
                v = (FLOOR, SAND, "Sand", "Sand")
                if (i, j) in path_cells:
                    v = (FLOOR, PATH, "Paths", "Path")
                elif abs(x - px_) < ph and abs(z - pz_) < ph:
                    v = None  # under the pyramid (its own slabs)
                else:
                    orr = wob(x, z, *OASIS, seed=1.2)
                    vt = volcano_top(x, z)
                    if orr < 0.55:
                        v = (4, BED_DEEP, "Oasis", "Bed")
                        water_cells.append((x, z))
                    elif orr < 1.0:
                        v = (5.5, BED_SHALLOW, "Oasis", "Bed")
                        water_cells.append((x, z))
                    elif orr < 1.25:
                        v = (FLOOR, OASIS_GRASS, "Oasis", "Grass")
                    elif vt:
                        v = (vt[0], vt[1], "Volcano", "Basalt")
                    else:
                        h = 0
                        for n_, (cx, cz, rx, rz, H) in enumerate(DUNES):
                            dr = mound_r(x, z, cx, cz, rx, rz, seed=2.0 + n_)
                            if dr < 1:
                                h = max(h, 2 * math.floor(H * (1 - dr ** 2.2) ** 0.8 / 2 + 0.5))
                        # slope down to the road (and keep 2 studs of flat sand beside it)
                        h = min(h, max(0, int(dist.get((i, j), 99) - 2)))
                        # and down to the pyramid's foot, its doorways' approaches and its towers
                        gap = max(abs(x - px_), abs(z - pz_)) - ph
                        h = min(h, max(0, int(gap - 2)))
                        for (kx0, kx1, kz0, kz1) in keep_flat:
                            kd = math.hypot(max(kx0 - x, x - kx1, 0), max(kz0 - z, z - kz1, 0))
                            h = min(h, max(0, int(kd - 2)))
                        h -= h % 2  # 2-stud steps
                        if h > 0:
                            v = (FLOOR + h, dune_colour(FLOOR + h), "Dunes", "Dune")
                if v:
                    cells[(i, j)] = v
            else:
                if x > EAST_LIMIT:
                    continue
                d = rim_dist(x, z)
                if d > RIM_LEVELS * RIM_LEDGE + RIM_BACK:
                    continue
                lv = min(RIM_LEVELS, 1 + int(d // RIM_LEDGE))
                if x > -216 and corridor_d(x, z) <= CORRIDOR_HALF + CORRIDOR_WALL:
                    lv = RIM_LEVELS  # the corridor's walls are the rim's full height
                top = FLOOR + TERRACE * lv
                if lv == RIM_LEVELS and d >= RIM_LEVELS * RIM_LEDGE and x < -216 and any(
                        a < x < b and c < z < e for (a, b, c, e) in RIM_CAP_STRETCHES):
                    top += RIM_CAP
                cells[(i, j)] = (top, dune_colour(top), "Rim", "Dune")
                # the volcano's back runs up into the rim where it reaches it, taking the
                # whole first terrace there (a strip of it left between the volcano's rings
                # and the second terrace was a 2-stud sliver)
                vt = volcano_top(x, z)
                if vt and (vt[0] > top or lv == 1):
                    cells[(i, j)] = (vt[0], vt[1], "Volcano", "Basalt")

    # where the volcano's round foot meets the rim's straight first terrace, little wedges
    # of terrace are left between them: give those to the volcano, so no part of the rim is
    # narrower than an 8-stud square (the user: thick blocks only)
    def thin(c):
        t = cells[c][0]
        for a in range(-3, 1):
            for b in range(-3, 1):
                if all(cells.get((c[0] + a + u, c[1] + b + w), (None,))[0] == t for u in range(4) for w in range(4)):
                    return False
        return True
    for _ in range(12):
        changed = False
        for c, v in list(cells.items()):
            if v[2] != "Rim" or not thin(c):
                continue
            near = [cells[n] for n in ((c[0] + 1, c[1]), (c[0] - 1, c[1]), (c[0], c[1] + 1), (c[0], c[1] - 1))
                    if n in cells and cells[n][2] == "Volcano"]
            if near:
                cells[c] = min(near, key=lambda n: abs(n[0] - v[0]))
                changed = True
        if not changed:
            break

    # where the corridor's diagonal walls meet the straight terraces, little wedges of
    # terrace are left: raise them to the wall beside them
    for _ in range(12):
        changed = False
        for c, v in list(cells.items()):
            if v[2] != "Rim" or not thin(c):
                continue
            near = [cells[n] for n in ((c[0] + 1, c[1]), (c[0] - 1, c[1]), (c[0], c[1] + 1), (c[0], c[1] - 1))
                    if n in cells and cells[n][2] == "Rim" and cells[n][0] > v[0]]
            if near:
                cells[c] = max(near, key=lambda n: n[0])
                changed = True
        if not changed:
            break

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

    # the pyramid: one square slab a step, from the sand up, with the hall and the four
    # doorways taken out of them (each slab split round the holes into world-aligned boxes)
    # each doorway's tunnel, from the hall's edge out past the foot, down to the columns' base:
    # its floor is the doorway lane's path
    hd, out_ = PYR_HALL, ph + 1
    doors = [
        (px_ + hd, px_ + out_, pz_ - PYR_DOOR, pz_ + PYR_DOOR, BASE, PYR_DOOR_TOP),
        (px_ - out_, px_ - hd, pz_ - PYR_DOOR, pz_ + PYR_DOOR, BASE, PYR_DOOR_TOP),
        (px_ - PYR_DOOR, px_ + PYR_DOOR, pz_ + hd, pz_ + out_, BASE, PYR_DOOR_TOP),
        (px_ - PYR_DOOR, px_ + PYR_DOOR, pz_ - out_, pz_ - hd, BASE, PYR_DOOR_TOP),
    ]
    half, y, k = ph, BASE, 0
    while half >= 2:
        top = FLOOR + PYR_RISE * (k + 1) if k > 0 else FLOOR + PYR_RISE
        bottom = BASE if k == 0 else FLOOR + PYR_RISE * k
        colour = GOLD if half <= 4 else (SANDSTONE_BAND if k % 4 == 3 else SANDSTONE)
        pieces = [(px_ - half, px_ + half, pz_ - half, pz_ + half, bottom, top)]
        # the hall: this slab's ring keeps the shell's thickness, capped at the hall's width
        hall = min(PYR_HALL, half - PYR_SHELL)
        holes = list(doors)
        if hall >= 2:
            holes.append((px_ - hall, px_ + hall, pz_ - hall, pz_ + hall, max(bottom, FLOOR), top))
        for hole in holes:
            pieces = [q for pc in pieces for q in subtract(pc, hole)]
        for pc in pieces:
            boxes.append((*pc, colour, "Pyramid", "Gold" if colour == GOLD else "Sandstone"))
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
            if not (cx0 + CELL == EAST_LIMIT and corridor_d(cx0 + 1, cz_n - 1) <= CORRIDOR_HALF):
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
    return boxes, water, cells, borders, samples, vr


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
    lines.append("\ttowers = {")
    for t in towers():
        name, x0, x1, z0, z1, y0, y1, col, part = t
        lines.append(f'\t\t{{"{name}", {x0}, {x1}, {z0}, {z1}, {y0}, {y1}, "{col}", "{part}"}},')
    lines.append("\t},")
    lines.append("\tportals = {")
    for t in portals():
        name, x0, x1, z0, z1, y0, y1, col, part = t
        lines.append(f'\t\t{{"{name}", {x0}, {x1}, {z0}, {z1}, {y0}, {y1}, "{col}", "{part}"}},')
    lines.append("\t},")
    lines.append(f"\tboss = {{{', '.join(str(v) for v in BOSS)}}},")
    lines.append(f"\tplace = {{ from = {{ {EAST_LIMIT}, {CORRIDOR_Z} }}, to = {{ {WORLD_END[0]}, {WORLD_END[1]} }}, turn = {WORLD_TURN}, drop = {WORLD_DROP} }},")
    lines.append("}")
    open(OUT, "w", encoding="utf-8", newline="\n").write("\n".join(lines) + "\n")


def route_length(points):
    c = catmull(points)
    return sum(math.dist(c[k], c[k + 1]) for k in range(len(c) - 1))


if __name__ == "__main__":
    boxes, water, cells, borders, samples, vr = build()
    write(boxes, water, borders)
    by = {}
    for b in boxes:
        by[b[7]] = by.get(b[7], 0) + 1
    print("boxes", len(boxes), by, "borders", len(borders))
    lens = [round(route_length(r)) for r in all_routes()]
    print("road lengths (entry, north way, south way, west arm, doorways E W N S)", lens,
          "entry to the west arm: north", lens[0] + lens[1] + lens[3], "south", lens[0] + lens[2] + lens[3])
    print("doorway lanes (x0, x1, z0, z1)", [tuple(round(v) for v in l) for l in door_lanes()])
    tall = max(b[5] for b in boxes if b[7] == "Dunes")
    print("volcano radius", vr, "top", max(b[5] for b in boxes if b[7] == "Volcano"), "tallest mound top", tall, "pyramid top", max(b[5] for b in boxes if b[7] == "Pyramid"))
