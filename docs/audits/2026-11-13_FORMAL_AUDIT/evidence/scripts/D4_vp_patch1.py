# D4: one-off edits to the VP part files after the fix cards (plan/wp) and the proven rig facts became known.
import os
BASE = r"docs/audits/2026-11-13_FORMAL_AUDIT/evidence/scripts/D4_vp_parts"


def rep(name, a, b, count=1):
    p = os.path.join(BASE, name)
    s = open(p, encoding="utf-8").read()
    n = s.count(a)
    assert n == count, (name, a[:60], n)
    open(p, "w", encoding="utf-8", newline="\n").write(s.replace(a, b))


# ---- part0
rep("part0.md",
    "and `/cim_craft_standard` (static evidence suggests it asserts, see section 3 row F-05).",
    "and `/cim_craft_standard` (static evidence suggests it asserts until fix card WP-CIM-03 lands).")
rep("part0.md",
    "- The isolated rig profile isolates local files only: `user_settings.config` (every VMF mod setting, including the stores L1 to L5 below) and the local save (`PlayerData`, L6).",
    "- The isolated rig profile isolates local files only: `user_settings.config` (every VMF mod setting, including the stores L1 to L5 below) and the local save (`PlayerData`, L6). The rig copies the owner's settings and save into that profile and never writes them back, so a boot starts with the owner's real store contents, not empty stores.")
rep("part0.md",
    "6. A baseline that is already dirty is INCONCLUSIVE, not FAIL:",
    "6. A case cannot edit a VMF setting table in place: `mod:get` returns a copy. Set up store state only through the mod's own command or writer (`/reset_modded_loadouts`, `/forge`, an equip through E1).\n7. A baseline that is already dirty is INCONCLUSIVE, not FAIL:")
rep("part0.md",
    "(runner line numbers for the last two `[unverified]`; findings A5-F07 and A7-F12).",
    "(runner line numbers for the last two `[unverified]`; findings A5-F07 and A7-F12). Fix cards: WP-T-01 (programmatic entry and printf verdicts), WP-CIM-05, WP-GUT-07.")
rep("part0.md",
    "- R-3P: third-party Workshop mods on the rig machine where a card names one: Loremaster's Armoury, UI Tweaks, Simple UI.",
    "- R-3P: third-party Workshop mods where a card names one: Loremaster's Armoury, UI Tweaks, Simple UI. The rig picks mods per run by Workshop folder id, so the items must be subscribed on the rig machine.")

# ---- part1
rep("part1.md",
    "Remaining work is an offline audit of career and passive data in the decompile (section 3 row F-13) | keep open until F-13 lands;",
    "Remaining work is an offline audit of career and passive data in the decompile (section 3, row #153) | keep open until that audit lands;")
rep("part1.md",
    "| section 3 row F-12 (export and test), then close on U |",
    "| section 3, row #224 (export and test), then close on U |")
rep("part1.md",
    "the hook is gone at `modded_progression.lua:1343` | close |",
    "the hook is gone at `modded_progression.lua:1343`. Fix card WP-CIM-08 lists the same closure | close |")

# ---- part2
rep("part2.md",
    "| Boots | 2. Boot 1 starts on a profile whose `native_loadouts` setting is empty (seeding, edits, mission). Boot 2 reuses the same profile and edits nothing (restart persistence) |",
    "| Boots | 2. Boot 1 starts from a copy of the owner's settings, so the store is not empty: the first case runs the mod's own `/reset_modded_loadouts` (`gui_tweaker/scripts/mods/gui_tweaker/_gut_native_loadouts.lua:1260`) to force a fresh seed from the official rows; then edits and a mission. Boot 2 reuses the same profile and edits nothing (restart persistence) |")
rep("part2.md",
    "Fix WP-GUT-01 (finding A7-F01) is not on master: expect case 8 to FAIL until it lands |",
    "Fix WP-GUT-01 (finding A7-F01) is not on master: expect case 8 to FAIL until it lands. Related fix cards: WP-GUT-09 (bot refresh, case 4), WP-CIM-01 with WP-GUT-04 and WP-CIM-07 (crafted ids in career data, case 3), WP-GUT-02 and WP-GUT-03 (one store owner) |")
rep("part2.md",
    "| `T.open_view(\"hero_view\", {menu_state_name = \"overview\"})` so the store seeds; close;",
    "| `T.cmd(\"reset_modded_loadouts\")`; `T.open_view(\"hero_view\", {menu_state_name = \"overview\"})` so the store seeds again; close;")
rep("part2.md",
    "If only `cim` wrote the id: finding A5-F01 (`_cim_modded_loadout_owner.lua:519-526`).",
    "If only `cim` wrote the id: finding A5-F01, fix card WP-CIM-01 (`crafting_in_modded/scripts/mods/crafting_in_modded/_cim_modded_loadout_owner.lua:519-526`).")
rep("part2.md",
    "Bot carries the player row: `_gut_bot_loadout_snapshot.lua:452-471` (findings A7-F07, A7-F08).",
    "Bot carries the player row: `_gut_bot_loadout_snapshot.lua:452-471` (findings A7-F07, A7-F08; fix card WP-GUT-09).")
rep("part2.md",
    "Do not use `/cim_craft_standard` (section 3 row F-05) |",
    "Do not use `/cim_craft_standard` until WP-CIM-03 lands |")
rep("part2.md",
    "Fix for case 4 on `gut_dev`: section 3 row F-09 (finding A7-F03) |",
    "Fix for case 4 on `gut_dev`: WP-GUT-08 (finding A7-F03) |")
rep("part2.md", "so expect FAIL until F-09 |", "so expect FAIL until WP-GUT-08 |")
rep("part2.md", "the duplicate command registration (F-09).", "the duplicate command registration (WP-GUT-08).")

# ---- part3
rep("part3.md",
    "Fix F-04 (finding A5-F03) is not on master: expect case 5 to FAIL until it lands. Never use `/cim_craft_standard` (F-05):",
    "Fix WP-CIM-02 (finding A5-F03) is not on master: expect case 5 to FAIL until it lands. Never use `/cim_craft_standard` before WP-CIM-03:")
rep("part3.md",
    "returns without calling the callback (F-04).",
    "returns without calling the callback (WP-CIM-02).")
rep("part3.md",
    "Fixes F-01 and F-02 are not on master; case 1 is the reproduction tool for F-01 |",
    "Fix WP-CIM-04 (restore keeps the row) is not on master, and the diagnostic gap in section 3 (row #1654) is open; case 1 is the reproduction tool for WP-CIM-04. Related: WP-CIM-06 (backup and import of the craft store) |")
rep("part3.md",
    "a FAIL names which store lost the item and feeds F-01. Close only after F-01 and F-02 land and this case passes |",
    "a FAIL names which store lost the item and feeds WP-CIM-04. Close only after WP-CIM-04 lands and this case passes |")
rep("part3.md",
    "the restore postcondition removed the row (F-01, `_cim_synthetic_item_contract.lua:1113-1130`).",
    "the restore postcondition removed the row (WP-CIM-04, `crafting_in_modded/scripts/mods/crafting_in_modded/_cim_synthetic_item_contract.lua:1113-1130`).")
rep("part3.md",
    "the record was never flushed or was dropped at load (F-02; store owner `_cim_forge_state_owner.lua:65-89` and its load path).",
    "the record was never flushed or was dropped at load (section 3, row #1654; store owner `_cim_forge_state_owner.lua:65-89` and its load path; WP-CIM-06).")
rep("part3.md",
    "| Depends on | rig: R-PRIVATE, R-BOOTS, R-RT, R-PRESS (claim and purchase buttons). R-SHIELD is required,",
    "| Depends on | rig: R-PRIVATE, R-BOOTS, R-RT, R-PRESS (claim and purchase buttons). Related fix cards: WP-CIM-08 (inert realm brackets), WP-CIM-09 (plan for the unbuilt slices). R-SHIELD is required,")
rep("part3.md",
    "| Depends on | rig: `T.as_bot`, bot hero choice (`findings/C1.md` 4.3 row 29), R-RT, options seeded before boot (same file, row 56) |",
    "| Depends on | rig: `T.as_bot`, bot hero choice (`findings/C1.md` 4.3 row 29), R-RT, options seeded before boot (same file, row 56). Related fix card: WP-CIM-10 (makes the rework catalog checkable) |")

# ---- part4
rep("part4.md",
    "Fix F-16 (finding A7-F05) is not on master: expect the functional half of case 1 to FAIL in boot A |",
    "Fix WP-GUT-11 (finding A7-F05) is not on master: expect the functional half of case 1 to FAIL in boot A |")
rep("part4.md", "expected until F-16.", "expected until WP-GUT-11.")
rep("part4.md",
    "| Depends on | rig: R-RT. The local hero is the subject (camera state is local), so no bot stand-in |",
    "| Depends on | rig: R-RT. The local hero is the subject (camera state is local), so no bot stand-in. Related fix cards: WP-GUT-07 and WP-T-02 (the source-text check for #1796 must report SKIP, not PASS) |")
print("patched")
