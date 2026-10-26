"""The 2026-10-26 rescale (the user's playtest feedback): every world harder and slower.

  * Armour is needed, not recommended: health per level is cut (100 at level 1 to 350 at 25,
    then x10 a world as before) and a world's best set gives about twice the level's health at
    the gate (so about 2/3 of a player's health is armour).
  * Enemies attack quickly: windups 0.2-0.35 s (hard to dodge), cooldowns about 0.6 of before,
    each hit about the same share, so they deal much more a second.
  * The base fights: World 1's Chicken still takes a fresh level-1 player to about 50%; World 2's
    first Fox takes a maxed arrival (level 25, Harvest Knight, upgrades 3, the Pumpkin King's
    Mace) to about 25% left (75% taken), and World 3's Cave Bat the same.
  * Gentler weapon steps: a world's Common is the last world's boss Legendary x1.15, and its
    ladder runs Common 1 .. Secret 2 (it was ~2.9), so one drop no longer multiplies a player's
    damage (World 2's Hatchet was 3.8x the Mace).
  * A steeper health ladder in every world: medium 3x, elite 4.5x, boss 7x the small enemy
    (2.4 / 3.3 / 5 before), the secret enemy 5x.
  * Weapon drops at a quarter of before; a boss's Legendary at 2%; secrets stay 0.1%.
  * Times (to buying the gate, a typical player): World 1 45 min, World 2 90, World 3 about 120;
    tuned with world_sim.py through each world's kill EXP and coins (KNOBS below).

Reads the world<N>.json dumps as committed before the rescale (git HEAD~ copies in
before/), writes world<N>.json with the new numbers, and prints every change. The same numbers
then go into the Luau configs (apply_rescale.py).

  py rescale.py              # write world1..3.json from before/
"""
import copy, json, math
from pathlib import Path

HERE = Path(__file__).parent
BEFORE = HERE / "before"

# ---------------------------------------------------------------------------
# the health curve (Leveling)
LEVELING = {"healthKnee": 25, "kneeHealth": 350, "baseHealth": 100, "start": 1, "first": 40, "growth": 10 ** (1 / 25)}

# armour health: twice the level's health at the gate of its world for the best set
ARMOR_HEALTH = {
    "FarmhandsGear": 150, "HarvestKnight": 700,
    "WoodlandHide": 2200, "HeartwoodBark": 7000,
    "CaveRunner": 22000, "CrystalQueen": 70000,
}

# the weapon ladder: a share of the world's Common anchor
LADDER = {"Common": 1.0, "Uncommon": 1.12, "Rare": 1.25, "Epic": 1.4, "Secret": 2.0}
# the boss's Legendary drop is its world's best (the user, 2026-10-26: the quest one was easier to get
# and better); the questline's sits between the Epics and it
QUEST_LEGENDARY = 1.6
BOSS_LEGENDARY = 1.75
NEXT_WORLD_STEP = 1.15     # a world's Common over the last world's boss Legendary
QUEST_WEAPON = {1: "WeathervaneSpear", 2: "LanternFlail", 3: "DiamondPickaxe"}
BOSS_WEAPON = {1: "PumpkinMace", 2: "HeartwoodStaff", 3: "QueensFang"}
SECRET_WEAPON = {1: "CornCob", 2: "MarshmallowStick", 3: "RockCandyClub"}
WORLD1_COMMON = 31.1       # the Sickle's DPS as it was: World 1 stays put at its bottom
ARMOR_PIERCE = 0.85        # an armour-ignoring weapon (the Diamond Pickaxe) on its own rung

# enemy health ladder, a multiple of the world's small enemy
HP_LADDER = {"small": 1.0, "medium": 3.0, "elite": 4.5, "boss": 6.0, "secret": 5.0}
# World 1 keeps its old ladder: its Scarecrow King has to fall by the middle of the world (Dale's step
# 8 gives the Lucky Horseshoe Harvest Knight needs), and its levels give little health now
HP_LADDER_W1 = {"small": 1.0, "medium": 2.4, "elite": 3.25, "boss": 4.0, "secret": 4.5}
# quick attacks: (windup, cooldown) by move
TIMING = {
    "peck": (0.2, 0.75), "gore": (0.3, 1.2), "slam": (0.35, 1.4), "stab": (0.3, 1.3), "slash": (0.3, 1.0),
    "pounce": (0.25, 0.6), "charge": (0.3, 1.1), "stomp": (0.35, 1.4), "zap": (0.25, 1.0),
    "swoop": (0.25, 0.7), "punch": (0.3, 1.1), "smash": (0.35, 1.4), "legstab": (0.35, 1.4),
}
DROP_SHARE = 0.25

# --- gathering matters more (the user, 2026-10-26: wood and stone came too easily, in big bunches;
# "more integrated into the game so it's not just a killing RPG") -------------------------------
GATHER_YIELD = 1            # every node gives one of its material a break (2-3 before); rare extras stay
# armour recipes: material -> count (the coins too); the first set cheaper (the user: hard to come by at
# its level 5)
ARMOR_CHANGES = {
    # no Stone (2026-10-26): the pickaxe only comes at Dale's step 5, after the bulls the set is for
    "FarmhandsGear": {"coins": 75, "ChickenFeather": 8, "OakLog": 8},
    "HarvestKnight": {"OakLog": 10, "Stone": 12},
    "WoodlandHide": {"RedwoodLog": 15},
    "HeartwoodBark": {"RedwoodLog": 20},
    "CaveRunner": {"IronOre": 18},
    "CrystalQueen": {"CrystalShard": 20},
}
GATE_MATERIALS = {1: {"OakLog": 20, "Stone": 20}, 2: {"RedwoodLog": 35, "AmberSap": 3}, 3: {"CrystalShard": 30, "RawGem": 3}}
# the questlines: no level steps (the user), every line has its elite, more kills and gathering;
# (kind, target or items, count, coins, exp, extra reward)
QUESTS = {
    1: [("kill", "Chicken", 8, 25, 20), ("gather", "OakLog", 8, 30, 30), ("kill", "Chicken", 15, 40, 40),
        ("kill", "Bull", 5, 60, 60), ("gather", "Stone", 10, 50, 60, {"weapon": "RustyBlade"}),
        ("kill", "Bull", 8, 100, 100), ("bring", {"OakLog": 15, "Stone": 15}, None, 80, 100),
        ("kill", "BossScarecrow", 1, 150, 150, {"item": "LuckyHorseshoe"}), ("kill", "Stallion", 6, 120, 150),
        ("kill", "BossScarecrow", 5, 300, 300, {"weapon": "WeathervaneSpear"})],
    2: [("kill", "Fox", 8, 250, 200), ("gather", "FoxFur", 10, 300, 300), ("kill", "Fox", 15, 400, 400),
        ("kill", "Boar", 5, 600, 600), ("gather", "RedwoodLog", 12, 500, 600),
        ("bring", {"RedwoodLog": 15, "BoarTusk": 6}, None, 800, 1000), ("kill", "Bear", 3, 1000, 1000),
        ("kill", "ElderTreant", 1, 1500, 1500, {"item": "RangerBadge"}), ("kill", "Bear", 6, 1200, 1500),
        ("kill", "ElderTreant", 5, 3000, 3000, {"weapon": "LanternFlail"})],
    3: [("kill", "CaveBat", 8, 2500, 2000), ("gather", "IronOre", 8, 3000, 3000), ("kill", "CaveBat", 15, 4000, 4000),
        ("kill", "PebbleGolem", 5, 6000, 6000), ("gather", "CrystalShard", 10, 5000, 6000),
        ("bring", {"IronOre": 15, "CrystalShard": 15}, None, 8000, 10000), ("kill", "CrystalGolem", 3, 10000, 10000),
        ("kill", "SpiderQueen", 1, 15000, 15000, {"item": "MinersLantern"}), ("kill", "CrystalGolem", 6, 12000, 15000),
        ("kill", "SpiderQueen", 5, 30000, 30000, {"weapon": "DiamondPickaxe"})],
}


def quest_steps(n, exp_mult=1.0):
    """The world<N>.json form of QUESTS[n] (kill / gather: target + count; bring: items)."""
    out = {}
    for i, st in enumerate(QUESTS[n], 1):
        kind, what, count, coins, exp = st[:5]
        extra = st[5] if len(st) > 5 else {}
        reward = {"coins": coins, "exp": round(exp * exp_mult)}
        reward.update(extra)
        step = {"kind": kind, "reward": reward}
        if kind == "bring":
            step["items"] = {str(k): {"id": m, "count": c} for k, (m, c) in enumerate(what.items(), 1)}
        else:
            step["target"], step["count"] = what, count
        out[str(i)] = step
    return out
BOSS_LEGENDARY_CHANCE = 0.02

# base fights: (small enemy, its base fight length in seconds, share of max HP it should take)
BASE = {1: ("Chicken", None, 0.50), 2: ("Fox", 10.0, 0.75), 3: ("CaveBat", 11.0, 0.75)}

# time knobs per world (kill EXP and coins multipliers on the current values), tuned with world_sim
KNOBS = {1: {"exp": 1.0, "coins": 1.0}, 2: {"exp": 1.0, "coins": 1.0}, 3: {"exp": 1.0, "coins": 1.0}}


def load(n):
    return json.load(open(BEFORE / f"world{n}.json", encoding="utf-8"))


def dps(w):
    return w["damage"] / w["cooldown"]


def items(t):
    return t.values() if isinstance(t, dict) else t


def main(knobs=KNOBS, quiet=False):
    data = {n: load(n) for n in (1, 2, 3)}
    log = []
    # health curve
    for d in data.values():
        d["leveling"].update(LEVELING)
    # armour
    for d in data.values():
        for aid, a in d["armor"].items():
            if aid in ARMOR_HEALTH:
                log.append(f"armour {aid}: health {a['health']} -> {ARMOR_HEALTH[aid]}")
                a["health"] = ARMOR_HEALTH[aid]

    # World 1's first set no longer needs the Bull's hide: the Bulls are what it's for (they wall a
    # player in plain clothes), so it's Chicken Feathers, Oak Logs and Stone; the hide moves to
    # Harvest Knight
    a1 = data[1]["armor"]
    a1["FarmhandsGear"]["recipe"] = {"1": {"id": "ChickenFeather", "count": 8}, "2": {"id": "OakLog", "count": 8}}
    hk = a1["HarvestKnight"]["recipe"]
    if not any(x["id"] == "BullHide" for x in items(hk)):
        hk[str(len(hk) + 1)] = {"id": "BullHide", "count": 8}
    log.append("recipe FarmhandsGear: Chicken Feather 8 + Oak Log 8 (no Bull Hide); HarvestKnight + Bull Hide 8")
    # World 2 the same way: its first set and the Stone Axe (the Redwood Logs) come from the Fox
    # alone, and the Boar Tusks go to Heartwood Bark
    a2 = data[2]["armor"]
    a2["WoodlandHide"]["recipe"] = {"1": {"id": "FoxFur", "count": 20}, "2": {"id": "RedwoodLog", "count": 10}}
    hb = a2["HeartwoodBark"]["recipe"]
    if not any(x["id"] == "BoarTusk" for x in items(hb)):
        hb[str(len(hb) + 1)] = {"id": "BoarTusk", "count": 10}
    for tid, fur in (("StoneAxe", 8), ("StoneRod", 7)):
        mats = data[2]["tools"][tid]["recipe"]["materials"]
        data[2]["tools"][tid]["recipe"]["materials"] = {k: (dict(v, count=fur) if v["id"] == "FoxFur" else v)
                                                        for k, v in mats.items() if v["id"] != "BoarTusk"}
    log.append("recipe WoodlandHide: Fox Fur 20 + Redwood Log 10 (no Boar Tusk); HeartwoodBark + Boar Tusk 10; "
               "Stone Axe / Rod: no Boar Tusk, Fox Fur 8 / 7")
    # and World 3: the Crystal Pickaxe / Rod and Cave Runner from the Bats and the ore, the Golem
    # Pebbles to Crystal Queen
    a3 = data[3]["armor"]
    a3["CaveRunner"]["recipe"] = {"1": {"id": "BatWing", "count": 22}, "2": {"id": "IronOre", "count": 12}}
    cq = a3["CrystalQueen"]["recipe"]
    if not any(x["id"] == "GolemPebble" for x in items(cq)):
        cq[str(len(cq) + 1)] = {"id": "GolemPebble", "count": 10}
    for tid, wing in (("CrystalPickaxe", 8), ("CrystalRod", 7)):
        mats = data[3]["tools"][tid]["recipe"]["materials"]
        data[3]["tools"][tid]["recipe"]["materials"] = {k: (dict(v, count=wing) if v["id"] == "BatWing" else v)
                                                        for k, v in mats.items() if v["id"] != "GolemPebble"}
    log.append("recipe CaveRunner: Bat Wing 22 + Iron Ore 12 (no Golem Pebble); CrystalQueen + Golem Pebble 10; "
               "Crystal Pickaxe / Rod: no Golem Pebble, Bat Wing 8 / 7")

    # gathering yields, armour counts, gate materials, the questlines
    for n, d in data.items():
        for nid, node in d.get("gathering", {}).items():
            for dr in items(node["drops"]):
                if dr["chance"] >= 1:
                    dr["min"] = dr["max"] = GATHER_YIELD
        for aid, ch in ARMOR_CHANGES.items():
            if aid in d["armor"]:
                a = d["armor"][aid]
                for k, v in ch.items():
                    if k == "coins":
                        a["coins"] = v
                    else:
                        for x in items(a["recipe"]):
                            if x["id"] == k:
                                x["count"] = v
        if n in GATE_MATERIALS:
            d["gate"]["materials"] = [{"id": m, "count": c} for m, c in GATE_MATERIALS[n].items()]
        d["quest"]["steps"] = quest_steps(n, knobs[n].get("questExp", 1.0))
    log.append("gathering 1 a break; armour counts; gates; questlines (no level steps)")

    # weapons, world by world
    anchor = WORLD1_COMMON
    new_dps = {}
    for n in (1, 2, 3):
        ws = data[n]["weapons"]
        by_rarity = {}
        for wid, w in ws.items():
            if w.get("starter") or w.get("rarity") in ("Relic", "Transcendent") or wid in (QUEST_WEAPON[n], BOSS_WEAPON[n]):
                continue
            by_rarity.setdefault(w["rarity"], []).append(wid)
        targets = {}
        for rarity, ids in by_rarity.items():
            mean = sum(dps(ws[i]) for i in ids) / len(ids)
            for i in ids:
                # weapons sharing a rarity keep their spread round the rung
                share = dps(ws[i]) / mean
                targets[i] = anchor * LADDER[rarity] * share
        targets[QUEST_WEAPON[n]] = anchor * QUEST_LEGENDARY
        targets[BOSS_WEAPON[n]] = anchor * BOSS_LEGENDARY
        for wid, t in targets.items():
            w = ws[wid]
            if w.get("ignoreArmor"):
                t *= ARMOR_PIERCE
            dmg = max(1, round(t * w["cooldown"]))
            log.append(f"weapon {wid} (W{n} {w['rarity']}): {w['damage']} -> {dmg}  ({dps(w):.1f} -> {dmg / w['cooldown']:.1f} DPS)")
            w["damage"] = dmg
            new_dps[wid] = dmg / w["cooldown"]
        # the Worldheart tier of this world: its secret x1.1
        for wid, w in ws.items():
            if w.get("rarity") == "Transcendent":
                d = round(new_dps[SECRET_WEAPON[n]] * 1.1 * w["cooldown"])
                log.append(f"weapon {wid}: {w['damage']} -> {d}")
                w["damage"] = d
        anchor = new_dps[BOSS_WEAPON[n]] * NEXT_WORLD_STEP
    # carried weapons (world N+1's dump lists the last world's for --from): keep them in step
    for n in (2, 3):
        for wid, w in data[n]["weapons"].items():
            for m in (1, 2):
                if m < n and wid in data[m]["weapons"]:
                    w["damage"] = data[m]["weapons"][wid]["damage"]

    # enemies
    for n, d in data.items():
        cfg = d["config"]
        for group, is_boss in ((cfg["enemies"], False), (cfg["bosses"], True)):
            for eid, e in group.items():
                m = e["melee"]
                moves = m.get("moves")
                move = m["move"]
                if move in TIMING:
                    w0, c0 = TIMING[move]
                    log.append(f"enemy {eid} timing: windup {m['windup']} -> {w0}, cooldown {m['cooldown']} -> {c0}")
                    m["windup"], m["cooldown"] = w0, c0
                # drops
                for dr in items(e.get("drops", {})):
                    old = dr["chance"]
                    if old <= 0.001:
                        continue  # secrets stay 0.1%
                    if is_boss and dr["weapon"] == BOSS_WEAPON[n]:
                        dr["chance"] = BOSS_LEGENDARY_CHANCE
                    else:
                        dr["chance"] = round(old * DROP_SHARE, 4)
                    log.append(f"drop {eid} -> {dr['weapon']}: {old} -> {dr['chance']}")
                e["exp"] = max(1, round(e.get("exp", 0) * knobs[n]["exp"]))
                e["coins"] = {"min": max(1, round(e["coins"]["min"] * knobs[n]["coins"])),
                              "max": max(1, round(e["coins"]["max"] * knobs[n]["coins"]))}
    calibrate(data, log)
    if not quiet:
        print("\n".join(log))
    return data


# the base player of each world: (level, base weapon, armour worn, upgrade level)
BASE_PLAYER = {1: (1, "Dagger", None, 0), 2: (25, "PumpkinMace", "HarvestKnight", 3), 3: (50, "HeartwoodStaff", "HeartwoodBark", 6)}


def calibrate(data, log, runs=4000):
    """Each world's enemies from its base fight: the small enemy's health from the fight's length
    against the base weapon (World 1 keeps the Chicken's), its damage until the fight takes the
    target share, then the others by the health ladder and their old damage ratio to it."""
    import random, statistics
    import base_fights as B
    weapons, armor = {}, {}
    for d in data.values():
        weapons.update(d["weapons"]); armor.update(d["armor"])
    lv = data[1]["leveling"]
    for n in (1, 2, 3):
        cfg = data[n]["config"]
        small_id, length, share = BASE[n]
        level, wid, aid, up = BASE_PLAYER[n]
        wpn = weapons[wid]
        arm = armor[aid] if aid else {"health": 0, "defense": 0}
        hp = B.max_hp(lv, level, arm["health"], up)
        taken = (1 - arm["defense"]) * (1 + B.UP["Defense"] * up)
        small = cfg["enemies"][small_id]
        old_small_dmg = small["melee"]["damage"]
        if length:
            # the base weapon's damage a second against it, hits and crits on average
            per = wpn["damage"] * (1 + B.UP["Attack"] * up)
            cd = wpn["cooldown"] * (1 + B.UP["AttackSpeed"] * up)
            chance, mult = B.CRIT_CHANCE + B.UP["CritChance"] * up, B.CRIT_MULT + B.UP["CritDamage"] * up
            eff = per * (1 + chance * (mult - 1)) * B.HIT_RATE / cd
            new_hp = round(eff * length / 10) * 10
            log.append(f"enemy {small_id} (W{n} base): hp {small['hp']} -> {new_hp}")
            small["hp"] = new_hp
        e = {"hp": small["hp"], "armor": small["melee"].get("armor", 0), "windup": small["melee"]["windup"],
             "cooldown": small["melee"]["cooldown"]}
        rng = random.Random(1)
        lo, hi = 1, hp
        for _ in range(30):
            mid = (lo + hi) / 2
            e["damage"] = mid
            got = statistics.mean(B.fight(rng, wpn, e, up, taken)[1] for _ in range(runs)) / hp
            lo, hi = (mid, hi) if got < share else (lo, mid)
        dmg = round((lo + hi) / 2)
        log.append(f"enemy {small_id} (W{n} base): damage {old_small_dmg} -> {dmg}  (a fight takes ~{share:.0%} of {hp:,.0f} HP)")
        small["melee"]["damage"] = dmg
        for group, is_boss in ((cfg["enemies"], False), (cfg["bosses"], True)):
            for eid, x in group.items():
                if eid == small_id:
                    continue
                t = tier_of(x, is_boss)
                new_hp = round(small["hp"] * (HP_LADDER_W1 if n == 1 else HP_LADDER)[t] / 10) * 10
                new_dmg = round(dmg * x["melee"]["damage"] / old_small_dmg * KNOBS[n].get(t, 1.0))
                log.append(f"enemy {eid} (W{n} {t}): hp {x['hp']} -> {new_hp}, damage {x['melee']['damage']} -> {new_dmg}")
                x["hp"], x["melee"]["damage"] = new_hp, new_dmg


def tier_of(e, is_boss):
    if is_boss:
        return "boss"
    if e.get("secret"):
        return "secret"
    return e.get("tier")


def write(data):
    for n, d in data.items():
        with open(HERE / f"world{n}.json", "w", encoding="utf-8", newline="\n") as f:
            json.dump(d, f, separators=(",", ":"))  # compact, like dump_world.luau writes it


if __name__ == "__main__":
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--knob", action="append", default=[], help="world.what=value, e.g. 1.exp=1.5, 2.coins=0.8, 1.medium=0.8")
    ap.add_argument("--quiet", action="store_true")
    a = ap.parse_args()
    for k in a.knob:
        key, val = k.split("=")
        w, what = key.split(".")
        KNOBS[int(w)][what] = float(val)
    write(main(KNOBS, a.quiet))
