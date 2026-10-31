"""World 4, The Scorching Sands: where its enemies stand (2026-10-29, the user: "scatter the dogs and
mummies as you like, but the 4 guardians need to be on the path right outside each entrance and the
boss obviously in the middle").

Reads the ground from build_ground.py and the decorations from decor_plan.json (with place_decor.py's
footprints), in World 4's own unturned coordinates, like place_decor.py:

  * the Sand Pharaoh stands in the middle of the pyramid's hall, on the dais's top step (2 up);
  * a Tomb Guardian on each doorway's lane, `GUARD_OUT` studs out from the pyramid's face, facing
    out to the road, its roaming circle inside the lane (12 wide);
  * 6 Shambling Mummies, then 18 Bone Jackals, spread farthest-first (the mummies first, so they
    spread among the jackals), the World 1 / 2 rule for regular enemies: the whole roaming circle
    (WanderRadius + half the Root's wider side) on one level of plain sand at the floor's height,
    its edge 1+ studs off the road (beside it was
    the World 1 / 2 rule, but the mounds come down to 2 studs of the road, so a strip of flat sand that
    wide rarely holds a roaming circle: they stand in the flat sand between the road and the mounds,
    up to 30 off it), nothing of a decoration within it + 1, 16+ studs between
    markers, out of the pyramid (4 off), its doorway approaches and tower flats, the corridor and
    spawn, the west arm's end (the World 5 gate), the oasis and the volcano; each faces the road.

The Phantom Pharaoh (the secret enemy) isn't placed: World 4 has no secret room yet.

Writes art/tools/w4/enemy_plan.json: per marker the template, its name, local x / y (the feet) / z
and yaw in degrees, and its WanderRadius. A Studio script places each as a copy of its template
(the preview body) with build_ground's `place` transform.

Usage: python place_enemies.py
"""
import json
import math
import os
import random

HERE = os.path.dirname(os.path.abspath(__file__))
# place_decor.py's ground, keep-outs, footprints and helpers, without placing anything (everything
# before its "report = {}" line)
_src = open(os.path.join(HERE, "place_decor.py"), encoding="utf-8").read().replace("\r\n", "\n")
D = {"__file__": os.path.join(HERE, "place_decor.py"), "__name__": "place_decor_lib"}
import sys
sys.path.insert(0, HERE)
exec(_src[:_src.index("\nreport = {}")], D)
G = D["G"]

OUT = os.path.join(HERE, "enemy_plan.json")
rng = random.Random(20261029)
PX, PZ, PH = G.PYRAMID
cell_at, dist_cells, PB, KEEP = D["cell_at"], D["dist_cells"], D["PB"], D["KEEP"]

# per kind: WanderRadius and half the Root's wider side (the templates' Roots: Jackal 1.8 x 6,
# Mummy 4 x 2, Guardian 4 x 2.2, Pharaoh 9 x 5), and its Root's height
KINDS = {
    "BoneJackal": dict(wander=4, half=3.0, h=5.0),
    "ShamblingMummy": dict(wander=4, half=2.0, h=5.3),
    "TombGuardian": dict(wander=2, half=2.0, h=8.0),
    "SandPharaoh": dict(wander=4, half=4.5, h=17.7),
}
ROAD_GAP = (1.0, 30.0)
SEP = 16.0
GUARD_OUT = 10.0
DAIS_TOP = 2.0

plan = json.load(open(os.path.join(HERE, "decor_plan.json"), encoding="utf-8"))
decor = []   # (x, z, r) foot circles of every placed decoration
for it in plan["items"]:
    t = D["T"].get(it["template"])
    if t:
        # a tomb's four sets of water jars stand round its foot, outside place_decor's footprint
        pad = 3.0 if it["template"] == "Tomb" else 0.0
        for (cx, cz, r) in D["world_circles"](t["foot"], it["x"], it["z"], it.get("yaw", 0)):
            decor.append((cx, cz, r + pad))


def face_road(x, z):
    p = D["nearest_path"](x, z)
    return math.degrees(math.atan2(-(p[0] - x), -(p[1] - z))) if p else 0.0


def ok(kind, x, z):
    k = KINDS[kind]
    R = k["wander"] + k["half"]
    for (px, pz) in [(x, z)] + D["ring"](x, z, R, 16) + D["ring"](x, z, R / 2, 8):
        v = cell_at(px, pz)
        if v is None or (v[2], v[3]) != ("Sand", "Sand") or v[0] != G.FLOOR:
            return False
    if D["in_keep"](x, z, R + 1):
        return False
    if abs(x - PX) < PH + R + 4 and abs(z - PZ) < PH + R + 4:
        return False
    d = dist_cells(PB, x, z) - R
    if not (ROAD_GAP[0] <= d <= ROAD_GAP[1]):
        return False
    for (cx, cz, r) in decor:
        if math.hypot(cx - x, cz - z) < R + r + 1:
            return False
    return True


markers = []

# the boss: the hall's middle, on the dais, facing the east doorway (the one the road reaches first)
markers.append(dict(template="SandPharaoh", folder="BossSpawns", name="SandPharaoh", x=PX, y=G.FLOOR + DAIS_TOP,
                    z=PZ, yaw=-90.0, wander=KINDS["SandPharaoh"]["wander"]))

# a guardian outside each doorway, on its lane, facing out
for i, (dx, dz, nm) in enumerate(((1, 0, "East"), (-1, 0, "West"), (0, 1, "North"), (0, -1, "South"))):
    x, z = PX + dx * (PH + GUARD_OUT), PZ + dz * (PH + GUARD_OUT)
    v = cell_at(x, z)
    assert v is not None and v[3] == "Path", (nm, v)
    yaw = math.degrees(math.atan2(-dx, -dz))   # CFrame.Angles(0, yaw, 0) looks along (dx, dz): out to the road
    markers.append(dict(template="TombGuardian", folder="EnemySpawns", name="TombGuardian_%02d" % (i + 1),
                        x=x, y=G.FLOOR, z=z, yaw=yaw, wander=KINDS["TombGuardian"]["wander"]))

# the candidates: every 2-stud cell centre of plain sand that passes for each kind
xs = [c[0] for c in D["path_cells"]]
zs = [c[1] for c in D["path_cells"]]
cands = {k: [(x + 0.0, z + 0.0) for x in range(int(min(xs)) - 20, int(max(xs)) + 20, 2)
             for z in range(int(min(zs)) - 20, int(max(zs)) + 20, 2) if ok(k, x, z)]
         for k in ("ShamblingMummy", "BoneJackal")}


def spread(kind, n):
    k = KINDS[kind]
    for i in range(n):
        best, bd = None, -1
        for (x, z) in cands[kind]:
            d = min((math.hypot(x - m["x"], z - m["z"]) for m in markers), default=1e9)
            if d >= SEP and d > bd:
                best, bd = (x, z), d
        assert best, "no room for %s %d" % (kind, i + 1)
        x, z = best
        markers.append(dict(template=kind, folder="EnemySpawns", name="%s_%02d" % (kind, i + 1), x=x, y=G.FLOOR,
                            z=z, yaw=face_road(x, z), wander=k["wander"]))


spread("ShamblingMummy", 6)
spread("BoneJackal", 18)

regular = [m for m in markers if m["folder"] == "EnemySpawns"]
nn = [min(math.hypot(a["x"] - b["x"], a["z"] - b["z"]) for b in regular if b is not a) for a in regular]
print("candidates", {k: len(v) for k, v in cands.items()})
print("nearest neighbour %.1f .. %.1f, median %.1f" % (min(nn), max(nn), sorted(nn)[len(nn) // 2]))
json.dump({"place": plan["place"], "markers": markers}, open(OUT, "w", encoding="utf-8"), indent=1)
print("wrote", OUT, len(markers))
