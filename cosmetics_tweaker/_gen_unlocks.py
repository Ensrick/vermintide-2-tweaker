"""Generate the cosmetics_tweaker unlock data.

Per-(item × career) toggle. Each character's career menu shows ALL hats and ALL
skins in that character's pool: native ones default-checked, non-native default-
unchecked. Checking enables; unchecking removes. Cross-character is forbidden
(would crash on skeleton mismatch). wh_priest is excluded both ways inside
Saltzpyre.

Reads `_cos_probe.txt` next to this script (lines: `DATA|section|careers|key`
or `NAME|key|localized_name`). Writes:
    scripts/mods/cosmetics_tweaker/_cosmetic_unlocks.lua

Module returns { managed = ..., widgets = ..., localization = ... } where:
- managed[item_key] = { section, character, native_set } — used by apply.
- widgets           = nested VMF tree.
- localization      = en labels per setting_id.
"""
import os
import re
import sys

HERE = os.path.dirname(__file__)
PROBE = os.path.join(HERE, "_cos_probe.txt")
OUT = os.path.join(HERE, "scripts", "mods", "cosmetics_tweaker", "_cosmetic_unlocks.lua")

CHARACTERS = {
    "kruber":   ["es_mercenary", "es_huntsman", "es_knight", "es_questingknight"],
    "bardin":   ["dr_ranger", "dr_ironbreaker", "dr_slayer", "dr_engineer"],
    "saltzpyre": ["wh_captain", "wh_bountyhunter", "wh_zealot"],  # wh_priest excluded
    "elf":      ["we_waywatcher", "we_maidenguard", "we_shade", "we_thornsister"],
    "sienna":   ["bw_adept", "bw_scholar", "bw_unchained", "bw_necromancer"],
}
CHARACTER_LABEL = {
    "kruber": "Kruber", "bardin": "Bardin", "saltzpyre": "Saltzpyre",
    "elf": "Kerillian", "sienna": "Sienna",
}
CAREER_LABEL = {
    "es_mercenary": "Mercenary", "es_huntsman": "Huntsman", "es_knight": "Foot Knight", "es_questingknight": "Grail Knight",
    "dr_ranger": "Ranger Veteran", "dr_ironbreaker": "Ironbreaker", "dr_slayer": "Slayer", "dr_engineer": "Outcast Engineer",
    "wh_captain": "Witch Hunter Captain", "wh_bountyhunter": "Bounty Hunter", "wh_zealot": "Zealot",
    "we_waywatcher": "Waystalker", "we_maidenguard": "Handmaiden", "we_shade": "Shade", "we_thornsister": "Sister of the Thorn",
    "bw_adept": "Battle Wizard", "bw_scholar": "Pyromancer", "bw_unchained": "Unchained", "bw_necromancer": "Necromancer",
}

career_to_char = {c: ch for ch, lst in CHARACTERS.items() for c in lst}
all_player_careers = set(career_to_char.keys())  # excludes wh_priest

# Parse probe: native[item_key] = {section, careers set}; names[item_key] = label.
native = {}
names = {}
with open(PROBE) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        if line.startswith("NAME|"):
            _, k, n = line.split("|", 2)
            names[k] = n
            continue
        if not line.startswith("DATA|"):
            continue
        _, section, careers_csv, key = line.split("|", 3)
        careers = {c for c in careers_csv.split(",") if c}
        if any(c.startswith("vs_") for c in careers):
            continue
        if not (careers & (all_player_careers | {"wh_priest"})):
            continue
        if key not in native:
            native[key] = {"section": section, "careers": set()}
        native[key]["careers"] |= careers


# Determine character for each item; reject cross-character / priest-only.
items_by_char = {ch: {"hats": [], "skins": []} for ch in CHARACTERS}
managed = {}  # key -> { section, character, native_set }
for key, info in native.items():
    natives_in_player = info["careers"] & all_player_careers
    chars = {career_to_char[c] for c in natives_in_player}
    if not natives_in_player:
        continue  # priest-only
    if len(chars) > 1:
        continue  # cross-character
    ch = chars.pop()
    managed[key] = {
        "section": info["section"],
        "character": ch,
        "native": natives_in_player & set(CHARACTERS[ch]),  # exclude wh_priest from native record
    }
    items_by_char[ch][info["section"]].append(key)

# Strip non-ASCII so the in-game font renders cleanly.
_TRANSLIT = {
    "ä": "a", "ö": "o", "ü": "u", "Ä": "A", "Ö": "O", "Ü": "U",
    "ß": "ss", "à": "a", "á": "a", "â": "a", "ã": "a", "å": "a",
    "è": "e", "é": "e", "ê": "e", "ë": "e",
    "ì": "i", "í": "i", "î": "i", "ï": "i",
    "ò": "o", "ó": "o", "ô": "o", "õ": "o", "ø": "o",
    "ù": "u", "ú": "u", "û": "u",
    "ñ": "n", "ç": "c",
    "À": "A", "Á": "A", "Â": "A", "Ã": "A", "Å": "A",
    "È": "E", "É": "E", "Ê": "E", "Ë": "E",
    "Ì": "I", "Í": "I", "Î": "I", "Ï": "I",
    "Ò": "O", "Ó": "O", "Ô": "O", "Õ": "O", "Ø": "O",
    "Ù": "U", "Ú": "U", "Û": "U",
    "Ñ": "N", "Ç": "C", "—": "-", "–": "-", "’": "'", "‘": "'",
    "“": '"', "”": '"', "…": "...",
}


def asciify(s: str) -> str:
    out = []
    for ch in s:
        if ch in _TRANSLIT:
            out.append(_TRANSLIT[ch])
        elif ord(ch) < 128:
            out.append(ch)
        else:
            out.append("?")
    return "".join(out)


# Pretty source-career prefix from the item's native career list. For items
# native to one career, e.g. "Mercenary". For multi-career items, join with "/".
def source_prefix(key: str, info: dict) -> str:
    natives = sorted(info["native"])
    parts = [CAREER_LABEL.get(c, c) for c in natives]
    return "/".join(parts)


def label_for(key: str) -> str:
    raw = names.get(key, key)
    info = managed.get(key)
    base = asciify(raw)
    if info:
        prefix = source_prefix(key, info)
        if prefix:
            return f"{prefix}: {base}"
    return base

for ch in items_by_char:
    items_by_char[ch]["hats"].sort(key=lambda k: label_for(k).lower())
    items_by_char[ch]["skins"].sort(key=lambda k: label_for(k).lower())


def lua_str(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


lines = []
lines.append("-- AUTO-GENERATED by _gen_unlocks.py from `cos probe_cosmetics` output.")
lines.append("-- Re-run the python script after updating _cos_probe.txt; do not edit by hand.")
lines.append("")

# managed: per-item table the apply logic walks.
lines.append("local managed = {")
for key in sorted(managed):
    info = managed[key]
    nat = ", ".join(lua_str(c) for c in sorted(info["native"]))
    lines.append(
        f'    [{lua_str(key)}] = {{ section = {lua_str(info["section"])}, '
        f'character = {lua_str(info["character"])}, '
        f"native = {{ {nat} }} }},"
    )
lines.append("}")
lines.append("")

# localization: group titles + per-(career, item) labels.
lines.append("local localization = {")
for ch in CHARACTERS:
    if not (items_by_char[ch]["hats"] or items_by_char[ch]["skins"]):
        continue
    lines.append(f'    cos_unlock_{ch}_group = {{ en = {lua_str(CHARACTER_LABEL[ch] + " Cosmetics")} }},')
    for career in CHARACTERS[ch]:
        lines.append(f'    cos_unlock_{career}_group = {{ en = {lua_str(CAREER_LABEL[career])} }},')
        for sec in ("hats", "skins"):
            keys = items_by_char[ch][sec]
            if not keys:
                continue
            lines.append(f'    cos_unlock_{career}_{sec}_group = {{ en = {lua_str(sec.capitalize())} }},')
            for k in keys:
                sid = f"cos_unlock_{career}_{k}"
                lines.append(f"    {sid} = {{ en = {lua_str(label_for(k))} }},")
lines.append("}")
lines.append("")

# widgets: Character → Career → Hats/Skins → all character items.
lines.append("local widgets = {")
for ch in CHARACTERS:
    if not (items_by_char[ch]["hats"] or items_by_char[ch]["skins"]):
        continue
    lines.append("    {")
    lines.append(f'        setting_id = "cos_unlock_{ch}_group",')
    lines.append('        type = "group",')
    lines.append("        sub_widgets = {")
    for career in CHARACTERS[ch]:
        lines.append("            {")
        lines.append(f'                setting_id = "cos_unlock_{career}_group",')
        lines.append('                type = "group",')
        lines.append("                sub_widgets = {")
        for sec in ("hats", "skins"):
            keys = items_by_char[ch][sec]
            if not keys:
                continue
            lines.append("                    {")
            lines.append(f'                        setting_id = "cos_unlock_{career}_{sec}_group",')
            lines.append('                        type = "group",')
            lines.append("                        sub_widgets = {")
            for k in keys:
                native_for_career = career in managed[k]["native"]
                sid = f"cos_unlock_{career}_{k}"
                default = "true" if native_for_career else "false"
                lines.append("                            {")
                lines.append(f'                                setting_id = {lua_str(sid)},')
                lines.append('                                type = "checkbox",')
                lines.append(f"                                default_value = {default},")
                lines.append("                            },")
            lines.append("                        },")
            lines.append("                    },")
        lines.append("                },")
        lines.append("            },")
    lines.append("        },")
    lines.append("    },")
lines.append("}")
lines.append("")

lines.append("return { managed = managed, widgets = widgets, localization = localization }")
lines.append("")

with open(OUT, "w", encoding="utf8") as f:
    f.write("\n".join(lines))

# Counts
total_toggles = 0
for ch in CHARACTERS:
    h = len(items_by_char[ch]["hats"])
    s = len(items_by_char[ch]["skins"])
    careers = len(CHARACTERS[ch])
    print(f"  {ch:10s} hats={h:3d}  skins={s:3d}  toggles={(h + s) * careers:4d}", file=sys.stderr)
    total_toggles += (h + s) * careers
print(f"  TOTAL TOGGLES: {total_toggles}", file=sys.stderr)
print(f"  Wrote: {OUT}", file=sys.stderr)
