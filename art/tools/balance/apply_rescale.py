"""Writes the 2026-10-26 rescale (rescale.py's world<N>.json) into the game's Luau configs:
enemies (health, damage, windup, cooldown, kill coins and EXP, weapon drop chances) in
Config/Worlds, weapon damage in Config/Weapons, the Worldheart tiers in Config/Infuse, armour
health, coins and recipes in Config/Armor, tool recipes in Config/Tools, node yields in
Config/Gathering, gate materials in Config/Gates. (The questlines are written by hand in
Config/Quests; rescale.py's QUESTS mirrors them for the simulation.) Prints every line it changes;
--dry shows them without writing.

  py apply_rescale.py --dry
  py apply_rescale.py
"""
import argparse, json, re
from pathlib import Path

HERE = Path(__file__).parent
SRC = HERE.parents[2] / "src" / "shared" / "Config"
WORLD_FILES = {1: "W01_SunnyMeadows", 2: "W02_RedwoodForest", 3: "W03_CrystalCaverns"}
STAMP = "2026-10-26 rescale"


def num(v):
    return ("%g" % v) if isinstance(v, float) else str(v)


def block(text, name, indent):
    """(start, end) of `<indent>name = {` .. its closing `<indent>},`."""
    m = re.search(r"\n" + indent + re.escape(name) + r" = \{\n", text)
    if not m:
        raise KeyError(name)
    end = text.index("\n" + indent + "},", m.end())
    return m.start(), end


def sub_in(text, span, pattern, repl, changes, what):
    a, b = span
    part = text[a:b]
    new, n = re.subn(pattern, repl, part, count=1)
    if n == 0:
        raise ValueError(f"{what}: no match for {pattern}")
    if new != part:
        changes.append(what)
    return text[:a] + new + text[b:], (a, a + len(new))


def items(t):
    return list(t.values()) if isinstance(t, dict) else t


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry", action="store_true")
    a = ap.parse_args()
    data = {n: json.load(open(HERE / f"world{n}.json", encoding="utf-8")) for n in (1, 2, 3)}
    files = {}
    changes = []

    # --- enemies ---------------------------------------------------------------
    for n, fname in WORLD_FILES.items():
        path = SRC / "Worlds" / f"{fname}.luau"
        text = path.read_text(encoding="utf-8")
        cfg = data[n]["config"]
        for group in ("enemies", "bosses"):
            for eid, e in cfg[group].items():
                span = block(text, eid, "\t\t")
                m = e["melee"]
                text, span = sub_in(text, span, r"hp = [\d.]+,", f"hp = {e['hp']},", changes, f"{eid} hp {e['hp']}")
                for key in ("damage", "cooldown", "windup"):
                    text, span = sub_in(text, span, r"(melee = \{[^\n]*?\b" + key + r" = )[\d.]+", r"\g<1>" + num(m[key]),
                                        changes, f"{eid} {key} {m[key]}")
                text, span = sub_in(text, span, r"coins = \{ min = \d+, max = \d+ \}",
                                    f"coins = {{ min = {e['coins']['min']}, max = {e['coins']['max']} }}", changes,
                                    f"{eid} coins {e['coins']['min']}-{e['coins']['max']}")
                if "exp" in e:
                    text, span = sub_in(text, span, r"exp = \d+,", f"exp = {e['exp']},", changes, f"{eid} exp {e['exp']}")
                for dr in items(e.get("drops", {})):
                    text, span = sub_in(text, span, r'(\{ weapon = "' + dr["weapon"] + r'", chance = )[\d.]+',
                                        r"\g<1>" + num(dr["chance"]), changes, f"{eid} drop {dr['weapon']} {dr['chance']}")
        files[path] = text

    # --- weapons -----------------------------------------------------------------
    path = SRC / "Weapons.luau"
    text = path.read_text(encoding="utf-8")
    seen = set()
    for n in (1, 2, 3):
        for wid, w in data[n]["weapons"].items():
            if wid in seen:
                continue
            seen.add(wid)
            try:
                span = block(text, wid, "\t")
            except KeyError:
                continue
            text, span = sub_in(text, span, r"\bdamage = \d+,", f"damage = {w['damage']},", changes, f"weapon {wid} damage {w['damage']}")
    files[path] = text

    # --- the Worldheart tiers: each world's secret x1.1 a second ----------------------
    path = SRC / "Infuse.luau"
    text = path.read_text(encoding="utf-8")
    secrets = {1: "CornCob", 2: "MarshmallowStick", 3: "RockCandyClub"}
    tiers = []
    for n in (1, 2, 3):
        w = data[n]["weapons"][secrets[n]]
        tiers.append(round(w["damage"] / w["cooldown"] * 1.1, 1))
    while len(tiers) < 8:
        tiers.append(round(tiers[-1] * 2, 1))   # placeholders until those worlds' secrets exist
    new = "Infuse.DPS = { " + ", ".join(num(float(t)) for t in tiers) + " }"
    text, n = re.subn(r"Infuse\.DPS = \{[^}]*\}", new, text, count=1)
    if n:
        changes.append(f"Infuse.DPS {tiers}")
    files[path] = text

    # --- armour ---------------------------------------------------------------------
    path = SRC / "Armor.luau"
    text = path.read_text(encoding="utf-8")
    for n in (1, 2, 3):
        for aid, ar in data[n]["armor"].items():
            span = block(text, aid, "\t")
            text, span = sub_in(text, span, r"\bhealth = \d+,", f"health = {ar['health']},", changes, f"armour {aid} health {ar['health']}")
            text, span = sub_in(text, span, r"\bcoins = \d+,", f"coins = {ar['coins']},", changes, f"armour {aid} coins {ar['coins']}")
            text, span = sub_in(text, span, r"\blevel = \d+,", f"level = {ar['level']},", changes, f"armour {aid} level {ar['level']}")
            text, span = sub_in(text, span, r"\bdefense = [\d.]+,", f"defense = {ar['defense']:.2f},", changes, f"armour {aid} defense {ar['defense']}")
            lines = "".join(f"\t\t\t{{ id = \"{x['id']}\", count = {x['count']} }},\n" for x in items(ar["recipe"]))
            text, span = sub_in(text, span, r"recipe = \{\n(?:\t\t\t[^\n]*\n)*?\t\t\},", "recipe = {\n" + lines + "\t\t},",
                                changes, f"armour {aid} recipe")
    files[path] = text

    # --- tools ----------------------------------------------------------------------
    path = SRC / "Tools.luau"
    text = path.read_text(encoding="utf-8")
    for n in (2, 3):
        for tid, t in data[n]["tools"].items():
            r = t.get("recipe")
            if not r:
                continue
            span = block(text, tid, "\t")
            lines = "".join(f"\t\t\t\t{{ id = \"{x['id']}\", count = {x['count']} }},\n" for x in items(r["materials"]))
            text, span = sub_in(text, span, r"(recipe = \{\n\t\t\ttool = \"\w+\",\n\t\t\tmaterials = \{\n)(?:\t\t\t\t[^\n]*\n)*?(\t\t\t\},)",
                                r"\g<1>" + lines.replace("\\", "\\\\") + r"\g<2>", changes, f"tool {tid} recipe")
    files[path] = text

    # --- gathering yields -------------------------------------------------------------
    path = SRC / "Gathering.luau"
    text = path.read_text(encoding="utf-8")
    for n in (1, 2, 3):
        for nid, node in data[n].get("gathering", {}).items():
            span = block(text, nid, "\t")
            for dr in items(node["drops"]):
                text, span = sub_in(text, span, r'\{ id = "' + dr["id"] + r'", min = \d+, max = \d+,',
                                    f'{{ id = "{dr["id"]}", min = {dr["min"]}, max = {dr["max"]},', changes,
                                    f"node {nid} {dr['id']} {dr['min']}-{dr['max']}")
    files[path] = text

    # --- gate materials ---------------------------------------------------------------
    path = SRC / "Gates.luau"
    text = path.read_text(encoding="utf-8")
    for n in (1, 2, 3):
        g = data[n]["gate"]
        a0 = text.index(f'id = "{g["id"]}",')
        span = (a0, text.index("\n\t},", a0))
        mats = ", ".join(f'{{ id = "{m["id"]}", count = {m["count"]} }}' for m in g["materials"])
        text, span = sub_in(text, span, r"materials = \{ \{[^\n]*\} \},", "materials = { " + mats + " },",
                            changes, f"gate {g['id']} materials")
    files[path] = text

    print("\n".join(changes))
    print(f"\n{len(changes)} changes in {len(files)} files")
    if not a.dry:
        for p, t in files.items():
            p.write_text(t, encoding="utf-8", newline="\n")


if __name__ == "__main__":
    main()
