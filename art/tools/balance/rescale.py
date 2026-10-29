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
    "FarmhandsGear": {"coins": 900},
    "WoodlandHide": {"RedwoodLog": 15},
    "HeartwoodBark": {"RedwoodLog": 20},
    "CaveRunner": {"IronOre": 18},
    "CrystalQueen": {"CrystalShard": 20},
}
GATE_MATERIALS = {1: {"OakLog": 20, "Stone": 20}, 2: {"RedwoodLog": 35, "AmberSap": 3}, 3: {"CrystalShard": 30, "RawGem": 3}}
# the questlines: no level steps (the user), every line has its elite, more kills and gathering;
# (kind, target or items, count, coins, exp, extra reward)
QUESTS = {
    # (2026-10-26, the user's second round: mixed hunts at steps 3 and 7 and a Clean Up at step 10,
    # every item where it was: Rusty Blade 5, the quest item 8, the quest weapon 10)
    1: [("kill", "Chicken", 8, 25, 20), ("gather", "OakLog", 8, 30, 30),
        ("hunt", {"Chicken": 12, "Bull": 3}, None, 40, 40), ("kill", "Bull", 5, 60, 60),
        ("gather", "Stone", 10, 50, 60, {"weapon": "RustyBlade"}), ("bring", {"OakLog": 15, "Stone": 15}, None, 80, 100),
        ("hunt", {"Bull": 6, "Stallion": 3}, None, 100, 100),
        ("kill", "BossScarecrow", 1, 150, 150, {"item": "LuckyHorseshoe"}), ("hunt", {"Stallion": 4, "BossScarecrow": 1}, None, 120, 150),
        ("hunt", {"Chicken": 10, "Bull": 8, "Stallion": 5, "BossScarecrow": 3}, None, 300, 300, {"weapon": "WeathervaneSpear"})],
    2: [("kill", "Fox", 8, 250, 200), ("gather", "FoxFur", 10, 300, 300),
        ("hunt", {"Fox": 12, "Boar": 3}, None, 400, 400), ("kill", "Boar", 5, 600, 600),
        ("gather", "RedwoodLog", 12, 500, 600), ("bring", {"RedwoodLog": 15, "BoarTusk": 6}, None, 800, 1000),
        ("hunt", {"Boar": 6, "Bear": 3}, None, 1000, 1000),
        ("kill", "ElderTreant", 1, 1500, 1500, {"item": "RangerBadge"}), ("hunt", {"Bear": 4, "ElderTreant": 1}, None, 1200, 1500),
        ("hunt", {"Fox": 10, "Boar": 8, "Bear": 5, "ElderTreant": 3}, None, 3000, 3000, {"weapon": "LanternFlail"})],
    3: [("kill", "CaveBat", 8, 2500, 2000), ("gather", "IronOre", 8, 3000, 3000),
        ("hunt", {"CaveBat": 12, "PebbleGolem": 3}, None, 4000, 4000), ("kill", "PebbleGolem", 5, 6000, 6000),
        ("gather", "CrystalShard", 10, 5000, 6000), ("bring", {"IronOre": 15, "CrystalShard": 15}, None, 8000, 10000),
        ("hunt", {"PebbleGolem": 6, "CrystalGolem": 3}, None, 10000, 10000),
        ("kill", "SpiderQueen", 1, 15000, 15000, {"item": "MinersLantern"}), ("hunt", {"CrystalGolem": 4, "SpiderQueen": 1}, None, 12000, 15000),
        ("hunt", {"CaveBat": 10, "PebbleGolem": 8, "CrystalGolem": 5, "SpiderQueen": 3}, None, 30000, 30000, {"weapon": "DiamondPickaxe"})],
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
        elif kind == "hunt":
            step["targets"] = {str(k): {"id": m, "count": c} for k, (m, c) in enumerate(what.items(), 1)}
        else:
            step["target"], step["count"] = what, count
        out[str(i)] = step
    return out
BOSS_LEGENDARY_CHANCE = 0.02

# --- World 1's steep ladder (2026-10-26, the user's second playtest: the first five weapons spanned
# about 10 DPS and the enemies were all alike; the first weapon should do very little, chickens have
# very little health, the Bull a big step up that kills a player without the Machete and leaves one
# with it and the coin set at 80-90%) -----------------------------------------------------------------
# Three weapons per enemy (the user's third round): a common one that makes its own tier quicker,
# one that just beats the next tier, and a rare one that beats the next tier easily, which the next
# enemy up drops again as its common one. So the ladder is
#   Chicken: Sickle 20% (quicker chickens), Machete 6% (just beats a Bull), Pitchfork 1% (easy Bulls)
#   Bull:    Pitchfork 20%, Shovel 6% (just beats a Stallion), the new Rare 1% (easy Stallions)
#   Stallion: the new Rare 20%, Scythe 6% (just beats the King), the new Epic 1% (easy King)
#   King:    the new Epic 20%, Pumpkin King's Mace 2%, Corn Cob 0.1%
# with the Weathervane Spear (Dale's) between the new Epic and the Mace. The "just beats" weapons are
# the ones the enemies are solved against (WORLD1_FIGHTS); the "easily" ones are solved here for a
# fight that takes WORLD1_EASY's share at the same level and armour; the rest step from them.
WORLD1_DPS = {"Dagger": 10, "Sickle": 16, "Machete": 26, "RustyBlade": 9}
WORLD1_EASY = {"Pitchfork": ("Bull", 0.5), "FarriersHammer": ("Stallion", 0.5), "CrowbaneHoe": ("BossScarecrow", 0.5)}
WORLD1_STEP = {"Shovel": ("Pitchfork", 1.15), "Scythe": ("FarriersHammer", 1.15),
               "WeathervaneSpear": ("CrowbaneHoe", 1.1), "PumpkinMace": ("CrowbaneHoe", 1.2), "CornCob": ("CrowbaneHoe", 1.5)}
# the two new weapons (the user's picks on the canvas: A and B): their stats live in Config/Weapons, these
# are for the simulations; apply_rescale.py leaves out any weapon Config/Weapons doesn't have
WORLD1_NEW = {"FarriersHammer": {"name": "Farrier's Hammer", "rarity": "Rare", "cooldown": 1.0, "hitTime": 0.6,
                                 "handed": 1, "price": 1100, "sell": 90},
              "CrowbaneHoe": {"name": "Crowbane Hoe", "rarity": "Epic", "cooldown": 1.15, "hitTime": 0.6,
                              "handed": 2, "price": 2600, "sell": 240}}
# (the user's fourth round: the rates needn't be 20 / 6 / 1 everywhere, only harder to get for the
# stronger enemies' weapons)
WORLD1_DROP_TABLE = {
    "Chicken": {"Sickle": 0.25, "Machete": 0.08, "Pitchfork": 0.015},
    "Bull": {"Pitchfork": 0.15, "Shovel": 0.05, "FarriersHammer": 0.01},
    "Stallion": {"FarriersHammer": 0.10, "Scythe": 0.03, "CrowbaneHoe": 0.005},
    "BossScarecrow": {"CrowbaneHoe": 0.08, "PumpkinMace": 0.02, "CornCob": 0.001},
}
# Worlds 2 and 3 the same way (2026-10-27, the user's picks on https://claude.ai/artifact/F1P7JW8tuzRYJRE2zfhAWx):
# each gets a 7th regular weapon, a Rare that beats the elite easily (the medium enemy's rare drop and the
# elite's common one, like the Farrier's Hammer), and World 1's drop rates; the two Epics split as the
# Scythe and the Crowbane Hoe do (the stronger one is the elite's rare drop and the boss's common one)
NEW_WEAPONS = {
    2: {"HoneycombHammer": {"name": "Honeycomb Hammer", "rarity": "Rare", "cooldown": 1.0, "hitTime": 0.6, "handed": 1,
                            "reach": 6.5, "arc": 90, "maxTargets": 3, "swing": "CornBonk", "price": 11000, "sell": 900, "order": 13.5}},
    3: {"CopperDrill": {"name": "Copper Drill", "rarity": "Rare", "cooldown": 0.7, "hitTime": 0.5, "handed": 1,
                        "reach": 7.5, "arc": 50, "maxTargets": 2, "swing": "Jab", "price": 110000, "sell": 9000, "order": 25.5}},
}
NEW_RUNG = 1.3   # of the world's Common: between its Rare (1.25) and its Epics (1.4)
DROP_TABLES = {
    1: WORLD1_DROP_TABLE,
    2: {"Fox": {"Hatchet": 0.25, "Quarterstaff": 0.08, "Cleaver": 0.015},   # the Cleaver is the stronger Uncommon
        "Boar": {"Cleaver": 0.15, "Mace": 0.05, "HoneycombHammer": 0.01},
        "Bear": {"HoneycombHammer": 0.10, "Greatclub": 0.03, "WoodsmansAxe": 0.005},
        "ElderTreant": {"WoodsmansAxe": 0.08, "HeartwoodStaff": 0.02, "MarshmallowStick": 0.001}},
    3: {"CaveBat": {"BatwingBlade": 0.25, "IronPickaxe": 0.08, "PebbleMallet": 0.015},
        "PebbleGolem": {"PebbleMallet": 0.15, "GoldGauntlets": 0.05, "CopperDrill": 0.01},
        "CrystalGolem": {"CopperDrill": 0.10, "EmberCoalMaul": 0.03, "GeodeGlaive": 0.005},
        "SpiderQueen": {"GeodeGlaive": 0.08, "QueensFang": 0.02, "RockCandyClub": 0.001}},
}
# each world's coin set (the user: a worse set bought with coins alone, from a decent number of kills
# of its first enemy), first in the Crafter's list
COIN_SETS = {1: {"PatchworkVest": {"id": "PatchworkVest", "name": "Patchwork Vest", "world": 1, "order": 0,
                                   "rarity": "Common", "level": 7, "coins": 500, "recipe": {},
                                   "defense": 0.05, "health": 60, "sell": 40}},
             # (2026-10-27, the user's picks on https://claude.ai/artifact/JfZ26WCcj2QYXq163LXaCV) a step up from the
             # last world's best set, under the world's first crafted one
             2: {"PineconeScale": {"id": "PineconeScale", "name": "Pinecone Scale", "world": 2, "order": 2.5,
                                   "rarity": "Uncommon", "level": 26, "coins": 5000, "recipe": {},
                                   "defense": 0.21, "health": 1100, "sell": 400}},
             3: {"IronPlate": {"id": "IronPlate", "name": "Iron Plate", "world": 3, "order": 4.5,
                               "rarity": "Rare", "level": 52, "coins": 50000, "recipe": {},
                               "defense": 0.35, "health": 11000, "sell": 4000}}}
# and Farmhand's Gear buffed (the user): it is what makes the Bulls a fair fight
# (its second round: level 12 and 900 coins, so the Patchwork Vest carries a player from level 7 to 12)
WORLD1_ARMOR = {"FarmhandsGear": {"health": 220, "defense": 0.12}}
# World 1's fights, each solved for the enemy's damage: (hp, weapon, level, armour, share of max HP taken)
WORLD1_FIGHTS = {
    "Chicken": (35, "Dagger", 1, None, 0.55),          # the first fight: at least half your health
    # (the user's second round, from their playtest) level 7 with the Machete: 75% with the Patchwork
    # Vest, dead without it
    "Bull": (240, "Machete", 7, "PatchworkVest", 0.75),
    # level 12 with the Shovel: Farmhand's Gear needed (about 70% with it, dead in the Patchwork Vest)
    "Stallion": (450, "Shovel", 12, "FarmhandsGear", 0.70),
    # the Scythe leaves a quarter of your health, in Farmhand's Gear at level 15 (Harvest Knight needs the
    # King's Lucky Horseshoe, so he's fought before it)
    "BossScarecrow": (700, "Scythe", 15, "FarmhandsGear", 0.75),
    "CornWraith": (500, "Shovel", 12, "FarmhandsGear", 0.7),
}

# --- Worlds 2 and 3 fight by fight, like World 1 (2026-10-27, the user: "do the same fight-by-fight
# balancing for Worlds 2 and 3"). Each world's small enemy keeps its base fight (the arrival from the
# world before, 75% taken); the medium enemy is fought at the coin set's level wearing it with the
# small enemy's "just beats it" drop, the elite at the first crafted set's level in it, the boss three
# levels on in the same set (the second crafted set needs the boss's quest item), the secret enemy as
# the elite; the shares are World 1's. Health keeps the world's ladder (HP_LADDER); every enemy's damage
# is solved from its fight, the "beats it easily" weapons for 50% of the same fight, and the rest step
# from them as World 1's do. Upgrades: the arrival's (World 2 3, World 3 6).
# (enemy: (weapon, level, armour, share))
WORLD_FIGHTS = {
    2: {"Fox": ("PumpkinMace", 25, "HarvestKnight", 0.75),
        "Boar": ("Quarterstaff", 26, "PineconeScale", 0.75),
        "Bear": ("Mace", 28, "WoodlandHide", 0.70),
        "Fairy": ("Mace", 28, "WoodlandHide", 0.70),
        "ElderTreant": ("Greatclub", 31, "WoodlandHide", 0.75)},
    3: {"CaveBat": ("HeartwoodStaff", 50, "HeartwoodBark", 0.75),
        "PebbleGolem": ("IronPickaxe", 52, "IronPlate", 0.75),
        "CrystalGolem": ("GoldGauntlets", 58, "CaveRunner", 0.70),
        "GemMole": ("GoldGauntlets", 58, "CaveRunner", 0.70),
        "SpiderQueen": ("EmberCoalMaul", 61, "CaveRunner", 0.75)},
}
WORLD_UPGRADES = {2: 3, 3: 6}
# the small enemy's common drop is the world's anchor (the last boss Legendary x1.15); its "just beats
# the medium enemy" drop a step over it
WORLD_SET = {2: {"Hatchet": 1.0, "Quarterstaff": 1.15}, 3: {"BatwingBlade": 1.0, "IronPickaxe": 1.15}}
WORLD_EASY = {2: {"Cleaver": ("Boar", 0.5), "HoneycombHammer": ("Bear", 0.5), "WoodsmansAxe": ("ElderTreant", 0.5)},
              3: {"PebbleMallet": ("PebbleGolem", 0.5), "CopperDrill": ("CrystalGolem", 0.5), "GeodeGlaive": ("SpiderQueen", 0.5)}}
WORLD_STEP = {2: {"Mace": ("Cleaver", 1.15), "Greatclub": ("HoneycombHammer", 1.15),
                  "LanternFlail": ("WoodsmansAxe", 1.1), "HeartwoodStaff": ("WoodsmansAxe", 1.2), "MarshmallowStick": ("WoodsmansAxe", 1.5)},
              3: {"GoldGauntlets": ("PebbleMallet", 1.15), "EmberCoalMaul": ("CopperDrill", 1.15),
                  "DiamondPickaxe": ("GeodeGlaive", 1.1), "QueensFang": ("GeodeGlaive", 1.2), "RockCandyClub": ("GeodeGlaive", 1.5)}}
# the order each world's ladder climbs in (each enemy before the weapon that beats it easily)
WORLD_ORDER = {2: ["Fox", "Boar", "+Cleaver", "+Mace", "Bear", "Fairy", "+HoneycombHammer", "+Greatclub", "ElderTreant",
                   "+WoodsmansAxe", "+LanternFlail", "+HeartwoodStaff", "+MarshmallowStick"],
               3: ["CaveBat", "PebbleGolem", "+PebbleMallet", "+GoldGauntlets", "CrystalGolem", "GemMole", "+CopperDrill",
                   "+EmberCoalMaul", "SpiderQueen", "+GeodeGlaive", "+DiamondPickaxe", "+QueensFang", "+RockCandyClub"]}

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
    for aid, ch in WORLD1_ARMOR.items():
        log.append(f"armour {aid}: {ch}")
        data[1]["armor"][aid].update(ch)
    for n, sets in COIN_SETS.items():
        for aid, a in sets.items():
            log.append(f"armour {aid} (W{n} coin set): {a['coins']} coins, health {a['health']}, defence {a['defense']}")
            data[n]["armor"][aid] = copy.deepcopy(a)

    # World 1's first set no longer needs the Bull's hide: the Bulls are what it's for (they wall a
    # player in plain clothes), so it's Chicken Feathers, Oak Logs and Stone; the hide moves to
    # Harvest Knight
    a1 = data[1]["armor"]
    # (2026-10-26, the user's second round: the hide back in the first set, it fits the leather
    # theme; both sets harder to make, so their levels go up with them: knobs 1.farmLevel / 1.hkLevel)
    a1["FarmhandsGear"]["recipe"] = {"1": {"id": "ChickenFeather", "count": 10}, "2": {"id": "BullHide", "count": 3},
                                     "3": {"id": "OakLog", "count": 8}}
    a1["HarvestKnight"]["recipe"] = {"1": {"id": "Horsehair", "count": 6}, "2": {"id": "LuckyHorseshoe", "count": 1},
                                     "3": {"id": "GoldenStraw", "count": 3}, "4": {"id": "OakLog", "count": 5},
                                     "5": {"id": "Stone", "count": 15}, "6": {"id": "BullHide", "count": 10}}
    a1["FarmhandsGear"]["level"] = int(knobs[1].get("farmLevel", 7))
    a1["HarvestKnight"]["level"] = int(knobs[1].get("hkLevel", 16))
    log.append("recipe FarmhandsGear: Chicken Feather 10 + Bull Hide 3 + Oak Log 8; HarvestKnight: Horsehair 6, "
               "Lucky Horseshoe, Golden Straw 3, Oak Log 5, Stone 15, Bull Hide 10")
    # World 1's trees and rocks: 50 HP, the wooden tools 10 a hit (the user; 5 hits a node)
    for nid in ("OakTree", "Boulder"):
        data[1]["gathering"][nid]["hp"] = 50
    for tid in ("WoodenAxe", "WoodenPickaxe"):
        data[1]["tools"][tid]["power"] = 10
    # every enemy material a flat 50% for 1, luck never applied (cores keep their 1%)
    for d in data.values():
        for group in ("enemies", "bosses"):
            for e in d["config"][group].values():
                for dr in items(e.get("materials", {})):
                    if dr["chance"] > 0.02:
                        dr["chance"], dr["min"], dr["max"] = 0.5, 1, 1
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

    # enemies (before the weapons: World 1's ladder is solved from its fights)
    for n, d in data.items():
        cfg = d["config"]
        for group, is_boss in ((cfg["enemies"], False), (cfg["bosses"], True)):
            for eid, e in group.items():
                m = e["melee"]
                move = m["move"]
                if move in TIMING:
                    w0, c0 = TIMING[move]
                    log.append(f"enemy {eid} timing: windup {m['windup']} -> {w0}, cooldown {m['cooldown']} -> {c0}")
                    m["windup"], m["cooldown"] = w0, c0
                # drops
                if eid in DROP_TABLES.get(n, {}):
                    table = DROP_TABLES[n][eid]
                    e["drops"] = {str(k): {"weapon": wid, "chance": c} for k, (wid, c) in enumerate(table.items(), 1)}
                    log.append(f"drops {eid}: {table}")
                else:
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

    # weapons, world by world
    anchor = WORLD1_COMMON
    new_dps = {}
    for wid, w in WORLD1_NEW.items():
        data[1]["weapons"][wid] = dict(w, id=wid, world=1, damage=1, reach=7, arc=90, maxTargets=2, swing="Sweep",
                                       order=max(v.get("order", 0) for v in data[1]["weapons"].values()) + 1)
    for n, new in NEW_WEAPONS.items():
        for wid, w in new.items():
            data[n]["weapons"][wid] = dict(w, id=wid, world=n, damage=1)
    for n in (1, 2, 3):
        ws = data[n]["weapons"]
        if n == 1:
            solve_world1(data, log)
            for wid, w in ws.items():
                new_dps[wid] = dps(w)
        else:
            solve_world(data, n, anchor, log)
            for wid, w in ws.items():
                new_dps[wid] = dps(w)
        # the Worldheart tier of this world: its secret x1.1
        for wid, w in ws.items():
            if w.get("rarity") == "Transcendent":
                d = round(new_dps[SECRET_WEAPON[n]] * 1.1 * w["cooldown"])
                log.append(f"weapon {wid}: {w['damage']} -> {d}")
                w["damage"] = d
        anchor = new_dps[BOSS_WEAPON[n]] * NEXT_WORLD_STEP
    # carried weapons (world N+1's dump lists the last world's for --from): keep them in step
    for n in (2, 3):
        for wid, w in list(data[n]["weapons"].items()):
            for m in (1, 2):
                if m < n and wid in data[m]["weapons"]:
                    w["damage"] = data[m]["weapons"][wid]["damage"]
    if not quiet:
        print("\n".join(log))
    return data


# the base player of each world: (level, base weapon, armour worn, upgrade level)
BASE_PLAYER = {1: (1, "Dagger", None, 0), 2: (25, "PumpkinMace", "HarvestKnight", 3), 3: (50, "HeartwoodStaff", "HeartwoodBark", 6)}


def solve_world1(data, log, runs=4000):
    """World 1's ladder and enemies together (WORLD1_DPS / _EASY / _STEP / _FIGHTS): each enemy's damage
    from the fight with its "just beats it" weapon, then the weapon that beats it easily, solved for
    WORLD1_EASY's share of the same player's health, then the next rungs from that one."""
    import random, statistics
    import base_fights as B
    ws, armor, lv = data[1]["weapons"], data[1]["armor"], data[1]["leveling"]
    cfg = data[1]["config"]
    enemies = dict(cfg["enemies"]); enemies.update(cfg["bosses"])

    def set_dps(wid, t, why):
        w = ws[wid]
        dmg = max(1, round(t * w["cooldown"]))
        log.append(f"weapon {wid} (W1 {w['rarity']}): {w['damage']} -> {dmg}  ({dps(w):.1f} -> {dmg / w['cooldown']:.1f} DPS; {why})")
        w["damage"] = dmg

    def player(eid):
        _, _, level, aid, _ = WORLD1_FIGHTS[eid]
        arm = armor[aid] if aid else {"health": 0, "defense": 0}
        return B.max_hp(lv, level, arm["health"], 0), 1 - arm["defense"], level, aid

    def stats(eid):
        x = enemies[eid]
        return {"hp": x["hp"], "armor": x["melee"].get("armor", 0), "windup": x["melee"]["windup"],
                "cooldown": x["melee"]["cooldown"], "damage": x["melee"]["damage"]}

    def taken(eid, w):
        hp, mult, _, _ = player(eid)
        rng = random.Random(1)
        return statistics.mean(B.fight(rng, w, stats(eid), 0, mult)[1] for _ in range(runs)) / hp

    def solve_enemy(eid):
        x = enemies[eid]
        new_hp, wid, level, aid, share = WORLD1_FIGHTS[eid]
        x["hp"] = new_hp
        hp = player(eid)[0]
        lo, hi = 1, hp
        for _ in range(30):
            mid = (lo + hi) / 2
            x["melee"]["damage"] = mid
            lo, hi = (mid, hi) if taken(eid, ws[wid]) < share else (lo, mid)
        dmg = round((lo + hi) / 2)
        x["melee"]["damage"] = dmg
        log.append(f"enemy {eid} (W1): hp {new_hp}, damage {dmg}  ({wid}, level {level}, {aid or 'no armour'}: "
                   f"~{share:.0%} of {hp:,.0f} HP)")

    def solve_easy(wid):
        eid, share = WORLD1_EASY[wid]
        w = dict(ws[wid])
        lo, hi = 1, 2000
        for _ in range(30):
            mid = (lo + hi) / 2
            w["damage"] = mid * w["cooldown"]
            lo, hi = (lo, mid) if taken(eid, w) < share else (mid, hi)
        set_dps(wid, (lo + hi) / 2, f"beats the {eid} easily: ~{share:.0%} taken")

    def step(wid):
        base, mult = WORLD1_STEP[wid]
        set_dps(wid, dps(ws[base]) * mult, f"{base} x{mult}")

    for wid, t in WORLD1_DPS.items():
        set_dps(wid, t, "set")
    # the order the ladder climbs in: each enemy before the weapon that beats it easily
    solve_enemy("Chicken")
    solve_enemy("Bull"); solve_easy("Pitchfork"); step("Shovel")
    solve_enemy("Stallion"); solve_enemy("CornWraith"); solve_easy("FarriersHammer"); step("Scythe")
    solve_enemy("BossScarecrow"); solve_easy("CrowbaneHoe")
    for wid in ("WeathervaneSpear", "PumpkinMace", "CornCob"):
        step(wid)
    # the check: every fight with the ladder's weapons
    for eid in WORLD1_FIGHTS:
        for wid in [w for w, (e, _) in WORLD1_EASY.items() if e == eid] + [WORLD1_FIGHTS[eid][1]]:
            log.append(f"  check {eid} with {wid}: {taken(eid, ws[wid]):.0%} of max HP taken")


def solve_world(data, n, anchor, log, runs=4000):
    """World n (2 or 3) fight by fight (WORLD_FIGHTS / _SET / _EASY / _STEP): health from the world's
    ladder (the small enemy's from its base fight's length), every enemy's damage from its fight, the
    "beats it easily" weapons from theirs, the rest stepped."""
    import random, statistics
    import base_fights as B
    ws, lv = data[n]["weapons"], data[1]["leveling"]
    every_w, every_a = {}, {}
    for m, d in data.items():
        for wid, w in d["weapons"].items():
            if w.get("world") == m:
                every_w[wid] = w
        every_a.update(d["armor"])
    cfg = data[n]["config"]
    enemies = dict(cfg["enemies"]); enemies.update(cfg["bosses"])
    up = WORLD_UPGRADES[n]
    fights = WORLD_FIGHTS[n]

    def set_dps(wid, t, why):
        w = ws[wid]
        dmg = max(1, round(t * w["cooldown"]))
        log.append(f"weapon {wid} (W{n} {w['rarity']}): {w['damage']} -> {dmg}  ({dps(w):.1f} -> {dmg / w['cooldown']:.1f} DPS; {why})")
        w["damage"] = dmg

    def player(eid):
        _, level, aid, _ = fights[eid]
        arm = every_a[aid]
        return B.max_hp(lv, level, arm["health"], up), (1 - arm["defense"]) * (1 + B.UP["Defense"] * up)

    def stats(eid):
        x = enemies[eid]
        return {"hp": x["hp"], "armor": x["melee"].get("armor", 0), "windup": x["melee"]["windup"],
                "cooldown": x["melee"]["cooldown"], "damage": x["melee"]["damage"]}

    def taken(eid, w):
        hp, mult = player(eid)
        rng = random.Random(1)
        return statistics.mean(B.fight(rng, w, stats(eid), up, mult)[1] for _ in range(runs)) / hp

    def seconds(eid, w):
        rng = random.Random(1)
        return statistics.mean(B.fight(rng, w, stats(eid), up, 1)[0] for _ in range(runs // 4))

    # health: the small enemy's from its base fight's length against the arrival weapon, the rest by the ladder
    small_id, length, _ = BASE[n]
    wpn = every_w[fights[small_id][0]]
    per = wpn["damage"] * (1 + B.UP["Attack"] * up)
    cd = wpn["cooldown"] * (1 + B.UP["AttackSpeed"] * up)
    chance, mult = B.CRIT_CHANCE + B.UP["CritChance"] * up, B.CRIT_MULT + B.UP["CritDamage"] * up
    small_hp = round(per * (1 + chance * (mult - 1)) * B.HIT_RATE / cd * length / 10) * 10
    for group, is_boss in ((cfg["enemies"], False), (cfg["bosses"], True)):
        for eid, x in group.items():
            new_hp = round(small_hp * HP_LADDER[tier_of(x, is_boss)] / 10) * 10
            log.append(f"enemy {eid} (W{n}): hp {x['hp']} -> {new_hp}")
            x["hp"] = new_hp

    def solve_enemy(eid):
        x = enemies[eid]
        wid, level, aid, share = fights[eid]
        hp = player(eid)[0]
        lo, hi = 1, hp
        for _ in range(30):
            mid = (lo + hi) / 2
            x["melee"]["damage"] = mid
            lo, hi = (mid, hi) if taken(eid, every_w[wid]) < share else (lo, mid)
        dmg = round((lo + hi) / 2)
        x["melee"]["damage"] = dmg
        log.append(f"enemy {eid} (W{n}): hp {x['hp']}, damage {dmg}  ({wid}, level {level}, {aid}, upgrades {up}: "
                   f"~{share:.0%} of {hp:,.0f} HP, {seconds(eid, every_w[wid]):.1f} s)")

    def solve_easy(wid):
        eid, share = WORLD_EASY[n][wid]
        w = dict(ws[wid])
        lo, hi = 1, 1e6
        for _ in range(40):
            mid = (lo + hi) / 2
            w["damage"] = mid * w["cooldown"]
            lo, hi = (lo, mid) if taken(eid, w) < share else (mid, hi)
        set_dps(wid, (lo + hi) / 2, f"beats the {eid} easily: ~{share:.0%} taken")

    def step(wid):
        base, k = WORLD_STEP[n][wid]
        t = dps(ws[base]) * k
        pierce = ws[wid].get("ignoreArmor")
        if pierce:
            t *= ARMOR_PIERCE
        set_dps(wid, t, f"{base} x{k}" + (" x armour-piercing" if pierce else ""))

    for wid, k in WORLD_SET[n].items():
        set_dps(wid, anchor * k, f"anchor x{k}")
    for item in WORLD_ORDER[n]:
        if item.startswith("+"):
            wid = item[1:]
            (solve_easy if wid in WORLD_EASY[n] else step)(wid)
        else:
            solve_enemy(item)
    for eid, f in fights.items():
        for w2 in [w for w, (e, _) in WORLD_EASY[n].items() if e == eid] + [f[0]]:
            log.append(f"  check {eid} with {w2}: {taken(eid, every_w[w2]):.0%} of max HP taken, {seconds(eid, every_w[w2]):.1f} s")


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
    for n in (2, 3):
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
