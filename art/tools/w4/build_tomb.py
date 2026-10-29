"""World 4's secret tomb (2026-10-29, the user's design on https://claude.ai/artifact/29us8FDHD1zBP9Nw9WRBnE):
the quicksand at Obelisk_3's shadow tip drops you into a 13 x 13 maze of traps; a boulder hall leads to the
Phantom Pharaoh's burial chamber.

Writes src/shared/DevData/W4Tomb.luau (temporary, never committed: a one-off execute_luau builds the tomb from
it, then the file is deleted). Coordinates are the tomb's own: x east, z south from the maze's north-west
corner, y up from the floor's top; the build adds ORIGIN.

  - Maze: N x N cells of CELL studs (10-wide corridors between 2-thick walls, WALL_H tall), a randomized
    depth-first maze (seed SEED, the canvas's) with LOOPS extra openings; the route runs from cell (0, 0)
    (the landing) to (N-1, N-1), whose east side opens on the boulder hall.
  - Four sections along the route (darts, blades, fire, collapsing floor), three traps each on straight route
    cells, spike tiles sprinkled through, a scarab checkpoint at the start of each section, an Eye of Horus
    floor mosaic at every fork on the route looking the right way, a wall torch every few route cells.
  - Walls are boxes on the grid lines; a horizontal (east-west) wall is 1.9 thick so its faces never sit in a
    north-south wall's face where they meet.

Usage: python build_tomb.py
"""
import json
import os
import random
from collections import deque

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "..", "src", "shared", "DevData", "W4Tomb.luau")

SEED, N, CELL, LOOPS = 0, 13, 12, 6
WALL_H, ROOF_T, FLOOR_T = 14, 2, 4
ORIGIN = (-2400, -100, -2400)
SIZE = N * CELL

D = {"N": (-1, 0, "S"), "S": (1, 0, "N"), "E": (0, 1, "W"), "W": (0, -1, "E")}


def make_maze():
    rnd = random.Random(SEED)
    walls = {(r, c): {"N": True, "E": True, "S": True, "W": True} for r in range(N) for c in range(N)}
    seen, stack = {(0, 0)}, [(0, 0)]
    while stack:
        r, c = stack[-1]
        opts = [(d, r + dr, c + dc, o) for d, (dr, dc, o) in D.items()
                if 0 <= r + dr < N and 0 <= c + dc < N and (r + dr, c + dc) not in seen]
        if not opts:
            stack.pop()
            continue
        d, nr, nc, o = rnd.choice(opts)
        walls[(r, c)][d] = False
        walls[(nr, nc)][o] = False
        seen.add((nr, nc))
        stack.append((nr, nc))
    for _ in range(LOOPS):
        r, c = rnd.randrange(N), rnd.randrange(N - 1)
        walls[(r, c)]["E"] = False
        walls[(r, c + 1)]["W"] = False
    return walls


def route(walls):
    prev = {(0, 0): None}
    q = deque([(0, 0)])
    while q:
        cur = q.popleft()
        r, c = cur
        for d, (dr, dc, o) in D.items():
            if not walls[cur][d]:
                nb = (r + dr, c + dc)
                if nb not in prev:
                    prev[nb] = cur
                    q.append(nb)
    path, cur = [], (N - 1, N - 1)
    while cur:
        path.append(cur)
        cur = prev[cur]
    return path[::-1]


walls = make_maze()
path = route(walls)
L = len(path)
walls[(N - 1, N - 1)]["E"] = False  # the way out to the boulder hall
index = {p: i for i, p in enumerate(path)}


def axis_at(i):
    """'x' or 'z' if the route goes straight through path[i], else None"""
    if i <= 0 or i >= L - 1:
        return None
    (r0, c0), (r1, c1), (r2, c2) = path[i - 1], path[i], path[i + 1]
    if r0 == r1 == r2:
        return "x"
    if c0 == c1 == c2:
        return "z"
    return None


def entry_axis(i):
    """the axis the route enters path[i] along"""
    (r0, c0), (r1, c1) = path[max(i - 1, 0)], path[i]
    return "x" if r0 == r1 else "z"


# traps that fill a whole cell (spikes, darts) may sit on a corner too; blades, fire jets and the collapsing
# floor (its safe path runs along the cell) need the route to run straight through
WHOLE_CELL = {"Spikes", "Darts"}


def degree(p):
    return sum(1 for d in "NESW" if not walls[p][d])


boxes = []


def box(folder, name, x0, x1, y0, y1, z0, z1, color):
    boxes.append({"f": folder, "n": name, "c": [round((x0 + x1) / 2, 3), round((y0 + y1) / 2, 3), round((z0 + z1) / 2, 3)],
                  "s": [round(x1 - x0, 3), round(y1 - y0, 3), round(z1 - z0, 3)], "col": color})


SAND_WALL, FLOOR, ROOF, CHAMBER = "e0bc78", "c9a46a", "8a6a44", "d9b27a"

# --- maze walls: merge runs along each grid line ---
# north-south lines (x = k * CELL): a wall between (r, k-1) and (r, k)
for k in range(N + 1):
    run = None
    for r in range(N + 1):
        on = r < N and ((k < N and walls[(r, k)]["W"]) or (k == N and walls[(r, N - 1)]["E"]))
        if on and run is None:
            run = r
        if not on and run is not None:
            box("Walls", "Wall", k * CELL - 1, k * CELL + 1, 0, WALL_H, run * CELL - 1, r * CELL + 1, SAND_WALL)
            run = None
# east-west lines (z = k * CELL)
for k in range(N + 1):
    run = None
    for c in range(N + 1):
        on = c < N and ((k < N and walls[(k, c)]["N"]) or (k == N and walls[(N - 1, c)]["S"]))
        if on and run is None:
            run = c
        if not on and run is not None:
            box("Walls", "Wall", run * CELL - 1, c * CELL + 1, 0, WALL_H, k * CELL - 0.95, k * CELL + 0.95, SAND_WALL)
            run = None

# --- the boulder hall: x SIZE+1 .. HALL_END, lane z 145..155, two alcoves a side ---
LANE0, LANE1 = (N - 1) * CELL + 1, N * CELL - 1  # 145 .. 155
HALL_END = SIZE + 58  # 214
NORTH_ALCOVES, SOUTH_ALCOVES = [SIZE + 12, SIZE + 36], [SIZE + 24, SIZE + 48]  # alcove centres (x)
AL_W, AL_D = 4, 4


def wall_with_gaps(z0, z1, gaps):
    x = SIZE + 1
    for g in sorted(gaps):
        box("Hall", "Wall", x, g - AL_W / 2, 0, WALL_H, z0, z1, SAND_WALL)
        x = g + AL_W / 2
    box("Hall", "Wall", x, HALL_END, 0, WALL_H, z0, z1, SAND_WALL)


wall_with_gaps(LANE0 - 2, LANE0, NORTH_ALCOVES)
wall_with_gaps(LANE1, LANE1 + 2, SOUTH_ALCOVES)
for g in NORTH_ALCOVES:
    box("Hall", "Wall", g - AL_W / 2 - 2, g - AL_W / 2, 0, WALL_H, LANE0 - 2 - AL_D, LANE0 - 2, SAND_WALL)
    box("Hall", "Wall", g + AL_W / 2, g + AL_W / 2 + 2, 0, WALL_H, LANE0 - 2 - AL_D, LANE0 - 2, SAND_WALL)
    box("Hall", "Wall", g - AL_W / 2 - 2, g + AL_W / 2 + 2, 0, WALL_H, LANE0 - 4 - AL_D, LANE0 - 2 - AL_D, SAND_WALL)
for g in SOUTH_ALCOVES:
    box("Hall", "Wall", g - AL_W / 2 - 2, g - AL_W / 2, 0, WALL_H, LANE1 + 2, LANE1 + 2 + AL_D, SAND_WALL)
    box("Hall", "Wall", g + AL_W / 2, g + AL_W / 2 + 2, 0, WALL_H, LANE1 + 2, LANE1 + 2 + AL_D, SAND_WALL)
    box("Hall", "Wall", g - AL_W / 2 - 2, g + AL_W / 2 + 2, 0, WALL_H, LANE1 + 2 + AL_D, LANE1 + 4 + AL_D, SAND_WALL)
HALL_Z0, HALL_Z1 = LANE0 - 4 - AL_D, LANE1 + 4 + AL_D  # 137 .. 163

# --- the chamber: inside x 216..256, z 130..170, 20 tall; doorway in the west wall on the lane ---
CX0, CX1, CZ0, CZ1, CH = HALL_END + 2, HALL_END + 42, 130, 170, 20
box("Chamber", "Wall", HALL_END, CX0, 0, CH, CZ0 - 2, LANE0, CHAMBER)
box("Chamber", "Wall", HALL_END, CX0, 0, CH, LANE1, CZ1 + 2, CHAMBER)
box("Chamber", "Lintel", HALL_END, CX0, WALL_H, CH, LANE0, LANE1, CHAMBER)
box("Chamber", "Wall", CX0, CX1 + 2, 0, CH, CZ0 - 2, CZ0, CHAMBER)
box("Chamber", "Wall", CX0, CX1 + 2, 0, CH, CZ1, CZ1 + 2, CHAMBER)
box("Chamber", "Wall", CX1, CX1 + 2, 0, CH, CZ0, CZ1, CHAMBER)

# --- floors and roofs (no two share a top face) ---
box("Floor", "Floor", -1, SIZE + 1, -FLOOR_T, 0, -1, SIZE + 1, FLOOR)
box("Floor", "Floor", SIZE + 1, HALL_END, -FLOOR_T, 0, HALL_Z0, HALL_Z1, FLOOR)
box("Floor", "Floor", HALL_END, CX1 + 2, -FLOOR_T, 0, CZ0 - 2, CZ1 + 2, FLOOR)
box("Roof", "Roof", -1, SIZE + 1, WALL_H, WALL_H + ROOF_T, -1, SIZE + 1, ROOF)
box("Roof", "Roof", SIZE + 1, HALL_END, WALL_H, WALL_H + ROOF_T, HALL_Z0, HALL_Z1, ROOF)
box("Roof", "Roof", HALL_END, CX1 + 2, CH, CH + ROOF_T, CZ0 - 2, CZ1 + 2, ROOF)

# --- what goes where along the route ---
SECTIONS = ["Darts", "Blade", "Fire", "Collapse"]
checkpoints = {0: 1, L // 4: 2, L // 2: 3, 3 * L // 4: 4}
taken = set(checkpoints)
traps = []
for s in range(4):
    a, b = s * L // 4, (s + 1) * L // 4
    straight = [i for i in range(a + 2, b - 1) if (axis_at(i) or SECTIONS[s] in WHOLE_CELL) and i not in taken]
    for k in (1, 2, 3):
        want = a + (b - a) * k / 4
        if not straight:
            break
        i = min(straight, key=lambda j: (abs(j - want), j))
        straight = [j for j in straight if abs(j - i) > 2]
        taken.add(i)
        traps.append({"kind": SECTIONS[s], "i": i, "r": path[i][0], "c": path[i][1], "axis": axis_at(i) or entry_axis(i), "sec": s + 1,
                      "n": len([t for t in traps if t["kind"] == SECTIONS[s]])})
spikes = 0
for f in (0.12, 0.38, 0.6, 0.86):
    want = int(L * f)
    cands = [i for i in range(2, L - 2) if all(abs(i - t) > 1 for t in taken)]
    if cands:
        i = min(cands, key=lambda j: abs(j - want))
        taken.add(i)
        traps.append({"kind": "Spikes", "i": i, "r": path[i][0], "c": path[i][1], "axis": axis_at(i) or entry_axis(i),
                      "sec": min(4, 1 + 4 * i // L), "n": spikes})
        spikes += 1

cps = [{"index": n, "r": path[i][0], "c": path[i][1]} for i, n in sorted(checkpoints.items())]
eyes = []
for i in range(1, L - 1):
    p = path[i]
    if degree(p) >= 3:
        nr, nc = path[i + 1]
        eyes.append({"r": p[0], "c": p[1], "dx": nc - p[1], "dz": nr - p[0]})

# torches: every 4th route cell, on a wall that cell has (not one a trap needs), facing into the cell
torches = []
trap_cells = {(t["r"], t["c"]) for t in traps}
for i in range(1, L, 4):
    p = path[i]
    if p in trap_cells:
        continue
    for d in "NESW":
        if walls[p][d]:
            dr, dc, _ = D[d]
            torches.append({"r": p[0], "c": p[1], "dx": dc, "dz": dr})
            break

dead = [{"r": r, "c": c} for r in range(N) for c in range(N) if degree((r, c)) == 1 and (r, c) not in ((0, 0), (N - 1, N - 1))]

data = {
    "origin": ORIGIN, "n": N, "cell": CELL, "wallH": WALL_H, "size": SIZE,
    "boxes": boxes, "traps": traps, "checkpoints": cps, "eyes": eyes, "torches": torches, "dead": dead,
    "lane": [LANE0, LANE1], "hallEnd": HALL_END, "hall": [SIZE + 1, HALL_END, HALL_Z0, HALL_Z1],
    "alcoves": {"north": NORTH_ALCOVES, "south": SOUTH_ALCOVES},
    "chamber": [CX0, CX1, CZ0, CZ1, CH], "route": len(path),
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
print("route", L, "boxes", len(boxes), "traps", len(traps), [(t["kind"], t["i"]) for t in traps])
print("checkpoints", [(c["index"], c["r"], c["c"]) for c in cps], "eyes", len(eyes), "torches", len(torches), "dead ends", len(dead))
