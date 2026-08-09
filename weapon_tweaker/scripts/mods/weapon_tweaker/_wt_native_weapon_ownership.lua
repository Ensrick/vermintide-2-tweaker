-- Immutable vanilla ownership for the 83 base weapons managed by WT.
--
-- ItemMasterList.can_wield is mutable shared runtime state, so it cannot be
-- used to decide whether a loadout write is safe for the official PlayFab
-- backend: WT, its sibling stream, or another availability mod may already
-- have added a career. This catalog is derived from VT2 6.11.2's exported
-- ItemMasterList rows plus the official DLC UpdateItemMasterList additions
-- (Grail Knight, Engineer, Sister of the Thorn, and Necromancer). Unknown
-- pairs deliberately return false so backend writes fail closed to WT's
-- session cache instead of being sent to PlayFab. Verified unchanged through
-- VT2 6.11.3.

local M = {}

local NATIVE_WEAPONS = {
    es_mercenary = {
        "es_1h_mace", "es_1h_sword", "es_2h_hammer", "es_2h_heavy_spear", "es_2h_sword",
        "es_2h_sword_executioner", "es_bastard_sword", "es_deus_01", "es_dual_wield_hammer_sword", "es_halberd",
        "es_mace_shield", "es_sword_shield", "es_blunderbuss", "es_handgun", "es_repeating_handgun",
    },
    es_huntsman = {
        "es_1h_mace", "es_1h_sword", "es_2h_hammer", "es_2h_heavy_spear", "es_2h_sword",
        "es_2h_sword_executioner", "es_bastard_sword", "es_deus_01", "es_dual_wield_hammer_sword", "es_halberd",
        "es_mace_shield", "es_sword_shield", "es_blunderbuss", "es_handgun", "es_longbow",
        "es_repeating_handgun",
    },
    es_knight = {
        "es_1h_mace", "es_1h_sword", "es_2h_hammer", "es_2h_sword", "es_2h_sword_executioner",
        "es_bastard_sword", "es_deus_01", "es_dual_wield_hammer_sword", "es_halberd", "es_mace_shield",
        "es_sword_shield", "es_blunderbuss", "es_handgun", "es_repeating_handgun",
    },
    es_questingknight = {
        "es_1h_mace", "es_1h_sword", "es_2h_hammer", "es_2h_sword", "es_2h_sword_executioner",
        "es_bastard_sword", "es_dual_wield_hammer_sword", "es_mace_shield", "es_sword_shield", "es_sword_shield_breton",
    },
    dr_ranger = {
        "dr_1h_axe", "dr_1h_hammer", "dr_2h_axe", "dr_2h_cog_hammer", "dr_2h_hammer",
        "dr_2h_pick", "dr_dual_wield_hammers", "dr_shield_axe", "dr_shield_hammer", "dr_1h_throwing_axes",
        "dr_crossbow", "dr_handgun", "dr_rakegun", "dr_steam_pistol",
    },
    dr_ironbreaker = {
        "dr_1h_axe", "dr_1h_hammer", "dr_2h_axe", "dr_2h_cog_hammer", "dr_2h_hammer",
        "dr_2h_pick", "dr_dual_wield_hammers", "dr_shield_axe", "dr_shield_hammer", "dr_crossbow",
        "dr_deus_01", "dr_drake_pistol", "dr_drakegun", "dr_handgun", "dr_rakegun",
        "dr_steam_pistol",
    },
    dr_slayer = {
        "dr_1h_axe", "dr_1h_hammer", "dr_2h_axe", "dr_2h_cog_hammer", "dr_2h_hammer",
        "dr_2h_pick", "dr_dual_wield_axes", "dr_dual_wield_hammers", "dr_1h_throwing_axes",
    },
    dr_engineer = {
        "dr_1h_axe", "dr_1h_hammer", "dr_2h_axe", "dr_2h_cog_hammer", "dr_2h_hammer",
        "dr_2h_pick", "dr_dual_wield_hammers", "dr_shield_axe", "dr_shield_hammer", "dr_deus_01",
        "dr_drake_pistol", "dr_drakegun", "dr_handgun", "dr_rakegun", "dr_steam_pistol",
    },
    we_waywatcher = {
        "we_1h_axe", "we_1h_sword", "we_2h_axe", "we_2h_sword", "we_dual_wield_daggers",
        "we_dual_wield_sword_dagger", "we_dual_wield_swords", "we_spear", "we_deus_01", "we_javelin",
        "we_longbow", "we_shortbow", "we_shortbow_hagbane",
    },
    we_maidenguard = {
        "we_1h_axe", "we_1h_spears_shield", "we_1h_sword", "we_2h_axe", "we_2h_sword",
        "we_dual_wield_daggers", "we_dual_wield_sword_dagger", "we_dual_wield_swords", "we_spear", "we_deus_01",
        "we_javelin", "we_longbow", "we_shortbow", "we_shortbow_hagbane",
    },
    we_shade = {
        "we_1h_axe", "we_1h_sword", "we_2h_axe", "we_2h_sword", "we_dual_wield_daggers",
        "we_dual_wield_sword_dagger", "we_dual_wield_swords", "we_spear", "we_crossbow_repeater", "we_deus_01",
        "we_javelin", "we_longbow", "we_shortbow", "we_shortbow_hagbane",
    },
    we_thornsister = {
        "we_1h_axe", "we_1h_sword", "we_2h_axe", "we_2h_sword", "we_dual_wield_daggers",
        "we_dual_wield_sword_dagger", "we_dual_wield_swords", "we_spear", "we_deus_01", "we_javelin",
        "we_life_staff", "we_longbow", "we_shortbow", "we_shortbow_hagbane",
    },
    wh_captain = {
        "es_1h_flail", "wh_1h_axe", "wh_1h_falchion", "wh_2h_billhook", "wh_2h_sword",
        "wh_dual_wield_axe_falchion", "wh_fencing_sword", "wh_brace_of_pistols", "wh_crossbow", "wh_crossbow_repeater",
        "wh_deus_01", "wh_repeating_pistols",
    },
    wh_bountyhunter = {
        "es_1h_flail", "wh_1h_axe", "wh_1h_falchion", "wh_2h_billhook", "wh_2h_sword",
        "wh_dual_wield_axe_falchion", "wh_fencing_sword", "wh_brace_of_pistols", "wh_crossbow", "wh_crossbow_repeater",
        "wh_deus_01", "wh_repeating_pistols",
    },
    wh_zealot = {
        "es_1h_flail", "wh_1h_axe", "wh_1h_falchion", "wh_1h_hammer", "wh_2h_billhook",
        "wh_2h_hammer", "wh_2h_sword", "wh_dual_hammer", "wh_dual_wield_axe_falchion", "wh_fencing_sword",
        "wh_brace_of_pistols", "wh_crossbow", "wh_crossbow_repeater", "wh_deus_01", "wh_repeating_pistols",
    },
    wh_priest = {
        "wh_1h_hammer", "wh_2h_hammer", "wh_dual_hammer", "wh_flail_shield", "wh_hammer_book",
        "wh_hammer_shield",
    },
    bw_adept = {
        "bw_1h_crowbill", "bw_1h_flail_flaming", "bw_1h_mace", "bw_dagger", "bw_flame_sword",
        "bw_ghost_scythe", "bw_sword", "bw_deus_01", "bw_skullstaff_beam", "bw_skullstaff_fireball",
        "bw_skullstaff_flamethrower", "bw_skullstaff_geiser", "bw_skullstaff_spear",
    },
    bw_scholar = {
        "bw_1h_crowbill", "bw_1h_flail_flaming", "bw_1h_mace", "bw_dagger", "bw_flame_sword",
        "bw_ghost_scythe", "bw_sword", "bw_deus_01", "bw_skullstaff_beam", "bw_skullstaff_fireball",
        "bw_skullstaff_flamethrower", "bw_skullstaff_geiser", "bw_skullstaff_spear",
    },
    bw_unchained = {
        "bw_1h_crowbill", "bw_1h_flail_flaming", "bw_1h_mace", "bw_dagger", "bw_flame_sword",
        "bw_ghost_scythe", "bw_sword", "bw_deus_01", "bw_skullstaff_beam", "bw_skullstaff_fireball",
        "bw_skullstaff_flamethrower", "bw_skullstaff_geiser", "bw_skullstaff_spear",
    },
    bw_necromancer = {
        "bw_1h_crowbill", "bw_1h_flail_flaming", "bw_1h_mace", "bw_dagger", "bw_flame_sword",
        "bw_ghost_scythe", "bw_sword", "bw_deus_01", "bw_necromancy_staff", "bw_skullstaff_beam",
        "bw_skullstaff_fireball", "bw_skullstaff_geiser", "bw_skullstaff_spear",
    },
}

local OWNERSHIP = {}
for career_name, weapon_keys in pairs(NATIVE_WEAPONS) do
    local row = {}
    OWNERSHIP[career_name] = row
    for _, weapon_key in ipairs(weapon_keys) do row[weapon_key] = true end
end

function M.is_native(career_name, weapon_key)
    local row = OWNERSHIP[career_name]
    return row and row[weapon_key] == true or false
end

function M.snapshot(managed_map)
    local result = {}
    for career_name, weapon_keys in pairs(managed_map or {}) do
        local row = {}
        result[career_name] = row
        for _, weapon_key in ipairs(weapon_keys) do
            row[weapon_key] = M.is_native(career_name, weapon_key)
        end
    end
    return result
end

return M
