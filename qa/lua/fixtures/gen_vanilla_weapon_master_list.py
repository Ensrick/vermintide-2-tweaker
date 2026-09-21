"""Generate qa/lua/fixtures/vanilla_weapon_master_list.lua from the decompiled
vanilla source. Read-only over the decompile; writes one Lua fixture file.

Usage: py -3 qa/lua/fixtures/gen_vanilla_weapon_master_list.py <decompile_root> qa/lua/fixtures/vanilla_weapon_master_list.lua
"""
import glob
import os
import re
import sys

root = sys.argv[1]
out_path = sys.argv[2]

item_files = sorted(
    glob.glob(os.path.join(root, "scripts/settings/equipment/item_master_list*.lua"))
    + glob.glob(os.path.join(root, "scripts/settings/dlcs/*/item_master_list*.lua"))
    + glob.glob(os.path.join(root, "scripts/settings/dlcs/*/*equipment_settings*.lua"))
)
entry_re = re.compile(r"^ItemMasterList\.([A-Za-z0-9_]+) = \{\n(.*?)^\}", re.M | re.S)
update_re = re.compile(r"^UpdateItemMasterList\(\{\n(.*?)^\}, \"([a-z_]+)\"\)", re.M | re.S)

weapons = {}
patches = []
for f in item_files:
    txt = open(f, encoding="utf-8", errors="replace").read()
    rel = os.path.relpath(f, root).replace("\\", "/")
    for m in entry_re.finditer(txt):
        key, body = m.group(1), m.group(2)
        st = re.search(r'^\tslot_type = "([a-z_]+)"', body, re.M)
        if not st or st.group(1) not in ("melee", "ranged"):
            continue
        wield_all = re.search(r"^\tcan_wield = CanWieldAllItemTemplates", body, re.M) is not None
        cw = re.search(r"^\tcan_wield = \{(.*?)^\t\}", body, re.M | re.S)
        wield = re.findall(r'"([a-z_]+)"', cw.group(1)) if cw else []
        rar = re.search(r'^\trarity = "([a-z_]+)"', body, re.M)
        rhu = re.search(r'^\tright_hand_unit = "([^"]+)"', body, re.M)
        lhu = re.search(r'^\tleft_hand_unit = "([^"]+)"', body, re.M)
        tpl = re.search(r'^\ttemplate = "([^"]+)"', body, re.M)
        itype = re.search(r'^\titem_type = "([^"]+)"', body, re.M)
        weapons[key] = dict(
            file=rel,
            slot_type=st.group(1),
            can_wield=wield,
            wield_all=wield_all,
            rarity=rar.group(1) if rar else None,
            rhu=rhu.group(1) if rhu else None,
            lhu=lhu.group(1) if lhu else None,
            template=tpl.group(1) if tpl else None,
            item_type=itype.group(1) if itype else None,
        )
    for m in update_re.finditer(txt):
        names = re.findall(r'"([A-Za-z0-9_]+)"', m.group(1))
        patches.append((rel, names, m.group(2)))

for rel, names, career in patches:
    for name in names:
        if name in weapons and career not in weapons[name]["can_wield"]:
            weapons[name]["can_wield"].append(career)

# Career slot-type tables (item_slot_types_by_slot_name) for the 20 hero careers.
career_files = [os.path.join(root, "scripts/settings/profiles/career_settings.lua")] + sorted(
    glob.glob(os.path.join(root, "scripts/settings/dlcs/*/career_settings_*.lua"))
)
career_re = re.compile(r"^(?:\t)?([a-z]{2}_[a-z_]+) = \{\n|^CareerSettings\.([a-z_]+) = \{\n", re.M)
careers = {}
for f in career_files:
    txt = open(f, encoding="utf-8", errors="replace").read()
    rel = os.path.relpath(f, root).replace("\\", "/")
    starts = [(m.start(), m.group(1) or m.group(2)) for m in career_re.finditer(txt)]
    for i, (pos, name) in enumerate(starts):
        end = starts[i + 1][0] if i + 1 < len(starts) else len(txt)
        block = txt[pos:end]
        m = re.search(r"item_slot_types_by_slot_name = \{(.*?)\n\t*\},\n\t*loadout_equipment_slots", block, re.S)
        if not m:
            continue
        slots = {}
        for sm in re.finditer(r"(slot_[a-z_0-9]+) = \{(.*?)\}", m.group(1), re.S):
            slots[sm.group(1)] = re.findall(r'"([a-z_]+)"', sm.group(2))
        if "slot_melee" in slots and "slot_ranged" in slots:
            careers[name] = dict(file=rel, slot_melee=slots["slot_melee"], slot_ranged=slots["slot_ranged"])

HERO_CAREERS = [
    "dr_ironbreaker", "dr_slayer", "dr_ranger", "dr_engineer",
    "es_huntsman", "es_knight", "es_mercenary", "es_questingknight",
    "we_shade", "we_maidenguard", "we_waywatcher", "we_thornsister",
    "wh_zealot", "wh_bountyhunter", "wh_captain", "wh_priest",
    "bw_scholar", "bw_adept", "bw_unchained", "bw_necromancer",
]
missing = [c for c in HERO_CAREERS if c not in careers]
if missing:
    raise SystemExit("career slot tables missing: %s" % missing)

# Demo starting gear seeds (scripts/settings/demo_settings.lua character_starting_gear).
demo = open(os.path.join(root, "scripts/settings/demo_settings.lua"), encoding="utf-8", errors="replace").read()
gear = re.search(r"character_starting_gear = \{(.*?)\n\t\},\n", demo, re.S).group(1)
seeds = {}
for m in re.finditer(r"\n\t\t([a-z_]+) = \{(.*?)\n\t\t\}", gear, re.S):
    career, body = m.group(1), m.group(2)
    melee = re.search(r'slot_melee = "([^"]+)"', body).group(1)
    ranged = re.search(r'slot_ranged = "([^"]+)"', body).group(1)
    seeds[career] = (melee, ranged)

def lua_str_list(items):
    return "{ " + ", ".join('"%s"' % s for s in items) + " }"

lines = []
lines.append("-- vanilla_weapon_master_list.lua -- OFFLINE FIXTURE, GENERATED. Do not hand-edit.")
lines.append("-- Source: decompiled Vermintide 2 script bundle (release_hon_2026_03_25_yearly_events),")
lines.append("-- every ItemMasterList weapon entry (slot_type melee/ranged) from")
lines.append("-- scripts/settings/equipment/item_master_list*.lua and scripts/settings/dlcs/*/item_master_list_*.lua,")
lines.append("-- with the UpdateItemMasterList({...}, career) can_wield patches applied")
lines.append("-- (item_master_list.lua:30-60), plus each hero career's item_slot_types_by_slot_name")
lines.append("-- weapon rows (career_settings.lua / dlcs/*/career_settings_*.lua) and the demo")
lines.append("-- starting-gear seeds (demo_settings.lua DemoOfflineBackendTitleInternalData.character_starting_gear).")
lines.append("-- Regenerate with the generator noted in qa/lua/README.md when the decompile changes.")
lines.append("-- Shape per weapon: { slot_type, rarity, can_wield, right_hand_unit, left_hand_unit, template, item_type }.")
lines.append("local F = { weapons = {}, careers = {}, demo_seeds = {}, hero_careers = %s }" % lua_str_list(HERO_CAREERS))
lines.append("local W = F.weapons")
for key in sorted(weapons):
    w = weapons[key]
    cw = "CAN_WIELD_ALL" if w["wield_all"] else lua_str_list(w["can_wield"])
    def q(v):
        return '"%s"' % v if v is not None else "nil"
    lines.append('W["%s"] = { slot_type = %s, rarity = %s, can_wield = %s, right_hand_unit = %s, left_hand_unit = %s, template = %s, item_type = %s }' % (
        key, q(w["slot_type"]), q(w["rarity"]), cw, q(w["rhu"]), q(w["lhu"]), q(w["template"]), q(w["item_type"])))
lines.append("local C = F.careers")
for c in HERO_CAREERS:
    lines.append('C["%s"] = { slot_melee = %s, slot_ranged = %s }' % (c, lua_str_list(careers[c]["slot_melee"]), lua_str_list(careers[c]["slot_ranged"])))
lines.append("local S = F.demo_seeds")
for c in sorted(seeds):
    lines.append('S["%s"] = { slot_melee = "%s", slot_ranged = "%s" }' % (c, seeds[c][0], seeds[c][1]))
lines.append("return F")

text = "\n".join(lines) + "\n"
text = text.replace("CAN_WIELD_ALL", "F.CAN_WIELD_ALL")
text = text.replace("local F = {", "local F = {", 1)
# CAN_WIELD_ALL sentinel must exist before use.
text = text.replace("local W = F.weapons", "F.CAN_WIELD_ALL = { all_careers = true }\nlocal W = F.weapons", 1)
os.makedirs(os.path.dirname(out_path), exist_ok=True)
with open(out_path, "w", encoding="utf-8", newline="\n") as fh:
    fh.write(text)
print("weapons", len(weapons), "careers", len(careers), "seeds", len(seeds), "patches", len(patches))
wield_all_weapons = [k for k, v in weapons.items() if v["wield_all"]]
print("wield_all weapons:", wield_all_weapons)
for c in HERO_CAREERS:
    print(c, careers[c]["slot_melee"], careers[c]["slot_ranged"], seeds.get(c))
