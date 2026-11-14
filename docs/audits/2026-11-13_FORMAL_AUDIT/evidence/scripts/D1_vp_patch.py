# D1 round 2: exact-string corrections to plan/vp/D1.md after verification greps. Each must match once.
import os
A = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VP = os.path.join(A, 'plan', 'vp', 'D1.md')
t = open(VP, encoding='utf-8').read()
EDITS = [
    ("R3 craft a CWV weapon with a custom mesh (use `cwv_es_greataxe`; the card's \"Poleaxe\" was replaced by the Greataxe, see check `issue597_greataxe_replaces_poleaxe`).",
     "R3 craft a CWV weapon with a custom mesh: use `cwv_es_greataxe`. The pinned card says to craft a \"Poleaxe\", but no item with that name exists: `git grep -ci poleaxe character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_variant_catalog.lua` is 0 and the weapon is named Greataxe at `:606-608` (see NF-09)."),
    ("via `items:get_filtered_items(\"can_salvage\")` `[unverified filter string form]`",
     "via `items:get_filtered_items(\"can_salvage\")` (filter strings are expressions over those macros; form used at `Vermintide-2-Source-Code/scripts/ui/views/hero_view/craft_pages/craft_page_craft_item.lua:99`)"),
    ("The projectile unit is an instance of `ProjectileUnits.grenade.projectile_unit_name` (the authored",
     "The projectile unit is an instance of `ProjectileUnits.grenade.projectile_unit_name` (`Vermintide-2-Source-Code/scripts/settings/equipment/projectile_units.lua:47`; the authored"),
    ("is not nil (`Vermintide-2-Source-Code/foundation/scripts/managers/world/world_manager.lua:53, 60-62`).",
     "is not nil (`Vermintide-2-Source-Code/foundation/scripts/managers/world/world_manager.lua:53, 60-62, 107, 111`)."),
    ("| NF-09 | #798, #932, #613 | Tracker text, not code: #798's and #932's pinned cards contain corrupted characters; #613 still carries the 2026-10-17 hold although #1687 shipped. | Re-cut the three cards from the cases in VP-D1-09, VP-D1-10 and VP-D1-04. | S |",
     "| NF-09 | #798, #932, #613, #419 | Tracker text, not code: #798's and #932's pinned cards contain corrupted characters; #613 still carries the 2026-10-17 hold although #1687 shipped; #419's card asks for a \"Poleaxe\", an item name that no longer exists. | Re-cut the four cards from the cases in VP-D1-09, VP-D1-10, VP-D1-04 and VP-D1-13. | S |"),
    ("`host_forbid_log`: `official%-fallback%-resolve%-no`. No `%[gut:persist%] .* -> store` line while the mechanism is deus.",
     "`host_forbid_log`: `official%-fallback%-resolve%-no`. No `%[gut:persist%] .* %-> store` line while the mechanism is deus (receipt at `gui_tweaker/scripts/mods/gui_tweaker/_gut_native_loadouts.lua:1397`)."),
    ("`host_expect_log` has `%[cim%] Apply rejected: Block Cost Reduction needs 2 to 5 bubbles`.",
     "`host_expect_log` has `%[cim%] Apply rejected: ` (emitted at `crafting_in_modded/scripts/mods/crafting_in_modded/_cim_temper_runtime.lua:481`)."),
    ("`host_expect_log` in boot 2: `OFFHAND%-RESTORE restored=`.",
     "`host_expect_log` in boot 2: `OFFHAND%-RESTORE restored=` (emitted at `cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_offhand_state_runtime.lua:334`)."),
]
for old, new in EDITS:
    assert t.count(old) == 1, ('match count %d for: %s' % (t.count(old), old[:70]))
    t = t.replace(old, new)
open(VP, 'w', encoding='utf-8', newline='\n').write(t)
print('applied', len(EDITS), 'edits')
