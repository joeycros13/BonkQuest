"""World 4's secret tomb, v2 (2026-10-29, the user's design and fixes on https://claude.ai/artifact/29us8FDHD1zBP9Nw9WRBnE):
the quicksand at Obelisk_3's shadow tip drops you into a real maze full of traps; its goal, the sanctum in the middle,
stands on its own island of walls so following one wall never finds it; stairs in the sanctum lead down to the boulder
tunnel and the Phantom Pharaoh's burial chamber.

Writes src/shared/DevData/W4Tomb.luau (temporary, never committed: art/tools/w4/build_tomb_studio.luau builds the tomb
from it in Studio, then the file is deleted). Coordinates are the tomb's own: x east, z south from the maze's north-west
corner, y up from the maze floor's top; the build adds ORIGIN.

  - Maze: N x N cells of CELL studs (8-wide corridors between 2-thick walls, WALL_H tall), a recursive backtracker with
    most dead ends braided away and extra openings (loops). The 3 x 3 sanctum in the middle opens west and east; no
    wall touching its outside meets a wall connected to the outer walls (checked with union-find over the grid points,
    and by walking both hands from the landing in every starting direction). Shortest way in 30..40 cells.
  - Traps on every kind of cell, wrong turns and dead ends too: lava pits with a balance beam, buzzsaws in floor slots,
    swinging axes, jackal-head fire jets and dart walls (on straight cells), collapsing floors (straight cells, a safe
    path of whole tiles), spike tiles (any cell). Never two of a kind within 2 cells. Clutter (rubble, a broken statue,
    a sarcophagus, bones, canopic jars) in dead ends and corners. Six scarab checkpoints spread farthest-first (1 = the
    landing) and a seventh in the sanctum.
  - Under the maze: stairs down from the sanctum's north row, the boulder tunnel east (alcoves both sides), then the
    burial chamber (the v1 chamber's contents moved by CHAMBER_DELTA).
  - Walls are boxes on the grid lines; a horizontal (east-west) wall is 1.9 thick so its faces never sit in a
    north-south wall's face where they meet. Each wall has a base band and a lapis frieze a hair proud of it.

Usage: python build_tomb.py
"""
import json
import math
import os
import random
from collections import deque

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "..", "src", "shared", "DevData", "W4Tomb.luau")

N, CELL = 17, 10
S0, S1 = 7, 9                      # the sanctum: cells 7..9 both ways
START = (0, 0)                     # the landing: the north-west corner
WALL_H, ROOF_T, FLOOR_T = 11, 2, 4
SIZE = N * CELL
ORIGIN = (-2400, -100, -2400)
LOW = -14                          # the tunnel and chamber floor's top
TRAP_SEED, SCATTER_SEED = 0, 11

WALL, FLOOR, ROOF, BAND, FRIEZE = "cdb48c", "ad9470", "54463a", "8f7656", "2f5fb3"
STEP, CHAMBER = "c4a378", "d9b27a"

D = {"N": (-1, 0, "S"), "S": (1, 0, "N"), "E": (0, 1, "W"), "W": (0, -1, "E")}


def in_s(r, c):
    return S0 <= r <= S1 and S0 <= c <= S1


# ---------------------------------------------------------------- the maze
def build(seed, braid=0.5, loops=18):
    rnd = random.Random(seed)
    W = {(r, c): {"N": True, "E": True, "S": True, "W": True} for r in range(N) for c in range(N)}

    def opn(a, d):
        r, c = a
        dr, dc, o = D[d]
        W[a][d] = False
        W[(r + dr, c + dc)][o] = False

    for r in range(S0, S1 + 1):            # the sanctum: one open room
        for c in range(S0, S1 + 1):
            if c < S1:
                opn((r, c), "E")
            if r < S1:
                opn((r, c), "S")
    seen = {(r, c) for r in range(N) for c in range(N) if in_s(r, c)}
    stack = [START]
    seen.add(START)
    while stack:
        r, c = stack[-1]
        opts = [(d, (r + dr, c + dc)) for d, (dr, dc, o) in D.items()
                if 0 <= r + dr < N and 0 <= c + dc < N and (r + dr, c + dc) not in seen]
        if not opts:
            stack.pop()
            continue
        d, nb = rnd.choice(opts)
        opn((r, c), d)
        seen.add(nb)
        stack.append(nb)
    opn((8, 6), "E")                       # the sanctum's two doors, west and east
    opn((8, 10), "W")

    def deg(p):
        return sum(1 for d in "NESW" if not W[p][d])

    dead = [p for p in W if deg(p) == 1 and not in_s(*p) and p != START]
    rnd.shuffle(dead)
    for p in dead[: int(len(dead) * braid)]:   # braid most dead ends into loops, keep some wrong turns
        if deg(p) != 1:
            continue
        r, c = p
        opts = [d for d, (dr, dc, o) in D.items() if W[p][d] and 0 <= r + dr < N and 0 <= c + dc < N and not in_s(r + dr, c + dc)]
        if opts:
            opn(p, rnd.choice(opts))
    for _ in range(loops):
        r, c = rnd.randrange(N), rnd.randrange(N)
        d = rnd.choice("NESW")
        dr, dc, o = D[d]
        if 0 <= r + dr < N and 0 <= c + dc < N and not in_s(r, c) and not in_s(r + dr, c + dc):
            opn((r, c), d)
    # cut every wall that touches the sanctum's perimeter from outside, so the sanctum's walls are an island
    for y in range(S0, S1 + 2):
        for x in range(S0, S1 + 2):
            if not (y in (S0, S1 + 1) or x in (S0, S1 + 1)):
                continue
            if x == S0 and 0 < y < N and W[(y, x - 1)]["N"]:
                opn((y, x - 1), "N")
            if x == S1 + 1 and 0 < y < N and W[(y, x)]["N"]:
                opn((y, x), "N")
            if y == S0 and 0 < x < N and W[(y - 1, x)]["W"]:
                opn((y - 1, x), "W")
            if y == S1 + 1 and 0 < x < N and W[(y, x)]["W"]:
                opn((y, x), "W")
    return W


def segments(W):
    segs = set()
    for r in range(N):
        for c in range(N):
            if W[(r, c)]["N"]:
                segs.add(((r, c), (r, c + 1)))
            if W[(r, c)]["W"]:
                segs.add(((r, c), (r + 1, c)))
            if r == N - 1 and W[(r, c)]["S"]:
                segs.add(((N, c), (N, c + 1)))
            if c == N - 1 and W[(r, c)]["E"]:
                segs.add(((r, N), (r + 1, N)))
    return segs


def find_root(parent, a):
    parent.setdefault(a, a)
    while parent[a] != a:
        parent[a] = parent[parent[a]]
        a = parent[a]
    return a


def follow(W, hand, heading):
    """walk from the landing keeping one hand on the wall; True if it ever reaches the sanctum"""
    order, dirs = {"N": 0, "E": 1, "S": 2, "W": 3}, "NESW"
    pos, h = START, heading
    for _ in range(N * N * 16):
        if in_s(*pos):
            return True
        turns = [-1, 0, 1, 2] if hand == "left" else [1, 0, -1, 2]
        for t in turns:
            d = dirs[(order[h] + t) % 4]
            if not W[pos][d]:
                dr, dc, _ = D[d]
                pos, h = (pos[0] + dr, pos[1] + dc), d
                break
    return False


def bfs(W, src):
    dist = {src: 0}
    q = deque([src])
    while q:
        p = q.popleft()
        for d, (dr, dc, _) in D.items():
            if not W[p][d]:
                nb = (p[0] + dr, p[1] + dc)
                if nb not in dist:
                    dist[nb] = dist[p] + 1
                    q.append(nb)
    return dist


def pick_maze():
    for seed in range(TRAP_SEED, TRAP_SEED + 300):
        W = build(seed)
        parent = {}
        for a, b in segments(W):
            parent[find_root(parent, a)] = find_root(parent, b)
        outer = find_root(parent, (0, 0))
        if any(find_root(parent, p) == outer for p in [(S0, S0), (S0, S1 + 1), (S1 + 1, S0), (S1 + 1, S1 + 1)]):
            continue
        if any(follow(W, hand, h) for hand in ("left", "right") for h in "NESW"):
            continue
        dist = bfs(W, START)
        if len(dist) != N * N:
            continue
        goal = min(dist[(8, 6)], dist[(8, 10)])
        dead = sum(1 for p in W if sum(1 for d in "NESW" if not W[p][d]) == 1)
        if 30 <= goal <= 40 and dead >= 14:
            edges = sum(1 for p in W for d in "ES" if not W[p][d])
            return seed, W, goal, dead, edges - N * N + 1
    raise SystemExit("no maze passed the checks")


seed, W, goal, dead_count, loop_count = pick_maze()


def deg(p):
    return sum(1 for d in "NESW" if not W[p][d])


def straight(p):
    w = W[p]
    if not w["N"] and not w["S"] and w["E"] and w["W"]:
        return "z"
    if not w["E"] and not w["W"] and w["N"] and w["S"]:
        return "x"
    return None


# ---------------------------------------------------------------- what goes where
rnd = random.Random(SCATTER_SEED)
cells = [(r, c) for r in range(N) for c in range(N) if not in_s(r, c)]
near_start = {START, (0, 1), (1, 0), (1, 1)}
door_cells = {(8, 6), (8, 10)}
cps = []
pool = [p for p in cells if p not in near_start and deg(p) >= 2]
for _ in range(5):
    cps.append(max(pool, key=lambda p: min(abs(p[0] - q[0]) + abs(p[1] - q[1]) for q in [START] + cps)))
taken = set(cps) | near_start | door_cells
WANT = [("Lava", 10), ("Saw", 12), ("Blade", 8), ("Fire", 8), ("Collapse", 6), ("Darts", 12), ("Spikes", 14)]
NEED_STRAIGHT = {"Lava", "Saw", "Blade", "Fire", "Collapse", "Darts"}
placed = []
for kind, want in WANT:
    cand = [p for p in cells if p not in taken and (straight(p) if kind in NEED_STRAIGHT else True)]
    rnd.shuffle(cand)
    n = 0
    for p in cand:
        if n >= want:
            break
        if any(t["kind"] == kind and abs(t["r"] - p[0]) + abs(t["c"] - p[1]) <= 2 for t in placed):
            continue
        placed.append({"kind": kind, "r": p[0], "c": p[1], "axis": straight(p) or "z"})
        taken.add(p)
        n += 1
clutter_cells = [p for p in cells if p not in taken and (deg(p) == 1 or (deg(p) == 2 and not straight(p)))]
rnd.shuffle(clutter_cells)
clutter_cells = clutter_cells[:28]
taken |= set(clutter_cells)

# ---------------------------------------------------------------- geometry
boxes = []


def box(folder, name, x0, x1, y0, y1, z0, z1, color, **extra):
    b = {"f": folder, "n": name, "c": [round((x0 + x1) / 2, 3), round((y0 + y1) / 2, 3), round((z0 + z1) / 2, 3)],
         "s": [round(x1 - x0, 3), round(y1 - y0, 3), round(z1 - z0, 3)], "col": color}
    b.update(extra)
    boxes.append(b)


def wall_box(folder, x0, x1, y0, y1, z0, z1, horizontal, color=WALL, bands=True):
    box(folder, "Wall", x0, x1, y0, y1, z0, z1, color)
    if bands:
        g, h = 0.06, (0.02 if horizontal else 0.0)
        box("Bands", "Band", x0 - g, x1 + g, y0, y0 + 0.6 + h, z0 - g, z1 + g, BAND)
        box("Bands", "Frieze", x0 - g, x1 + g, 8.6, 9.1 + h, z0 - g, z1 + g, FRIEZE)


# maze walls: merge runs along each grid line. North-south lines (x = k * CELL)
for k in range(N + 1):
    run = None
    for r in range(N + 1):
        on = r < N and ((k < N and W[(r, k)]["W"]) or (k == N and W[(r, N - 1)]["E"]))
        if on and run is None:
            run = r
        if not on and run is not None:
            wall_box("Walls", k * CELL - 1, k * CELL + 1, 0, WALL_H, run * CELL - 1, r * CELL + 1, False)
            run = None
for k in range(N + 1):                    # east-west lines (z = k * CELL)
    run = None
    for c in range(N + 1):
        on = c < N and ((k < N and W[(k, c)]["N"]) or (k == N and W[(N - 1, c)]["S"]))
        if on and run is None:
            run = c
        if not on and run is not None:
            wall_box("Walls", run * CELL - 1, c * CELL + 1, 0, WALL_H, k * CELL - 0.95, k * CELL + 0.95, True)
            run = None

# the stairwell (the sanctum's north row) and the lava pits are holes in the maze floor
STAIR_X0, STAIR_X1, LANE_Z0, LANE_Z1 = 76, 94, 72, 80
holes = [(STAIR_X0, STAIR_X1, LANE_Z0, LANE_Z1)]
lava = []
for t in placed:
    if t["kind"] != "Lava":
        continue
    r, c = t["r"], t["c"]
    if t["axis"] == "z":
        hole = (c * CELL + 1, c * CELL + 9, r * CELL, r * CELL + 10)
    else:
        hole = (c * CELL, c * CELL + 10, r * CELL + 1, r * CELL + 9)
    holes.append(hole)
    t["hole"] = hole
    lava.append(t)

FX0, FX1, FZ0, FZ1 = -1, SIZE + 1, -1, SIZE + 1
blocked = set()
for x0, x1, z0, z1 in holes:
    for x in range(x0, x1):
        for z in range(z0, z1):
            blocked.add((x, z))
done = set()
for z in range(FZ0, FZ1):                 # greedy rectangles of the floor slab round the holes
    for x in range(FX0, FX1):
        if (x, z) in blocked or (x, z) in done:
            continue
        x1 = x
        while x1 < FX1 and (x1, z) not in blocked and (x1, z) not in done:
            x1 += 1
        z1 = z + 1
        while z1 < FZ1 and all((xx, z1) not in blocked and (xx, z1) not in done for xx in range(x, x1)):
            z1 += 1
        for zz in range(z, z1):
            for xx in range(x, x1):
                done.add((xx, zz))
        box("Floor", "Floor", x, x1, -FLOOR_T, 0, z, z1, FLOOR)
box("Roof", "Roof", FX0, FX1, WALL_H, WALL_H + ROOF_T, FZ0, FZ1, ROOF)

# stairs: 13 steps of 1 down eastward, then the tunnel floor at LOW
RUN = (STAIR_X1 - STAIR_X0 - 0.5) / 14.0          # 1.25
for k in range(1, 14):
    box("Lower", "Step", STAIR_X0 + RUN * (k - 1), STAIR_X0 + RUN * k, LOW, -k, LANE_Z0, LANE_Z1, STEP)
STEPS_END = STAIR_X0 + RUN * 13
TUNNEL_X1 = 172                                    # the chamber's west wall starts here
ALCOVES_N, ALCOVES_S = [112, 144], [128, 160]
AL_W, AL_D = 4, 4
box("Lower", "Floor", STAIR_X0 - 2, TUNNEL_X1, LOW - FLOOR_T, LOW, LANE_Z0 - 2, LANE_Z1 + 2, FLOOR)
box("Lower", "Wall", STAIR_X0 - 2, STAIR_X0, LOW, -FLOOR_T, LANE_Z0, LANE_Z1, WALL)          # the stairwell's west end


def tunnel_wall(z0, z1, gaps):
    x = STAIR_X0 - 2
    for g in sorted(gaps):
        box("Lower", "Wall", x, g - AL_W / 2, LOW, -FLOOR_T, z0, z1, WALL)
        x = g + AL_W / 2
    box("Lower", "Wall", x, TUNNEL_X1, LOW, -FLOOR_T, z0, z1, WALL)


tunnel_wall(LANE_Z0 - 2, LANE_Z0, ALCOVES_N)
tunnel_wall(LANE_Z1, LANE_Z1 + 2, ALCOVES_S)
for g in ALCOVES_N:
    z0 = LANE_Z0 - 2 - AL_D
    box("Lower", "Floor", g - AL_W / 2 - 2, g + AL_W / 2 + 2, LOW - FLOOR_T, LOW, z0 - 2, LANE_Z0 - 2, FLOOR)
    box("Lower", "Wall", g - AL_W / 2 - 2, g - AL_W / 2, LOW, -FLOOR_T, z0, LANE_Z0 - 2, WALL)
    box("Lower", "Wall", g + AL_W / 2, g + AL_W / 2 + 2, LOW, -FLOOR_T, z0, LANE_Z0 - 2, WALL)
    box("Lower", "Wall", g - AL_W / 2 - 2, g + AL_W / 2 + 2, LOW, -FLOOR_T, z0 - 2, z0, WALL)
for g in ALCOVES_S:
    z1 = LANE_Z1 + 2 + AL_D
    box("Lower", "Floor", g - AL_W / 2 - 2, g + AL_W / 2 + 2, LOW - FLOOR_T, LOW, LANE_Z1 + 2, z1 + 2, FLOOR)
    box("Lower", "Wall", g - AL_W / 2 - 2, g - AL_W / 2, LOW, -FLOOR_T, LANE_Z1 + 2, z1, WALL)
    box("Lower", "Wall", g + AL_W / 2, g + AL_W / 2 + 2, LOW, -FLOOR_T, LANE_Z1 + 2, z1, WALL)
    box("Lower", "Wall", g - AL_W / 2 - 2, g + AL_W / 2 + 2, LOW, -FLOOR_T, z1, z1 + 2, WALL)
# the tunnel's roof past the maze slab's east edge, up to the chamber's wall
box("Lower", "Roof", FX1, TUNNEL_X1, -FLOOR_T, 0, LANE_Z0 - 2, LANE_Z1 + 2, ROOF)

# the chamber: inside x 174..214, z 56..96, floor LOW, 20 tall; a 10-wide doorway west on the lane
CX0, CX1, CZ0, CZ1, CH = TUNNEL_X1 + 2, TUNNEL_X1 + 42, 56, 96, 20
DOOR_Z0, DOOR_Z1 = LANE_Z0 - 1, LANE_Z1 + 1
CTOP = LOW + CH
box("Chamber", "Wall", TUNNEL_X1, CX0, LOW, CTOP, CZ0 - 2, DOOR_Z0, CHAMBER)
box("Chamber", "Wall", TUNNEL_X1, CX0, LOW, CTOP, DOOR_Z1, CZ1 + 2, CHAMBER)
box("Chamber", "Lintel", TUNNEL_X1, CX0, -FLOOR_T, CTOP, DOOR_Z0, DOOR_Z1, CHAMBER)
box("Chamber", "Wall", CX0, CX1 + 2, LOW, CTOP, CZ0 - 2, CZ0, CHAMBER)
box("Chamber", "Wall", CX0, CX1 + 2, LOW, CTOP, CZ1, CZ1 + 2, CHAMBER)
box("Chamber", "Wall", CX1, CX1 + 2, LOW, CTOP, CZ0, CZ1, CHAMBER)
box("Chamber", "Floor", TUNNEL_X1, CX1 + 2, LOW - FLOOR_T, LOW, CZ0 - 2, CZ1 + 2, FLOOR)
box("Chamber", "Roof", TUNNEL_X1, CX1 + 2, CTOP, CTOP + ROOF_T, CZ0 - 2, CZ1 + 2, ROOF)
# a wooden board over the doorway, standing proud of the wall on both sides
box("Chamber", "Board", TUNNEL_X1 - 1.4, CX0 + 0.6, -FLOOR_T - 0.2, -FLOOR_T + 1.6, DOOR_Z0 - 1.6, DOOR_Z1 + 1.6, "6b4a2a")
# the v1 chamber (inside x 216..256, z 130..170, floor 0) moves by this
CHAMBER_DELTA = [CX0 - 216, LOW - 0, CZ0 - 130]

# the stairwell's gold rim on the sanctum floor
box("Sanctum", "Rim", STAIR_X0 - 0.4, STAIR_X1 + 0.4, 0, 0.12, LANE_Z0 - 0.4, LANE_Z0, "e0b040")
box("Sanctum", "Rim", STAIR_X0 - 0.4, STAIR_X1 + 0.4, 0, 0.12, LANE_Z1, LANE_Z1 + 0.4, "e0b040")
box("Sanctum", "Rim", STAIR_X1, STAIR_X1 + 0.4, 0, 0.12, LANE_Z0, LANE_Z1, "e0b040")


# ---------------------------------------------------------------- placements (what the Studio build clones)
def centre(r, c):
    return [c * CELL + 5, 0, r * CELL + 5]


def yaw_across(axis):
    """a trap model's yaw: its local X across the corridor, local Z along it"""
    return 0 if axis == "z" else -90


def yaw_facing(fx, fz):
    """yaw that turns a model's front (-Z) toward (fx, fz)"""
    return round(math.degrees(math.atan2(-fx, -fz)), 3)


traps = []
counts = {}
for t in placed:
    kind, r, c, axis = t["kind"], t["r"], t["c"], t["axis"]
    counts[kind] = counts.get(kind, 0) + 1
    C = centre(r, c)
    across = (1, 0) if axis == "z" else (0, 1)
    side = rnd.choice((1, -1))
    item = {"kind": kind, "n": counts[kind], "r": r, "c": c, "pos": C, "yaw": yaw_across(axis), "axis": axis,
            "period": round(rnd.uniform(2.2, 3.0), 2), "offset": round(rnd.uniform(0, 3), 2), "side": side}
    if kind in ("Fire", "Darts"):
        # on the wall at side * across, facing back across the corridor
        item["face"] = yaw_facing(-side * across[0], -side * across[1])
        item["wall"] = [C[0] + side * across[0] * 4, 0, C[2] + side * across[1] * 4]
        if kind == "Darts":
            item["beat"] = rnd.random() < 0.5
            item["period"] = round(rnd.uniform(1.8, 2.4), 2)
        else:
            item["period"] = round(rnd.uniform(3.0, 3.6), 2)
    if kind == "Lava":
        item["hole"] = t["hole"]
        item["beam"] = rnd.choice((-2, 0, 2))
    if kind == "Collapse":
        col, safe = rnd.randrange(4), []
        for row in range(4):
            safe.append(col)
            col = max(0, min(3, col + rnd.choice((-1, 0, 1))))
        item["safe"] = safe
    traps.append(item)

checkpoints = [{"index": 1, "pos": centre(*START)}] + [{"index": i + 2, "pos": centre(*p)} for i, p in enumerate(cps)]
checkpoints.append({"index": 7, "pos": [73.5, 0, 76]})

# torches: about one cell in five, on a wall no wall trap uses, facing into the cell
wall_sides = {(t["r"], t["c"]): t["side"] for t in traps if t["kind"] in ("Fire", "Darts")}
torches = []
for r in range(N):
    for c in range(N):
        if (r + 2 * c) % 5 or in_s(r, c):
            continue
        busy = wall_sides.get((r, c))
        for d in "NESW":
            if not W[(r, c)][d]:
                continue
            dr, dc, _ = D[d]
            if busy is not None and ((d == "E" and busy == 1) or (d == "W" and busy == -1) or (d == "S" and busy == 1) or (d == "N" and busy == -1)):
                continue
            C = centre(r, c)
            torches.append({"pos": [C[0] + dc * 3.6, 7, C[2] + dr * 3.6], "face": [-dc, -dr]})
            break
for x, z, fz in [(74.5, 71.3, 1), (98.5, 71.3, 1), (74.5, 88.7, -1), (98.5, 88.7, -1)]:    # the sanctum
    torches.append({"pos": [x, 7, z], "face": [0, fz]})
for x in (100, 120, 136, 152, 168):                                                       # the tunnel
    torches.append({"pos": [x, LOW + 6.5, LANE_Z0 + 0.4], "face": [0, 1]})

# clutter: dead ends get a big piece against the back wall, corners a small one in the closed corner
BIG = ["ToppledSarcophagus", "BrokenStatue", "Rubble", "BonePile", "CanopicJars", "Rubble"]
SMALL = ["BonePile", "CanopicJars", "Rubble"]
BACK = {"ToppledSarcophagus": 0.9, "BrokenStatue": 1.35, "Rubble": 1.4, "BonePile": 1.2, "CanopicJars": 0.7}
clutter = []
bi = si = 0
for p in clutter_cells:
    C = centre(*p)
    opens = [d for d in "NESW" if not W[p][d]]
    if len(opens) == 1:
        dr, dc, _ = D[opens[0]]
        bx, bz = -dc, -dr                      # from the middle toward the back wall
        name = BIG[bi % len(BIG)]
        bi += 1
        back = BACK[name]
        pos = [C[0] + bx * (4 - back), 0, C[2] + bz * (4 - back)]
        if name == "ToppledSarcophagus":       # its local +X toward the back wall
            yaw = math.degrees(math.atan2(-bz, bx))
        else:                                  # its local +Z toward the back wall
            yaw = math.degrees(math.atan2(bx, bz))
    else:
        (dr1, dc1, _), (dr2, dc2, _) = D[opens[0]], D[opens[1]]
        bx, bz = -(dc1 + dc2), -(dr1 + dr2)    # toward the closed corner
        name = SMALL[si % len(SMALL)]
        si += 1
        pos = [C[0] + bx * 2.3, 0, C[2] + bz * 2.3]
        yaw = math.degrees(math.atan2(bx, bz)) + rnd.uniform(-20, 20)
    clutter.append({"name": name, "pos": [round(v, 3) for v in pos], "yaw": round(yaw, 2), "r": p[0], "c": p[1]})

data = {
    "origin": ORIGIN, "n": N, "cell": CELL, "wallH": WALL_H, "size": SIZE, "low": LOW,
    "boxes": boxes, "traps": traps, "checkpoints": checkpoints, "torches": torches, "clutter": clutter,
    "landing": centre(*START), "tablet": [7.0, 1.35], "chamberDelta": CHAMBER_DELTA,
    "lane": [LANE_Z0, LANE_Z1], "stairs": [STAIR_X0, STAIR_X1, STEPS_END],
    "boulder": {"start": [TUNNEL_X1 - 4, LOW + 3.3, (LANE_Z0 + LANE_Z1) / 2], "finish": [STEPS_END + 4, LOW + 3.3, (LANE_Z0 + LANE_Z1) / 2],
                "zone": [STEPS_END + 1, TUNNEL_X1, LANE_Z0, LANE_Z1]},
    "mazeZone": [FX0, TUNNEL_X1 + 2, LOW, WALL_H, FZ0, FZ1],
}


def lua(v):
    if isinstance(v, dict):
        return "{" + ", ".join(f"{k} = {lua(x)}" for k, x in v.items()) + "}"
    if isinstance(v, (list, tuple)):
        return "{" + ", ".join(lua(x) for x in v) + "}"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, str):
        return json.dumps(v)
    if v is None:
        return "nil"
    return repr(v)


os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, "w", encoding="utf-8", newline="\n") as f:
    f.write("-- generated by art/tools/w4/build_tomb.py; temporary, never committed\nreturn " + lua(data) + "\n")
kinds = {}
for t in traps:
    kinds[t["kind"]] = kinds.get(t["kind"], 0) + 1
print("seed", seed, "shortest", goal, "dead ends", dead_count, "loops", loop_count)
print("boxes", len(boxes), "traps", kinds, "clutter", len(clutter), "torches", len(torches), "checkpoints", len(checkpoints))
