"""Potion icons (2026-10-19, the user's pick: style B "grows with tier" on the Potions UI canvas,
https://claude.ai/artifact/W9XiBtGwqgKrgc5hacFfjn). Tier I is a small vial, Tier II a shouldered bottle
with a gold collar, Tier III a wide gold-stoppered decanter on a gold base with a sparkle. The liquid is the
potion's colour (Config/Potions) and carries its symbol: a heart (Health), a sword (Strength), a shield
(Stoneskin) and a lightning bolt (Swiftness). Ink 23303a, like the other icons. World 2's three (2026-10-20):
Regen (green, a plus), Gatherer's (amber, an axe) and Angler's (blue, a fish).

  py potion_icons.py              writes potion_icons.html (one <svg data-export> per icon)
  py ../ui/svg_render.py potion_icons.html raw 512 8772   then open http://127.0.0.1:8772/render.html
  py potion_icons.py finish [Kind ...] [--sheet=<path>]
                                  crops raw/potion_<Id>.png into art/icons/potions/ (every kind, or the ones
                                  named); a review sheet only when asked (art/ keeps live art only)
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.dirname(os.path.dirname(HERE))
INK = "#23303a"
GLASS = "#e9f7fb"

COLORS = {
    "Health": ("#e4424c", "#ff9ea3"),
    "Strength": ("#f28c28", "#ffcf8f"),
    "Stoneskin": ("#9a9aa8", "#dcdce4"),
    "Swiftness": ("#40c4e8", "#b4f0ff"),
    "Regen": ("#58c860", "#bff2b8"),
    "Gatherer": ("#c88234", "#f2cc8e"),
    "Angler": ("#3a6ee8", "#aac6ff"),
}
SYMBOLS = {
    "Health": "M0 11 C-15 1 -15 -12 -6.5 -12 C-2.5 -12 0 -9 0 -6.5 C0 -9 2.5 -12 6.5 -12 C15 -12 15 1 0 11 Z",
    "Strength": "M-3.2 -15 L3.2 -15 L4.4 -11 L4.4 3 L10.5 3 L10.5 8 L4.4 8 L4.4 15 L-4.4 15 L-4.4 8 L-10.5 8 L-10.5 3 L-4.4 3 L-4.4 -11 Z",
    "Stoneskin": "M0 -14 L12 -9.5 L12 1 C12 8 6 12.5 0 14.5 C-6 12.5 -12 8 -12 1 L-12 -9.5 Z",
    "Swiftness": "M4 -15 L-9 2 L-1 2 L-5 15 L9 -3 L1 -3 Z",
    "Regen": "M-4.5 -14 L4.5 -14 L4.5 -4.5 L14 -4.5 L14 4.5 L4.5 4.5 L4.5 14 L-4.5 14 L-4.5 4.5 L-14 4.5 L-14 -4.5 L-4.5 -4.5 Z",
    "Gatherer": "M1 -15 L6 -15 L6 16 L1 16 Z M1 -12 L-3 -12 C-4 -16 -9 -17 -13 -15 C-17 -11 -17 1 -13 5 C-9 7 -4 6 -3 2 L1 2 Z",
    "Angler": "M-14 0 C-9 -9 3 -9 7 -2.5 L14 -9 L14 9 L7 2.5 C3 9 -9 9 -14 0 Z",
}
TURN = {"Gatherer": 40}  # degrees: the axe leans like the emoji, blade up and to the left
RARITY = {1: "uncommon", 2: "epic", 3: "legendary"}


def symbol(kind, x, y, scale=1.0, width=3.0):
    turn = f" rotate({TURN[kind]})" if kind in TURN else ""
    return (f'<g transform="translate({x} {y}) scale({scale}){turn}"><path d="{SYMBOLS[kind]}" fill="#ffffff" '
            f'stroke="{INK}" stroke-width="{width}" stroke-linejoin="round"></path></g>')


def tier1(liq, light, kind):
    return "".join([
        f'<rect x="42" y="52" width="44" height="64" rx="16" fill="{GLASS}" stroke="{INK}" stroke-width="5"></rect>',
        f'<rect x="46" y="70" width="36" height="42" rx="12" fill="{liq}"></rect>',
        f'<path d="M48 72 L80 72" stroke="{light}" stroke-width="4" stroke-linecap="round"></path>',
        f'<path d="M55 54 L55 34 L73 34 L73 54" fill="{GLASS}" stroke="{INK}" stroke-width="5" stroke-linejoin="round"></path>',
        f'<rect x="50" y="20" width="28" height="16" rx="5" fill="#c98a4b" stroke="{INK}" stroke-width="4.5"></rect>',
        '<path d="M49 64 L49 90" stroke="#ffffff" stroke-width="5" stroke-linecap="round" opacity="0.9"></path>',
        symbol(kind, 64, 92, 0.85, 3.5),
    ])


def tier2(liq, light, kind):
    return "".join([
        f'<path d="M34 66 Q34 50 52 46 L52 26 L76 26 L76 46 Q94 50 94 66 L94 104 Q94 117 81 117 L47 117 Q34 117 34 104 Z" fill="{GLASS}" stroke="{INK}" stroke-width="5" stroke-linejoin="round"></path>',
        f'<path d="M38 72 L90 72 L90 103 Q90 113 80 113 L48 113 Q38 113 38 103 Z" fill="{liq}"></path>',
        f'<path d="M40 74 L88 74" stroke="{light}" stroke-width="4" stroke-linecap="round"></path>',
        f'<rect x="46" y="40" width="36" height="9" rx="3" fill="#f6c840" stroke="{INK}" stroke-width="3.5"></rect>',
        f'<rect x="47" y="11" width="34" height="17" rx="5" fill="#c98a4b" stroke="{INK}" stroke-width="4.5"></rect>',
        '<path d="M42 62 L42 96" stroke="#ffffff" stroke-width="5" stroke-linecap="round" opacity="0.9"></path>',
        symbol(kind, 64, 93),
    ])


def tier3(liq, light, kind):
    return "".join([
        f'<path d="M64 46 C96 46 112 66 112 86 C112 106 92 116 64 116 C36 116 16 106 16 86 C16 66 32 46 64 46 Z" fill="{GLASS}" stroke="{INK}" stroke-width="5"></path>',
        f'<path d="M24 72 L104 72 C109 96 92 111 64 111 C36 111 19 96 24 72 Z" fill="{liq}"></path>',
        f'<path d="M26 72 L102 72" stroke="{light}" stroke-width="4" stroke-linecap="round"></path>',
        f'<path d="M54 48 L54 30 L74 30 L74 48" fill="{GLASS}" stroke="{INK}" stroke-width="5" stroke-linejoin="round"></path>',
        f'<rect x="48" y="42" width="32" height="9" rx="3" fill="#f6c840" stroke="{INK}" stroke-width="3.5"></rect>',
        f'<path d="M64 4 L78 18 L64 32 L50 18 Z" fill="#f6c840" stroke="{INK}" stroke-width="4.5" stroke-linejoin="round"></path>',
        '<path d="M58 14 L64 9" stroke="#fff3b0" stroke-width="3" stroke-linecap="round"></path>',
        f'<path d="M38 112 L90 112 L94 120 L34 120 Z" fill="#f6c840" stroke="{INK}" stroke-width="4" stroke-linejoin="round"></path>',
        '<path d="M30 70 C34 62 42 56 50 54" fill="none" stroke="#ffffff" stroke-width="5" stroke-linecap="round" opacity="0.9"></path>',
        symbol(kind, 64, 92),
        f'<path d="M106 22 L109 31 L118 34 L109 37 L106 46 L103 37 L94 34 L103 31 Z" fill="#fff3b0" stroke="{INK}" stroke-width="3" stroke-linejoin="round"></path>',
    ])


# The Crafter's "Lasts" card icon: a gold-framed hourglass with the sand running.
HOURGLASS = "".join([
    f'<path d="M40 22 L88 22 L88 30 C88 48 72 56 68 64 C72 72 88 80 88 98 L88 106 L40 106 L40 98 C40 80 56 72 60 64 C56 56 40 48 40 30 Z" fill="{GLASS}" stroke="{INK}" stroke-width="5" stroke-linejoin="round"></path>',
    '<path d="M46 34 L82 34 C80 46 70 52 64 58 C58 52 48 46 46 34 Z" fill="#f2b33a"></path>',
    '<path d="M64 62 L64 92" stroke="#f2b33a" stroke-width="4" stroke-linecap="round"></path>',
    '<path d="M46 101 C48 90 58 86 64 86 C70 86 80 90 82 101 Z" fill="#f2b33a"></path>',
    '<path d="M48 40 C50 46 54 50 58 53" fill="none" stroke="#ffffff" stroke-width="4" stroke-linecap="round" opacity="0.9"></path>',
    f'<rect x="30" y="10" width="68" height="14" rx="6" fill="#f6c840" stroke="{INK}" stroke-width="4.5"></rect>',
    f'<rect x="30" y="104" width="68" height="14" rx="6" fill="#f6c840" stroke="{INK}" stroke-width="4.5"></rect>',
    '<path d="M38 15 L60 15" stroke="#fff3b0" stroke-width="3" stroke-linecap="round"></path>',
])


def write_html():
    parts = ["<!doctype html><body>\n<!-- Generated by potion_icons.py; edit that, not this. -->\n"]
    for kind, (liq, light) in COLORS.items():
        for tier, draw in ((1, tier1), (2, tier2), (3, tier3)):
            parts.append(f'<svg viewBox="0 0 128 128" data-export="potion_{kind}{tier}" aria-hidden="true">'
                         f'{draw(liq, light, kind)}</svg>\n')
    parts.append(f'<svg viewBox="0 0 128 128" data-export="stat_Lasts" aria-hidden="true">{HOURGLASS}</svg>\n')
    parts.append("</body>\n")
    with open(os.path.join(HERE, "potion_icons.html"), "w", encoding="utf-8", newline="\n") as f:
        f.write("".join(parts))
    print("wrote potion_icons.html")


def fit(src, dst):
    from PIL import Image
    im = Image.open(src).convert("RGBA")
    im = im.crop(im.getchannel("A").getbbox())
    k = 464 / max(im.size)
    im = im.resize((round(im.width * k), round(im.height * k)), Image.LANCZOS)
    icon = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
    icon.alpha_composite(im, ((512 - im.width) // 2, (512 - im.height) // 2))
    icon.save(dst)
    return icon


def finish(kinds, sheet_path):
    from PIL import Image
    out_dir = os.path.join(ART, "icons", "potions")
    os.makedirs(out_dir, exist_ok=True)
    tiles = os.path.join(ART, "ui", "inventory")
    cell, gap = 200, 14
    sheet = Image.new("RGBA", (3 * (cell + gap) + gap, len(kinds) * (cell + gap) + gap), (196, 232, 238, 255))
    for row, kind in enumerate(kinds):
        for tier in (1, 2, 3):
            icon = fit(os.path.join(HERE, "raw", f"potion_{kind}{tier}.png"), os.path.join(out_dir, f"{kind}{tier}.png"))
            x, y = gap + (tier - 1) * (cell + gap), gap + row * (cell + gap)
            tile = os.path.join(tiles, f"tile_{RARITY[tier]}.png")
            if os.path.exists(tile):
                sheet.alpha_composite(Image.open(tile).convert("RGBA").resize((cell, cell), Image.LANCZOS), (x, y))
            pad = cell // 9
            sheet.alpha_composite(icon.resize((cell - 2 * pad, cell - 2 * pad), Image.LANCZOS), (x + pad, y + pad))
    lasts = os.path.join(HERE, "raw", "stat_Lasts.png")
    if os.path.exists(lasts):
        fit(lasts, os.path.join(out_dir, "Lasts.png"))
    if sheet_path:
        sheet.save(sheet_path)
    print("saved", 3 * len(kinds), "icons")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "finish":
        named = [a for a in sys.argv[2:] if not a.startswith("--")]
        sheet = next((a.split("=", 1)[1] for a in sys.argv[2:] if a.startswith("--sheet=")), None)
        finish(named or list(COLORS), sheet)
    else:
        write_html()
