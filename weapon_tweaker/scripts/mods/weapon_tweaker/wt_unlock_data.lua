--[[
============================================================================
 wt_unlock_data.lua — shared source of truth for the weapon-unlock tables
============================================================================

Returns `{ weapon_unlock_map = {...}, cwv_conditional_managed = {...} }`. Both
`weapon_tweaker.lua` (main script) AND `wt_dev_anim_picker.lua` (dev menu)
`mod:dofile` this file directly.

WHY THIS EXISTS — load-order bug class:
  VMF calls a mod's `_data.lua` BEFORE the main script finishes execution
  (verified empirically v0.12.98-dev: log showed `[wt:dev_anim] catalog
  built: 0 entries` followed by `[VMF Mod Manager] ... [widget
  "wt_dev_anim_picker" (group)]: must have at least 1 sub_widget`). The dev
  picker's `build_widget_tree()` is called FROM `_data.lua`, which means
  any data it reads off `mod._weapon_unlock_map` is nil at that moment —
  even though main wt.lua sets `mod._weapon_unlock_map = weapon_unlock_map`
  later in its load. That order is a VMF invariant we can't fight.

The fix: put the data in a file BOTH sides `dofile` at first need. No
load-order dependency, no mirror to drift.

Edits to either table propagate to both sides automatically.
============================================================================
]]

-- SKIP DECISIONS (Kruber receiver, weapons NOT added).
-- These cross-character weapons are intentionally NOT added to Kruber's
-- careers because they are functionally identical to existing Kruber
-- natives. See CROSS_CHARACTER_PORT_DECISIONS.md.
-- v0.12.102-dev (user decision 2026-05-28):
--   * dr_1h_hammer     ~ es_1h_mace          (Bardin 1H Hammer    = Empire 1H Mace)
--   * dr_2h_hammer     ~ es_2h_hammer        (Bardin 2H Hammer    = Empire Greathammer)
--   * dr_handgun       ~ es_handgun          (Bardin Handgun      = Empire Handgun)
--   * dr_shield_hammer ~ es_mace_shield      (Bardin Hammer+Shld  = Empire Mace+Shield)
--   * dr_rakegun       ~ es_blunderbuss      (Bardin Grudge-Raker = Empire Blunderbuss)
-- v0.12.103-dev (user decision 2026-05-30, reaffirmed multiple times):
--   * wh_1h_hammer     ~ es_1h_mace          (Saltzpyre Skull-Splitter = Empire 1H Mace).
--                                            CWV handles hammer-vs-mace visual
--                                            differentiation; wt does NOT add this
--                                            cross-character port.

local DATA = {
    weapon_unlock_map = {
        -- Kruber
        -- v0.12.103-dev (2026-05-30): bulk-bake of cross-character ports from
        -- CROSS_CHARACTER_PORT_DECISIONS.md. Added Bardin batch (cog hammer,
        -- pick, dual axes, shield-axe, throwing axes, drakefire pistols,
        -- drakegun, masterwork pistol, trollhammer torpedo), Kerillian batch
        -- (1h axe, glaive, dual daggers, dual swords, sword-dagger, moonfire,
        -- shortbow, hagbane, repeater crossbow), Saltzpyre batch (1h axe,
        -- dual hammers, 2h hammer, rapier, volley crossbow, griffon-foot),
        -- WP batch (flail-shield, hammer-tome), Sienna batch (mace, dagger,
        -- flame sword, ensorcelled reaper, all 5 skullstaves, necromancy
        -- staff, coruscation staff). we_javelin added later (v0.12.110-dev
        -- era). we_life_staff (Deepwood Staff) added to all 4 Kruber careers
        -- v0.12.198-dev (user request 2026-07-02) — uses staff_life ->
        -- to_2h_hammer wield source, flagged [Untested] until confirmed.
        es_mercenary      = { "we_life_staff", "dr_2h_axe", "dr_2h_cog_hammer", "dr_2h_pick", "dr_shield_axe", "es_bastard_sword", "es_sword_shield_breton", "es_2h_sword_executioner", "es_2h_sword", "es_halberd", "we_2h_sword", "we_spear", "we_1h_spears_shield", "we_1h_sword", "we_1h_axe", "we_2h_axe", "we_dual_wield_daggers", "we_dual_wield_swords", "we_dual_wield_sword_dagger", "es_1h_mace", "es_mace_shield", "es_dual_wield_hammer_sword", "wh_2h_billhook", "wh_1h_falchion", "wh_1h_axe", "wh_dual_hammer", "wh_2h_hammer", "wh_fencing_sword", "wh_flail_shield", "wh_hammer_book", "es_1h_flail", "bw_1h_crowbill", "bw_1h_flail_flaming", "bw_1h_mace", "bw_dagger", "bw_flame_sword", "bw_ghost_scythe", "es_deus_01", "es_1h_sword", "es_sword_shield", "es_2h_heavy_spear", "es_2h_hammer", "es_blunderbuss", "es_handgun", "we_longbow", "es_longbow", "es_repeating_handgun", "we_deus_01", "we_shortbow", "we_shortbow_hagbane", "we_javelin", "we_crossbow_repeater", "wh_brace_of_pistols", "wh_repeating_pistols", "wh_crossbow_repeater", "wh_crossbow", "wh_deus_01", "dr_1h_throwing_axes", "dr_drake_pistol", "dr_drakegun", "dr_steam_pistol", "dr_deus_01", "bw_skullstaff_beam", "bw_skullstaff_fireball", "bw_skullstaff_flamethrower", "bw_skullstaff_geiser", "bw_skullstaff_spear", "bw_necromancy_staff", "bw_deus_01" },
        es_huntsman       = { "we_life_staff", "dr_2h_axe", "dr_2h_cog_hammer", "dr_2h_pick", "dr_shield_axe", "es_bastard_sword", "es_2h_sword_executioner", "es_2h_sword", "es_halberd", "we_2h_sword", "we_spear", "we_1h_spears_shield", "we_1h_sword", "we_1h_axe", "we_2h_axe", "we_dual_wield_daggers", "we_dual_wield_swords", "we_dual_wield_sword_dagger", "es_1h_mace", "es_mace_shield", "es_dual_wield_hammer_sword", "wh_2h_billhook", "wh_1h_falchion", "wh_1h_axe", "wh_dual_hammer", "wh_2h_hammer", "wh_fencing_sword", "wh_flail_shield", "wh_hammer_book", "es_1h_flail", "bw_1h_crowbill", "bw_1h_flail_flaming", "bw_1h_mace", "bw_dagger", "bw_flame_sword", "bw_ghost_scythe", "es_deus_01", "es_1h_sword", "es_sword_shield", "es_2h_heavy_spear", "es_2h_hammer", "es_blunderbuss", "es_handgun", "we_longbow", "es_longbow", "es_repeating_handgun", "we_deus_01", "we_shortbow", "we_shortbow_hagbane", "we_javelin", "we_crossbow_repeater", "wh_brace_of_pistols", "wh_repeating_pistols", "wh_crossbow_repeater", "wh_crossbow", "wh_deus_01", "dr_1h_throwing_axes", "dr_drake_pistol", "dr_drakegun", "dr_steam_pistol", "dr_deus_01", "bw_skullstaff_beam", "bw_skullstaff_fireball", "bw_skullstaff_flamethrower", "bw_skullstaff_geiser", "bw_skullstaff_spear", "bw_necromancy_staff", "bw_deus_01" },
        es_knight         = { "we_life_staff", "dr_2h_axe", "dr_2h_cog_hammer", "dr_2h_pick", "dr_shield_axe", "es_bastard_sword", "es_sword_shield_breton", "es_2h_sword_executioner", "es_2h_sword", "es_halberd", "we_2h_sword", "we_spear", "we_1h_spears_shield", "we_1h_sword", "we_1h_axe", "we_2h_axe", "we_dual_wield_daggers", "we_dual_wield_swords", "we_dual_wield_sword_dagger", "es_1h_mace", "es_mace_shield", "es_dual_wield_hammer_sword", "wh_2h_billhook", "wh_1h_falchion", "wh_1h_axe", "wh_dual_hammer", "wh_2h_hammer", "wh_fencing_sword", "wh_flail_shield", "wh_hammer_book", "es_1h_flail", "bw_1h_crowbill", "bw_1h_flail_flaming", "bw_1h_mace", "bw_dagger", "bw_flame_sword", "bw_ghost_scythe", "es_deus_01", "es_1h_sword", "es_sword_shield", "es_2h_heavy_spear", "es_2h_hammer", "es_blunderbuss", "es_handgun", "we_longbow", "es_longbow", "es_repeating_handgun", "we_deus_01", "we_shortbow", "we_shortbow_hagbane", "we_javelin", "we_crossbow_repeater", "wh_brace_of_pistols", "wh_repeating_pistols", "wh_crossbow_repeater", "wh_crossbow", "wh_deus_01", "dr_1h_throwing_axes", "dr_drake_pistol", "dr_drakegun", "dr_steam_pistol", "dr_deus_01", "bw_skullstaff_beam", "bw_skullstaff_fireball", "bw_skullstaff_flamethrower", "bw_skullstaff_geiser", "bw_skullstaff_spear", "bw_necromancy_staff", "bw_deus_01" },
        es_questingknight = { "we_life_staff", "dr_2h_axe", "dr_2h_cog_hammer", "dr_2h_pick", "dr_shield_axe", "es_bastard_sword", "es_sword_shield_breton", "es_2h_sword_executioner", "es_2h_sword", "es_halberd", "we_2h_sword", "we_spear", "we_1h_spears_shield", "we_1h_sword", "we_1h_axe", "we_2h_axe", "we_dual_wield_daggers", "we_dual_wield_swords", "we_dual_wield_sword_dagger", "es_1h_mace", "es_mace_shield", "es_dual_wield_hammer_sword", "wh_2h_billhook", "wh_1h_falchion", "wh_1h_axe", "wh_dual_hammer", "wh_2h_hammer", "wh_fencing_sword", "wh_flail_shield", "wh_hammer_book", "es_1h_flail", "bw_1h_crowbill", "bw_1h_flail_flaming", "bw_1h_mace", "bw_dagger", "bw_flame_sword", "bw_ghost_scythe", "es_deus_01", "es_1h_sword", "es_sword_shield", "es_2h_heavy_spear", "es_2h_hammer", "es_blunderbuss", "es_handgun", "we_longbow", "es_longbow", "es_repeating_handgun", "we_deus_01", "we_shortbow", "we_shortbow_hagbane", "we_javelin", "we_crossbow_repeater", "wh_brace_of_pistols", "wh_repeating_pistols", "wh_crossbow_repeater", "wh_crossbow", "wh_deus_01", "dr_1h_throwing_axes", "dr_drake_pistol", "dr_drakegun", "dr_steam_pistol", "dr_deus_01", "bw_skullstaff_beam", "bw_skullstaff_fireball", "bw_skullstaff_flamethrower", "bw_skullstaff_geiser", "bw_skullstaff_spear", "bw_necromancy_staff", "bw_deus_01" },
        -- Bardin
        -- v0.12.102-dev: wh_crossbow removed from Bardin's 4 careers. User
        -- decision 2026-05-28: wh_crossbow (Witch Hunter Crossbow) and
        -- dr_crossbow (Dwarf Crossbow) are functionally analogous; Bardin's
        -- native dr_crossbow already covers the role. wh_crossbow remains
        -- on Saltzpyre (his native) but not on Bardin.
        dr_ranger         = { "dr_1h_axe", "dr_shield_axe", "dr_2h_cog_hammer", "dr_dual_wield_axes", "dr_dual_wield_hammers", "dr_2h_axe", "dr_2h_hammer", "dr_1h_hammer", "dr_shield_hammer", "we_1h_sword", "es_1h_sword", "wh_1h_falchion", "bw_1h_crowbill", "dr_2h_pick", "dr_crossbow", "dr_rakegun", "dr_handgun", "es_handgun", "dr_steam_pistol", "dr_1h_throwing_axes", "dr_deus_01" },
        dr_ironbreaker    = { "dr_1h_axe", "dr_shield_axe", "dr_2h_cog_hammer", "dr_dual_wield_axes", "dr_dual_wield_hammers", "dr_2h_axe", "dr_2h_hammer", "dr_1h_hammer", "dr_shield_hammer", "we_1h_sword", "es_1h_sword", "wh_1h_falchion", "bw_1h_crowbill", "dr_2h_pick", "dr_crossbow", "dr_drake_pistol", "dr_drakegun", "dr_rakegun", "dr_handgun", "es_handgun", "dr_1h_throwing_axes", "dr_deus_01" },
        dr_slayer         = { "dr_1h_axe", "dr_shield_axe", "dr_2h_cog_hammer", "dr_dual_wield_axes", "dr_dual_wield_hammers", "dr_2h_axe", "dr_2h_hammer", "dr_1h_hammer", "dr_shield_hammer", "we_1h_sword", "es_1h_sword", "wh_1h_falchion", "bw_1h_crowbill", "dr_2h_pick", "dr_crossbow", "dr_rakegun", "dr_handgun", "es_handgun", "dr_steam_pistol", "dr_1h_throwing_axes", "dr_deus_01" },
        dr_engineer       = { "dr_1h_axe", "dr_shield_axe", "dr_2h_cog_hammer", "dr_dual_wield_axes", "dr_dual_wield_hammers", "dr_2h_axe", "dr_2h_hammer", "dr_1h_hammer", "dr_shield_hammer", "we_1h_sword", "es_1h_sword", "wh_1h_falchion", "bw_1h_crowbill", "dr_2h_pick", "dr_crossbow", "dr_drake_pistol", "dr_drakegun", "dr_rakegun", "dr_handgun", "es_handgun", "dr_steam_pistol", "dr_1h_throwing_axes", "dr_deus_01" },
        -- Kerillian
        -- v0.12.103-dev (2026-05-30): bulk-bake of cross-character ports from
        -- CROSS_CHARACTER_PORT_DECISIONS.md (Batches EK + DK). Added Kruber
        -- batch (flail, 2h hammer, tuskgor spear, executioner, bretonnian
        -- longsword, mace+sword, halberd, mace+shield, sword+shield,
        -- bretonnian sword+shield, blunderbuss, handgun, repeater handgun)
        -- and Bardin batch (1h hammer, throwing axes, greataxe, cog hammer,
        -- pickaxe, crossbow, trollhammer, drakefire pistols, drakegun, dual
        -- axes, dual hammers, grudge-raker, axe+shield, masterwork pistol,
        -- plus wh_1h_axe BONUS for 1h-axe route via Saltzpyre).
        -- v0.12.103-dev (2026-05-30): Saltzpyre batch SK1-SK15 added — all 15
        -- WH/WP source weapons routed to Kerillian (falchion, 1h hammer,
        -- billhook, 2h hammer, 2h sword, brace of pistols, crossbow,
        -- griffon-foot, dual hammers, axe+falchion, rapier, repeater pistol,
        -- flail+shield, hammer+tome, skull-splitter+shield).
        -- v0.12.103-dev (2026-05-31): Sienna batch SiK1-SiK14 added — 12 BW
        -- source weapons routed to Kerillian (crowbill, flaming flail, dagger,
        -- flame sword, ensorcelled reaper, 5 skullstaves, necromancy staff,
        -- coruscation staff). SKIPPED bw_1h_mace (~ es_1h_mace already in
        -- Kerillian's unlock_map) and bw_sword (~ we_1h_sword).
        we_waywatcher     = { "we_dual_wield_daggers", "we_dual_wield_swords", "we_1h_axe", "we_2h_axe", "we_2h_sword", "es_2h_sword", "es_1h_mace", "es_deus_01", "es_1h_flail", "es_2h_hammer", "es_2h_heavy_spear", "es_2h_sword_executioner", "es_bastard_sword", "es_dual_wield_hammer_sword", "es_halberd", "es_mace_shield", "es_sword_shield", "es_sword_shield_breton", "wh_1h_axe", "wh_1h_falchion", "wh_1h_hammer", "wh_2h_billhook", "wh_2h_hammer", "wh_2h_sword", "wh_dual_hammer", "wh_dual_wield_axe_falchion", "wh_fencing_sword", "wh_flail_shield", "wh_hammer_book", "wh_hammer_shield", "dr_1h_hammer", "dr_2h_axe", "dr_2h_cog_hammer", "dr_2h_pick", "dr_dual_wield_axes", "dr_dual_wield_hammers", "dr_shield_axe", "we_spear", "we_1h_spears_shield", "we_1h_sword", "we_dual_wield_sword_dagger", "bw_1h_crowbill", "bw_1h_flail_flaming", "bw_dagger", "bw_flame_sword", "bw_ghost_scythe", "we_shortbow_hagbane", "we_javelin", "es_longbow", "we_longbow", "we_deus_01", "wh_brace_of_pistols", "wh_crossbow", "wh_crossbow_repeater", "wh_deus_01", "wh_repeating_pistols", "we_shortbow", "we_crossbow_repeater", "es_blunderbuss", "es_handgun", "es_repeating_handgun", "dr_1h_throwing_axes", "dr_crossbow", "dr_deus_01", "dr_drake_pistol", "dr_drakegun", "dr_rakegun", "dr_steam_pistol", "bw_skullstaff_beam", "bw_skullstaff_fireball", "bw_skullstaff_flamethrower", "bw_skullstaff_geiser", "bw_skullstaff_spear", "bw_necromancy_staff", "bw_deus_01" },
        we_maidenguard    = { "we_dual_wield_daggers", "we_dual_wield_swords", "we_1h_axe", "we_2h_axe", "we_2h_sword", "es_2h_sword", "es_1h_mace", "es_deus_01", "es_1h_flail", "es_2h_hammer", "es_2h_heavy_spear", "es_2h_sword_executioner", "es_bastard_sword", "es_dual_wield_hammer_sword", "es_halberd", "es_mace_shield", "es_sword_shield", "es_sword_shield_breton", "wh_1h_axe", "wh_1h_falchion", "wh_1h_hammer", "wh_2h_billhook", "wh_2h_hammer", "wh_2h_sword", "wh_dual_hammer", "wh_dual_wield_axe_falchion", "wh_fencing_sword", "wh_flail_shield", "wh_hammer_book", "wh_hammer_shield", "dr_1h_hammer", "dr_2h_axe", "dr_2h_cog_hammer", "dr_2h_pick", "dr_dual_wield_axes", "dr_dual_wield_hammers", "dr_shield_axe", "we_spear", "we_1h_spears_shield", "we_1h_sword", "we_dual_wield_sword_dagger", "bw_1h_crowbill", "bw_1h_flail_flaming", "bw_dagger", "bw_flame_sword", "bw_ghost_scythe", "we_shortbow_hagbane", "we_javelin", "es_longbow", "we_longbow", "we_deus_01", "wh_brace_of_pistols", "wh_crossbow", "wh_crossbow_repeater", "wh_deus_01", "wh_repeating_pistols", "we_shortbow", "we_crossbow_repeater", "es_blunderbuss", "es_handgun", "es_repeating_handgun", "dr_1h_throwing_axes", "dr_crossbow", "dr_deus_01", "dr_drake_pistol", "dr_drakegun", "dr_rakegun", "dr_steam_pistol", "bw_skullstaff_beam", "bw_skullstaff_fireball", "bw_skullstaff_flamethrower", "bw_skullstaff_geiser", "bw_skullstaff_spear", "bw_necromancy_staff", "bw_deus_01" },
        we_shade          = { "we_dual_wield_daggers", "we_dual_wield_swords", "we_1h_axe", "we_2h_axe", "we_2h_sword", "es_2h_sword", "es_1h_mace", "es_deus_01", "es_1h_flail", "es_2h_hammer", "es_2h_heavy_spear", "es_2h_sword_executioner", "es_bastard_sword", "es_dual_wield_hammer_sword", "es_halberd", "es_mace_shield", "es_sword_shield", "es_sword_shield_breton", "wh_1h_axe", "wh_1h_falchion", "wh_1h_hammer", "wh_2h_billhook", "wh_2h_hammer", "wh_2h_sword", "wh_dual_hammer", "wh_dual_wield_axe_falchion", "wh_fencing_sword", "wh_flail_shield", "wh_hammer_book", "wh_hammer_shield", "dr_1h_hammer", "dr_2h_axe", "dr_2h_cog_hammer", "dr_2h_pick", "dr_dual_wield_axes", "dr_dual_wield_hammers", "dr_shield_axe", "we_spear", "we_1h_spears_shield", "we_1h_sword", "we_dual_wield_sword_dagger", "bw_1h_crowbill", "bw_1h_flail_flaming", "bw_dagger", "bw_flame_sword", "bw_ghost_scythe", "we_shortbow_hagbane", "we_javelin", "es_longbow", "we_longbow", "we_deus_01", "wh_brace_of_pistols", "wh_crossbow", "wh_crossbow_repeater", "wh_deus_01", "wh_repeating_pistols", "we_shortbow", "we_crossbow_repeater", "es_blunderbuss", "es_handgun", "es_repeating_handgun", "dr_1h_throwing_axes", "dr_crossbow", "dr_deus_01", "dr_drake_pistol", "dr_drakegun", "dr_rakegun", "dr_steam_pistol", "bw_skullstaff_beam", "bw_skullstaff_fireball", "bw_skullstaff_flamethrower", "bw_skullstaff_geiser", "bw_skullstaff_spear", "bw_necromancy_staff", "bw_deus_01" },
        we_thornsister    = { "we_dual_wield_daggers", "we_dual_wield_swords", "we_1h_axe", "we_2h_axe", "we_2h_sword", "es_2h_sword", "es_1h_mace", "es_deus_01", "es_1h_flail", "es_2h_hammer", "es_2h_heavy_spear", "es_2h_sword_executioner", "es_bastard_sword", "es_dual_wield_hammer_sword", "es_halberd", "es_mace_shield", "es_sword_shield", "es_sword_shield_breton", "wh_1h_axe", "wh_1h_falchion", "wh_1h_hammer", "wh_2h_billhook", "wh_2h_hammer", "wh_2h_sword", "wh_dual_hammer", "wh_dual_wield_axe_falchion", "wh_fencing_sword", "wh_flail_shield", "wh_hammer_book", "wh_hammer_shield", "dr_1h_hammer", "dr_2h_axe", "dr_2h_cog_hammer", "dr_2h_pick", "dr_dual_wield_axes", "dr_dual_wield_hammers", "dr_shield_axe", "we_spear", "we_1h_spears_shield", "we_1h_sword", "we_dual_wield_sword_dagger", "bw_1h_crowbill", "bw_1h_flail_flaming", "bw_dagger", "bw_flame_sword", "bw_ghost_scythe", "we_life_staff", "we_shortbow_hagbane", "we_javelin", "es_longbow", "we_longbow", "we_deus_01", "wh_brace_of_pistols", "wh_crossbow", "wh_crossbow_repeater", "wh_deus_01", "wh_repeating_pistols", "we_shortbow", "we_crossbow_repeater", "es_blunderbuss", "es_handgun", "es_repeating_handgun", "dr_1h_throwing_axes", "dr_crossbow", "dr_deus_01", "dr_drake_pistol", "dr_drakegun", "dr_rakegun", "dr_steam_pistol", "bw_skullstaff_beam", "bw_skullstaff_fireball", "bw_skullstaff_flamethrower", "bw_skullstaff_geiser", "bw_skullstaff_spear", "bw_necromancy_staff", "bw_deus_01" },
        -- Saltzpyre
        -- v0.12.103-dev (2026-05-31): Kruber batch KS1/KS3/KS4/KS5/KS10/KS11/KS12
        -- added — 7 ES source weapons routed to non-WP careers (bretonnian
        -- longsword, executioner sword, greathammer, mace+sword, blunderbuss,
        -- handgun, repeater handgun). SKIPPED KS2 es_2h_sword (~ wh_2h_sword
        -- native), KS6 es_mace_shield / KS7 es_sword_shield / KS8
        -- es_sword_shield_breton / KS9 es_deus_01 (shield combos — non-WP
        -- careers lack native shield-stance support; flagged for user review).
        -- v0.12.103-dev (2026-05-31): Bardin batch BS-A added — 6 DR source
        -- weapons routed to non-WP careers (1h axe, 1h hammer, greataxe, cog
        -- hammer, 2h hammer, pickaxe). All melee. SKIPPED es_mace_shield
        -- (identical to wh_hammer_shield Saltzpyre native); es_sword_shield /
        -- es_sword_shield_breton / es_deus_01 deferred to WP receiver
        -- consideration (non-WP careers lack native shield stance).
        -- v0.12.103-dev (2026-05-31): Bardin batch BS-B added — 8 more DR
        -- source weapons routed to non-WP careers (throwing axes, dual axes,
        -- dual hammers, grudge-raker, drakefire pistols, drakegun, masterwork
        -- pistol, trollhammer torpedo). 2 melee + 6 ranged. SKIPPED dr_crossbow
        -- (identical to wh_crossbow Saltzpyre native); dr_handgun (identical
        -- to es_handgun — Kruber route is preferred and already added in KS
        -- batch).
        -- v0.12.103-dev (2026-05-31): Kerillian batch C added — 9 WE source
        -- weapons routed to non-WP careers (1h axe, glaive, elf 2h sword,
        -- dual daggers, dual swords, sword+dagger melee; shortbow, hagbane
        -- shortbow, moonfire bow ranged). 6 melee + 3 ranged. SKIPPED
        -- we_crossbow_repeater (already in non-WP rows natively).
        -- v0.12.109-dev (2026-06-03): Sienna batch D added — 8 BW source
        -- weapons routed to non-WP careers (bw_1h_mace, bw_dagger,
        -- bw_flame_sword, bw_ghost_scythe melee; bw_skullstaff_beam,
        -- bw_skullstaff_fireball, bw_skullstaff_flamethrower,
        -- bw_skullstaff_geiser ranged). 4 melee + 4 ranged. SKIPPED
        -- bw_1h_flail_flaming (~ Saltzpyre native es_1h_flail) and bw_sword
        -- (~ wh_1h_falchion native 1H sword-class).
        -- v0.12.110-dev (2026-06-04): Batch E remaining (5 weapons) + Shield-
        -- combos override (7 weapons) added — 12 source weapons per career,
        -- = 36 new entries. Batch E remaining: bw_skullstaff_spear,
        -- bw_necromancy_staff, bw_deus_01 (Coruscation Staff), we_javelin,
        -- we_life_staff — all routed to wh_1h_falchion except we_javelin
        -- (wh_1h_axe per its short-haft/throw role). Shield-combos override
        -- supersedes Batch A SKIP decisions (BS-A-skip-2/3/4) and adds 3
        -- previously-unqueued shield combos (Bardin axe+shield, Bardin
        -- hammer+shield, Kerillian spear+shield). Per user 2026-06-04: all
        -- 7 shield-combo source weapons target wh_dual_wield_axe_falchion
        -- as the 3P animation source (Saltzpyre's two-handed off-hand
        -- vocab is the closest non-WP body has to a shield-stance).
        wh_captain        = { "wh_1h_axe", "wh_dual_wield_axe_falchion", "wh_2h_billhook", "wh_dual_hammer", "wh_1h_falchion", "es_1h_flail", "wh_2h_sword", "wh_1h_hammer", "wh_2h_hammer", "we_spear", "we_1h_sword", "es_halberd", "es_1h_mace", "es_1h_sword", "es_2h_heavy_spear", "wh_fencing_sword", "bw_1h_crowbill", "bw_1h_mace", "bw_dagger", "bw_flame_sword", "bw_ghost_scythe", "bw_skullstaff_beam", "bw_skullstaff_fireball", "bw_skullstaff_flamethrower", "bw_skullstaff_geiser", "bw_skullstaff_spear", "bw_necromancy_staff", "bw_deus_01", "es_bastard_sword", "es_2h_sword_executioner", "es_2h_hammer", "es_dual_wield_hammer_sword", "es_mace_shield", "es_sword_shield", "es_sword_shield_breton", "es_deus_01", "dr_2h_axe", "dr_2h_cog_hammer", "dr_2h_hammer", "dr_2h_pick", "dr_shield_axe", "dr_shield_hammer", "we_1h_spears_shield", "wh_brace_of_pistols", "wh_crossbow", "wh_deus_01", "we_crossbow_repeater", "wh_repeating_pistols", "wh_crossbow_repeater", "es_longbow", "we_longbow", "we_1h_axe", "we_2h_axe", "we_2h_sword", "we_dual_wield_daggers", "we_dual_wield_swords", "we_dual_wield_sword_dagger", "we_shortbow", "we_shortbow_hagbane", "we_deus_01", "we_javelin", "es_blunderbuss", "es_handgun", "es_repeating_handgun", "dr_1h_throwing_axes", "dr_rakegun", "dr_drake_pistol", "dr_drakegun", "dr_steam_pistol", "dr_deus_01" },
        wh_bountyhunter   = { "wh_1h_axe", "wh_dual_wield_axe_falchion", "wh_2h_billhook", "wh_dual_hammer", "wh_1h_falchion", "es_1h_flail", "wh_2h_sword", "wh_1h_hammer", "wh_2h_hammer", "we_spear", "we_1h_sword", "es_halberd", "es_1h_mace", "es_1h_sword", "es_2h_heavy_spear", "wh_fencing_sword", "bw_1h_crowbill", "bw_1h_mace", "bw_dagger", "bw_flame_sword", "bw_ghost_scythe", "bw_skullstaff_beam", "bw_skullstaff_fireball", "bw_skullstaff_flamethrower", "bw_skullstaff_geiser", "bw_skullstaff_spear", "bw_necromancy_staff", "bw_deus_01", "es_bastard_sword", "es_2h_sword_executioner", "es_2h_hammer", "es_dual_wield_hammer_sword", "es_mace_shield", "es_sword_shield", "es_sword_shield_breton", "es_deus_01", "dr_2h_axe", "dr_2h_cog_hammer", "dr_2h_hammer", "dr_2h_pick", "dr_shield_axe", "dr_shield_hammer", "we_1h_spears_shield", "wh_brace_of_pistols", "wh_crossbow", "wh_deus_01", "we_crossbow_repeater", "wh_repeating_pistols", "wh_crossbow_repeater", "es_longbow", "we_longbow", "we_1h_axe", "we_2h_axe", "we_2h_sword", "we_dual_wield_daggers", "we_dual_wield_swords", "we_dual_wield_sword_dagger", "we_shortbow", "we_shortbow_hagbane", "we_deus_01", "we_javelin", "es_blunderbuss", "es_handgun", "es_repeating_handgun", "dr_1h_throwing_axes", "dr_rakegun", "dr_drake_pistol", "dr_drakegun", "dr_steam_pistol", "dr_deus_01" },
        wh_zealot         = { "wh_1h_axe", "wh_dual_wield_axe_falchion", "wh_2h_billhook", "wh_dual_hammer", "wh_1h_falchion", "es_1h_flail", "wh_2h_sword", "wh_1h_hammer", "wh_2h_hammer", "we_spear", "we_1h_sword", "es_halberd", "es_1h_mace", "es_1h_sword", "es_2h_heavy_spear", "wh_fencing_sword", "bw_1h_crowbill", "bw_1h_mace", "bw_dagger", "bw_flame_sword", "bw_ghost_scythe", "bw_skullstaff_beam", "bw_skullstaff_fireball", "bw_skullstaff_flamethrower", "bw_skullstaff_geiser", "bw_skullstaff_spear", "bw_necromancy_staff", "bw_deus_01", "es_bastard_sword", "es_2h_sword_executioner", "es_2h_hammer", "es_dual_wield_hammer_sword", "es_mace_shield", "es_sword_shield", "es_sword_shield_breton", "es_deus_01", "dr_2h_axe", "dr_2h_cog_hammer", "dr_2h_hammer", "dr_2h_pick", "dr_shield_axe", "dr_shield_hammer", "we_1h_spears_shield", "wh_brace_of_pistols", "wh_crossbow", "wh_deus_01", "we_crossbow_repeater", "wh_repeating_pistols", "wh_crossbow_repeater", "es_longbow", "we_longbow", "we_1h_axe", "we_2h_axe", "we_2h_sword", "we_dual_wield_daggers", "we_dual_wield_swords", "we_dual_wield_sword_dagger", "we_shortbow", "we_shortbow_hagbane", "we_deus_01", "we_javelin", "es_blunderbuss", "es_handgun", "es_repeating_handgun", "dr_1h_throwing_axes", "dr_rakegun", "dr_drake_pistol", "dr_drakegun", "dr_steam_pistol", "dr_deus_01" },
        wh_priest         = { "wh_dual_hammer", "es_1h_flail", "wh_flail_shield", "wh_1h_hammer", "wh_hammer_shield", "wh_hammer_book", "wh_2h_hammer" },
        -- Sienna
        bw_adept          = { "bw_1h_crowbill", "bw_dagger", "bw_ghost_scythe", "bw_flame_sword", "bw_1h_flail_flaming", "bw_1h_mace", "bw_sword", "bw_skullstaff_beam", "bw_skullstaff_spear", "bw_skullstaff_geiser", "bw_deus_01", "bw_skullstaff_fireball", "bw_skullstaff_flamethrower" },
        bw_scholar        = { "bw_1h_crowbill", "bw_dagger", "bw_ghost_scythe", "bw_flame_sword", "bw_1h_flail_flaming", "bw_1h_mace", "bw_sword", "bw_skullstaff_beam", "bw_skullstaff_spear", "bw_skullstaff_geiser", "bw_deus_01", "bw_skullstaff_fireball", "bw_skullstaff_flamethrower" },
        bw_unchained      = { "bw_1h_crowbill", "bw_dagger", "bw_ghost_scythe", "bw_flame_sword", "bw_1h_flail_flaming", "bw_1h_mace", "bw_sword", "bw_skullstaff_beam", "bw_skullstaff_spear", "bw_skullstaff_geiser", "bw_deus_01", "bw_skullstaff_fireball", "bw_skullstaff_flamethrower" },
        bw_necromancer    = { "bw_1h_crowbill", "bw_dagger", "bw_ghost_scythe", "bw_flame_sword", "bw_1h_flail_flaming", "bw_1h_mace", "bw_sword", "bw_skullstaff_beam", "bw_skullstaff_spear", "bw_skullstaff_geiser", "bw_deus_01", "bw_skullstaff_fireball", "bw_necromancy_staff" },
    },

    -- #593: these are reversible live
    -- handoffs. WT owns the fallback while CWV is inactive and strips it on
    -- an active transition, then restores the saved WT preference on disable.
    cwv_conditional_managed = {
        es_mercenary      = { dr_shield_axe = true },
        es_huntsman       = { dr_shield_axe = true },
        es_knight         = { dr_shield_axe = true },
        es_questingknight = { dr_shield_axe = true },
        -- #593 follow-up: standard Saltzpyre gets the same reversible handoff.
        -- CWV active -> Empire CWV Axe+Shield; CWV absent -> Bardin WT fallback.
        wh_captain        = { dr_shield_axe = true },
        wh_bountyhunter   = { dr_shield_axe = true },
        wh_zealot         = { dr_shield_axe = true },
    },
}

-- #576/user correction: Saltzpyre receives Kruber's Empire Greathammer
-- (`es_2h_hammer`, ItemMasterList template `two_handed_hammers_template_1`),
-- not Bardin's analogous `dr_2h_hammer`. Keep the source lists readable above
-- while enforcing the catalog contract here for all standard Saltz careers.
-- #594 applies the same native-ownership boundary to shield hammers: keep
-- Kruber's `es_mace_shield` and remove Bardin's `dr_shield_hammer` regardless
-- of CWV state. Vanilla authors both from the 1h_hammers_shield base, while
-- Bardin's template adds three dwarf-specific light-attack range modifiers.
-- #368: WT and CWV are independent availability providers. Axe + Falchion is
-- therefore a normal WT Kruber row (the old cwv_managed cede is gone).
for _, career in ipairs({ "es_mercenary", "es_huntsman", "es_knight", "es_questingknight" }) do
    local weapons = DATA.weapon_unlock_map[career]
    local found = false
    for _, weapon_key in ipairs(weapons) do
        if weapon_key == "wh_dual_wield_axe_falchion" then found = true; break end
    end
    if not found then weapons[#weapons + 1] = "wh_dual_wield_axe_falchion" end
end

for _, career in ipairs({ "wh_captain", "wh_bountyhunter", "wh_zealot" }) do
    local weapons = DATA.weapon_unlock_map[career]
    for i = #weapons, 1, -1 do
        if weapons[i] == "dr_2h_hammer" or weapons[i] == "dr_shield_hammer" then
            table.remove(weapons, i)
        end
    end
end

return DATA
