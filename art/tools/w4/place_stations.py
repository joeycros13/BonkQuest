"""World 4, The Scorching Sands: its stalls at the start of the world (2026-10-29, the user: "set up the 3
stations for W4. We may need to move some decorations and mounds around to fit them into the beginning").

The Crafter (with the Infuser beside its front corner) stands on the flat sand north of the entry road
facing it, the Weaponsmith opposite it south of the road, and the Upgrader behind the Weaponsmith facing
the south way round (the road's first branch). Each is a copy of World 3's stall; its box below is the
whole stall (x +-10.35 across, 13.85 back and 7.92 forward of its pivot, in its own frame) in World 4's
own unturned coordinates.

Every decoration, gathering node or enemy marker that a stall's box (plus PAD) touches moves to the
nearest spot that passes place_decor.py's / place_enemies.py's rules with the stalls counted in, and
decor_plan.json / enemy_plan.json are rewritten with the new spots (so they stay the truth for later
runs). Prints what moved; a Studio script moves the same things.

Usage: python place_stations.py
"""
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
_src = open(os.path.join(HERE, "place_decor.py"), encoding="utf-8").read().replace("\r\n", "\n")
D = {"__file__": os.path.join(HERE, "place_decor.py"), "__name__": "place_decor_lib"}
exec(_src[:_src.index("\nreport = {}")], D)
G = D["G"]

PAD = 1.5
# name: (pivot x, z, facing (dx, dz)) in World 4's local frame
STALLS = {
    "CraftingStation": (-240.0, -970.6, (0, -1)),
    "WeaponStation": (-236.0, -1005.9, (0, 1)),
    "UpgradeStation": (-246.1, -1032.0, (-1, 0)),
}
INFUSER = (-253.0, -974.0, 1.3)


def stall_box(x, z, f):
    """the stall's box (x0, x1, z0, z1): 20.7 across, 13.85 behind and 7.92 in front of its pivot"""
    dx, dz = f
    if dx == 0:
        z0, z1 = sorted((z + dz * 7.92, z - dz * 13.85))
        return (x - 10.35, x + 10.35, z0, z1)
    x0, x1 = sorted((x + dx * 7.92, x - dx * 13.85))
    return (x0, x1, z - 10.35, z + 10.35)


BOXES = {n: stall_box(*v) for n, v in STALLS.items()}
BOXES["Infuser"] = (INFUSER[0] - INFUSER[2], INFUSER[0] + INFUSER[2], INFUSER[1] - INFUSER[2], INFUSER[1] + INFUSER[2])
# the ground under each: every cell plain sand at the floor, none of it road
for n, (x0, x1, z0, z1) in BOXES.items():
    bad = []
    x = x0
    while x <= x1:
        z = z0
        while z <= z1:
            v = D["cell_at"](x, z)
            if v is None or (v[2], v[3]) != ("Sand", "Sand") or v[0] != G.FLOOR:
                bad.append((round(x), round(z), v and v[3]))
            z += 1
        x += 1
    print(n, "box", [round(a, 2) for a in (x0, x1, z0, z1)], "off flat sand:", len(bad), bad[:6])
# decorations and enemies keep out of the stalls (placed after them)
for (x0, x1, z0, z1) in BOXES.values():
    D["KEEP"].append((x0 - PAD, x1 + PAD, z0 - PAD, z1 + PAD))


def hits(circles):
    for (cx, cz, r) in circles:
        for (x0, x1, z0, z1) in BOXES.values():
            qx, qz = min(max(cx, x0), x1), min(max(cz, z0), z1)
            if math.hypot(cx - qx, cz - qz) < r + PAD:
                return True
    return False


# --- decorations and nodes ------------------------------------------------------------
plan = json.load(open(os.path.join(HERE, "decor_plan.json"), encoding="utf-8"))
T = D["T"]
items = plan["items"]
moving = []
for it in items:
    t = T[it["template"]]
    foot = D["world_circles"](t["foot"], it["x"], it["z"], it["yaw"])
    crown = D["world_circles"](t.get("crown", []), it["x"], it["z"], it["yaw"])
    # a crown only reaches a stall if it hangs lower than the roof (13.8)
    if hits(foot) or (t.get("crown_y", 99) < 14 and hits(crown)) or (crown and hits([(c[0], c[1], c[2] * 0.6) for c in crown])):
        moving.append(it)
    else:
        D["put"](it["template"], it["x"], it["z"], it["yaw"], ("ok", it["y"]))
NODE_GAP = 4.0
MIN_SEP = {"Tomb": 120, "Saguaro": 35, "DigPile": 32}
AGAINST = {"Tomb": {"Tomb"}, "Saguaro": {"Saguaro"}, "DigPile": {"DigPile", "Saguaro"}}
def relocate(it, avoid=()):
    name = it["template"]
    found = None
    for k in range(1, 400):
        r = 0.5 * k
        n = max(8, int(2 * math.pi * r / 1.0))
        for a in range(n):
            ang = 2 * math.pi * a / n
            x, z = it["x"] + r * math.cos(ang), it["z"] + r * math.sin(ang)
            yaw = D["face_road"](x, z) if name in ("Tomb", "Saguaro", "DigPile") else it["yaw"]
            res = D["check"](name, x, z, yaw)
            if isinstance(res, tuple) and avoid and any(math.hypot(ax - bx, az - bz) < ar + br + D["GAP"] for (ax, az, ar) in avoid
                                                         for (bx, bz, br) in D["world_circles"](T[name]["foot"], x, z, yaw)):
                continue
            if not isinstance(res, tuple):
                continue
            # a moved node or tomb keeps NODE_GAP off the stalls
            if name in MIN_SEP and hits([(c[0], c[1], c[2] + NODE_GAP) for c in D["world_circles"](T[name]["foot"], x, z, yaw)]):
                continue
            if name in MIN_SEP and any(math.hypot(p[1] - x, p[2] - z) < MIN_SEP[name]
                                       for p in D["placed"] if p[0] in AGAINST[name]):
                continue
            found = (x, z, yaw, res)
            break
        if found:
            break
    assert found, it["name"]
    x, z, yaw, res = found
    D["put"](name, x, z, yaw, res)
    print("move %s (%.1f, %.1f) -> (%.1f, %.1f) yaw %.1f, %.1f away" % (it["name"], it["x"], it["z"], x, z, yaw % 360,
                                                                      math.hypot(x - it["x"], z - it["z"])))
    it.update(x=round(x, 2), z=round(z, 2), y=res[1], yaw=round(yaw % 360, 1), moved=True)


for it in moving:
    relocate(it)


# a tomb's four sets of water jars stand round its foot, outside place_decor's footprint (place_enemies.py
# pads it by 3 the same way): whatever a moved tomb's jars reach moves too, by the same search
for tomb in [it for it in moving if it["template"] == "Tomb"]:
    jars = [(x, z, r + 3.0) for (x, z, r) in D["world_circles"](T["Tomb"]["foot"], tomb["x"], tomb["z"], tomb["yaw"])]
    for it in items:
        if it is tomb or it.get("moved"):
            continue
        foot = D["world_circles"](T[it["template"]]["foot"], it["x"], it["z"], it["yaw"])
        if any(math.hypot(ax - bx, az - bz) < ar + br + D["GAP"] for (ax, az, ar) in jars for (bx, bz, br) in foot):
            D["placed"][:] = [p for p in D["placed"] if not (p[0] == it["template"] and abs(p[1] - it["x"]) < 0.01 and abs(p[2] - it["z"]) < 0.01)]
            relocate(it, avoid=jars)
json.dump(plan, open(os.path.join(HERE, "decor_plan.json"), "w", newline="\n"), indent=1)

# --- enemies ----------------------------------------------------------------------------
_esrc = open(os.path.join(HERE, "place_enemies.py"), encoding="utf-8").read().replace("\r\n", "\n")
E = {"__file__": os.path.join(HERE, "place_enemies.py"), "__name__": "place_enemies_lib"}
exec(_esrc[:_esrc.index("\nmarkers = []")], E)   # its ok() reads the decorations just rewritten
E["D"]["KEEP"].extend(D["KEEP"][-len(BOXES):])
eplan = json.load(open(os.path.join(HERE, "enemy_plan.json"), encoding="utf-8"))
for m in eplan["markers"]:
    if m["folder"] != "EnemySpawns" or m["template"] not in ("BoneJackal", "ShamblingMummy"):
        continue
    k = E["KINDS"][m["template"]]
    R = k["wander"] + k["half"]
    if not hits([(m["x"], m["z"], R + 1)]) and E["ok"](m["template"], m["x"], m["z"]):
        continue
    others = [o for o in eplan["markers"] if o is not m]
    found = None
    for kk in range(1, 300):
        r = 1.0 * kk
        n = max(8, int(2 * math.pi * r / 2.0))
        for a in range(n):
            ang = 2 * math.pi * a / n
            x, z = round(m["x"] + r * math.cos(ang)), round(m["z"] + r * math.sin(ang))
            if hits([(x, z, R + 1)]) or not E["ok"](m["template"], x, z):
                continue
            if any(math.hypot(o["x"] - x, o["z"] - z) < E["SEP"] for o in others):
                continue
            found = (x, z)
            break
        if found:
            break
    assert found, m["name"]
    print("move %s (%.1f, %.1f) -> (%.1f, %.1f)" % (m["name"], m["x"], m["z"], found[0], found[1]))
    m.update(x=float(found[0]), z=float(found[1]), yaw=E["face_road"](*found), moved=True)
json.dump(eplan, open(os.path.join(HERE, "enemy_plan.json"), "w", encoding="utf-8", newline="\n"), indent=1)
