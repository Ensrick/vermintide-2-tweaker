--[[
============================================================================
 wt_wield_patches.lua — shared source of truth for cross-character 3P WIELD
 (`wield_anim_career_3p`) patch tables
============================================================================

Returns `{ patches = {...}, bulk = {...} }`. Both `weapon_tweaker.lua` (main
script) AND `wt_dev_anim_picker.lua` (dev menu) `mod:dofile` this file.

WHY THIS EXISTS — same load-order bug class as `wt_unlock_data.lua`:
  VMF loads a mod's three files in the order localization -> data -> script
  (the main `.lua` SCRIPT runs LAST — see `reference_vmf_mod_file_load_order`).
  The dev anim picker's `build_widget_tree()` / `loc_keys()` run from
  `_data.lua` / `_localization.lua`, i.e. BEFORE the main script's top-level
  patcher calls. The picker resolves each Kruber port's TARGET template (and
  thus whether it's "[Needs Animations]" with per-attack dropdowns) from the
  port's chosen WIELD event. If those wield events lived only in the main
  script and were applied only at script-run time, they'd be nil when the
  picker builds its catalog → no target → no per-attack dropdowns → no prefix.

  Moving the wield-patch DATA here lets the picker pre-apply it to `Weapons.*`
  at catalog-build time (idempotent with the main script's later apply — both
  write the same fields), so `_resolve_target_for_port` resolves correctly
  regardless of file load order. 3P-only: every value is a `to_*` event written
  to `wield_anim_career_3p` (a 3P field) — never `anim_event`/`wield_anim` (1P).

  Vanilla cross-character templates carry NO `wield_anim_career_3p` natively
  (verified: e.g. `2h_picks.lua` has none), so without this pre-apply the
  picker would see nil and skip the per-attack surface entirely.

Provenance of the data: extracted verbatim (v0.12.139-dev) from the inline
`_WIELD_ANIM_CAREER_3P_PATCHES` / `_WIELD_ANIM_CAREER_3P_PATCHES_BULK` tables
that lived in `weapon_tweaker.lua`. Event strings were VERIFIED against each
target template's vanilla `wield_anim` (see the per-block comments preserved
below and `CROSS_CHARACTER_PORT_DECISIONS.md`).
============================================================================
--]]

local M = {}

-- Already-encoded ports. Event strings VERIFIED from each target template's own
-- vanilla wield_anim — NOT the decisions-doc shorthand (to_1h_mace_shield /
-- to_dual_hammer_sword, which do NOT exist in vanilla). All four es_* careers are
-- set because the picker sorts careers and reads careers[1] = es_huntsman for
-- target resolution.
M.patches = {
    -- Kerillian's elf spear (we_spear) on cross-character wielders.
    two_handed_spears_elf_template_1 = {
        wh_captain        = "to_2h_billhook",
        wh_bountyhunter   = "to_2h_billhook",
        wh_zealot         = "to_2h_billhook",
        es_mercenary      = "to_polearm",
        es_huntsman       = "to_polearm",
        es_knight         = "to_polearm",
        es_questingknight = "to_polearm",
    },
    -- Kruber's halberd (es_halberd), vanilla wield_anim = "to_polearm".
    two_handed_halberds_template_1 = {
        es_mercenary      = "to_polearm",
        es_huntsman       = "to_polearm",
        es_knight         = "to_polearm",
        es_questingknight = "to_polearm",
        wh_captain        = "to_2h_billhook",
        wh_bountyhunter   = "to_2h_billhook",
        wh_zealot         = "to_2h_billhook",
    },
    -- Kruber's Tuskgor heavy spear (es_2h_heavy_spear).
    two_handed_heavy_spears_template = {
        es_mercenary      = "to_polearm",
        es_huntsman       = "to_polearm",
        es_knight         = "to_polearm",
        es_questingknight = "to_polearm",
        wh_captain        = "to_2h_billhook",
        wh_bountyhunter   = "to_2h_billhook",
        wh_zealot         = "to_2h_billhook",
    },
    -- Saltzpyre's billhook (wh_2h_billhook) on Kruber cross-character.
    two_handed_billhooks_template = {
        es_mercenary      = "to_polearm",
        es_huntsman       = "to_polearm",
        es_knight         = "to_polearm",
        es_questingknight = "to_polearm",
    },
    -- (a) Warrior Priest Flail & Shield -> Mace & Shield (one_handed_hammer_shield_template_1).
    one_handed_flail_shield_template = {
        es_mercenary      = "to_1h_hammer_shield",
        es_huntsman       = "to_1h_hammer_shield",
        es_knight         = "to_1h_hammer_shield",
        es_questingknight = "to_1h_hammer_shield",
    },
    -- (b) Kerillian Dual Daggers -> Mace & Sword (dual_wield_hammer_sword_template).
    dual_wield_daggers_template_1 = {
        es_mercenary      = "to_dual_hammer_sword_es",
        es_huntsman       = "to_dual_hammer_sword_es",
        es_knight         = "to_dual_hammer_sword_es",
        es_questingknight = "to_dual_hammer_sword_es",
    },
    -- (c) Bardin Dual Axes -> Mace & Sword (same target as the daggers).
    dual_wield_axes_template_1 = {
        es_mercenary      = "to_dual_hammer_sword_es",
        es_huntsman       = "to_dual_hammer_sword_es",
        es_knight         = "to_dual_hammer_sword_es",
        es_questingknight = "to_dual_hammer_sword_es",
    },
    -- (d) Sienna Dagger -> Sword (one_handed_swords_template_1).
    one_handed_daggers_template_1 = {
        es_mercenary      = "to_1h_sword",
        es_huntsman       = "to_1h_sword",
        es_knight         = "to_1h_sword",
        es_questingknight = "to_1h_sword",
    },
    -- (e) Crowbill INVENTORY-MODEL FIX. Bake to_1h_sword so the keep previewer
    -- resolves the grip natively on every non-Sienna receiver. The original
    -- Crowbill remains distinct; these entries alter only its receiver-side
    -- 3P wield/preview stance.
    one_handed_crowbill = {
        es_mercenary      = "to_1h_sword",
        es_huntsman       = "to_1h_sword",
        es_knight         = "to_1h_sword",
        es_questingknight = "to_1h_sword",
        dr_ranger         = "to_1h_sword",
        dr_ironbreaker    = "to_1h_sword",
        dr_slayer         = "to_1h_sword",
        dr_engineer       = "to_1h_sword",
        wh_captain        = "to_1h_sword",
        wh_bountyhunter   = "to_1h_sword",
        wh_zealot         = "to_1h_sword",
    },
}

-- BULK cross-character port wield encodings (v0.12.132-dev). Indexed by SOURCE
-- template; each receiver's careers map to the target weapon's wield event.
-- Setting wield_anim_career_3p[career] both wires the in-mission wield stance AND
-- lets the dev anim-picker resolve the per-attack target template (via
-- _WIELD_TARGET_BY_RECEIVER / _WIELD_EVENT_TO_TARGET in the picker). Already-
-- encoded ports (in M.patches above) are NOT duplicated here.
M.bulk = {
    bastard_sword_template = { we_waywatcher = "to_2h_sword_we", we_maidenguard = "to_2h_sword_we", we_shade = "to_2h_sword_we", we_thornsister = "to_2h_sword_we", wh_captain = "to_2h_sword", wh_bountyhunter = "to_2h_sword", wh_zealot = "to_2h_sword" },
    blunderbuss_template_1 = { we_waywatcher = "to_repeating_crossbow_elf", we_maidenguard = "to_repeating_crossbow_elf", we_shade = "to_repeating_crossbow_elf", we_thornsister = "to_repeating_crossbow_elf", wh_captain = "to_crossbow", wh_bountyhunter = "to_crossbow", wh_zealot = "to_crossbow" },
    brace_of_drakefirepistols_template_1 = { es_mercenary = "to_repeating_handgun", es_huntsman = "to_repeating_handgun", es_knight = "to_repeating_handgun", es_questingknight = "to_repeating_handgun", we_waywatcher = "to_repeating_crossbow_elf", we_maidenguard = "to_repeating_crossbow_elf", we_shade = "to_repeating_crossbow_elf", we_thornsister = "to_repeating_crossbow_elf", wh_captain = "to_brace_of_pistols", wh_bountyhunter = "to_brace_of_pistols", wh_zealot = "to_brace_of_pistols" },
    brace_of_pistols_template_1 = { we_waywatcher = "to_repeating_crossbow_elf", we_maidenguard = "to_repeating_crossbow_elf", we_shade = "to_repeating_crossbow_elf", we_thornsister = "to_repeating_crossbow_elf" },
    bw_deus_01_template_1 = { es_mercenary = "to_2h_hammer", es_huntsman = "to_2h_hammer", es_knight = "to_2h_hammer", es_questingknight = "to_2h_hammer", we_waywatcher = "to_2h_axe_we", we_maidenguard = "to_2h_axe_we", we_shade = "to_2h_axe_we", we_thornsister = "to_2h_axe_we", wh_captain = "to_1h_sword", wh_bountyhunter = "to_1h_sword", wh_zealot = "to_1h_sword" },
    crossbow_template_1 = { we_waywatcher = "to_repeating_crossbow_elf", we_maidenguard = "to_repeating_crossbow_elf", we_shade = "to_repeating_crossbow_elf", we_thornsister = "to_repeating_crossbow_elf" },
    dr_deus_01_template_1 = { es_mercenary = "to_blunderbuss", es_huntsman = "to_blunderbuss", es_knight = "to_blunderbuss", es_questingknight = "to_blunderbuss", we_waywatcher = "to_repeating_crossbow_elf", we_maidenguard = "to_repeating_crossbow_elf", we_shade = "to_repeating_crossbow_elf", we_thornsister = "to_repeating_crossbow_elf", wh_captain = "to_crossbow", wh_bountyhunter = "to_crossbow", wh_zealot = "to_crossbow" },
    drakegun_template_1 = { es_mercenary = "to_blunderbuss", es_huntsman = "to_blunderbuss", es_knight = "to_blunderbuss", es_questingknight = "to_blunderbuss", we_waywatcher = "to_repeating_crossbow_elf", we_maidenguard = "to_repeating_crossbow_elf", we_shade = "to_repeating_crossbow_elf", we_thornsister = "to_repeating_crossbow_elf" },
    dual_wield_axe_falchion_template = { we_waywatcher = "to_dual_sword_dagger", we_maidenguard = "to_dual_sword_dagger", we_shade = "to_dual_sword_dagger", we_thornsister = "to_dual_sword_dagger" },
    -- dual_wield_axes_template_1 = Bardin's "Dual Axes" (in-game name). Saltzpyre (wh_):
    -- route to the Dual Axe & Falchion wield (to_dual_axe_sword_wh) per user 2026-06-28;
    -- was to_dual_hammers_priest (Dual Skullsplitters / WP Dual Hammers).
    dual_wield_axes_template_1 = { we_waywatcher = "to_dual_swords", we_maidenguard = "to_dual_swords", we_shade = "to_dual_swords", we_thornsister = "to_dual_swords", wh_captain = "to_dual_axe_sword_wh", wh_bountyhunter = "to_dual_axe_sword_wh", wh_zealot = "to_dual_axe_sword_wh" },
    dual_wield_daggers_template_1 = { wh_captain = "to_dual_axe_sword_wh", wh_bountyhunter = "to_dual_axe_sword_wh", wh_zealot = "to_dual_axe_sword_wh" },
    dual_wield_hammer_sword_template = { we_waywatcher = "to_dual_sword_dagger", we_maidenguard = "to_dual_sword_dagger", we_shade = "to_dual_sword_dagger", we_thornsister = "to_dual_sword_dagger", wh_captain = "to_dual_axe_sword_wh", wh_bountyhunter = "to_dual_axe_sword_wh", wh_zealot = "to_dual_axe_sword_wh" },
    dual_wield_hammers_priest_template = { es_mercenary = "to_dual_hammer_sword_es", es_huntsman = "to_dual_hammer_sword_es", es_knight = "to_dual_hammer_sword_es", es_questingknight = "to_dual_hammer_sword_es", we_waywatcher = "to_dual_swords", we_maidenguard = "to_dual_swords", we_shade = "to_dual_swords", we_thornsister = "to_dual_swords" },
    dual_wield_hammers_template = { we_waywatcher = "to_dual_swords", we_maidenguard = "to_dual_swords", we_shade = "to_dual_swords", we_thornsister = "to_dual_swords", wh_captain = "to_dual_hammers_priest", wh_bountyhunter = "to_dual_hammers_priest", wh_zealot = "to_dual_hammers_priest" },
    dual_wield_sword_dagger_template_1 = { es_mercenary = "to_dual_hammer_sword_es", es_huntsman = "to_dual_hammer_sword_es", es_knight = "to_dual_hammer_sword_es", es_questingknight = "to_dual_hammer_sword_es", wh_captain = "to_dual_axe_sword_wh", wh_bountyhunter = "to_dual_axe_sword_wh", wh_zealot = "to_dual_axe_sword_wh" },
    dual_wield_swords_template_1 = { es_mercenary = "to_dual_hammer_sword_es", es_huntsman = "to_dual_hammer_sword_es", es_knight = "to_dual_hammer_sword_es", es_questingknight = "to_dual_hammer_sword_es", wh_captain = "to_dual_axe_sword_wh", wh_bountyhunter = "to_dual_axe_sword_wh", wh_zealot = "to_dual_axe_sword_wh" },
    es_deus_01_template = { wh_captain = "to_dual_axe_sword_wh", wh_bountyhunter = "to_dual_axe_sword_wh", wh_zealot = "to_dual_axe_sword_wh" },
    -- fencing_sword_template_1 = Saltzpyre's "Rapier". Kruber (#178): Empire Sword & Shield
    -- (to_1h_sword_shield) per user 2026-06-29 — reverted from a wrong to_1h_sword detour.
    fencing_sword_template_1 = { es_mercenary = "to_1h_sword_shield", es_huntsman = "to_1h_sword_shield", es_knight = "to_1h_sword_shield", es_questingknight = "to_1h_sword_shield", we_waywatcher = "to_1h_sword", we_maidenguard = "to_1h_sword", we_shade = "to_1h_sword", we_thornsister = "to_1h_sword" },
    flaming_sword_template_1 = { es_mercenary = "to_1h_sword", es_huntsman = "to_1h_sword", es_knight = "to_1h_sword", es_questingknight = "to_1h_sword", we_waywatcher = "to_1h_sword", we_maidenguard = "to_1h_sword", we_shade = "to_1h_sword", we_thornsister = "to_1h_sword", wh_captain = "to_1h_sword", wh_bountyhunter = "to_1h_sword", wh_zealot = "to_1h_sword" },
    grudge_raker_template_1 = { we_waywatcher = "to_repeating_crossbow_elf", we_maidenguard = "to_repeating_crossbow_elf", we_shade = "to_repeating_crossbow_elf", we_thornsister = "to_repeating_crossbow_elf" },
    handgun_template_1 = { we_waywatcher = "to_repeating_crossbow_elf", we_maidenguard = "to_repeating_crossbow_elf", we_shade = "to_repeating_crossbow_elf", we_thornsister = "to_repeating_crossbow_elf", wh_captain = "to_crossbow", wh_bountyhunter = "to_crossbow", wh_zealot = "to_crossbow" },
    heavy_steam_pistol_template_1 = { es_mercenary = "to_repeating_handgun", es_huntsman = "to_repeating_handgun", es_knight = "to_repeating_handgun", es_questingknight = "to_repeating_handgun", we_waywatcher = "to_repeating_crossbow_elf", we_maidenguard = "to_repeating_crossbow_elf", we_shade = "to_repeating_crossbow_elf", we_thornsister = "to_repeating_crossbow_elf", wh_captain = "to_repeater_pistol", wh_bountyhunter = "to_repeater_pistol", wh_zealot = "to_repeater_pistol" },
    javelin_template = { wh_captain = "to_1h_axe", wh_bountyhunter = "to_1h_axe", wh_zealot = "to_1h_axe" },
    one_hand_axe_shield_template_1 = { es_mercenary = "to_1h_hammer_shield", es_huntsman = "to_1h_hammer_shield", es_knight = "to_1h_hammer_shield", es_questingknight = "to_1h_hammer_shield", we_waywatcher = "to_1h_spear_shield", we_maidenguard = "to_1h_spear_shield", we_shade = "to_1h_spear_shield", we_thornsister = "to_1h_spear_shield", wh_captain = "to_dual_axe_sword_wh", wh_bountyhunter = "to_dual_axe_sword_wh", wh_zealot = "to_dual_axe_sword_wh" },
    one_hand_axe_template_1 = { we_waywatcher = "to_1h_axe", we_maidenguard = "to_1h_axe", we_shade = "to_1h_axe", we_thornsister = "to_1h_axe" },
    one_hand_axe_template_2 = { wh_captain = "to_1h_axe", wh_bountyhunter = "to_1h_axe", wh_zealot = "to_1h_axe" },
    one_hand_falchion_template_1 = { we_waywatcher = "to_1h_sword", we_maidenguard = "to_1h_sword", we_shade = "to_1h_sword", we_thornsister = "to_1h_sword" },
    one_handed_crowbill = { we_waywatcher = "to_1h_sword", we_maidenguard = "to_1h_sword", we_shade = "to_1h_sword", we_thornsister = "to_1h_sword" },
    -- one_handed_daggers_template_1 = Sienna's "Dagger" (in-game name). Saltzpyre (wh_):
    -- route to 1H Falchion — its wield_anim is "to_1h_sword" (1h_falchions.lua:1183, falchion
    -- shares the 1h-sword wield) per user 2026-06-28; was to_fencing_sword (Rapier).
    one_handed_daggers_template_1 = { we_waywatcher = "to_1h_sword", we_maidenguard = "to_1h_sword", we_shade = "to_1h_sword", we_thornsister = "to_1h_sword", wh_captain = "to_1h_sword", wh_bountyhunter = "to_1h_sword", wh_zealot = "to_1h_sword" },
    one_handed_flail_shield_template = { we_waywatcher = "to_1h_spear_shield", we_maidenguard = "to_1h_spear_shield", we_shade = "to_1h_spear_shield", we_thornsister = "to_1h_spear_shield" },
    one_handed_flail_template_1 = { we_waywatcher = "to_1h_sword", we_maidenguard = "to_1h_sword", we_shade = "to_1h_sword", we_thornsister = "to_1h_sword" },
    one_handed_flails_flaming_template = { we_waywatcher = "to_1h_sword", we_maidenguard = "to_1h_sword", we_shade = "to_1h_sword", we_thornsister = "to_1h_sword" },
    -- #181: Skullsplitter & Tome (wh_hammer_book) on Kruber renders as a regular 1H
    -- Skullsplitter (hammer in the RIGHT hand, no book) playing 1H mace/hammer 3P
    -- anims, so the es_* wield is the bare to_1h_hammer (Kruber's native es_1h_mace /
    -- one_handed_hammer_template_1 wield), NOT to_1h_hammer_shield. The 3P mesh swap +
    -- book/left-hand-hammer hide live in weapon_tweaker.lua (_wt_hammer_book_3p_swap_apply).
    -- we_* (Kerillian) entries deliberately unchanged.
    one_handed_hammer_book_priest_template = { es_mercenary = "to_1h_hammer", es_huntsman = "to_1h_hammer", es_knight = "to_1h_hammer", es_questingknight = "to_1h_hammer", we_waywatcher = "to_1h_spear_shield", we_maidenguard = "to_1h_spear_shield", we_shade = "to_1h_spear_shield", we_thornsister = "to_1h_spear_shield" },
    one_handed_hammer_priest_template = { we_waywatcher = "to_1h_axe", we_maidenguard = "to_1h_axe", we_shade = "to_1h_axe", we_thornsister = "to_1h_axe" },
    one_handed_hammer_shield_priest_template = { we_waywatcher = "to_1h_spear_shield", we_maidenguard = "to_1h_spear_shield", we_shade = "to_1h_spear_shield", we_thornsister = "to_1h_spear_shield" },
    one_handed_hammer_shield_template_1 = { we_waywatcher = "to_1h_spear_shield", we_maidenguard = "to_1h_spear_shield", we_shade = "to_1h_spear_shield", we_thornsister = "to_1h_spear_shield", wh_captain = "to_dual_axe_sword_wh", wh_bountyhunter = "to_dual_axe_sword_wh", wh_zealot = "to_dual_axe_sword_wh" },
    one_handed_hammer_shield_template_2 = { wh_captain = "to_dual_axe_sword_wh", wh_bountyhunter = "to_dual_axe_sword_wh", wh_zealot = "to_dual_axe_sword_wh" },
    one_handed_hammer_template_2 = { we_waywatcher = "to_1h_axe", we_maidenguard = "to_1h_axe", we_shade = "to_1h_axe", we_thornsister = "to_1h_axe", wh_captain = "to_1h_hammer", wh_bountyhunter = "to_1h_hammer", wh_zealot = "to_1h_hammer" },
    one_handed_hammer_wizard_template_1 = { es_mercenary = "to_2h_hammer", es_huntsman = "to_2h_hammer", es_knight = "to_2h_hammer", es_questingknight = "to_2h_hammer", wh_captain = "to_2h_hammer_priest", wh_bountyhunter = "to_2h_hammer_priest", wh_zealot = "to_2h_hammer_priest" },
    one_handed_spears_shield_template = { wh_captain = "to_dual_axe_sword_wh", wh_bountyhunter = "to_dual_axe_sword_wh", wh_zealot = "to_dual_axe_sword_wh" },
    one_handed_sword_shield_template_1 = { we_waywatcher = "to_1h_spear_shield", we_maidenguard = "to_1h_spear_shield", we_shade = "to_1h_spear_shield", we_thornsister = "to_1h_spear_shield", wh_captain = "to_dual_axe_sword_wh", wh_bountyhunter = "to_dual_axe_sword_wh", wh_zealot = "to_dual_axe_sword_wh" },
    one_handed_sword_shield_template_2 = { we_waywatcher = "to_1h_spear_shield", we_maidenguard = "to_1h_spear_shield", we_shade = "to_1h_spear_shield", we_thornsister = "to_1h_spear_shield", wh_captain = "to_dual_axe_sword_wh", wh_bountyhunter = "to_dual_axe_sword_wh", wh_zealot = "to_dual_axe_sword_wh" },
    one_handed_throwing_axes_template = { es_mercenary = "to_1h_hammer", es_huntsman = "to_1h_hammer", es_knight = "to_1h_hammer", es_questingknight = "to_1h_hammer", we_waywatcher = "to_javelin", we_maidenguard = "to_javelin", we_shade = "to_javelin", we_thornsister = "to_javelin", wh_captain = "to_1h_axe", wh_bountyhunter = "to_1h_axe", wh_zealot = "to_1h_axe" },
    -- #441 (v0.12.212-dev): ADD wh_* careers (Kerillian Volley Crossbow -> Saltzpyre).
    -- Was es_* only, so on Saltzpyre the keep inventory previewer fell back to the
    -- elf template's base wield_anim "to_repeating_crossbow_elf" (repeating_crossbows
    -- _elf.lua:257) and fired it on the wh 3P body (world_hero_previewer.lua:1060-1065
    -- reads wield_anim_career_3p[career] or base wield_anim directly) -> wrong idle
    -- pose in the preview. In-mission was already correct because the animation_event
    -- funnel's _career_anim_redirect.to_repeating_crossbow_elf redirects non-we_
    -- careers to "to_repeating_crossbow" - but the preview body has no career
    -- extension, so that funnel path is a no-op there (the v0.12.146 preview resolver
    -- is has_anim-gated and does not cover this event). Bake the SAME receiver-native
    -- event the in-mission redirect produces: "to_repeating_crossbow" is Saltzpyre's
    -- own Volley Crossbow wield (repeating_crossbows.lua:245; NetworkLookup-registered,
    -- anims_lookup_table.lua:645). Bardin/Sienna: weapon not exposed in the unlock map.
    repeating_crossbow_elf_template = { es_mercenary = "to_repeating_handgun", es_huntsman = "to_repeating_handgun", es_knight = "to_repeating_handgun", es_questingknight = "to_repeating_handgun", wh_captain = "to_repeating_crossbow", wh_bountyhunter = "to_repeating_crossbow", wh_zealot = "to_repeating_crossbow" },
    -- #441 mirror (v0.12.212-dev): ADD we_* careers (Saltzpyre Volley Crossbow ->
    -- Kerillian) - the identical preview gap in the other direction: base wield_anim
    -- "to_repeating_crossbow" is not authored native on the elf body, so the preview
    -- held the wrong idle there too. "to_repeating_crossbow_elf" is Kerillian's native
    -- Volley Crossbow wield (repeating_crossbows_elf.lua:257) - the same value every
    -- other we_-receiver firearm row in this table uses. Wire-safe despite not being
    -- NetworkLookup-registered: wield_anim_career_3p is only ever consumed by direct
    -- Unit.animation_event (simple_inventory_extension.lua:2011-2013, simple_husk_
    -- inventory_extension.lua:710/724, world_hero_previewer.lua:1003/1063) - it never
    -- rides an RPC lookup (unlike wield_anim_not_loaded, see the v0.12.139 block in
    -- weapon_tweaker.lua).
    repeating_crossbow_template_1 = { es_mercenary = "to_repeating_handgun", es_huntsman = "to_repeating_handgun", es_knight = "to_repeating_handgun", es_questingknight = "to_repeating_handgun", we_waywatcher = "to_repeating_crossbow_elf", we_maidenguard = "to_repeating_crossbow_elf", we_shade = "to_repeating_crossbow_elf", we_thornsister = "to_repeating_crossbow_elf" },
    repeating_handgun_template_1 = { we_waywatcher = "to_repeating_crossbow_elf", we_maidenguard = "to_repeating_crossbow_elf", we_shade = "to_repeating_crossbow_elf", we_thornsister = "to_repeating_crossbow_elf", wh_captain = "to_repeater_pistol", wh_bountyhunter = "to_repeater_pistol", wh_zealot = "to_repeater_pistol" },
    repeating_pistol_template_1 = { we_waywatcher = "to_repeating_crossbow_elf", we_maidenguard = "to_repeating_crossbow_elf", we_shade = "to_repeating_crossbow_elf", we_thornsister = "to_repeating_crossbow_elf" },
    shortbow_hagbane_template_1 = { es_mercenary = "to_es_longbow", es_huntsman = "to_es_longbow", es_knight = "to_es_longbow", es_questingknight = "to_es_longbow" },
    shortbow_template_1 = { es_mercenary = "to_es_longbow", es_huntsman = "to_es_longbow", es_knight = "to_es_longbow", es_questingknight = "to_es_longbow" },
    staff_blast_beam_template_1 = { es_mercenary = "to_2h_hammer", es_huntsman = "to_2h_hammer", es_knight = "to_2h_hammer", es_questingknight = "to_2h_hammer", we_waywatcher = "to_2h_axe_we", we_maidenguard = "to_2h_axe_we", we_shade = "to_2h_axe_we", we_thornsister = "to_2h_axe_we", wh_captain = "to_1h_sword", wh_bountyhunter = "to_1h_sword", wh_zealot = "to_1h_sword" },
    staff_death = { es_mercenary = "to_2h_hammer", es_huntsman = "to_2h_hammer", es_knight = "to_2h_hammer", es_questingknight = "to_2h_hammer", we_waywatcher = "to_2h_axe_we", we_maidenguard = "to_2h_axe_we", we_shade = "to_2h_axe_we", we_thornsister = "to_2h_axe_we", wh_captain = "to_1h_sword", wh_bountyhunter = "to_1h_sword", wh_zealot = "to_1h_sword" },
    staff_fireball_fireball_template_1 = { es_mercenary = "to_2h_hammer", es_huntsman = "to_2h_hammer", es_knight = "to_2h_hammer", es_questingknight = "to_2h_hammer", we_waywatcher = "to_2h_axe_we", we_maidenguard = "to_2h_axe_we", we_shade = "to_2h_axe_we", we_thornsister = "to_2h_axe_we", wh_captain = "to_1h_sword", wh_bountyhunter = "to_1h_sword", wh_zealot = "to_1h_sword" },
    staff_fireball_geiser_template_1 = { es_mercenary = "to_2h_hammer", es_huntsman = "to_2h_hammer", es_knight = "to_2h_hammer", es_questingknight = "to_2h_hammer", we_waywatcher = "to_2h_axe_we", we_maidenguard = "to_2h_axe_we", we_shade = "to_2h_axe_we", we_thornsister = "to_2h_axe_we", wh_captain = "to_1h_sword", wh_bountyhunter = "to_1h_sword", wh_zealot = "to_1h_sword" },
    staff_flamethrower_template = { es_mercenary = "to_2h_hammer", es_huntsman = "to_2h_hammer", es_knight = "to_2h_hammer", es_questingknight = "to_2h_hammer", we_waywatcher = "to_2h_axe_we", we_maidenguard = "to_2h_axe_we", we_shade = "to_2h_axe_we", we_thornsister = "to_2h_axe_we", wh_captain = "to_1h_sword", wh_bountyhunter = "to_1h_sword", wh_zealot = "to_1h_sword" },
    staff_life = { es_mercenary = "to_2h_hammer", es_huntsman = "to_2h_hammer", es_knight = "to_2h_hammer", es_questingknight = "to_2h_hammer", wh_captain = "to_1h_sword", wh_bountyhunter = "to_1h_sword", wh_zealot = "to_1h_sword" },
    staff_scythe = { es_mercenary = "to_2h_hammer", es_huntsman = "to_2h_hammer", es_knight = "to_2h_hammer", es_questingknight = "to_2h_hammer", we_waywatcher = "to_2h_axe_we", we_maidenguard = "to_2h_axe_we", we_shade = "to_2h_axe_we", we_thornsister = "to_2h_axe_we", wh_captain = "to_2h_hammer_priest", wh_bountyhunter = "to_2h_hammer_priest", wh_zealot = "to_2h_hammer_priest" },
    staff_spark_spear_template_1 = { es_mercenary = "to_2h_hammer", es_huntsman = "to_2h_hammer", es_knight = "to_2h_hammer", es_questingknight = "to_2h_hammer", we_waywatcher = "to_2h_axe_we", we_maidenguard = "to_2h_axe_we", we_shade = "to_2h_axe_we", we_thornsister = "to_2h_axe_we", wh_captain = "to_1h_sword", wh_bountyhunter = "to_1h_sword", wh_zealot = "to_1h_sword" },
    -- #286: Bardin Greataxe on Saltzpyre wields as WP greathammer (was to_2h_sword;
    -- every other 2H-blunt template incl. sibling template_2 already uses hammer_priest).
    two_handed_axes_template_1 = { we_waywatcher = "to_2h_axe_we", we_maidenguard = "to_2h_axe_we", we_shade = "to_2h_axe_we", we_thornsister = "to_2h_axe_we", wh_captain = "to_2h_hammer_priest", wh_bountyhunter = "to_2h_hammer_priest", wh_zealot = "to_2h_hammer_priest" },
    two_handed_axes_template_2 = { es_mercenary = "to_2h_hammer", es_huntsman = "to_2h_hammer", es_knight = "to_2h_hammer", es_questingknight = "to_2h_hammer", wh_captain = "to_2h_hammer_priest", wh_bountyhunter = "to_2h_hammer_priest", wh_zealot = "to_2h_hammer_priest" },
    two_handed_billhooks_template = { we_waywatcher = "to_spear", we_maidenguard = "to_spear", we_shade = "to_spear", we_thornsister = "to_spear" },
    two_handed_cog_hammers_template_1 = { es_mercenary = "to_2h_hammer", es_huntsman = "to_2h_hammer", es_knight = "to_2h_hammer", es_questingknight = "to_2h_hammer", we_waywatcher = "to_2h_axe_we", we_maidenguard = "to_2h_axe_we", we_shade = "to_2h_axe_we", we_thornsister = "to_2h_axe_we", wh_captain = "to_2h_hammer_priest", wh_bountyhunter = "to_2h_hammer_priest", wh_zealot = "to_2h_hammer_priest" },
    two_handed_halberds_template_1 = { we_waywatcher = "to_spear", we_maidenguard = "to_spear", we_shade = "to_spear", we_thornsister = "to_spear" },
    two_handed_hammer_priest_template = { es_mercenary = "to_2h_hammer", es_huntsman = "to_2h_hammer", es_knight = "to_2h_hammer", es_questingknight = "to_2h_hammer", we_waywatcher = "to_2h_axe_we", we_maidenguard = "to_2h_axe_we", we_shade = "to_2h_axe_we", we_thornsister = "to_2h_axe_we" },
    two_handed_hammers_template_1 = { we_waywatcher = "to_2h_axe_we", we_maidenguard = "to_2h_axe_we", we_shade = "to_2h_axe_we", we_thornsister = "to_2h_axe_we", wh_captain = "to_2h_hammer_priest", wh_bountyhunter = "to_2h_hammer_priest", wh_zealot = "to_2h_hammer_priest" },
    two_handed_heavy_spears_template = { we_waywatcher = "to_spear", we_maidenguard = "to_spear", we_shade = "to_spear", we_thornsister = "to_spear" },
    two_handed_picks_template_1 = { es_mercenary = "to_2h_hammer", es_huntsman = "to_2h_hammer", es_knight = "to_2h_hammer", es_questingknight = "to_2h_hammer", we_waywatcher = "to_2h_axe_we", we_maidenguard = "to_2h_axe_we", we_shade = "to_2h_axe_we", we_thornsister = "to_2h_axe_we", wh_captain = "to_2h_hammer_priest", wh_bountyhunter = "to_2h_hammer_priest", wh_zealot = "to_2h_hammer_priest" },
    two_handed_swords_executioner_template_1 = { we_waywatcher = "to_2h_sword_we", we_maidenguard = "to_2h_sword_we", we_shade = "to_2h_sword_we", we_thornsister = "to_2h_sword_we", wh_captain = "to_2h_sword", wh_bountyhunter = "to_2h_sword", wh_zealot = "to_2h_sword" },
    two_handed_swords_template_1 = { we_waywatcher = "to_2h_sword_we", we_maidenguard = "to_2h_sword_we", we_shade = "to_2h_sword_we", we_thornsister = "to_2h_sword_we" },
    two_handed_swords_wood_elf_template = { wh_captain = "to_2h_sword", wh_bountyhunter = "to_2h_sword", wh_zealot = "to_2h_sword" },
    we_deus_01_template_1 = { es_mercenary = "to_es_longbow", es_huntsman = "to_es_longbow", es_knight = "to_es_longbow", es_questingknight = "to_es_longbow", wh_captain = "to_crossbow", wh_bountyhunter = "to_crossbow", wh_zealot = "to_crossbow" },
    -- v0.12.140-dev: ADD es_* careers (Kerillian 1H Axe -> Kruber). Was wh_* only,
    -- so for Kruber `wield_anim_career_3p[es_huntsman]` was nil → _resolve_target_for_port
    -- returned nil → "[Needs Offsets]" with NO per-attack dropdowns. On Kruber `to_1h_axe`
    -- resolves via _WIELD_TARGET_BY_RECEIVER.es → one_hand_axe_template_1 (Witch Hunter 1H
    -- Axe vocab), moving this port into the RESOLVES ([Needs Animations]) set.
    we_one_hand_axe_template = { es_mercenary = "to_1h_axe", es_huntsman = "to_1h_axe", es_knight = "to_1h_axe", es_questingknight = "to_1h_axe", wh_captain = "to_1h_axe", wh_bountyhunter = "to_1h_axe", wh_zealot = "to_1h_axe" },
    wh_deus_01_template_1 = { es_mercenary = "to_repeating_handgun", es_huntsman = "to_repeating_handgun", es_knight = "to_repeating_handgun", es_questingknight = "to_repeating_handgun", we_waywatcher = "to_repeating_crossbow_elf", we_maidenguard = "to_repeating_crossbow_elf", we_shade = "to_repeating_crossbow_elf", we_thornsister = "to_repeating_crossbow_elf" },
}

return M
