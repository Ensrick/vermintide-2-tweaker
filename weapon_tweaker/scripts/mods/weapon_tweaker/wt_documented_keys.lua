--[[
============================================================================
 wt_documented_keys.lua -- player-facing names for internal weapon keys
============================================================================

This is the one declaration site for weapon keys used by Weapon Tweaker's
availability and 3P-routing data. The symbolic names keep the large data
tables readable without repeating undocumented engine keys hundreds of times.

The English names below are the same documented names exposed by the
`unlock_<career>_<weapon>` localization rows. They are developer annotations,
not runtime localization data; player-facing UI must still resolve through
ItemMasterList/display_name or Weapon Tweaker's localization table.

Issue #159: every engine-key literal in this registry has its localized
player-facing name on the same line. Add new weapon keys here first and use
the symbolic constant everywhere else.
============================================================================
--]]

return {
    SIENNA_CROWBILL = "bw_1h_crowbill",                         -- Sienna: Crowbill
    SIENNA_FLAMING_FLAIL = "bw_1h_flail_flaming",               -- Sienna: Flaming Flail
    SIENNA_MACE = "bw_1h_mace",                                 -- Sienna: Mace
    SIENNA_DAGGER = "bw_dagger",                                -- Sienna: Dagger
    SIENNA_CORUSCATION_STAFF = "bw_deus_01",                    -- Sienna: Coruscation Staff
    SIENNA_FLAME_SWORD = "bw_flame_sword",                      -- Sienna: Flame Sword
    SIENNA_ENSORCELLED_REAPER = "bw_ghost_scythe",              -- Sienna: Ensorcelled Reaper
    SIENNA_SOULSTEALER_STAFF = "bw_necromancy_staff",           -- Sienna: Soulstealer Staff
    SIENNA_BEAM_STAFF = "bw_skullstaff_beam",                   -- Sienna: Beam Staff
    SIENNA_FIREBALL_STAFF = "bw_skullstaff_fireball",           -- Sienna: Fireball Staff
    SIENNA_FLAMESTORM_STAFF = "bw_skullstaff_flamethrower",     -- Sienna: Flamestorm Staff
    SIENNA_CONFLAGRATION_STAFF = "bw_skullstaff_geiser",        -- Sienna: Conflagration Staff
    SIENNA_BOLT_STAFF = "bw_skullstaff_spear",                  -- Sienna: Bolt Staff
    SIENNA_SWORD = "bw_sword",                                  -- Sienna: Sword

    BARDIN_AXE = "dr_1h_axe",                                   -- Bardin: Axe
    BARDIN_HAMMER = "dr_1h_hammer",                             -- Bardin: Hammer
    BARDIN_THROWING_AXES = "dr_1h_throwing_axes",               -- Bardin: Throwing Axes
    BARDIN_GREAT_AXE = "dr_2h_axe",                             -- Bardin: Great Axe
    BARDIN_COG_HAMMER = "dr_2h_cog_hammer",                     -- Bardin: Cog Hammer
    BARDIN_GREAT_HAMMER = "dr_2h_hammer",                       -- Bardin: Great Hammer
    BARDIN_WAR_PICK = "dr_2h_pick",                             -- Bardin: War Pick
    BARDIN_CROSSBOW = "dr_crossbow",                            -- Bardin: Crossbow
    BARDIN_TROLLHAMMER_TORPEDO = "dr_deus_01",                  -- Bardin: Trollhammer Torpedo
    BARDIN_DRAKEFIRE_PISTOLS = "dr_drake_pistol",               -- Bardin: Drakefire Pistols
    BARDIN_DRAKEGUN = "dr_drakegun",                            -- Bardin: Drakegun
    BARDIN_DUAL_AXES = "dr_dual_wield_axes",                    -- Bardin: Dual Axes
    BARDIN_DUAL_HAMMERS = "dr_dual_wield_hammers",              -- Bardin: Dual Hammers
    BARDIN_HANDGUN = "dr_handgun",                              -- Bardin: Handgun
    BARDIN_GRUDGE_RAKER = "dr_rakegun",                         -- Bardin: Grudge-Raker
    BARDIN_AXE_AND_SHIELD = "dr_shield_axe",                    -- Bardin: Axe and Shield
    BARDIN_HAMMER_AND_SHIELD = "dr_shield_hammer",              -- Bardin: Hammer and Shield
    BARDIN_MASTERWORK_PISTOL = "dr_steam_pistol",               -- Bardin: Masterwork Pistol

    SALTZPYRE_FLAIL = "es_1h_flail",                            -- Saltzpyre: Flail
    KRUBER_MACE = "es_1h_mace",                                 -- Kruber: Mace
    KRUBER_SWORD = "es_1h_sword",                               -- Kruber: Sword
    KRUBER_TWO_HANDED_HAMMER = "es_2h_hammer",                  -- Kruber: Two-Handed Hammer
    KRUBER_TUSKGOR_SPEAR = "es_2h_heavy_spear",                 -- Kruber: Tuskgor Spear
    KRUBER_GREATSWORD = "es_2h_sword",                          -- Kruber: Greatsword
    KRUBER_EXECUTIONER_SWORD = "es_2h_sword_executioner",       -- Kruber: Executioner Sword
    KRUBER_BRETONNIAN_LONGSWORD = "es_bastard_sword",           -- Kruber: Bretonnian Longsword
    KRUBER_BLUNDERBUSS = "es_blunderbuss",                      -- Kruber: Blunderbuss
    KRUBER_SPEAR_AND_SHIELD = "es_deus_01",                     -- Kruber: Spear and Shield
    KRUBER_MACE_AND_SWORD = "es_dual_wield_hammer_sword",       -- Kruber: Mace and Sword
    KRUBER_HALBERD = "es_halberd",                              -- Kruber: Halberd
    KRUBER_HANDGUN = "es_handgun",                              -- Kruber: Handgun
    KRUBER_LONGBOW = "es_longbow",                              -- Kruber: Longbow
    KRUBER_MACE_AND_SHIELD = "es_mace_shield",                  -- Kruber: Mace and Shield
    KRUBER_REPEATING_HANDGUN = "es_repeating_handgun",          -- Kruber: Repeating Handgun
    KRUBER_SWORD_AND_SHIELD = "es_sword_shield",                -- Kruber: Sword and Shield
    KRUBER_BRETONNIAN_SWORD_AND_SHIELD = "es_sword_shield_breton", -- Kruber: Bretonnian Sword and Shield

    KERILLIAN_ELVEN_AXE = "we_1h_axe",                          -- Kerillian: Elven Axe
    KERILLIAN_SPEAR_AND_SHIELD = "we_1h_spears_shield",         -- Kerillian: Spear and Shield
    KERILLIAN_SWORD = "we_1h_sword",                            -- Kerillian: Sword
    KERILLIAN_GLAIVE = "we_2h_axe",                             -- Kerillian: Glaive
    KERILLIAN_GREATSWORD = "we_2h_sword",                       -- Kerillian: Greatsword
    KERILLIAN_VOLLEY_CROSSBOW = "we_crossbow_repeater",         -- Kerillian: Volley Crossbow
    KERILLIAN_MOONFIRE_BOW = "we_deus_01",                      -- Kerillian: Moonfire Bow
    KERILLIAN_DUAL_DAGGERS = "we_dual_wield_daggers",           -- Kerillian: Dual Daggers
    KERILLIAN_SWORD_AND_DAGGER = "we_dual_wield_sword_dagger",  -- Kerillian: Sword and Dagger
    KERILLIAN_DUAL_SWORDS = "we_dual_wield_swords",             -- Kerillian: Dual Swords
    KERILLIAN_JAVELIN = "we_javelin",                           -- Kerillian: Javelin
    KERILLIAN_DEEPWOOD_STAFF = "we_life_staff",                 -- Kerillian: Deepwood Staff
    KERILLIAN_LONGBOW = "we_longbow",                           -- Kerillian: Longbow
    KERILLIAN_SWIFT_BOW = "we_shortbow",                        -- Kerillian: Swift Bow
    KERILLIAN_HAGBANE_SHORT_BOW = "we_shortbow_hagbane",        -- Kerillian: Hagbane Short Bow
    KERILLIAN_SPEAR = "we_spear",                               -- Kerillian: Spear

    SALTZPYRE_AXE = "wh_1h_axe",                                -- Saltzpyre: Axe
    SALTZPYRE_FALCHION = "wh_1h_falchion",                      -- Saltzpyre: Falchion
    SALTZPYRE_1H_HAMMER = "wh_1h_hammer",                       -- Saltzpyre: 1H Hammer
    SALTZPYRE_BILLHOOK = "wh_2h_billhook",                      -- Saltzpyre: Billhook
    SALTZPYRE_HOLY_GREAT_HAMMER = "wh_2h_hammer",               -- Saltzpyre: Holy Great Hammer
    SALTZPYRE_2H_SWORD = "wh_2h_sword",                         -- Saltzpyre: 2H Sword
    SALTZPYRE_BRACE_OF_PISTOLS = "wh_brace_of_pistols",         -- Saltzpyre: Brace of Pistols
    SALTZPYRE_CROSSBOW = "wh_crossbow",                         -- Saltzpyre: Crossbow
    SALTZPYRE_VOLLEY_CROSSBOW = "wh_crossbow_repeater",         -- Saltzpyre: Volley Crossbow
    SALTZPYRE_GRIFFON_FOOT = "wh_deus_01",                      -- Saltzpyre: Griffon-foot
    SALTZPYRE_DUAL_SKULL_SPLITTERS = "wh_dual_hammer",          -- Saltzpyre: Dual Skull-Splitters
    SALTZPYRE_AXE_AND_FALCHION = "wh_dual_wield_axe_falchion",  -- Saltzpyre: Axe and Falchion
    SALTZPYRE_RAPIER = "wh_fencing_sword",                      -- Saltzpyre: Rapier
    SALTZPYRE_FLAIL_AND_SHIELD = "wh_flail_shield",             -- Saltzpyre: Flail and Shield
    SALTZPYRE_HAMMER_AND_TOME = "wh_hammer_book",               -- Saltzpyre: Hammer and Tome
    SALTZPYRE_SKULL_SPLITTER_AND_SHIELD = "wh_hammer_shield",   -- Saltzpyre: Skull-Splitter and Shield
    SALTZPYRE_REPEATING_PISTOL = "wh_repeating_pistols",        -- Saltzpyre: Repeating Pistol
}
