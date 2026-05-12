--[[
weapon_tweaker — cross-career weapon unlocks, animation remapping, and visual tweaks.

Major sections (search by name to jump):
  * weapon_unlock_map / apply_weapon_unlocks       — which careers can wield which weapons
  * patch_career_actions_on_weapons                — keep career abilities working on cross-career weapons
  * _anim_redirect / _career_anim_redirect / _3p_weapon_remap
                                                   — three-layer animation system (see DEVELOPMENT.md)
  * _suffix_career_map / _try_suffix_redirect      — suffix-based event swaps (e.g. *_2h_billhook)
  * _weapon_scale_overrides / _weapon_grip_offsets — per-career scale & grip-position tweaks
  * 3P state-machine probe / dump_actions / animlog — debug commands
  * Lifecycle: on_game_state_changed (re-applies unlocks per state), on_setting_changed,
                on_disabled (strip-only revert).

Key conventions (also in CLAUDE.md):
  * NEVER hook BackendUtils.can_wield_item — modify ItemMasterList[*].can_wield directly.
  * rawget(ItemMasterList, k) when k might not exist (DLC ownership, save-data drift).
  * Lua 5.1 — locals are not hoisted; verify forward references before using a name.
]]

local mod = get_mod("wt")
local weapon_backend = mod:dofile("scripts/mods/weapon_tweaker/weapon_tweaker_backend")

local MOD_VERSION = "0.12.22-dev"
mod:info("Weapon Tweaker v%s loaded", MOD_VERSION)
mod:echo("Weapon Tweaker v" .. MOD_VERSION)

local weapon_unlock_map = {
    -- Kruber
    es_mercenary      = { "dr_2h_axe", "dr_2h_hammer", "dr_1h_hammer", "dr_shield_hammer", "es_bastard_sword", "es_sword_shield_breton", "es_2h_sword_executioner", "es_2h_sword", "es_halberd", "we_2h_sword", "we_spear", "we_1h_spears_shield", "we_1h_sword", "es_1h_mace", "es_mace_shield", "es_dual_wield_hammer_sword", "wh_1h_axe", "wh_2h_billhook", "wh_1h_falchion", "es_1h_flail", "wh_1h_hammer", "wh_hammer_shield", "bw_1h_crowbill", "bw_1h_flail_flaming", "bw_sword", "es_deus_01", "es_1h_sword", "es_sword_shield", "es_2h_heavy_spear", "es_2h_hammer", "es_blunderbuss", "es_handgun", "we_longbow", "es_longbow", "es_repeating_handgun", "wh_brace_of_pistols" },
    es_huntsman       = { "dr_2h_axe", "dr_2h_hammer", "dr_1h_hammer", "dr_shield_hammer", "es_bastard_sword", "es_2h_sword_executioner", "es_2h_sword", "es_halberd", "we_2h_sword", "we_spear", "we_1h_spears_shield", "we_1h_sword", "es_1h_mace", "es_mace_shield", "es_dual_wield_hammer_sword", "wh_1h_axe", "wh_2h_billhook", "wh_1h_falchion", "es_1h_flail", "wh_1h_hammer", "wh_hammer_shield", "bw_1h_crowbill", "bw_1h_flail_flaming", "bw_sword", "es_deus_01", "es_1h_sword", "es_sword_shield", "es_2h_heavy_spear", "es_2h_hammer", "es_blunderbuss", "es_handgun", "we_longbow", "es_longbow", "es_repeating_handgun", "wh_brace_of_pistols" },
    es_knight         = { "dr_2h_axe", "dr_2h_hammer", "dr_1h_hammer", "dr_shield_hammer", "es_bastard_sword", "es_2h_sword_executioner", "es_2h_sword", "es_halberd", "we_2h_sword", "we_spear", "we_1h_spears_shield", "we_1h_sword", "es_1h_mace", "es_mace_shield", "es_dual_wield_hammer_sword", "wh_1h_axe", "wh_2h_billhook", "wh_1h_falchion", "es_1h_flail", "wh_1h_hammer", "wh_hammer_shield", "bw_1h_crowbill", "bw_1h_flail_flaming", "bw_sword", "es_deus_01", "es_1h_sword", "es_sword_shield", "es_2h_heavy_spear", "es_2h_hammer", "es_blunderbuss", "es_handgun", "we_longbow", "es_longbow", "es_repeating_handgun", "wh_brace_of_pistols" },
    es_questingknight = { "dr_2h_axe", "dr_2h_hammer", "dr_1h_hammer", "dr_shield_hammer", "es_bastard_sword", "es_sword_shield_breton", "es_2h_sword_executioner", "es_2h_sword", "es_halberd", "we_2h_sword", "we_spear", "we_1h_spears_shield", "we_1h_sword", "es_1h_mace", "es_mace_shield", "es_dual_wield_hammer_sword", "wh_1h_axe", "wh_2h_billhook", "wh_1h_falchion", "es_1h_flail", "wh_1h_hammer", "wh_hammer_shield", "bw_1h_crowbill", "bw_1h_flail_flaming", "bw_sword", "es_deus_01", "es_1h_sword", "es_sword_shield", "es_2h_heavy_spear", "es_2h_hammer", "es_blunderbuss", "es_handgun", "we_longbow", "es_longbow", "es_repeating_handgun", "wh_brace_of_pistols" },
    -- Bardin
    dr_ranger         = { "dr_1h_axe", "dr_shield_axe", "dr_2h_cog_hammer", "dr_dual_wield_axes", "dr_dual_wield_hammers", "dr_2h_axe", "dr_2h_hammer", "dr_1h_hammer", "dr_shield_hammer", "we_1h_sword", "es_1h_sword", "wh_1h_axe", "wh_dual_hammer", "wh_1h_falchion", "wh_1h_hammer", "wh_hammer_shield", "bw_1h_crowbill", "bw_sword", "dr_2h_pick", "dr_crossbow", "dr_rakegun", "dr_handgun", "es_handgun", "dr_steam_pistol", "wh_crossbow", "dr_1h_throwing_axes", "dr_deus_01" },
    dr_ironbreaker    = { "dr_1h_axe", "dr_shield_axe", "dr_2h_cog_hammer", "dr_dual_wield_axes", "dr_dual_wield_hammers", "dr_2h_axe", "dr_2h_hammer", "dr_1h_hammer", "dr_shield_hammer", "we_1h_sword", "es_1h_sword", "wh_1h_axe", "wh_dual_hammer", "wh_1h_falchion", "wh_1h_hammer", "wh_hammer_shield", "bw_1h_crowbill", "bw_sword", "dr_2h_pick", "dr_crossbow", "dr_drake_pistol", "dr_drakegun", "dr_rakegun", "dr_handgun", "es_handgun", "wh_crossbow", "dr_1h_throwing_axes", "dr_deus_01" },
    dr_slayer         = { "dr_1h_axe", "dr_shield_axe", "dr_2h_cog_hammer", "dr_dual_wield_axes", "dr_dual_wield_hammers", "dr_2h_axe", "dr_2h_hammer", "dr_1h_hammer", "dr_shield_hammer", "we_1h_sword", "es_1h_sword", "wh_1h_axe", "wh_dual_hammer", "wh_1h_falchion", "wh_1h_hammer", "wh_hammer_shield", "bw_1h_crowbill", "bw_sword", "dr_2h_pick", "dr_crossbow", "dr_rakegun", "dr_handgun", "es_handgun", "dr_steam_pistol", "wh_crossbow", "dr_1h_throwing_axes", "dr_deus_01" },
    dr_engineer       = { "dr_1h_axe", "dr_shield_axe", "dr_2h_cog_hammer", "dr_dual_wield_axes", "dr_dual_wield_hammers", "dr_2h_axe", "dr_2h_hammer", "dr_1h_hammer", "dr_shield_hammer", "we_1h_sword", "es_1h_sword", "wh_1h_axe", "wh_dual_hammer", "wh_1h_falchion", "wh_1h_hammer", "wh_hammer_shield", "bw_1h_crowbill", "bw_sword", "dr_2h_pick", "dr_crossbow", "dr_drake_pistol", "dr_drakegun", "dr_rakegun", "dr_handgun", "es_handgun", "dr_steam_pistol", "wh_crossbow", "dr_1h_throwing_axes", "dr_deus_01" },
    -- Kerillian
    we_waywatcher     = { "dr_1h_axe", "dr_1h_hammer", "we_dual_wield_daggers", "we_dual_wield_swords", "we_1h_axe", "we_2h_axe", "we_2h_sword", "es_2h_sword", "es_halberd", "es_1h_mace", "es_deus_01", "es_1h_sword", "es_2h_heavy_spear", "wh_1h_axe", "wh_1h_falchion", "wh_2h_sword", "wh_1h_hammer", "bw_1h_crowbill", "bw_sword", "we_spear", "we_1h_spears_shield", "we_1h_sword", "we_dual_wield_sword_dagger", "we_shortbow_hagbane", "we_javelin", "es_longbow", "we_longbow", "we_deus_01", "wh_crossbow_repeater", "we_shortbow", "we_crossbow_repeater" },
    we_maidenguard    = { "dr_1h_axe", "dr_1h_hammer", "we_dual_wield_daggers", "we_dual_wield_swords", "we_1h_axe", "we_2h_axe", "we_2h_sword", "es_2h_sword", "es_halberd", "es_1h_mace", "es_deus_01", "es_1h_sword", "es_2h_heavy_spear", "wh_1h_axe", "wh_1h_falchion", "wh_2h_sword", "wh_1h_hammer", "bw_1h_crowbill", "bw_sword", "we_spear", "we_1h_spears_shield", "we_1h_sword", "we_dual_wield_sword_dagger", "we_shortbow_hagbane", "we_javelin", "es_longbow", "we_longbow", "we_deus_01", "wh_crossbow_repeater", "we_shortbow", "we_crossbow_repeater" },
    we_shade          = { "dr_1h_axe", "dr_1h_hammer", "we_dual_wield_daggers", "we_dual_wield_swords", "we_1h_axe", "we_2h_axe", "we_2h_sword", "es_2h_sword", "es_halberd", "es_1h_mace", "es_deus_01", "es_1h_sword", "es_2h_heavy_spear", "wh_1h_axe", "wh_1h_falchion", "wh_2h_sword", "wh_1h_hammer", "bw_1h_crowbill", "bw_sword", "we_spear", "we_1h_spears_shield", "we_1h_sword", "we_dual_wield_sword_dagger", "we_shortbow_hagbane", "we_javelin", "es_longbow", "we_longbow", "we_deus_01", "wh_crossbow_repeater", "we_shortbow", "we_crossbow_repeater" },
    we_thornsister    = { "dr_1h_axe", "dr_1h_hammer", "we_dual_wield_daggers", "we_dual_wield_swords", "we_1h_axe", "we_2h_axe", "we_2h_sword", "es_2h_sword", "es_halberd", "es_1h_mace", "es_deus_01", "es_1h_sword", "es_2h_heavy_spear", "wh_1h_axe", "wh_1h_falchion", "wh_2h_sword", "wh_1h_hammer", "bw_1h_crowbill", "bw_sword", "we_spear", "we_1h_spears_shield", "we_1h_sword", "we_dual_wield_sword_dagger", "we_life_staff", "we_shortbow_hagbane", "we_javelin", "es_longbow", "we_longbow", "we_deus_01", "wh_crossbow_repeater", "we_shortbow", "we_crossbow_repeater" },
    -- Saltzpyre
    wh_captain        = { "wh_1h_axe", "wh_dual_wield_axe_falchion", "dr_1h_axe", "dr_dual_wield_hammers", "dr_1h_hammer", "wh_2h_billhook", "wh_dual_hammer", "wh_1h_falchion", "es_1h_flail", "wh_2h_sword", "wh_1h_hammer", "wh_2h_hammer", "we_2h_sword", "we_spear", "we_1h_sword", "es_halberd", "es_1h_mace", "es_1h_sword", "es_2h_heavy_spear", "wh_fencing_sword", "bw_1h_crowbill", "bw_1h_flail_flaming", "bw_sword", "dr_crossbow", "wh_brace_of_pistols", "wh_crossbow", "wh_deus_01", "we_crossbow_repeater", "wh_repeating_pistols", "wh_crossbow_repeater", "es_longbow" },
    wh_bountyhunter   = { "wh_1h_axe", "wh_dual_wield_axe_falchion", "dr_1h_axe", "dr_dual_wield_hammers", "dr_1h_hammer", "wh_2h_billhook", "wh_dual_hammer", "wh_1h_falchion", "es_1h_flail", "wh_2h_sword", "wh_1h_hammer", "wh_2h_hammer", "we_2h_sword", "we_spear", "we_1h_sword", "es_halberd", "es_1h_mace", "es_1h_sword", "es_2h_heavy_spear", "wh_fencing_sword", "bw_1h_crowbill", "bw_1h_flail_flaming", "bw_sword", "dr_crossbow", "wh_brace_of_pistols", "wh_crossbow", "wh_deus_01", "we_crossbow_repeater", "wh_repeating_pistols", "wh_crossbow_repeater", "es_longbow" },
    wh_zealot         = { "wh_1h_axe", "wh_dual_wield_axe_falchion", "dr_1h_axe", "dr_dual_wield_hammers", "dr_1h_hammer", "wh_2h_billhook", "wh_dual_hammer", "wh_1h_falchion", "es_1h_flail", "wh_2h_sword", "wh_1h_hammer", "wh_2h_hammer", "we_2h_sword", "we_spear", "we_1h_sword", "es_halberd", "es_1h_mace", "es_1h_sword", "es_2h_heavy_spear", "wh_fencing_sword", "bw_1h_crowbill", "bw_1h_flail_flaming", "bw_sword", "dr_crossbow", "wh_brace_of_pistols", "wh_crossbow", "wh_deus_01", "we_crossbow_repeater", "wh_repeating_pistols", "wh_crossbow_repeater", "es_longbow" },
    wh_priest         = { "wh_1h_axe", "dr_1h_axe", "dr_dual_wield_hammers", "dr_1h_hammer", "dr_shield_hammer", "wh_2h_billhook", "wh_dual_hammer", "wh_1h_falchion", "es_1h_flail", "wh_flail_shield", "wh_1h_hammer", "wh_hammer_shield", "wh_hammer_book", "wh_2h_hammer", "we_spear", "we_1h_sword", "es_halberd", "es_1h_mace", "es_mace_shield", "es_1h_sword", "es_2h_heavy_spear", "bw_1h_crowbill", "bw_1h_flail_flaming", "bw_sword", "we_crossbow_repeater", "es_longbow" },
    -- Sienna
    bw_adept          = { "dr_1h_axe", "dr_1h_hammer", "bw_1h_crowbill", "bw_dagger", "bw_ghost_scythe", "bw_flame_sword", "bw_1h_flail_flaming", "we_1h_sword", "es_1h_mace", "bw_1h_mace", "wh_1h_axe", "wh_1h_falchion", "es_1h_flail", "wh_1h_hammer", "bw_sword", "bw_skullstaff_beam", "bw_skullstaff_spear", "bw_skullstaff_geiser", "bw_deus_01", "bw_skullstaff_fireball", "bw_skullstaff_flamethrower" },
    bw_scholar        = { "dr_1h_axe", "dr_1h_hammer", "bw_1h_crowbill", "bw_dagger", "bw_ghost_scythe", "bw_flame_sword", "bw_1h_flail_flaming", "we_1h_sword", "es_1h_mace", "bw_1h_mace", "wh_1h_axe", "wh_1h_falchion", "es_1h_flail", "wh_1h_hammer", "bw_sword", "bw_skullstaff_beam", "bw_skullstaff_spear", "bw_skullstaff_geiser", "bw_deus_01", "bw_skullstaff_fireball", "bw_skullstaff_flamethrower" },
    bw_unchained      = { "dr_1h_axe", "dr_1h_hammer", "bw_1h_crowbill", "bw_dagger", "bw_ghost_scythe", "bw_flame_sword", "bw_1h_flail_flaming", "we_1h_sword", "es_1h_mace", "bw_1h_mace", "wh_1h_axe", "wh_1h_falchion", "es_1h_flail", "wh_1h_hammer", "bw_sword", "bw_skullstaff_beam", "bw_skullstaff_spear", "bw_skullstaff_geiser", "bw_deus_01", "bw_skullstaff_fireball", "bw_skullstaff_flamethrower" },
    bw_necromancer    = { "dr_1h_axe", "dr_1h_hammer", "bw_1h_crowbill", "bw_dagger", "bw_ghost_scythe", "bw_flame_sword", "bw_1h_flail_flaming", "we_1h_sword", "es_1h_mace", "bw_1h_mace", "wh_1h_axe", "wh_1h_falchion", "es_1h_flail", "wh_1h_hammer", "bw_sword", "bw_skullstaff_beam", "bw_skullstaff_spear", "bw_skullstaff_geiser", "bw_deus_01", "bw_skullstaff_fireball", "bw_necromancy_staff" },
}

-- CLARIFY: career_weapon_variants ("CWV") publishes its own custom items for
-- these (career, weapon) pairs. When CWV is installed, weapon_tweaker SKIPS
-- adding those careers to `can_wield` for the listed weapons (and the matching
-- widgets are stripped in _data.lua) so the two mods don't compete for the
-- same can_wield slot.
local _cwv_managed = {
    es_mercenary      = { wh_1h_axe = true, wh_1h_falchion = true, wh_dual_wield_axe_falchion = true },
    es_huntsman       = { wh_1h_axe = true, wh_1h_falchion = true, wh_dual_wield_axe_falchion = true },
    es_knight         = { wh_1h_axe = true, wh_1h_falchion = true, wh_dual_wield_axe_falchion = true },
    es_questingknight = { wh_1h_axe = true, wh_1h_falchion = true, wh_dual_wield_axe_falchion = true },
}

local function feature_enabled(setting_id, default_value)
    local value = mod:get(setting_id)
    if value == nil then return default_value ~= false end
    return value == true
end

-- CLARIFY: The strip-then-add pattern is required because this runs on
-- on_setting_changed too — toggling a checkbox off must REMOVE the career
-- from can_wield, not just leave it. Direct-modifying ItemMasterList is the
-- ONLY way (BackendUtils.can_wield_item is unhookable from split mods —
-- see DEVELOPMENT.md "Don't hook BackendUtils.can_wield_item").
local function apply_weapon_unlocks()
    if not ItemMasterList then return end

    local has_cwv = get_mod("character_weapon_variants") ~= nil

    -- Strip all mod-managed careers from can_wield
    for career, weapons in pairs(weapon_unlock_map) do
        local cwv_skip = has_cwv and _cwv_managed[career]
        for _, weapon_key in ipairs(weapons) do
            if not (cwv_skip and cwv_skip[weapon_key]) then
                local item = ItemMasterList[weapon_key]
                if item and item.can_wield then
                    for i = #item.can_wield, 1, -1 do
                        if item.can_wield[i] == career then
                            table.remove(item.can_wield, i)
                        end
                    end
                end
            end
        end
    end

    -- Add back only enabled ones
    for career, weapons in pairs(weapon_unlock_map) do
        local cwv_skip = has_cwv and _cwv_managed[career]
        for _, weapon_key in ipairs(weapons) do
            if not (cwv_skip and cwv_skip[weapon_key]) then
                if mod:get("unlock_" .. career .. "_" .. weapon_key) then
                    local item = ItemMasterList[weapon_key]
                    if item then
                        if not item.can_wield then item.can_wield = {} end
                        local already = false
                        for _, value in ipairs(item.can_wield) do
                            if value == career then already = true; break end
                        end
                        if not already then
                            item.can_wield[#item.can_wield + 1] = career
                        end
                    end
                end
            end
        end
    end
end

-- CLARIFY: tracks which (template, action_name) entries were injected by
-- patch_career_actions_on_weapons so subsequent calls (on setting change) can
-- back them out before re-applying. Without this, toggling settings would
-- accumulate stale ability-action entries on weapon templates.
local _career_action_injections = {}

-- CLARIFY: when a cross-career weapon is unlocked, that weapon's template
-- needs the unlocking career's ABILITY action (e.g. Foot Knight's shoulder
-- charge) so the ability still works while wielding the unlocked weapon.
-- Without this patch, activating the career ability on a cross-career weapon
-- silently does nothing because the action isn't on that template.
local function patch_career_actions_on_weapons()
    if not Weapons or not CareerSettings or not ActionTemplates or not ItemMasterList then return end

    for tmpl_key, actions in pairs(_career_action_injections) do
        local tmpl = Weapons[tmpl_key]
        if tmpl and tmpl.actions then
            for action_name in pairs(actions) do
                tmpl.actions[action_name] = nil
            end
        end
    end
    _career_action_injections = {}

    for career, weapons in pairs(weapon_unlock_map) do
        local cs = CareerSettings[career]
        if cs then
            local ability_list = cs.activated_ability
            local ability = ability_list and ability_list[1]
            local action_name = ability and ability.action_name
            local action_template = action_name and ActionTemplates[action_name]
            if action_template then
                for _, weapon_key in ipairs(weapons) do
                    if mod:get("unlock_" .. career .. "_" .. weapon_key) then
                        local item = ItemMasterList[weapon_key]
                        local tmpl_key = item and item.template
                        local tmpl = tmpl_key and Weapons[tmpl_key]
                        if tmpl and tmpl.actions and not tmpl.actions[action_name] then
                            tmpl.actions[action_name] = action_template
                            _career_action_injections[tmpl_key] = _career_action_injections[tmpl_key] or {}
                            _career_action_injections[tmpl_key][action_name] = true
                        end
                    end
                end
            end
        end
    end
end

-- CLARIFY: caches the last-known career name across calls. Falls back to the
-- cached value if Managers.player isn't ready (e.g. very early hook fires
-- during loading screens) so callers always get a usable career string when
-- one was ever resolved this session.
local _cached_career = nil
local function _local_career_name()
    local pm = Managers.player
    if not pm then return _cached_career end
    local pl = pm:local_player()
    if not pl then return _cached_career end
    local career = pl:career_name()
    if career then _cached_career = career; return career end
    -- CLARIFY: career_name() can return nil before character finishes spawning;
    -- profile_index/career_index are populated earlier so this is the fallback.
    local profile_idx = pl:profile_index()
    local career_idx = pl:career_index()
    if SPProfiles and profile_idx and career_idx then
        local prof = SPProfiles[profile_idx]
        local c = prof and prof.careers and prof.careers[career_idx]
        local n = c and c.name
        if n then _cached_career = n; return n end
    end
    return _cached_career
end

local _anim_redirect = {
    to_repeating_crossbow            = "to_repeating_crossbow_elf",
    to_repeating_crossbow_noammo     = "to_repeating_crossbow_elf_noammo",
    to_es_longbow                    = "to_longbow",
    to_es_longbow_noammo             = "to_longbow_noammo",
    attack_swing_down_left_axe       = "attack_swing_down_left",
    push_stab                        = "attack_swing_stab",
    attack_swing_stab_lh             = "attack_swing_stab",
}

-- Career-aware redirects for events that are phantom entries on all skeletons.
-- Key = event to intercept, value = { alt, character_prefix }
-- When the career does NOT match the prefix, redirect to alt.
-- CLARIFY: `invert = true` flips the rule — redirect when the career DOES match
-- the prefix (used when the native skeleton lacks the wield event despite being
-- "this character's weapon", e.g. Saltzpyre's `to_1h_falchion` is missing on
-- the WHC skeleton itself, so we need to redirect ON wh_priest career).
-- `overrides` is a per-career-name (not prefix) override that takes precedence
-- over both the prefix rule and `alt`.
local _career_anim_redirect = {
    to_longbow                       = { alt = "to_es_longbow",                 prefix = "we_" },
    to_longbow_noammo                = { alt = "to_es_longbow_noammo",          prefix = "we_" },
    to_repeating_crossbow_elf        = { alt = "to_repeating_crossbow",         prefix = "we_" },
    to_repeating_crossbow_elf_noammo = { alt = "to_repeating_crossbow_noammo",  prefix = "we_" },
    -- Note: `wh_priest` here is a full career name acting as a prefix; safe
    -- because no other `wh_*` career shares its first 9 chars.
    to_1h_falchion                   = { alt = "to_1h_hammer",                  prefix = "wh_priest", invert = true },
    to_1h_sword                      = { alt = "to_1h_hammer",                  prefix = "wh_priest", invert = true },
    to_1h_axe                        = { alt = "to_1h_sword",                   prefix = "bw_", invert = true,
                                         overrides = { wh_priest = "to_1h_hammer" } },
    to_1h_crowbill                   = { alt = "to_1h_sword",                   prefix = "bw_",
                                         overrides = { wh_priest = "to_1h_hammer" } },
    to_1h_hammer                     = { alt = "to_1h_sword",                   prefix = "we_", invert = true },
    to_1h_hammer_shield_priest       = { alt = "to_1h_hammer_shield",           prefix = "wh_priest" },
    to_1h_spear_shield               = { alt = "to_es_deus_01",                 prefix = "we_",
                                         overrides = { wh_priest = "to_1h_hammer_shield" } },
    to_es_deus_01                    = { alt = "to_1h_spear_shield",           prefix = "es_",
                                         overrides = { wh_priest = "to_1h_hammer_shield" } },
    to_spear                         = { alt = "to_polearm",                   prefix = "we_",
                                         overrides = { wh_captain = "to_2h_billhook", wh_bountyhunter = "to_2h_billhook", wh_zealot = "to_2h_billhook", wh_priest = "to_1h_hammer" } },
    to_polearm                       = { alt = "to_spear",                     prefix = "es_",
                                         overrides = { wh_captain = "to_2h_billhook", wh_bountyhunter = "to_2h_billhook", wh_zealot = "to_2h_billhook", wh_priest = "to_1h_hammer" } },
    -- QUESTION: `prefix = "wh_"` here means "redirect when career does NOT
    -- start with wh_". But ALL non-wh careers have explicit `overrides` entries
    -- below, so the `alt = "to_polearm"` fallback only triggers for careers
    -- not listed (none currently). The `alt` is effectively dead — every
    -- non-wh career maps via overrides. Intentional defensive default, or
    -- just leftover?
    to_2h_billhook                   = { alt = "to_polearm",                   prefix = "wh_",
                                         overrides = { es_mercenary = "to_polearm", es_huntsman = "to_polearm", es_knight = "to_polearm", es_questingknight = "to_polearm",
                                                       we_waywatcher = "to_spear", we_maidenguard = "to_spear", we_shade = "to_spear", we_thornsister = "to_spear",
                                                       wh_priest = "to_1h_hammer" } },
    to_2h_sword                      = { alt = "to_2h_sword_we",                prefix = "we_", invert = true },
    to_2h_sword_we                   = { alt = "to_bastard_sword",              prefix = "we_",
                                         overrides = { wh_priest = "to_1h_hammer",
                                                       wh_captain = "to_1h_sword", wh_bountyhunter = "to_1h_sword", wh_zealot = "to_1h_sword" } },
    to_dual_hammers_priest           = { alt = "to_dual_hammers",               prefix = "wh_" },
    to_dual_axes                     = { alt = "to_dual_hammers",               prefix = "dr_slayer" },
}

-- Suffix-based animation redirect: when an event ending in a weapon suffix
-- doesn't exist on the skeleton, swap the suffix based on career.
-- Checked longest-first to avoid e.g. "_spear" matching "_2h_heavy_spear".
-- CLARIFY: order matters because `event_name:sub(-#suffix) == suffix` is a
-- substring match — without longest-first, `to_es_deus_01` would match
-- `_es_deus_01` correctly but `to_1h_spear_shield` would match `_spear` first
-- (both 6 chars from end onwards differ but the shorter match wins by order).
local _suffix_order = { "_2h_sword_we", "_bastard_sword", "_1h_spear_shield", "_es_deus_01", "_2h_billhook", "_polearm", "_spear" }
local _suffix_career_map = {
    ["_2h_sword_we"] = {
        es_mercenary = "_bastard_sword", es_huntsman = "_bastard_sword", es_knight = "_bastard_sword", es_questingknight = "_bastard_sword",
        wh_captain = "_1h_sword", wh_bountyhunter = "_1h_sword", wh_zealot = "_1h_sword",
        wh_priest = "_1h_hammer",
    },
    ["_1h_spear_shield"] = {
        es_mercenary = "_es_deus_01", es_huntsman = "_es_deus_01", es_knight = "_es_deus_01", es_questingknight = "_es_deus_01",
        dr_ranger = "_1h_hammer_shield", dr_ironbreaker = "_1h_hammer_shield", dr_slayer = "_1h_hammer_shield", dr_engineer = "_1h_hammer_shield",
        wh_captain = "_1h_sword_shield", wh_bountyhunter = "_1h_sword_shield", wh_zealot = "_1h_sword_shield",
        wh_priest = "_1h_hammer_shield",
    },
    ["_es_deus_01"] = {
        we_waywatcher = "_1h_spear_shield", we_maidenguard = "_1h_spear_shield", we_shade = "_1h_spear_shield", we_thornsister = "_1h_spear_shield",
        wh_captain = "_1h_sword_shield", wh_bountyhunter = "_1h_sword_shield", wh_zealot = "_1h_sword_shield",
        wh_priest = "_1h_hammer_shield",
    },
    ["_spear"] = {
        wh_captain = "_2h_billhook", wh_bountyhunter = "_2h_billhook", wh_zealot = "_2h_billhook",
        wh_priest = "_1h_hammer",
    },
    ["_polearm"] = {
        we_waywatcher = "_spear", we_maidenguard = "_spear", we_shade = "_spear", we_thornsister = "_spear",
        wh_captain = "_2h_billhook", wh_bountyhunter = "_2h_billhook", wh_zealot = "_2h_billhook",
        wh_priest = "_1h_hammer",
    },
    ["_2h_billhook"] = {
        es_mercenary = "_polearm", es_huntsman = "_polearm", es_knight = "_polearm", es_questingknight = "_polearm",
        we_waywatcher = "_spear", we_maidenguard = "_spear", we_shade = "_spear", we_thornsister = "_spear",
        wh_priest = "_1h_hammer",
    },
}

-- pcall-guarded `Unit.has_animation_event`. Returns true only if the unit has
-- the named anim event. Used by every redirect/remap helper below — defined
-- BEFORE _try_suffix_redirect to avoid the forward-reference trap that bit
-- this codebase 5+ times (see feedback_lua_forward_reference.md).
local function _safe_has_anim(unit, event)
    local ok, result = pcall(Unit.has_animation_event, unit, event)
    return ok and result
end

local function _try_suffix_redirect(unit, event_name, career)
    for _, suffix in ipairs(_suffix_order) do
        local slen = #suffix
        if event_name:sub(-slen) == suffix then
            local map = _suffix_career_map[suffix]
            local target_suffix = map and map[career]
            if target_suffix then
                local base = event_name:sub(1, -(slen + 1))
                local target = base .. target_suffix
                if _safe_has_anim(unit, target) then
                    return target
                end
            end
            return nil
        end
    end
    return nil
end

-- ============================================================================
-- ANIMATION REMAPPING — READ FIRST
-- ============================================================================
-- 1P (first-person) animations are UNIVERSAL across all six characters and
-- all weapons. The first_person_base unit is shared, so any weapon's 1P state
-- machine and clips play correctly on any character's first-person view by
-- default. We never override anim_event (1P), wield_anim (1P), or
-- state_machine per character — only 3P fields need cross-character work.
--
-- Every remap table and every redirect in this file targets the 3P body
-- (player_unit + husks). The 1P first_person_unit gets an early return in the
-- animation_event hook so it stays untouched. See feedback_animation_remap_rules
-- and feedback_1p_animations_universal memory notes for the full rule.
--
-- When a remap table key looks like a 1P event name (e.g.
-- "attack_swing_charge_stab" — authored for the elf spear's 1P state machine),
-- it's there because the SAME event-name string also fires on the 3P body
-- where the empire-soldier skeleton has no clip for it. The remap value is the
-- 3P-body substitute. The 1P side fires the unmodified event and plays
-- correctly on first_person_base — we don't touch it.
-- ============================================================================

-- 3P body event remapping: player_unit IS the 3P body (receives anim_event_3p).
-- The non-player unit is the 1P hands (receives anim_event) — universal,
-- never remapped here.
-- When a cross-career weapon is equipped, remap attack events on player_unit
-- to the target weapon's anim_event_3p values so proper 3P animations play.

-- Elf spear actions → billhook 3P events (for Saltzpyre wielding elf spear)
local _3p_remap_spear_to_billhook = {
    attack_swing_charge_right    = "attack_swing_charge_left_diagonal",
    attack_swing_charge_left     = "attack_swing_stab_charge",
    attack_swing_down_right      = "attack_swing_stab",
    attack_swing_down_left_axe   = "attack_swing_left_diagonal",
    attack_swing_down_left       = "attack_swing_stab",
    attack_swing_right           = "attack_swing_left_diagonal",
    attack_swing_heavy_right     = "attack_swing_heavy_left_diagonal",
    attack_swing_heavy           = "attack_swing_heavy_stab",
    push_stab                    = "attack_swing_left_diagonal",
    attack_swing_stab_lh         = "attack_swing_stab",
    attack_swing_charge          = "attack_swing_stab_charge",
    attack_swing_charge_stab     = "attack_swing_charge_left_diagonal",
}

-- Polearm/heavy spear → billhook 3P fixes (for Saltzpyre)
-- Only remap events that are MISSING or broken on billhook skeleton.
-- Leave working events alone — elf spear table remaps interfere if shared.
local _3p_remap_polearm_to_billhook = {
    attack_swing_stab_lh         = "attack_swing_stab",
}

-- Elf spear 1P actions → Kruber polearm-compatible 3P events.
-- Only remap events that genuinely crash or don't exist on the
-- polearm skeleton. Let others play natively.
local _3p_remap_spear_to_polearm = {
    attack_swing_down_left_axe   = "attack_swing_down_left",
    attack_swing_left            = "attack_swing_down_left",
}

-- Billhook 1P events → polearm-compatible 3P events.
-- Cross-career equip sends the 1P anim_event (not anim_event_3p) to
-- both units. These billhook-specific events are phantom on the polearm
-- skeleton. Remap lights → lights, heavies → heavies, charges → charges.
local _3p_remap_billhook_to_polearm = {
    -- Heavy 1 (thrust): charge + release
    attack_swing_charge_stab         = "attack_swing_charge_right",
    attack_swing_stab_charge         = "attack_swing_charge_right",
    attack_swing_heavy_stab          = "attack_swing_heavy_right",
    -- Heavy 2 (overhead): charge + release
    attack_swing_charge_down         = "attack_swing_charge",
    attack_swing_charge_left_diagonal = "attack_swing_charge",
    attack_swing_heavy_down          = "attack_swing_heavy",
    attack_swing_heavy_left_diagonal = "attack_swing_heavy",
    -- Lights
    attack_swing_left_diagonal       = "attack_swing_down_left",
    attack_swing_stab                = "attack_swing_right",
    attack_swing_stab_02             = "attack_swing_right",
    attack_swing_heavy_left          = "attack_swing_heavy",
    attack_swing_down                = "attack_swing_down_right",
    push_stab                        = "attack_swing_right",
    attack_swing_left                = "attack_swing_down_left",
}

local _3p_remap_spear_shield_to_deus = {
    attack_swing_stab_lh             = "attack_swing_stab",
}

local _3p_remap_deus_to_spear_shield = {
    attack_swing_up                  = "attack_swing_stab_lh",
}

-- Career-aware remap triggers: event → { career_prefix = remap_table, ... }
-- "_default" key used when no career-specific entry matches.
local _3p_remap_triggers = {
    to_spear = {
        _default = _3p_remap_spear_to_polearm,
        wh_      = _3p_remap_spear_to_billhook,
    },
    to_polearm = {
        _default = _3p_remap_billhook_to_polearm,
        es_      = _3p_remap_spear_to_polearm,
        wh_      = _3p_remap_spear_to_billhook,
    },
    to_2h_billhook = {
        _default = _3p_remap_billhook_to_polearm,
        wh_      = false,
    },
    to_1h_spear_shield = {
        _default = _3p_remap_spear_shield_to_deus,
    },
    to_es_deus_01 = {
        _default = _3p_remap_spear_shield_to_deus,
        we_      = _3p_remap_deus_to_spear_shield,
    },
}

-- CLARIFY: returns either a remap table (truthy) or `false` (a deliberate
-- "no remap" entry like `to_2h_billhook.wh_ = false`). Caller (line ~838)
-- assigns the result to `_3p_weapon_remap` directly — `false` correctly clears
-- any prior remap; only `nil` (no entry at all) preserves the prior state.
local function _resolve_3p_remap(event_name, career)
    local trigger = _3p_remap_triggers[event_name]
    if not trigger then return nil end
    if not career then return trigger._default end
    for prefix, tbl in pairs(trigger) do
        if prefix ~= "_default" and career:sub(1, #prefix) == prefix then
            return tbl
        end
    end
    return trigger._default
end

-- CLARIFY: the currently-active 3P attack remap table for the local player's
-- equipped weapon. Set by either (a) `to_` weapon-switch event triggering
-- a template/key remap lookup [animation_event hook ~L727], or (b) a career
-- redirect that fires `_resolve_3p_remap` [~L838]. Cleared (set to nil) on
-- weapon-switch events whose new template/key differs from `_last_remap_template`.
-- A `false` value (from `_3p_remap_triggers[event].we_ = false` etc.) is a
-- DELIBERATE "no remap, native skeleton handles attacks" marker.
local _3p_weapon_remap = nil

-- Template-based 3P attack remaps: when a cross-career weapon shares a wield
-- event with a different native weapon, attack events may lack valid transitions
-- in the target skeleton's 3P state machine. Remap to compatible events.
-- Key: weapon template name. Value: { career_prefix = remap_table, ... }
-- A nil value for a prefix means no remap needed (native character).
local _3p_template_remaps = {
    two_handed_swords_template_1 = {
        we_ = {
            attack_swing_charge_diagonal       = "attack_swing_charge",
            attack_swing_charge_diagonal_right = "attack_swing_charge",
            attack_swing_charge_diagonal_left  = "attack_swing_charge",
            attack_swing_heavy_left_diagonal   = "attack_swing_left",
            attack_swing_heavy_right_diagonal  = "attack_swing_heavy_right",
            attack_swing_left_diagonal         = "attack_swing_left",
            attack_swing_right_diagonal        = "attack_swing_right",
            attack_swing_down_right            = "attack_swing_heavy",
        },
    },
    two_handed_axes_template_1 = {
        dr_ = false,
        _default = {
            attack_swing_up                   = "attack_swing_left",
            attack_swing_heavy_left_diagonal  = "attack_swing_heavy",
            attack_swing_heavy_right_diagonal = "attack_swing_heavy_right",
        },
    },
    two_handed_swords_wood_elf_template = {
        we_ = false,
        wh_ = {
            attack_swing_charge      = "attack_swing_charge_left_diagonal",
            attack_swing_right       = "attack_swing_right_diagonal",
            attack_swing_left        = "attack_swing_left_diagonal",
            attack_swing_heavy       = "attack_swing_heavy_left_diagonal",
            attack_swing_heavy_right = "attack_swing_heavy_right_diagonal",
        },
        _default = {
            attack_swing_charge      = "attack_swing_charge_left_diagonal",
            attack_swing_left        = "attack_swing_up_left",
            attack_swing_heavy       = "attack_swing_heavy_left_diagonal",
            attack_swing_heavy_right = "attack_swing_heavy_right_diagonal",
        },
    },
    one_hand_falchion_template_1 = {
        wh_ = false,
        dr_ = {
            -- Bardin: differentiate the two heavy variants
            --   left_diagonal (variant A)        → elf H1 (vertical) — charge fires natively
            --   right_diagonal_pose (variant B)  → elf H2 (right swing)
            attack_swing_charge_right_diagonal_pose = "attack_swing_charge_right_pose",
            attack_swing_heavy_left_diagonal        = "attack_swing_heavy_down",
            attack_swing_heavy_right_diagonal       = "attack_swing_heavy_right",
            attack_swing_up                         = "attack_swing_down",
        },
        _default = {
            attack_swing_charge_left_diagonal      = "attack_swing_charge_left",
            attack_swing_charge_right_diagonal_pose = "attack_swing_charge_right_pose",
            attack_swing_charge_left_diagonal_pose  = "attack_swing_charge_left_pose",
            attack_swing_heavy_left_diagonal        = "attack_swing_heavy",
            attack_swing_heavy_right_diagonal       = "attack_swing_heavy_right",
            attack_swing_up                         = "attack_swing_down",
        },
    },
    one_handed_crowbill = {
        bw_ = false,
        dr_ = {
            -- Bardin: H1 and H3 release fires events that produce no visible
            -- animation on his crowbill SM. Use the elf-sword overhead targets.
            attack_swing_stab                = "attack_swing_down",
            attack_swing_up_left             = "attack_swing_left_diagonal",
            attack_swing_charge_left         = "attack_swing_charge_left_diagonal", -- H1 charge windup
            attack_swing_heavy_left_up       = "attack_swing_heavy_down",           -- H1 release overhead
            attack_swing_charge_left_pose    = "attack_swing_charge_left_diagonal", -- H3 charge windup
            attack_swing_heavy_left_diagonal = "attack_swing_heavy_down",           -- H3 release overhead
        },
        _default = {
            -- attack_swing_left fires natively as a right-swing on cross
            -- skeletons (verified via wt force3p on Kruber). Don't remap it —
            -- earlier versions mapped it to attack_swing_down, which collapsed
            -- L2 into L1's vertical and made the first two lights look identical.
            attack_swing_stab          = "attack_swing_down",  -- thrust → vertical (no working thrust event on cross skeleton)
            attack_swing_heavy_left_up = "attack_swing_heavy",
            attack_swing_heavy_left_diagonal = "attack_swing_heavy",
            attack_swing_up_left       = "attack_swing_left_diagonal",
        },
    },
    -- one_handed_flails_flaming_template: no template-level remaps. H1
    -- (attack_swing_charge_down → attack_swing_heavy_down) fires natively as
    -- the correct overhead. H2's broken release (attack_swing_heavy_left) is
    -- handled by the direct-redirect block in the animation_event hook —
    -- table-remap of that event corrupts the SM (same pattern as billhook
    -- attack_swing_stab_02).
    -- Bardin's dual axes on non-Slayer careers. The wield event redirect
    -- (to_dual_axes → to_dual_hammers) loads the dual-hammers SM, but the
    -- dual_wield_axes template fires several attack events the dual-hammers
    -- SM doesn't define. Map them to dual-hammers anim_events that play.
    -- Per-career entries (dr_ironbreaker / dr_ranger / dr_engineer); dr_slayer
    -- has no entry so _resolve_template_remap returns nil → native plays.
    dual_wield_axes_template_1 = (function()
        -- Spread dual-axe lights across the 5 distinct dual_hammers light
        -- anim_events (left, down, left_diagonal, up, stab) so each chain
        -- position plays a unique animation. dual_axes L1's native release
        -- (attack_swing_left_diagonal) already plays as dual_hammers L3 swing,
        -- so leave it alone; remap the other 4 light releases onto the
        -- remaining 4 dual_hammers light anim_events.
        local t = {
            attack_swing_charge_diagonal = "attack_swing_charge_left",   -- L3 / H3 charge windup
            attack_swing_heavy_right     = "attack_swing_heavy_right_diagonal", -- H1 release
            attack_swing_heavy           = "attack_swing_heavy_down",    -- H2 release
            -- Lights (each maps to a different dual_hammers light):
            attack_swing_right_diagonal  = "attack_swing_left",          -- L2 release → dual_hammers L1
            attack_swing_left            = "attack_swing_down",          -- L3 release → dual_hammers L2
            attack_swing_right           = "attack_swing_up",            -- L4 release → dual_hammers L4
            attack_swing_down            = "attack_swing_stab",          -- L5 release → dual_hammers L5
            -- L1 native (attack_swing_left_diagonal) plays dual_hammers L3 swing
        }
        return { dr_ironbreaker = t, dr_ranger = t, dr_engineer = t }
    end)(),
}

local function _resolve_template_remap(template_name, career)
    local entry = _3p_template_remaps[template_name]
    if not entry then return nil end
    if career then
        for prefix, tbl in pairs(entry) do
            if prefix ~= "_default" and career:sub(1, #prefix) == prefix then
                return tbl
            end
        end
    end
    return entry._default
end

local _3p_key_remaps = {
    we_1h_sword = {
        we_ = false,
        _default = {
            attack_swing_stab          = "attack_swing_down",                 -- L4 stab → vertical
            attack_swing_charge_down   = "attack_swing_charge_left_diagonal", -- H1 charge windup (also L1 charge gains a windup)
            attack_swing_charge_left   = "attack_swing_charge_right_pose",    -- H2 charge windup
            attack_swing_heavy_left_up = "attack_swing_heavy_right",          -- H2 release → heavy right swing
            attack_swing_charge_right_diagonal_pose = "attack_swing_charge_left_diagonal", -- H3 charge → vertical (matches H1; also affects L2 charge — windup pose only, brief)
            attack_swing_heavy_down_right = "attack_swing_heavy_down",        -- H3 release → vertical (was horizontal)
        },
    },
    bw_sword = {
        dr_ = {
            -- 3-position heavy chain. Differentiate variants:
            --   H1 from idle (charge_left/heavy)            → elf H2 (right swing)
            --   H2 (charge_right_pose/heavy_right)          → elf H1 (vertical heavy)
            --   H3+ (charge_left_pose/heavy) — release is the same event as H1
            --   so it inherits the right-swing; charge gets right-pose windup to match.
            attack_swing_charge_left       = "attack_swing_charge_right_pose",
            attack_swing_heavy             = "attack_swing_heavy_right",
            attack_swing_charge_right_pose = "attack_swing_charge_left_diagonal",
            attack_swing_heavy_right       = "attack_swing_heavy_down",
            attack_swing_charge_left_pose  = "attack_swing_charge_right_pose", -- H3+ chain windup matches right swing
        },
    },
    es_1h_sword = {
        -- one_handed_swords_template_1 (shared with bw_sword) — same heavy chain.
        dr_ = {
            attack_swing_charge_left       = "attack_swing_charge_right_pose",
            attack_swing_heavy             = "attack_swing_heavy_right",
            attack_swing_charge_right_pose = "attack_swing_charge_left_diagonal",
            attack_swing_heavy_right       = "attack_swing_heavy_down",
            attack_swing_charge_left_pose  = "attack_swing_charge_right_pose", -- H3+ chain windup matches right swing
        },
    },
}

local function _resolve_key_remap(weapon_key, career)
    local entry = _3p_key_remaps[weapon_key]
    if not entry then return nil end
    if career then
        for prefix, tbl in pairs(entry) do
            if prefix ~= "_default" and career:sub(1, #prefix) == prefix then
                return tbl
            end
        end
    end
    return entry._default
end

-- CLARIFY: tracks the local player's equipped weapon. Updated in the
-- SimpleInventoryExtension.wield hook (~L905). Used to:
--   - select correct template/key remap on weapon-switch (~L727)
--   - scope the flail direct-redirect block (~L765, only fires for the
--     currently-equipped flail key)
--   - detect actual weapon switches vs. re-fired `to_` events (~L727)
local _current_weapon_template = nil
local _current_weapon_key = nil
-- CLARIFY: snapshot of `remap_id` (template or key) at the moment a `to_` event
-- caused us to evaluate remaps. Used to skip the clear-and-reset block when a
-- non-weapon `to_` event fires (e.g. `to_crouch`, `to_zoom`) — those don't
-- change `_current_weapon_template/_key`, so `remap_id` matches and we skip.
local _last_remap_template = nil

local _log_anims = false
local _last_3p_unit = nil
-- CLARIFY: captured in the wield hook from `self._first_person_unit`. Used
-- ONLY to distinguish the local 1P hands unit (which should NOT receive
-- redirects) from husks (which should). Cannot use `is_local` for this —
-- the 1P unit has `is_local=false` same as husks (see feedback_animation_remap_rules).
local _local_fp_unit = nil
-- CLARIFY: stashed reference to the original `Unit.animation_event` so we can
-- bypass our own hook for force-fire events that corrupt the SM when going
-- through the remap-table path (e.g. attack_swing_stab_02 on billhook).
local _original_animation_event = nil
local _animlog_last_was_attack = false

mod:command("status", "Show current weapon tweaker state", function()
    mod:echo("Weapon Tweaker v" .. MOD_VERSION)
    local career = _local_career_name()
    mod:echo("Career: " .. (career or "unknown"))
    local remap_name = "none"
    if _3p_weapon_remap then
        if _3p_weapon_remap == _3p_remap_spear_to_billhook then remap_name = "spear→billhook"
        elseif _3p_weapon_remap == _3p_remap_polearm_to_billhook then remap_name = "polearm→billhook"
        elseif _3p_weapon_remap == _3p_remap_spear_to_polearm then remap_name = "spear→polearm"
        elseif _3p_weapon_remap == _3p_remap_billhook_to_polearm then remap_name = "billhook→polearm"
        else remap_name = "custom" end
    end
    mod:echo("3P Remap: " .. remap_name)
    mod:echo("Anim log: " .. (_log_anims and "ON" or "OFF"))
    if career then
        local weapons = weapon_unlock_map[career]
        if weapons then
            local enabled = 0
            for _, wk in ipairs(weapons) do
                if mod:get("unlock_" .. career .. "_" .. wk) then enabled = enabled + 1 end
            end
            mod:echo("Weapons: " .. enabled .. "/" .. #weapons .. " enabled")
        end
    end
end)

mod:command("animlog", "Toggle animation event logging", function()
    _log_anims = not _log_anims
    mod:echo("Animation logging: " .. (_log_anims and "ON" or "OFF"))
end)

mod:command("force3p", "Force a 3P animation event on local player (usage: wt force3p attack_swing_stab)", function(event)
    -- CLARIFY: targets `player.player_unit` which is actually the 3P body
    -- (see CLAUDE.md "Animation Remapping"). Bypasses our own hook by calling
    -- `_original_animation_event` directly so the test isn't muddied by remap
    -- redirects — used to verify which raw events animate visibly on the
    -- currently-loaded weapon SM (per feedback_animation_remap_rules:
    -- has_animation_event TRUE does not guarantee visible playback).
    if not event then mod:echo("Usage: wt force3p <event_name>") return end
    local player = Managers.player:local_player(1)
    if not player or not player.player_unit then mod:echo("No local player unit") return end
    local unit = player.player_unit
    local ok_h, has = pcall(Unit.has_animation_event, unit, event)
    has = ok_h and has
    mod:echo("force3p: " .. event .. " (exists=" .. tostring(has) .. ")")
    if has then
        if _original_animation_event then
            pcall(_original_animation_event, unit, event)
        else
            pcall(Unit.animation_event, unit, event)
        end
        mod:echo("  -> fired on player_unit")
    else
        mod:echo("  -> event not found on player_unit")
    end
end)

mod:command("force1p", "Force a 1P animation event on local player's first-person unit (usage: wt force1p attack_swing_stab)", function(event)
    -- Mirror of force3p but targets the 1P hands unit captured in the wield
    -- hook. Used to probe whether the currently-wielded weapon's 1P SM has a
    -- visible animation for an event that's not referenced by the template
    -- (e.g. searching for a hidden stab on bastard_sword).
    if not event then mod:echo("Usage: wt force1p <event_name>") return end
    if not _local_fp_unit then mod:echo("No 1P unit captured (wield a weapon first)") return end
    local unit = _local_fp_unit
    local ok_h, has = pcall(Unit.has_animation_event, unit, event)
    has = ok_h and has
    mod:echo("force1p: " .. event .. " (exists=" .. tostring(has) .. ")")
    if has then
        if _original_animation_event then
            pcall(_original_animation_event, unit, event)
        else
            pcall(Unit.animation_event, unit, event)
        end
        mod:echo("  -> fired on first_person_unit")
    else
        mod:echo("  -> event not found on first_person_unit")
    end
end)

-- Keys are profile/character names. Warrior Priest (wh_priest career) shares
-- the witch_hunter profile but uses a distinct 3P skeleton, so it's listed
-- separately under its own key for `wt sm_probe`. Note: "way_watcher" is the
-- path for `we_` careers — VT2's source uses this naming.
local _3p_state_machine_paths = {
    empire_soldier            = "units/beings/player/third_person_base/empire_soldier/chr_third_person_base",
    witch_hunter              = "units/beings/player/third_person_base/witch_hunter/chr_third_person_base",
    witch_hunter_warrior_priest = "units/beings/player/third_person_base/witch_hunter_warrior_priest/chr_third_person_base",
    bright_wizard             = "units/beings/player/third_person_base/bright_wizard/chr_third_person_base",
    dwarf_ranger              = "units/beings/player/third_person_base/dwarf_ranger/chr_third_person_base",
    wood_elf                  = "units/beings/player/third_person_base/way_watcher/chr_third_person_base",
}

mod:command("sm_probe", "Probe what 3P state machine resources exist for all characters", function()
    local pm = Managers.player
    local player = pm and pm:local_player()
    if not player or not player.player_unit then
        mod:echo("No player unit")
        return
    end
    local unit_3p = player.player_unit
    local pkg = Managers.package

    local function log(msg)
        mod:echo(msg)
        mod:info("[PROBE] %s", msg)
    end

    for name, path in pairs(_3p_state_machine_paths) do
        local loaded = "?"
        if pkg then
            local ok_c, val = pcall(function() return pkg:has_loaded(path, "global") end)
            if ok_c then loaded = tostring(val)
            else loaded = "err" end
        end
        log(string.format("  %-16s loaded=%s", name, loaded))
    end

    local ok_sm, has_sm = pcall(Unit.has_animation_state_machine, unit_3p)
    log("3P has_animation_state_machine: " .. (ok_sm and tostring(has_sm) or "err"))

    local test_events = {
        "to_2h_sword", "to_2h_sword_we", "to_bastard_sword", "to_spear", "to_polearm",
        "to_1h_sword", "to_1h_hammer", "to_2h_billhook", "to_longbow", "to_es_longbow",
        "to_1h_sword_shield", "to_1h_hammer_shield", "to_dual_wield", "to_2h_hammer",
        "to_2h_axe", "to_1h_axe", "to_1h_falchion", "to_1h_flail", "to_crossbow",
        "to_repeating_crossbow", "to_handgun", "to_blunderbuss",
        "attack_swing_right", "attack_swing_left", "attack_swing_down",
        "attack_swing_up_left", "attack_swing_down_left", "attack_swing_down_right",
        "attack_swing_heavy", "attack_swing_heavy_right", "attack_swing_heavy_left",
        "attack_swing_heavy_down", "attack_swing_heavy_left_diagonal",
        "attack_swing_heavy_right_diagonal",
        "attack_swing_charge", "attack_swing_charge_left", "attack_swing_charge_right",
        "attack_swing_charge_left_diagonal", "attack_swing_charge_right_diagonal_pose",
        "attack_swing_charge_down_pose", "attack_swing_charge_left_diagonal_pose",
        "attack_swing_charge_stab", "attack_swing_charge_down",
        "attack_swing_stab", "attack_swing_stab_02", "attack_swing_stab_lh",
        "attack_swing_left_diagonal", "attack_swing_down_left_axe",
        "attack_push", "push_stab", "parry_pose",
    }
    log("Events on 3P unit:")
    for _, ev in ipairs(test_events) do
        local ok_e, has = pcall(Unit.has_animation_event, unit_3p, ev)
        if ok_e and has then
            log(string.format("  %-40s TRUE", ev))
        else
            log(string.format("  %-40s false", ev))
        end
    end
end)


local function _is_local_player_unit(unit)
    local pm = Managers.player
    if not pm then return false end
    local ok, player = pcall(pm.local_player, pm)
    if not ok or not player then return false end
    return player.player_unit == unit
end

-- Returns the career name of the player who owns this unit (local or husk).
-- nil for non-player units. Use for per-unit redirect decisions so husks of
-- other players get routed by THEIR career, not the local viewer's.
local function _unit_career_name(unit)
    if not unit then return nil end
    -- Primary: read from the inventory_system extension on the unit itself.
    -- SimpleInventoryExtension.init sets self._career_name BEFORE
    -- extensions_ready fires, and our GearUtils.spawn_inventory_unit hook
    -- is called from within add_equipment (invoked from extensions_ready).
    -- So this field is reliably populated at hook time — including the
    -- fresh-mission-spawn case where Managers.player:owner(unit) returns
    -- nil because the player-to-unit reverse association hasn't been
    -- re-pointed yet to the newly-spawned mission player_unit. See
    -- feedback_vt2_mission_spawn_career_lookup.
    local ok_ext, ext = pcall(ScriptUnit.has_extension, unit, "inventory_system")
    if ok_ext and ext and ext._career_name then return ext._career_name end
    -- Fallback: Managers.player path (post-spawn / husk lookups).
    local pm = Managers.player
    if not pm then return nil end
    local ok, player = pcall(pm.owner, pm, unit)
    if not ok or not player then return nil end
    local ok2, name = pcall(player.career_name, player)
    if ok2 and name then return name end
    local ok3, prof_idx = pcall(player.profile_index, player)
    local ok4, career_idx = pcall(player.career_index, player)
    if ok3 and ok4 and SPProfiles and prof_idx and career_idx then
        local prof = SPProfiles[prof_idx]
        local c = prof and prof.careers and prof.careers[career_idx]
        if c and c.name then return c.name end
    end
    return nil
end

-- CLARIFY: stringified hook on the C-API class `Unit`. VMF resolves this
-- against `_G.Unit.animation_event`. This is the central entry point — every
-- animation event for every unit goes through here once the mod is loaded,
-- so cheap early-exits matter for performance.
mod:hook("Unit", "animation_event", function(func, unit, event_name, ...)
    -- CLARIFY: capture the underlying function the FIRST time we're called so
    -- force-fire paths (force3p command, billhook stab_02 force-target) can
    -- bypass our own hook recursively without infinite loop.
    if not _original_animation_event then _original_animation_event = func end

    if not event_name then return func(unit, event_name, ...) end

    if not feature_enabled("enable_weapon_animation_redirects", true) then
        return func(unit, event_name, ...)
    end

    local is_local = _is_local_player_unit(unit)
    if not is_local then _last_3p_unit = unit end
    local career = _local_career_name()

    local _al_tag = nil
    if _log_anims then
        local is_fp = _local_fp_unit and unit == _local_fp_unit
        _al_tag = is_fp and "1P" or (is_local and "3P-body" or "3P-husk")
        local is_combat = event_name:sub(1, 7) == "attack_" or event_name:sub(1, 5) == "push_" or event_name:sub(1, 3) == "to_" or event_name:sub(1, 6) == "parry_"
        local exists = _safe_has_anim(unit, event_name)
        local suffix = exists and "" or " [MISSING]"
        if is_combat then
            if not _animlog_last_was_attack then
                local hdr = "--- [template: " .. tostring(_current_weapon_template) .. "] [key: " .. tostring(_current_weapon_key) .. "] [career: " .. tostring(career) .. "] ---"
                mod:info(hdr)
                mod:echo("--- " .. tostring(_current_weapon_key or _current_weapon_template) .. " ---")
            end
            _animlog_last_was_attack = true
            local msg = _al_tag .. " " .. event_name .. suffix
            mod:info(msg)
            mod:echo(msg)
        else
            _animlog_last_was_attack = false
            mod:info("[animlog] " .. _al_tag .. " " .. event_name .. suffix)
        end
    end

    -- Reset 3P weapon remap only on actual weapon change (not re-wield or nil template from block/ability)
    -- CLARIFY: this is the whitelist-by-template-change pattern from
    -- DEVELOPMENT.md "Non-Weapon `to_` Events". Non-weapon `to_` events
    -- (`to_crouch`, `to_zoom`, `to_onground`) don't change
    -- `_current_weapon_template`/`_key`, so `remap_id == _last_remap_template`
    -- and we skip the clear. Only true weapon switches (which update those
    -- via the wield hook ~L905) reach the clear-and-reset block.
    local remap_id = _current_weapon_template or _current_weapon_key
    if is_local and event_name:sub(1, 3) == "to_" and remap_id and remap_id ~= _last_remap_template then
        _last_remap_template = remap_id
        _3p_weapon_remap = nil
        if _current_weapon_template then
            local tmpl_remap = _resolve_template_remap(_current_weapon_template, career)
            if tmpl_remap then _3p_weapon_remap = tmpl_remap end
        end
        if not _3p_weapon_remap and _current_weapon_key then
            local key_remap = _resolve_key_remap(_current_weapon_key, career)
            if key_remap then _3p_weapon_remap = key_remap end
        end
        -- QUESTION: `tmpl_remap` and `key_remap` may be `false` (deliberate
        -- skip from `_3p_template_remaps[name][prefix] = false`). The chain
        -- `if tmpl_remap then` correctly treats false as "not found" and
        -- falls through to key_remap. Final `_3p_weapon_remap` ends up
        -- nil if both were false — desired (native skeleton handles it).
    end

    -- 1P first_person_unit must never get redirects — 1P animations work by default
    -- CLARIFY: see feedback_animation_remap_rules — 1P unit has is_local=false
    -- (same as husks), so we MUST identify it by its captured ref, not by
    -- is_local. v0.9.69 crashed when is_local was used to protect 1P because
    -- it ALSO skipped redirects on the 3P body.
    if _local_fp_unit and unit == _local_fp_unit then
        return func(unit, event_name, ...)
    end

    -- Flails on non-native careers: certain release events either play the wrong
    -- animation or play nothing on the cross-career 3P body, even though
    -- has_animation_event reports them TRUE. attack_swing_heavy is the only
    -- event that produces a visible heavy strike on both flails. We can't use
    -- the remap table — adding these events to it corrupts the SM chain (same
    -- pattern as billhook attack_swing_stab_02). Direct func() call works.
    --
    -- Scope: ONLY the local player_unit. _current_weapon_key tracks the local
    -- player's weapon; we have no signal for other players' weapons, and these
    -- event names also fire for light/heavy chains on non-flail weapons — so
    -- applying this to husks would hijack legitimate attacks. Cross-career flail
    -- on remote players' husks therefore still looks broken to the local viewer.
    if is_local then
        local target = nil
        local unit_career = _unit_career_name(unit)
        if unit_career then
            if _current_weapon_key == "es_1h_flail" then
                if unit_career:sub(1, 3) ~= "wh_" then
                    -- Saltzpyre's flail on non-Saltzpyre. H1 release fires
                    -- attack_swing_left (light name → wrong anim), H2 release
                    -- fires attack_swing_heavy_left (plays nothing on the
                    -- cross skeleton).
                    if event_name == "attack_swing_left"
                        or event_name == "attack_swing_heavy_left" then
                        target = "attack_swing_heavy"
                    end
                else
                    -- Saltzpyre native: push-attack release fires
                    -- attack_swing_right but doesn't visibly animate (vanilla
                    -- SM bug — confirmed via wt force3p from idle).
                    -- attack_swing_right_diagonal plays a visible L2-style
                    -- swing on Saltzpyre's flail SM, best stand-in.
                    if event_name == "attack_swing_right" then
                        target = "attack_swing_right_diagonal"
                    end
                end
            elseif _current_weapon_key == "bw_1h_flail_flaming"
                and unit_career:sub(1, 3) ~= "bw_" then
                -- Sienna's flaming flail on non-Sienna. H1 release
                -- (attack_swing_heavy_down) fires natively as the correct
                -- overhead — DO NOT touch it. Only H2 (attack_swing_heavy_left)
                -- is broken and needs the redirect.
                if event_name == "attack_swing_heavy_left" then
                    target = "attack_swing_heavy"
                end
            end
        end
        if target then
            return func(unit, target, ...)
        end
    end

    -- 3P attack remap
    -- CLARIFY: applies to BOTH the local 3P body (player_unit) AND husks of
    -- other players. We can't easily distinguish them past the fp early-return
    -- above, but for cross-career remaps the fix is the same on both
    -- (husks need the same remap to look correct from the local viewer).
    if _3p_weapon_remap then
        local target = _3p_weapon_remap[event_name]
        if target and _safe_has_anim(unit, target) then
            if _log_anims then
                local msg = "  REMAP " .. event_name .. " -> " .. target
                mod:info(msg)
                mod:echo(msg)
            end
            pcall(func, unit, target, ...)
            return
        end
        -- CLARIFY: force-fire path for SM-corrupting events (see
        -- feedback_animation_remap_rules). Adding `attack_swing_stab_02 ->
        -- attack_swing_left_diagonal` to the remap table broke ALL animations
        -- on the billhook SM (v0.9.43); calling _original_animation_event
        -- directly with the same target works. Block is GUARDED to only fire
        -- when the spear-to-billhook remap is active (v0.9.56 — without this
        -- guard, the billhook force-fires hijacked Kruber's spear+shield H1/H2).
        local force_target = nil
        if _3p_weapon_remap == _3p_remap_spear_to_billhook then
            if event_name == "attack_swing_stab_02" then
                force_target = "attack_swing_left_diagonal"
            elseif event_name == "attack_swing_heavy_left" then
                force_target = "attack_swing_heavy_stab"
            elseif event_name == "attack_swing_heavy_stab" then
                force_target = "attack_swing_heavy_left_diagonal"
            end
        end
        if force_target and _original_animation_event and _safe_has_anim(unit, force_target) then
            if _log_anims then
                local msg = "  FORCE " .. event_name .. " -> " .. force_target
                mod:info(msg)
                mod:echo(msg)
            end
            pcall(_original_animation_event, unit, force_target)
            return
        end
    end

    -- Career-aware redirects: phantom events exist on all skeletons but only play
    -- real animations on the correct character. Redirect by career prefix.
    local career_redir = _career_anim_redirect[event_name]
    if career_redir then
        if career_redir.overrides and career and career_redir.overrides[career] then
            local target = career_redir.overrides[career]
            if _safe_has_anim(unit, target) then
                local remap = _resolve_3p_remap(event_name, career)
                if remap then _3p_weapon_remap = remap end
                if _log_anims then
                    local msg = "  REDIR " .. event_name .. " -> " .. target
                    mod:info(msg)
                    mod:echo(msg)
                end
                pcall(func, unit, target, ...)
                return
            elseif _log_anims then
                mod:info("  REDIR FAIL: " .. target .. " not on unit")
            end
        end
        local matches_prefix = career and career:sub(1, #career_redir.prefix) == career_redir.prefix
        local should_redirect = career_redir.invert and matches_prefix or (not career_redir.invert and not matches_prefix)
        if should_redirect then
            if _safe_has_anim(unit, career_redir.alt) then
                local remap = _resolve_3p_remap(event_name, career)
                if remap then _3p_weapon_remap = remap end
                if _log_anims then
                    local msg = "  REDIR " .. event_name .. " -> " .. career_redir.alt
                    mod:info(msg)
                    mod:echo(msg)
                end
                pcall(func, unit, career_redir.alt, ...)
                return
            elseif _log_anims then
                mod:info("  REDIR FAIL: " .. career_redir.alt .. " not on unit")
            end
        end
        pcall(func, unit, event_name, ...)
        return
    end

    -- Standard redirect: only fire if original event is missing from skeleton.
    local alt = _anim_redirect[event_name]
    if alt then
        if _safe_has_anim(unit, event_name) then
            return func(unit, event_name, ...)
        end
        if _safe_has_anim(unit, alt) then
            pcall(func, unit, alt, ...)
            return
        end
    end

    -- Suffix-based redirect: swap weapon suffix based on career.
    if career then
        local target = _try_suffix_redirect(unit, event_name, career)
        if target then
            if _log_anims then mod:info("  SUFFIX -> " .. target) end
            pcall(func, unit, target, ...)
            return
        end
    end

    pcall(func, unit, event_name, ...)
end)

-- CLARIFY: wield runs on EVERY inventory's wield call, including bot/ally
-- husks. The `self._unit == player.player_unit` check filters to only the
-- local player so `_local_fp_unit`, `_current_weapon_template`, and
-- `_current_weapon_key` reflect the local player's state. Husks therefore
-- never update these — meaning the flail direct-redirect block (~L765) and
-- the template/key remap selection (~L727) are correctly scoped to local.
mod:hook("SimpleInventoryExtension", "wield", function(func, self, slot_name, ...)
    local ok, pm = pcall(function() return Managers.player end)
    if ok and pm then
        local player = pm:local_player()
        if player and self._unit == player.player_unit then
            _local_fp_unit = self._first_person_unit
            local equipment = self._equipment or self.equipment
            local slots = equipment and equipment.slots
            local slot_data = slots and slots[slot_name]
            local item_data = slot_data and slot_data.item_data
            _current_weapon_template = item_data and item_data.template
            _current_weapon_key = item_data and item_data.key
            if _log_anims then
                mod:info("[WIELD] slot=" .. tostring(slot_name) .. " template=" .. tostring(_current_weapon_template) .. " key=" .. tostring(_current_weapon_key))
                if item_data then
                    for k, v in pairs(item_data) do
                        if type(v) == "string" or type(v) == "number" or type(v) == "boolean" then
                            mod:info("[WIELD]   " .. tostring(k) .. " = " .. tostring(v))
                        end
                    end
                else
                    mod:info("[WIELD] item_data is nil, slot_data=" .. tostring(slot_data))
                end
            end
        end
    end
    return func(self, slot_name, ...)
end)

-- ============================================================
-- Weapon Scale Overrides
-- ============================================================
-- Scale factors for cross-character weapons that look too small/large.
-- Keys: weapon_key. Values: table of career_prefix -> scale factor.
-- A weapon only gets scaled when equipped on a career matching one of
-- the listed prefixes. Native-character entries are omitted (scale 1.0).
--
-- IMPORTANT: scale (and grip offset, see below) applies via TWO separate code
-- paths and BOTH must work for full visual consistency:
--   1. In-game keep / mission body: applied via the GearUtils.create_equipment
--      hook on the slot_data result (left/right_unit_1p/3p fields).
--   2. Inventory character preview (post-WoM new menu): applied via the
--      MenuWorldPreviewer hooks. The previewer spawns its OWN units that are
--      NOT the same instances as the in-game ones — modifying the in-game
--      units doesn't affect the preview. The previewer:
--        - exposes the weapon KEY only at equip_item(item_key, slot, backend_id)
--        - exposes the SPAWNED UNIT only at _spawn_item_unit(unit, slot_type, item_template, ...)
--          where item_template is the weapon TEMPLATE table (e.g. we_one_hand_axe_template),
--          not the inventory item — its .name is the template name, NOT the weapon key.
--      We therefore capture the weapon key in equip_item (per-previewer, weak-keyed
--      so dismissed previewers don't leak) and look it up in _spawn_item_unit by
--      slot_type ("melee"/"ranged"/"hat" — strip "slot_" prefix from the equip_item
--      slot.name to match).
-- When adding new scale or grip-offset entries, no extra code is needed — both
-- paths share the same _scale_weapon_units / _offset_weapon_units helpers and
-- look up the same _weapon_scale_overrides / _weapon_grip_offsets tables.

-- Scale overrides: value is a number (uniform) or {x,y,z} table (per-axis).
local _weapon_scale_overrides = {
    we_1h_sword    = { es_ = 1.15, wh_ = 1.15, dr_ = 1.10 },
    bw_sword       = { es_ = 1.15, wh_ = 1.15, dr_ = 1.10 },
    bw_1h_crowbill = { es_ = 1.10, wh_ = 1.10, dr_ = 1.05 },
    we_2h_sword    = { es_ = 1.15 },
    dr_2h_axe      = { es_ = {1, 1.15, 1}, wh_ = {1, 1.15, 1}, we_ = {1, 1.15, 1}, bw_ = {1, 1.15, 1} },
    dr_1h_axe      = { we_ = {0.85, 0.85, 1} },
    dr_1h_hammer   = { we_ = {0.85, 0.85, 1} },
}

local _scale_field_probe_logged = {}
local function _scale_weapon_units(slot_data, weapon_key, career_name)
    if not weapon_key or not career_name then return end

    local overrides = _weapon_scale_overrides[weapon_key]
    if not overrides then return end

    -- One-time probe: dump the slot_data fields the first time we scale this
    -- weapon. Helps identify any unit fields the menu preview uses that we're
    -- missing in the unit_fields list.
    if not _scale_field_probe_logged[weapon_key] then
        _scale_field_probe_logged[weapon_key] = true
        for k, v in pairs(slot_data) do
            local t = type(v)
            if t == "userdata" then
                mod:info("[scale_probe] %s slot_data.%s (UNIT)", weapon_key, tostring(k))
            elseif t == "table" then
                mod:info("[scale_probe] %s slot_data.%s (table)", weapon_key, tostring(k))
            end
        end
    end

    local scale_factor = nil
    for prefix, factor in pairs(overrides) do
        if career_name:sub(1, #prefix) == prefix then
            scale_factor = factor
            break
        end
    end
    if not scale_factor then return end

    local scale
    if type(scale_factor) == "table" then
        scale = Vector3(scale_factor[1], scale_factor[2], scale_factor[3])
    else
        scale = Vector3(scale_factor, scale_factor, scale_factor)
    end
    -- CLARIFY: scale all four hand units identically. Unlike grip offset (which
    -- has a `hand` field for shield-only/weapon-only scaling), scale always
    -- applies to both hands — there's no entry in `_weapon_scale_overrides`
    -- that scales only one hand, but if there were, the schema doesn't support
    -- it (no `_fields` like cosmetics_tweaker has).
    local unit_fields = { "left_unit_1p", "right_unit_1p", "left_unit_3p", "right_unit_3p" }
    for _, field in ipairs(unit_fields) do
        local unit = slot_data[field]
        if unit then
            pcall(Unit.set_local_scale, unit, 0, scale)
        end
    end
    if type(scale_factor) == "table" then
        mod:info("Scaled %s on %s by {%.2f, %.2f, %.2f}", weapon_key, career_name, scale_factor[1], scale_factor[2], scale_factor[3])
    else
        mod:info("Scaled %s on %s by %.2fx", weapon_key, career_name, scale_factor)
    end
end

-- Grip offset: shift weapon along its local axes to adjust hand position.
-- Values are {x, y, z} in the weapon's local space. +z = grip lower on weapon.
-- Optional `hand` field: "right" or "left" restricts to one hand (default both).
-- Same dual-path note as scale (above): in-game and menu preview both apply
-- via the same helper.
local _weapon_grip_offsets = {
    we_1h_sword    = { dr_ = {0, 0, 0.05} },
    bw_sword       = { dr_ = {0, 0, 0.05} },
    es_1h_sword    = { dr_ = {0, 0, 0.05} },
    wh_dual_hammer = { dr_ = {0, 0, 0.15} },
    wh_1h_hammer   = { es_ = {0, 0, 0.15} },
    wh_hammer_shield = { es_ = {0, 0, 0.15, hand = "right"} },
    es_2h_sword    = { we_ = {0, 0, -0.085} },
    wh_2h_sword    = { we_ = {0, 0, -0.085} },
}

local function _offset_weapon_units(slot_data, weapon_key, career_name)
    if not weapon_key or not career_name then return end

    local overrides = _weapon_grip_offsets[weapon_key]
    if not overrides then return end

    local offset = nil
    for prefix, off in pairs(overrides) do
        if career_name:sub(1, #prefix) == prefix then
            offset = off
            break
        end
    end
    if not offset then return end

    local pos = Vector3(offset[1], offset[2], offset[3])
    local hand = offset.hand
    local unit_fields
    if hand == "right" then
        unit_fields = { "right_unit_1p", "right_unit_3p" }
    elseif hand == "left" then
        unit_fields = { "left_unit_1p", "left_unit_3p" }
    else
        unit_fields = { "left_unit_1p", "right_unit_1p", "left_unit_3p", "right_unit_3p" }
    end
    for _, field in ipairs(unit_fields) do
        local unit = slot_data[field]
        if unit then
            -- POTENTIAL BUG (LOW): `Unit.local_position` is NOT pcall-wrapped
            -- (only set_local_position is). If `unit` is invalid/destroyed
            -- between the `if unit then` check and this line, this crashes
            -- the whole hook. Same wrap pattern as scale would be safer.
            -- POTENTIAL BUG (LOW): if create_equipment fires multiple times for
            -- the same unit instance (e.g. weapon swap that re-wields the same
            -- key), the offset compounds (current = previous_offset_position).
            -- Vanilla units start at zero local_position so the first apply
            -- is correct; subsequent applies double up. Not currently a known
            -- issue because spawning re-creates the unit instance.
            local current = Unit.local_position(unit, 0)
            pcall(Unit.set_local_position, unit, 0, current + pos)
        end
    end
    mod:info("Offset %s on %s by {%.3f, %.3f, %.3f} (hand=%s)", weapon_key, career_name, offset[1], offset[2], offset[3], tostring(hand or "both"))
end

-- INVESTIGATION: CW crash on ghost scythe 3P spawn (crashify://77917479-d053-4d34-b6b9-629878a7e6ec).
-- Unit hash 877616b4d5c71f36 = wpn_bw_ghost_scythe_01_3p (base/Necromancer variant). Unchained
-- should resolve to _fire_3p via right_hand_unit_override, so the base variant being requested
-- implies career_name was nil at spawn time. All vanilla code paths look correct; suspected
-- timing issue during CW level transitions where bot career data isn't resolved yet.
-- pcall guard prevents hard crash; diagnostic logging captures the actual state for next repro.
-- Rendering-path coverage: this is path 1 (in-game). Path 2 (HeroPreviewer)
-- is hooked at ~L1303. Path 3 (LootItemUnitPreviewer) is intentionally NOT
-- covered — weapon_tweaker shows un-offset weapons in the illusion browser
-- per feedback_grip_offset_sign.md. CWV covers all three.
mod:hook("GearUtils", "create_equipment", function(func, world, slot_name, item_data, unit_1p, unit_3p, is_bot, unit_template, extra_extension_data, ammo_percent, override_item_template, override_item_units, career_name)
    local ok, result = pcall(func, world, slot_name, item_data, unit_1p, unit_3p, is_bot, unit_template, extra_extension_data, ammo_percent, override_item_template, override_item_units, career_name)
    if not ok then
        local weapon_key = item_data and item_data.name or "unknown"
        local has_override = item_data and item_data.right_hand_unit_override and "yes" or "no"
        local rhu = item_data and item_data.right_hand_unit or "nil"
        mod:error("create_equipment CRASHED: weapon=%s slot=%s career=%s is_bot=%s rhu=%s has_override=%s err=%s",
            tostring(weapon_key), tostring(slot_name), tostring(career_name),
            tostring(is_bot), tostring(rhu), has_override, tostring(result))
        return nil
    end
    if result and item_data then
        local weapon_key = item_data.name
        _scale_weapon_units(result, weapon_key, career_name)
        _offset_weapon_units(result, weapon_key, career_name)
    end
    return result
end)

-- ============================================================
-- Brace of Pistols on Kruber → 3P unit swap to repeating handgun
-- ============================================================
-- Migrated from character_weapon_variants v0.1.187 (CWV's
-- `cwv_es_brace_repeater` variant + `_cwv_3p_unit_override_swap` hook).
-- WT exposes `wh_brace_of_pistols` to all 4 Kruber careers via the
-- unlock map at the top of this file. When Kruber actually equips it,
-- this hook swaps the 3P body unit from the brace pistol mesh to the
-- Empire repeating handgun mesh. The 1P side stays as the brace
-- (cross-arm fire animation is what makes it visually distinct).
--
-- Anim plumbing:
--   * `_BRACE_REPEATER_BASE_WIELD_3P` patches the base brace template's
--     `wield_anim_career_3p` for Kruber → `to_repeating_handgun` (Kruber's
--     vanilla repeater wield SM, authored on his empire-soldier 3P body).
--     Saltzpyre native wielders fall through (their careers aren't keyed
--     here), so vanilla brace 3P wield is unaffected for them.
--   * `_BRACE_REPEATER_ANIM_REMAP_3P`: the brace's `special_action`
--     (the fire-all-8-pistols finisher) doesn't exist on the repeater
--     SM. Substitute with `attack_shoot_fast` (closest repeater clip).
--     All other brace events (`attack_shoot`, `attack_shoot_fast`,
--     `lock_target`) ARE authored on the repeater SM and don't need a
--     remap.
--
-- Husks: same hook fires because remote-player spawn flows through the
-- same `GearUtils.spawn_inventory_unit`. Only `owner_unit_1p` is nil for
-- husks; the 3P spawn path is identical → other players see the
-- repeater on Kruber's body too.

local _BRACE_REPEATER_3P_UNIT = "units/weapons/player/wpn_emp_handgun_repeater_t1/wpn_emp_handgun_repeater_t1_3p"

-- Force-load the repeater rifle 3P unit at mod init. Vanilla packages for the
-- brace's right_hand_unit don't include the repeater unit (different weapon),
-- so when the swap below tries to spawn it via Managers.state.unit_spawner,
-- the resource manager has no entry → "Unit not found" assertion (crash GUID
-- d9e1d3d3 — the very crash this block is here to prevent).
--
-- Same fix CWV uses for the Tuskgor Javelin pup unit
-- (`character_weapon_variants.lua:2638` — Managers.package:load(unit_path,
-- ref, nil, async=true, prioritize=true)). Per VT2's pickup_package_loader
-- convention, the engine generates a per-unit synthetic package at the unit
-- path so calling :load with a unit path works as a "load this single unit's
-- assets" request. Load is async but fires at mod init, long before any
-- equip path runs — by the time the brace hook spawns, the unit is ready.
-- Documented in `feedback_cwv_cross_character_unit_packages.md` (pattern
-- known from Tuskgor v0.1.118 and now applied to Brace-Repeater).
local function _force_load_brace_repeater_3p_unit()
    if not (Managers and Managers.package) then return end
    local ok, err = pcall(function()
        Managers.package:load(_BRACE_REPEATER_3P_UNIT, "wt_brace_repeater_3p", nil, true, true)
    end)
    if ok then
        mod:info("[wt brace-3p-swap] force-loaded repeater 3P unit: %s", _BRACE_REPEATER_3P_UNIT)
    else
        mod:warning("[wt brace-3p-swap] failed to force-load repeater 3P unit: %s", tostring(err))
    end
end

_force_load_brace_repeater_3p_unit()

-- ============================================================
-- Saltzpyre Longbow → Crossbow 3P swap (parallel to brace→repeater)
-- ============================================================
-- Mirrors the brace→repeater pattern but with three differences:
--   1. LEFT-hand swap (bow/crossbow are left-hand weapons; brace was right-hand).
--   2. TWO units swapped per spawn: weapon (bow→crossbow) AND ammo (arrow→bolt).
--      The bow's ammo_data.ammo_hand == "left" so spawn_inventory_unit for
--      hand="left" returns (weapon_unit_3p, ammo_unit_3p, weapon_unit_1p,
--      ammo_unit_1p) — all four. Brace had no ammo unit; this one does.
--   3. Career detection still uses the v0.12.17 _unit_career_name (inventory-
--      ext-first; correctly populated at mission-spawn timing).
--
-- 1P stays vanilla longbow (1P is universal across characters — Saltzpyre
-- visually wields a bow in first-person view, fires arrows, same SM as
-- Huntsman). 3P body and ammo prop swap to crossbow + bolt so other
-- players (and the inventory preview) see Saltzpyre wielding a crossbow.
local _SP_CROSSBOW_3P_UNIT = "units/weapons/player/wpn_empire_crossbow_t1/wpn_empire_crossbow_tier1_3p"
local _SP_CROSSBOW_BOLT_3P_UNIT = "units/weapons/player/wpn_crossbow_quiver/wpn_crossbow_bolt_3p"

local function _force_load_sp_crossbow_3p_units()
    if not (Managers and Managers.package) then return end
    for ref_name, path in pairs({
        wt_sp_crossbow_3p     = _SP_CROSSBOW_3P_UNIT,
        wt_sp_crossbow_bolt_3p = _SP_CROSSBOW_BOLT_3P_UNIT,
    }) do
        local ok, err = pcall(function()
            Managers.package:load(path, ref_name, nil, true, true)
        end)
        if ok then
            mod:info("[wt sp-longbow-crossbow] force-loaded %s: %s", ref_name, path)
        else
            mod:warning("[wt sp-longbow-crossbow] failed to force-load %s: %s", ref_name, tostring(err))
        end
    end
end

_force_load_sp_crossbow_3p_units()

-- ============================================================
-- Brace → Repeater illusion resolver
-- ============================================================
-- When a brace illusion has a matching cosmetic tier on the repeater
-- (e.g. brace `wh_brace_of_pistols_skin_03_runed_01` "Stylish Infused"
-- ↔ repeater `es_repeating_handgun_skin_XX_runed_01" "Stylish Infused"),
-- the 3P repeater should render the MATCHED illusion's mesh, not the
-- base repeater. Match key is the suffix after `_skin_<digits>`:
--   `_runed_01`  → Stylish Infused (red glow)
--   `_runed_02`  → Bogenhafen (purple glow)
--   `_runed_03`  → Geheimnisnacht (gold glow)
--   `_magic_01`  → Weavebound
--   `_magic_02`  → Versus
--   `_runed_06`  → Chaos Wastes (Lileath)
--   "" (no suffix) → base mesh
-- Numbers differ between weapons (brace has 5 base skins, repeater has
-- 3), but the trailing suffix is consistent across the game's cosmetic
-- pipeline.
--
-- Returns: { unit_name = "<repeater_unit_3p_path>", skin_key = "<matched_repeater_skin_or_nil>" }
-- Cached so repeated lookups (every equip / picker swap) don't re-iterate
-- `WeaponSkins.skins`. Cache is invalidated only by mod reload.

local _BRACE_TO_REPEATER_CACHE = {}

local function _extract_skin_suffix(brace_skin_key)
    -- "wh_brace_of_pistols_skin_03_runed_01" → "_runed_01"
    -- "wh_brace_of_pistols_skin_05"          → "" (no cosmetic-tier suffix)
    -- nil / not-a-brace                       → nil
    if type(brace_skin_key) ~= "string" then return nil end
    if not brace_skin_key:find("^wh_brace_of_pistols_skin_") then return nil end
    -- Everything after `_skin_<digits>`. The digits portion might be
    -- multi-digit; capture trailing suffix.
    local suffix = brace_skin_key:match("^wh_brace_of_pistols_skin_%d+(.*)$")
    return suffix or ""  -- "" means "base mesh, no cosmetic tier"
end

local function _resolve_brace_to_repeater_skin(brace_skin_key)
    -- Returns: matched_repeater_3p_unit_path, matched_repeater_skin_key
    -- Both are nil if no match (caller falls back to base repeater 3P).
    if not brace_skin_key then return nil, nil end
    local cached = _BRACE_TO_REPEATER_CACHE[brace_skin_key]
    if cached ~= nil then  -- including the negative cache (cached = false)
        if cached == false then return nil, nil end
        return cached.unit_name, cached.skin_key
    end

    local suffix = _extract_skin_suffix(brace_skin_key)
    if not suffix then
        _BRACE_TO_REPEATER_CACHE[brace_skin_key] = false
        return nil, nil
    end

    if not WeaponSkins or not WeaponSkins.skins then return nil, nil end

    -- For empty suffix (base brace skin = skin_01/_02/_05/etc without runed/magic),
    -- match repeater's base skin_01 explicitly. Otherwise scan repeater skins for
    -- one whose key matches `es_repeating_handgun_skin_<digits><suffix>`.
    local matched_skin_key, matched_skin
    if suffix == "" then
        matched_skin_key = "es_repeating_handgun_skin_01"
        matched_skin = WeaponSkins.skins[matched_skin_key]
    else
        for skin_key, skin in pairs(WeaponSkins.skins) do
            if type(skin_key) == "string"
                    and skin_key:find("^es_repeating_handgun_skin_%d+" .. suffix:gsub("%-", "%%-") .. "$") then
                matched_skin_key = skin_key
                matched_skin = skin
                break
            end
        end
    end

    if not matched_skin or not matched_skin.right_hand_unit then
        _BRACE_TO_REPEATER_CACHE[brace_skin_key] = false
        return nil, nil
    end

    local unit_name = matched_skin.right_hand_unit .. "_3p"
    _BRACE_TO_REPEATER_CACHE[brace_skin_key] = { unit_name = unit_name, skin_key = matched_skin_key }
    return unit_name, matched_skin_key
end

-- Diagnostic command. `wt brace_to_repeater_skin <brace_skin_key>` prints
-- the resolved match. Use to verify each brace illusion maps to the
-- correct repeater illusion before relying on the resolver in the swap
-- hooks. Examples:
--   wt brace_to_repeater_skin wh_brace_of_pistols_skin_01
--   wt brace_to_repeater_skin wh_brace_of_pistols_skin_03_runed_01
--   wt brace_to_repeater_skin wh_brace_of_pistols_skin_03_runed_02
mod:command("brace_to_repeater_skin", "Resolve a brace illusion to its matching repeater illusion", function(brace_skin_key)
    if not brace_skin_key or brace_skin_key == "" then
        mod:echo("Usage: wt brace_to_repeater_skin <wh_brace_of_pistols_skin_*>")
        return
    end
    local suffix = _extract_skin_suffix(brace_skin_key)
    local unit, skin = _resolve_brace_to_repeater_skin(brace_skin_key)
    mod:echo("Brace: %s", brace_skin_key)
    mod:echo("  Suffix: %q", tostring(suffix))
    mod:echo("  Matched repeater skin: %s", tostring(skin or "(none — falls back to base repeater 3P)"))
    mod:echo("  Matched 3P unit: %s", tostring(unit or _BRACE_REPEATER_3P_UNIT .. "  [base, fallback]"))
end)

-- Dump command: walk every brace skin in WeaponSkins.skins and print
-- the resolved match. One-stop sanity check.
mod:command("brace_to_repeater_dump", "Dump every brace→repeater skin mapping", function()
    if not WeaponSkins or not WeaponSkins.skins then
        mod:echo("WeaponSkins.skins not loaded")
        return
    end
    local brace_keys = {}
    for skin_key in pairs(WeaponSkins.skins) do
        if type(skin_key) == "string" and skin_key:find("^wh_brace_of_pistols_skin_") then
            brace_keys[#brace_keys + 1] = skin_key
        end
    end
    table.sort(brace_keys)
    mod:info("=== Brace → Repeater skin mapping (%d brace skins) ===", #brace_keys)
    for _, brace_key in ipairs(brace_keys) do
        local unit, repeater_skin = _resolve_brace_to_repeater_skin(brace_key)
        mod:info("  %-50s → %s", brace_key, tostring(repeater_skin or "(no match, fallback)"))
    end
    mod:echo("Dumped %d brace skin mappings to log", #brace_keys)
end)

local _BRACE_REPEATER_BASE_WIELD_3P = {
    es_mercenary      = "to_repeating_handgun",
    es_huntsman       = "to_repeating_handgun",
    es_knight         = "to_repeating_handgun",
    es_questingknight = "to_repeating_handgun",
}

local _BRACE_REPEATER_ANIM_REMAP_3P = {
    special_action = "attack_shoot_fast",
}

local function _patch_brace_template_for_kruber()
    if not Weapons or not Weapons.brace_of_pistols_template_1 then return end
    local tpl = Weapons.brace_of_pistols_template_1

    -- Wield event per-career override.
    tpl.wield_anim_career_3p = tpl.wield_anim_career_3p or {}
    for k, v in pairs(_BRACE_REPEATER_BASE_WIELD_3P) do
        tpl.wield_anim_career_3p[k] = v
    end

    -- Per-action anim_event_3p remap for events the repeater SM doesn't
    -- author. Sets a sibling anim_event_3p alongside anim_event so the
    -- 3P body fires the substitute while 1P keeps the original.
    if tpl.actions then
        for _, action_group in pairs(tpl.actions) do
            if type(action_group) == "table" then
                for _, sub_action in pairs(action_group) do
                    if type(sub_action) == "table"
                            and sub_action.anim_event
                            and _BRACE_REPEATER_ANIM_REMAP_3P[sub_action.anim_event] then
                        sub_action.anim_event_3p = _BRACE_REPEATER_ANIM_REMAP_3P[sub_action.anim_event]
                    end
                end
            end
        end
    end
end

_patch_brace_template_for_kruber()

-- ============================================================
-- Saltzpyre Longbow → Crossbow: base template anim patches
-- ============================================================
-- Parallel to _patch_brace_template_for_kruber. The es_longbow's template
-- (longbow_empire_template) gets a wh_*-keyed wield_anim_career_3p so
-- Saltzpyre's 3P body plays the crossbow wield transition instead of
-- "to_es_longbow". Per-action anim_event_3p remaps cover firing events
-- that have different names on the crossbow SM than on the longbow's 1P.
--
-- The longbow's primary fire action uses anim_event = "attack_shoot_fast"
-- (1P bow draws-then-fires). Saltzpyre's 3P crossbow SM does NOT author
-- "attack_shoot_fast" (the crossbow has no rapid-fire variant) but DOES
-- author "attack_shoot" — so we remap. shoot_charged actions already use
-- "attack_shoot" so they fall through unchanged.
local _SP_LONGBOW_CROSSBOW_WIELD_3P = {
    wh_captain      = "to_crossbow",
    wh_bountyhunter = "to_crossbow",
    wh_zealot       = "to_crossbow",
    wh_priest       = "to_crossbow",
}

local _SP_LONGBOW_CROSSBOW_ANIM_REMAP_3P = {
    attack_shoot_fast       = "attack_shoot",
    attack_shoot_fast_last  = "attack_shoot_last",
    draw_bow                = "to_zoom",       -- charged-shot aim hold; crossbow uses to_zoom
}

local function _patch_longbow_empire_template_for_saltzpyre()
    if not Weapons or not Weapons.longbow_empire_template then return end
    local tpl = Weapons.longbow_empire_template

    tpl.wield_anim_career_3p = tpl.wield_anim_career_3p or {}
    for k, v in pairs(_SP_LONGBOW_CROSSBOW_WIELD_3P) do
        tpl.wield_anim_career_3p[k] = v
    end

    -- Per-action anim_event_3p remap. Pattern mirrors the brace patcher.
    if tpl.actions then
        for _, action_group in pairs(tpl.actions) do
            if type(action_group) == "table" then
                for _, sub_action in pairs(action_group) do
                    if type(sub_action) == "table"
                            and sub_action.anim_event
                            and _SP_LONGBOW_CROSSBOW_ANIM_REMAP_3P[sub_action.anim_event] then
                        sub_action.anim_event_3p = _SP_LONGBOW_CROSSBOW_ANIM_REMAP_3P[sub_action.anim_event]
                    end
                end
            end
        end
    end
end

_patch_longbow_empire_template_for_saltzpyre()

-- ============================================================
-- Authentic Brace of Pistols — toggleable flintlock-style override
-- ============================================================
-- Patches `Weapons.brace_of_pistols_template_1` in place when the
-- `authentic_brace_of_pistols` VMF setting is ON at mod init. Five
-- changes, all toggleable via the one setting:
--
--   1. Damage: every firing sub-action's `impact_data.damage_profile`
--      switches from `shot_carbine` (vanilla brace) to a clone of
--      `shot_sniper` (Kruber's handgun) with the near→far dropoff
--      flattened AND cleave_distribution halved (≈2x penetration:
--      from ~3 targets → ~6). Plus `ignore_shield_hit = true` on the
--      sub-action, which is what lets the handgun ignore shields.
--      Combined effect: armor-piercing, shield-breaking, full damage at
--      all ranges, passes through ~6 enemies.
--   2. Right-click is left vanilla. Lock-target / fast_shot rapid-fire
--      kept intact. (Previous revisions tried to disable or replace it
--      with a handgun-style zoom — both reverted in v0.12.15 because
--      rapid fire was reachable via paths we couldn't fully exorcise.
--      v0.12.19-v0.12.21 instead make secondary fire deliberately less
--      accurate than primary — see step 5. Speed was slowed in v0.12.19
--      then brought back to vanilla in v0.12.21 — see step 7.)
--   3. Manual reload re-enabled (v0.12.19). User wants single-shot
--      manual reload back; `weapon_reload.default` condition_funcs are
--      left vanilla. `auto_reload` chain is unchanged.
--   4. Ammo: `ammo_per_clip = 6`, `ammo_per_reload = 1`, `max_ammo = 12`.
--      Six rounds in the mag, six rounds in reserve, reloads one shot at
--      a time. (Vanilla: clip 12 / reload 2 / max 30. v0.12.16-v0.12.18:
--      clip 12 / reload 12 / max 12, no-reserve.) Each manual reload
--      animation loads one round; player can keep tapping R to top up
--      the clip one round at a time, can interrupt with a shot. Matches
--      a flintlock-pistol-bandolier feel.
--   6. (Removed in v0.12.15) fast_shot chain rewrite. Reverted along with
--      step 2; rapid fire is allowed.
--   7. Action speed: PRIMARY/all-other actions run at 2x speed (mult 0.5);
--      SECONDARY FIRE (`action_one.fast_shot` rapid-fire cadence) runs at
--      VANILLA speed (mult 1.0 — was 2.0 in v0.12.19-v0.12.20; user asked
--      to double it in v0.12.21). Chain-into-fast_shot start_times from
--      any source action also use the slow mult, so entering rapid fire
--      from RMB now takes the vanilla delay. Walks `tpl.actions[*][*]`
--      and scales `total_time`, `total_time_secondary`, `fire_time`,
--      `minimum_hold_time`, `cooldown`, `reload_time`, and every chain
--      `start_time`. 0/math.huge are skipped. The split walker is kept
--      even though mult=1.0 is a no-op, so future re-tunes (1.3, 1.5,
--      etc.) don't need a rewrite.
--   5. Spread: dramatically less accurate, with secondary fire MUCH
--      more inaccurate than primary. Default brace spread cloned +
--      widened by `_AUTHENTIC_BRACE_PRIMARY_SPREAD_MULT` (3.0);
--      `pistol_special` spread (used by RMB lock-target AND rapid-fire
--      shots) cloned + widened by `_AUTHENTIC_BRACE_SECONDARY_SPREAD_MULT`
--      (12.0 = 4× the primary multiplier). Primary clone is set as
--      `default_spread_template`; secondary clone overrides
--      `spread_template_override` on EVERY sub-action of every action
--      that pointed to `pistol_special` (action_two.default lock-target
--      and action_one.[default|fast_shot|special_action_shoot]). The
--      walk over every action — instead of only action_one — is what
--      makes the reticle jump to the full wide size the moment RMB is
--      pressed, instead of the prior two-step "RMB jump to vanilla
--      pistol_special, then LMB jump to wider clone".
--
-- All five patches are template-level globals so the change applies
-- to every wielder (Saltzpyre native + Kruber via WT cross-access).
-- A restart is required to toggle off because the in-place patches
-- can't be cleanly reverted without snapshotting + restoring vanilla.

local function _wt_clone_shot_sniper_no_dropoff()
    if not DamageProfileTemplates then return nil end
    local source = DamageProfileTemplates.shot_sniper
    if not source then return nil end
    local key = "wt_authentic_pistol"
    if DamageProfileTemplates[key] then return key end

    local clone = table.clone(source, true)

    -- Flatten near/far dropoff: mirror near values to far so range no
    -- longer reduces damage. shot_sniper has separate `armor_modifier_near`
    -- vs `armor_modifier_far` and per-target `power_distribution_near`
    -- vs `power_distribution_far`.
    if clone.armor_modifier_near then
        clone.armor_modifier_far = table.clone(clone.armor_modifier_near, true)
    end
    if clone.default_target then
        if clone.default_target.power_distribution_near then
            clone.default_target.power_distribution_far = table.clone(clone.default_target.power_distribution_near, true)
        end
        -- range_modifier_settings is the curve that interpolates between
        -- near and far. With both endpoints equal we don't strictly need
        -- to remove it, but clearing it makes the no-dropoff intent
        -- explicit.
        clone.default_target.range_modifier_settings = nil
    end

    -- Double penetration. `cleave_distribution.attack` / `.impact` is the
    -- fraction of cleave power consumed per target hit; halving each value
    -- lets projectiles pass through ~2x as many enemies before running
    -- out of cleave. shot_sniper vanilla is 0.3/0.3 (≈3 targets);
    -- wt_authentic_pistol becomes 0.15/0.15 (≈6 targets).
    if clone.cleave_distribution then
        if type(clone.cleave_distribution.attack) == "number" then
            clone.cleave_distribution.attack = clone.cleave_distribution.attack / 2
        end
        if type(clone.cleave_distribution.impact) == "number" then
            clone.cleave_distribution.impact = clone.cleave_distribution.impact / 2
        end
    end

    DamageProfileTemplates[key] = clone

    -- Register in NetworkLookup.damage_profiles. The lookup is built once at
    -- game load (network_lookup.lua:2203) and frozen with an __index metatable
    -- that errors on missing keys. PlayerProjectileUnitExtension (line 92)
    -- looks up `NetworkLookup.damage_profiles[impact_data.damage_profile]` at
    -- projectile spawn — without this registration every brace shot crashes
    -- with "Table damage_profiles does not contain key: wt_authentic_pistol",
    -- which is exactly what made v0.12.6 silently no-op. Same pattern CWV uses
    -- for its custom damage-profile clones (character_weapon_variants.lua:1364).
    if NetworkLookup and NetworkLookup.damage_profiles and not rawget(NetworkLookup.damage_profiles, key) then
        local tbl = NetworkLookup.damage_profiles
        local idx = #tbl + 1
        rawset(tbl, idx, key)
        rawset(tbl, key, idx)
    end

    return key
end

-- Primary spread mult: applied to the default brace spread used by
-- single-shot LMB (action_one.default). 3× wider than vanilla.
local _AUTHENTIC_BRACE_PRIMARY_SPREAD_MULT = 3.0
-- Secondary spread mult: applied to pistol_special, which both
-- action_two.default (lock-target / RMB aim) and action_one.fast_shot
-- (rapid-fire shot) override to via `spread_template_override`. 12×
-- (dialled back from 16× in v0.12.21 per user feel-test).
local _AUTHENTIC_BRACE_SECONDARY_SPREAD_MULT = 12.0

local function _wt_scale_spread(t, mult)
    for k, v in pairs(t) do
        if type(v) == "table" then
            _wt_scale_spread(v, mult)
        elseif type(v) == "number" then
            t[k] = v * mult
        end
    end
end

local function _wt_clone_spread_wider(source_key, dest_key, mult)
    if not SpreadTemplates then return nil end
    local source = SpreadTemplates[source_key]
    if not source then return nil end
    if SpreadTemplates[dest_key] then return dest_key end
    local clone = table.clone(source, true)
    _wt_scale_spread(clone, mult)
    SpreadTemplates[dest_key] = clone
    return dest_key
end

local function _wt_clone_brace_spread_wider()
    -- Default-stance spread (used by single-shot from action_one.default).
    -- Brace spread template is nested two levels deep (continuous/immediate →
    -- still/moving/etc → max_pitch/max_yaw/immediate_pitch/immediate_yaw).
    return _wt_clone_spread_wider("brace_of_pistols",
        "wt_authentic_brace_of_pistols_spread",
        _AUTHENTIC_BRACE_PRIMARY_SPREAD_MULT)
end

local function _wt_clone_pistol_special_spread_wider()
    -- pistol_special is what fast_shot (rapid-fire, action_two→fast_shot
    -- chain) uses via `spread_template_override`. Secondary mult (higher)
    -- so rapid fire is noticeably less accurate than single shots.
    return _wt_clone_spread_wider("pistol_special",
        "wt_authentic_brace_pistol_special_spread",
        _AUTHENTIC_BRACE_SECONDARY_SPREAD_MULT)
end

local function _apply_authentic_brace_mode()
    if not Weapons or not Weapons.brace_of_pistols_template_1 then
        mod:warning("[wt authentic-brace] brace_of_pistols_template_1 not found — patch skipped")
        return
    end
    local tpl = Weapons.brace_of_pistols_template_1

    -- 1) Damage profile + shield/armor piercing on all firing sub-actions.
    local damage_profile_key = _wt_clone_shot_sniper_no_dropoff()
    if not damage_profile_key then
        mod:warning("[wt authentic-brace] failed to clone shot_sniper — bailing")
        return
    end
    if tpl.actions and tpl.actions.action_one then
        for _, sub_name in ipairs({ "default", "fast_shot", "special_action_shoot" }) do
            local sub = tpl.actions.action_one[sub_name]
            if sub then
                if sub.impact_data then
                    sub.impact_data.damage_profile = damage_profile_key
                end
                sub.ignore_shield_hit = true
            end
        end
    end

    -- 2) (Removed in v0.12.15) Right-click is left alone — vanilla brace
    -- lock-target / fast_shot rapid-fire kept intact. The previous attempts
    -- to swap it for a handgun-style optical zoom and to scrub the
    -- fast_shot rapid-fire chain were both reverted: the user reported the
    -- rapid-fire path was reachable through paths we never tracked down,
    -- and would rather lean into the rapid-fire than keep chasing it. The
    -- accuracy reduction in step (5) compensates by making rapid fire
    -- highly inaccurate.

    -- 3) Manual reload re-enabled (v0.12.19). Earlier revisions disabled
    -- weapon_reload.default by stubbing its condition_funcs with
    -- _disable_action so the only reload path was the auto-load-empty
    -- chain. The user has changed their mind: they want manual reload
    -- back, one shot at a time. We leave weapon_reload.default at vanilla
    -- (no condition_func override) and rely on ammo_per_reload=1 (step 4)
    -- for the single-shot-per-cycle behavior.

    -- 4) Ammo: 6 in the mag, 6 in reserve, reload one shot at a time.
    -- ammo_per_clip = 6 (mag size, the number you can fire before reload
    -- is required), max_ammo = 12 (mag + reserve, total carry), so reserve
    -- = max_ammo - ammo_per_clip = 6. ammo_per_reload = 1 means each
    -- reload animation cycle loads one round; the player can interrupt
    -- with a shot at any time (vanilla brace already supports this via
    -- weapon_reload.default's chain into action_one) or keep tapping R to
    -- top up the clip one round at a time.
    if tpl.ammo_data then
        tpl.ammo_data.ammo_per_clip = 6
        tpl.ammo_data.ammo_per_reload = 1
        tpl.ammo_data.max_ammo = 12
    end

    -- 6) (Removed in v0.12.15) fast_shot chain rewrite was reverted along
    -- with the right-click aim mutation in step (2). Rapid fire is allowed
    -- to remain reachable through whatever vanilla path the engine uses;
    -- v0.12.19 makes secondary fire deliberately slower (step 7) and less
    -- accurate (step 5) instead of trying to block it.

    -- 7) Action speed: PRIMARY/all-other actions run at 2x speed
    -- (_FAST_MULT = 0.5 → halved timings). SECONDARY FIRE
    -- (action_one.fast_shot — the rapid-fire shot triggered by RMB-hold)
    -- runs at VANILLA speed (_SLOW_MULT = 1.0 → no scaling). This was
    -- 2.0 (50% of vanilla, i.e. 2x slower) in v0.12.19-v0.12.20; user
    -- felt that was too slow, asked to double the speed in v0.12.21 →
    -- 1.0 lands secondary fire at vanilla pacing while primary stays
    -- at 2x. Net: secondary is half the speed of primary, but at the
    -- vanilla cadence the engine ships with. Chain start_times use:
    --   * SLOW if the chain's SOURCE sub-action is secondary (so internal
    --     fast_shot pacing — the self-loop at start_time=0.25 — stays at
    --     vanilla 0.25s, giving ~4 shots/sec).
    --   * SLOW if the chain's TARGET sub-action is fast_shot (so the
    --     RMB-into-rapid-fire chain from action_two.default at
    --     start_time=0.25 also stays vanilla).
    --   * FAST otherwise.
    -- Skip 0/math.huge — neither "instant" nor "hold-forever" semantics
    -- should be scaled. With _SLOW_MULT=1.0 the "slow" branches are
    -- effectively no-ops; the structure is retained so the asymmetry
    -- can be re-tuned (e.g. back to 1.5 / 2.0) without rewriting the
    -- walker.
    local _FAST_MULT = 0.5  -- 2x speed for primary / non-secondary actions
    local _SLOW_MULT = 1.0  -- vanilla speed for secondary fire (was 2.0 in v0.12.19-v0.12.20)
    local function _is_secondary_sub(action_name, sub_name)
        return action_name == "action_one" and sub_name == "fast_shot"
    end
    local function _chain_targets_secondary(chain, source_action_name)
        -- chain.action is the target action; if absent it defaults to the
        -- source action's name (per ActionUtils chain resolution).
        local target_action = chain.action or source_action_name
        return target_action == "action_one" and chain.sub_action == "fast_shot"
    end
    local function _scale_time(field, mult)
        if type(field) ~= "number" then return field end
        if field == 0 or field == math.huge then return field end
        return field * mult
    end
    if tpl.actions then
        for action_name, sub_actions in pairs(tpl.actions) do
            for sub_name, sub in pairs(sub_actions) do
                if type(sub) == "table" then
                    local is_secondary = _is_secondary_sub(action_name, sub_name)
                    local sub_mult = is_secondary and _SLOW_MULT or _FAST_MULT
                    sub.total_time           = _scale_time(sub.total_time, sub_mult)
                    sub.total_time_secondary = _scale_time(sub.total_time_secondary, sub_mult)
                    sub.fire_time            = _scale_time(sub.fire_time, sub_mult)
                    sub.minimum_hold_time    = _scale_time(sub.minimum_hold_time, sub_mult)
                    sub.cooldown             = _scale_time(sub.cooldown, sub_mult)
                    sub.reload_time          = _scale_time(sub.reload_time, sub_mult)
                    if sub.allowed_chain_actions then
                        for _, chain in ipairs(sub.allowed_chain_actions) do
                            local chain_mult
                            if is_secondary or _chain_targets_secondary(chain, action_name) then
                                chain_mult = _SLOW_MULT
                            else
                                chain_mult = _FAST_MULT
                            end
                            chain.start_time = _scale_time(chain.start_time, chain_mult)
                        end
                    end
                end
            end
        end
    end

    -- 5) Spread: dramatically less accurate. Both the default spread (single
    -- shot from action_one.default) AND the pistol_special spread (used by
    -- fast_shot rapid-fire via `spread_template_override`) are widened by
    -- the same multiplier. Without the second clone, holding RMB + LMB
    -- enters rapid fire which falls back to vanilla pistol_special spread
    -- and the "dramatic" feel only shows on single shots.
    local spread_key = _wt_clone_brace_spread_wider()
    if spread_key then
        tpl.default_spread_template = spread_key
    end
    -- Replace `spread_template_override = "pistol_special"` everywhere it
    -- appears on the template, not just in action_one. Critically this
    -- catches `action_two.default` (the RMB lock-target / aim action)
    -- which vanilla also overrides to pistol_special. v0.12.20 and earlier
    -- only patched action_one.[default|fast_shot|special_action_shoot] —
    -- that meant pressing RMB jumped the reticle to the vanilla
    -- pistol_special max spread (≈1.0), and then pressing LMB triggered
    -- action_one.fast_shot which jumped it again to our wider clone
    -- (≈1.0 × secondary_mult). The user saw this as the reticle
    -- "unnaturally going from small to large" — a two-step jump on RMB
    -- then LMB. With this patch the override on action_two.default uses
    -- the same wider clone, so the reticle jumps to the correct (large)
    -- size the moment the player takes aim. `override_spread_template`
    -- in `weapon_spread_extension.lua:168-177` instantly sets
    -- `current_pitch = state_settings.max_pitch`, so no lerp is visible.
    local rapid_spread_key = _wt_clone_pistol_special_spread_wider()
    if rapid_spread_key and tpl.actions then
        for _, sub_actions in pairs(tpl.actions) do
            for _, sub in pairs(sub_actions) do
                if type(sub) == "table" and sub.spread_template_override == "pistol_special" then
                    sub.spread_template_override = rapid_spread_key
                end
            end
        end
    end

    mod:info("[wt authentic-brace] applied: damage=%s, primary_spread=%s (%sx), secondary_spread=%s (%sx, applied to ALL pistol_special overrides incl. action_two.default), ammo=6/12 (reload 1 at a time, manual reload re-enabled), primary-speed=2x, secondary-fire-speed=vanilla (slow_mult=1.0)",
        damage_profile_key,
        tostring(spread_key), tostring(_AUTHENTIC_BRACE_PRIMARY_SPREAD_MULT),
        tostring(rapid_spread_key), tostring(_AUTHENTIC_BRACE_SECONDARY_SPREAD_MULT))
end

if mod:get("authentic_brace_of_pistols") then
    _apply_authentic_brace_mode()
end

-- Hook GearUtils.spawn_inventory_unit. Always call vanilla first, capture
-- all 4 returns (v_w3p, v_a3p, v_w1p, v_a1p), then attempt the swap inside
-- a pcall so any failure returns vanilla's units unchanged. Equipping
-- never fails because of this swap.
mod:hook("GearUtils", "spawn_inventory_unit", function(func, world, hand, item_template, item_units, slot_name, item_data, owner_unit_1p, owner_unit_3p, unit_template, extra_extension_data, ammo_percent, material_settings_name)
    local v_w3p, v_a3p, v_w1p, v_a1p =
        func(world, hand, item_template, item_units, slot_name, item_data, owner_unit_1p, owner_unit_3p, unit_template, extra_extension_data, ammo_percent, material_settings_name)

    -- Gate: only apply swap when wielding a brace, on the right hand
    -- (where the brace's "main pistol" mounts), and the wielder is a
    -- Kruber career. _local_career_name() is defined earlier in this file;
    -- it returns the locally-wielded unit's career_name. For husks, fall
    -- back to checking `owner_unit_3p` via _unit_career_name (also
    -- defined earlier).
    if not item_data or item_data.name ~= "wh_brace_of_pistols" then
        return v_w3p, v_a3p, v_w1p, v_a1p
    end
    if hand ~= "right" then
        return v_w3p, v_a3p, v_w1p, v_a1p
    end
    -- Career detection: prefer owner_unit_3p (always present, both local
    -- and husk paths). _unit_career_name reads the inventory extension's
    -- career name from the unit.
    local career_name = _unit_career_name(owner_unit_3p)
    if not career_name or career_name:sub(1, 3) ~= "es_" then
        return v_w3p, v_a3p, v_w1p, v_a1p
    end

    if not v_w3p then return v_w3p, v_a3p, v_w1p, v_a1p end

    -- Package readiness check: the async force-load at mod init usually
    -- completes well before any equip flow, but guard the spawn anyway. A
    -- not-yet-loaded package would cause `spawn_local_unit_with_extensions`
    -- to throw the C++ "Unit not found" assertion (crash GUID d9e1d3d3).
    -- If unloaded here, just return vanilla's brace 3P unit — Kruber sees
    -- the brace mesh briefly until the next equip fires the swap.
    if Managers and Managers.package and Managers.package.has_loaded
            and not Managers.package:has_loaded(_BRACE_REPEATER_3P_UNIT, "wt_brace_repeater_3p") then
        return v_w3p, v_a3p, v_w1p, v_a1p
    end

    local pcall_ok, swap_result = pcall(function()
        local node_linking_settings = item_template[hand .. "_hand_attachment_node_linking"]
        if not node_linking_settings or not node_linking_settings.third_person then
            mod:warning("[wt brace-3p-swap] missing node_linking_settings.third_person; aborting")
            return nil
        end

        local unit_template_3p_name = item_data.third_person_extension_template
            or item_template.third_person_extension_template
            or "weapon_unit_3p"
        if owner_unit_1p then unit_template_3p_name = "weapon_unit_3p" end

        local extension_init_data_3p = {
            weapon_system = {
                item_template = item_template,
                item_name = item_data.name,
                owner_unit = owner_unit_3p,
                world = world,
            },
        }

        -- Spawn the repeater 3P unit FIRST. If spawn fails we still have
        -- vanilla's brace 3P unit to fall back to.
        local new_unit = Managers.state.unit_spawner:spawn_local_unit_with_extensions(
            _BRACE_REPEATER_3P_UNIT, unit_template_3p_name, extension_init_data_3p)
        if not new_unit then
            mod:warning("[wt brace-3p-swap] spawn returned nil for '%s'", _BRACE_REPEATER_3P_UNIT)
            return nil
        end

        -- Now safe to destroy vanilla's brace 3P unit.
        Managers.state.unit_spawner:mark_for_deletion(v_w3p)

        local attachment_node_linking_3p = node_linking_settings.third_person.wielded
        GearUtils.link(world, attachment_node_linking_3p, {}, owner_unit_3p, new_unit)

        local mat = material_settings_name or item_template.material_settings_name
        if mat then GearUtils.apply_material_settings(new_unit, mat) end

        Unit.set_unit_visibility(new_unit, false)

        mod:info("[wt brace-3p-swap] swapped 3P brace → repeater on career=%s (husk=%s)",
            career_name, tostring(owner_unit_1p == nil))

        return new_unit
    end)

    if not pcall_ok then
        mod:warning("[wt brace-3p-swap] pcall ERROR: %s — keeping vanilla unit", tostring(swap_result))
        return v_w3p, v_a3p, v_w1p, v_a1p
    end

    if swap_result then
        return swap_result, v_a3p, v_w1p, v_a1p
    end
    return v_w3p, v_a3p, v_w1p, v_a1p
end)

-- ============================================================
-- Saltzpyre Longbow → Crossbow in-game 3P spawn hook
-- ============================================================
-- Parallel to the brace→repeater hook above. Differences:
--   * `hand == "left"` (bows/crossbows are left-hand weapons; brace was right)
--   * Swaps TWO 3P units per spawn: v_w3p (bow→crossbow) AND v_a3p (arrow→bolt).
--     The bow's `ammo_data.ammo_hand == "left"`, so vanilla
--     spawn_inventory_unit("left", longbow, ...) returns a non-nil v_a3p.
--     Brace had no ammo unit; this case does.
--   * 1P returns (v_w1p = bow, v_a1p = arrow) are left untouched — 1P stays
--     the longbow visually because 1P is universal across characters
--     (`feedback_1p_animations_universal.md`).
--
-- The new bolt ammo unit attaches via the CROSSBOW template's bolt-attachment
-- node linking, NOT the bow's arrow-attachment. The bow's arrow attaches at
-- the bow's nock point on the player body; the crossbow's bolt attaches at
-- the crossbow's nock groove. Using bow's arrow linking would render the
-- bolt at the wrong position relative to the (now-crossbow) weapon mesh.
mod:hook("GearUtils", "spawn_inventory_unit", function(func, world, hand, item_template, item_units, slot_name, item_data, owner_unit_1p, owner_unit_3p, unit_template, extra_extension_data, ammo_percent, material_settings_name)
    local v_w3p, v_a3p, v_w1p, v_a1p =
        func(world, hand, item_template, item_units, slot_name, item_data, owner_unit_1p, owner_unit_3p, unit_template, extra_extension_data, ammo_percent, material_settings_name)

    if not item_data or item_data.name ~= "es_longbow" then
        return v_w3p, v_a3p, v_w1p, v_a1p
    end
    if hand ~= "left" then
        return v_w3p, v_a3p, v_w1p, v_a1p
    end
    local career_name = _unit_career_name(owner_unit_3p)
    if not career_name or career_name:sub(1, 3) ~= "wh_" then
        return v_w3p, v_a3p, v_w1p, v_a1p
    end

    if not v_w3p then return v_w3p, v_a3p, v_w1p, v_a1p end

    -- Package readiness checks — same async-load defensiveness as the brace hook.
    if Managers and Managers.package and Managers.package.has_loaded then
        if not Managers.package:has_loaded(_SP_CROSSBOW_3P_UNIT, "wt_sp_crossbow_3p") then
            return v_w3p, v_a3p, v_w1p, v_a1p
        end
        if v_a3p and not Managers.package:has_loaded(_SP_CROSSBOW_BOLT_3P_UNIT, "wt_sp_crossbow_bolt_3p") then
            return v_w3p, v_a3p, v_w1p, v_a1p
        end
    end

    local pcall_ok, swap_result = pcall(function()
        local node_linking_settings = item_template[hand .. "_hand_attachment_node_linking"]
        if not node_linking_settings or not node_linking_settings.third_person then
            mod:warning("[wt sp-longbow-crossbow] missing node_linking_settings.third_person; aborting")
            return nil
        end

        local unit_template_3p_name = item_data.third_person_extension_template
            or item_template.third_person_extension_template
            or "weapon_unit_3p"
        if owner_unit_1p then unit_template_3p_name = "weapon_unit_3p" end

        local extension_init_data_3p = {
            weapon_system = {
                item_template = item_template,
                item_name = item_data.name,
                owner_unit = owner_unit_3p,
                world = world,
            },
        }

        -- Spawn new crossbow 3P unit first; fall back to vanilla bow if it fails.
        local new_weapon = Managers.state.unit_spawner:spawn_local_unit_with_extensions(
            _SP_CROSSBOW_3P_UNIT, unit_template_3p_name, extension_init_data_3p)
        if not new_weapon then
            mod:warning("[wt sp-longbow-crossbow] weapon spawn returned nil for '%s'", _SP_CROSSBOW_3P_UNIT)
            return nil
        end

        -- Spawn new bolt 3P unit, attached via the crossbow template's bolt
        -- ammo-attachment linking (NOT the longbow's arrow linking — the
        -- bolt belongs at the crossbow's nock position on the player body).
        -- If the bow template had no v_a3p there's nothing to swap; only
        -- swap when both source and target ammo paths are available.
        local new_ammo
        if v_a3p then
            local crossbow_tpl = Weapons and Weapons.crossbow_template_1
            local xbow_ammo_linking = crossbow_tpl and crossbow_tpl.ammo_data
                                       and crossbow_tpl.ammo_data.ammo_unit_attachment_node_linking
                                       and crossbow_tpl.ammo_data.ammo_unit_attachment_node_linking.third_person
                                       and crossbow_tpl.ammo_data.ammo_unit_attachment_node_linking.third_person.wielded
            if xbow_ammo_linking and GearUtils._attach_ammo_unit then
                new_ammo = GearUtils._attach_ammo_unit(world, _SP_CROSSBOW_BOLT_3P_UNIT, xbow_ammo_linking, owner_unit_3p)
            else
                mod:warning("[wt sp-longbow-crossbow] missing crossbow_template_1 ammo linking; skipping bolt swap")
            end
        end

        -- Destroy vanilla units only after replacements are safely spawned.
        Managers.state.unit_spawner:mark_for_deletion(v_w3p)
        if new_ammo and v_a3p then
            Managers.state.unit_spawner:mark_for_deletion(v_a3p)
        end

        local attachment_node_linking_3p = node_linking_settings.third_person.wielded
        GearUtils.link(world, attachment_node_linking_3p, {}, owner_unit_3p, new_weapon)

        local mat = material_settings_name or item_template.material_settings_name
        if mat then GearUtils.apply_material_settings(new_weapon, mat) end

        Unit.set_unit_visibility(new_weapon, false)
        if new_ammo then Unit.set_unit_visibility(new_ammo, false) end

        mod:info("[wt sp-longbow-crossbow] swapped 3P bow→crossbow, arrow→bolt(%s) on career=%s (husk=%s)",
            tostring(new_ammo ~= nil), career_name, tostring(owner_unit_1p == nil))

        return { weapon = new_weapon, ammo = new_ammo }
    end)

    if not pcall_ok then
        mod:warning("[wt sp-longbow-crossbow] pcall ERROR: %s — keeping vanilla units", tostring(swap_result))
        return v_w3p, v_a3p, v_w1p, v_a1p
    end

    if swap_result then
        return swap_result.weapon, (swap_result.ammo or v_a3p), v_w1p, v_a1p
    end
    return v_w3p, v_a3p, v_w1p, v_a1p
end)

-- Hide the left-hand brace pistol on Kruber. The brace template renders TWO
-- pistols (one per hand) — the right-hand spawn_inventory_unit hook above
-- swaps the right-hand mesh to the Empire repeater, but the left-hand pistol
-- stays vanilla and clips through the repeater's body. We can't just hide it
-- in the spawn hook because `SimpleInventoryExtension.show_third_person_inventory`
-- (simple_inventory_extension.lua:1014-1075) sets visibility back to `show`
-- on every wield/unwield. So post-hook that function and re-hide the
-- left-hand 3P unit specifically when (a) the wielded item is the brace AND
-- (b) the wielder is a Kruber career.
mod:hook_safe("SimpleInventoryExtension", "show_third_person_inventory", function(self, show)
    if not show then return end
    local equipment = self._equipment
    if not equipment then return end
    local left_unit = equipment.left_hand_wielded_unit_3p
    if not left_unit or not Unit.alive(left_unit) then return end

    local wielded_slot = equipment.wielded_slot
    if not wielded_slot then return end
    local slot_data = equipment.slots and equipment.slots[wielded_slot]
    local item_data = slot_data and slot_data.item_data
    if not item_data or item_data.name ~= "wh_brace_of_pistols" then return end

    local owner_unit = self._unit
    local career_name = owner_unit and _unit_career_name(owner_unit)
    if not career_name or career_name:sub(1, 3) ~= "es_" then return end

    -- Force the left brace pistol invisible. Mirror the visibility-group
    -- branching that vanilla `show_third_person_inventory` uses so we hit
    -- whichever path the unit was rendered through.
    if Unit.has_visibility_group(left_unit, "normal") then
        Unit.set_visibility(left_unit, "normal", false)
    else
        Unit.set_unit_visibility(left_unit, false)
    end
end)

-- Character preview path: swap brace 3P → repeater 3P on Kruber.
-- The in-game spawn flow goes through GearUtils.spawn_inventory_unit (hooked
-- above); the keep inventory previewer does NOT — it calls
-- World.spawn_unit(world, unit_name) directly from precomputed `spawn_data`
-- built in equip_item. So the brace pistol mesh still rendered on the
-- inventory character preview while the in-game 3P showed the repeater
-- correctly.
--
-- Fix: post-hook equip_item, then mutate the stored spawn_data:
--   * right-hand entry: rewrite `unit_name` → _BRACE_REPEATER_3P_UNIT
--   * left-hand entry: drop it (vanilla brace's left pistol clips the
--     repeater body; mirrors the show_third_person_inventory hide above)
-- The repeater 3P unit is already force-loaded at mod init (see
-- _force_load_brace_repeater_3p_unit) so World.spawn_unit resolves it.
--
-- CRITICAL: hook MenuWorldPreviewer, NOT HeroPreviewer. The keep inventory
-- (HeroWindowCharacterPreview, character-select, store, loot) all
-- instantiate MenuWorldPreviewer. VT2's foundation class() helper COPIES
-- parent methods into the child at class-definition time (no __index
-- chain — see foundation/scripts/util/class.lua:51-57), so after
-- `MenuWorldPreviewer = class(MenuWorldPreviewer, HeroPreviewer)` runs
-- at game load, MenuWorldPreviewer.equip_item is a static copy of
-- HeroPreviewer.equip_item. VMF mod:hook("HeroPreviewer", "equip_item")
-- replaces HeroPreviewer.equip_item but NOT MenuWorldPreviewer.equip_item;
-- the previewer instance dispatches through the copy and the hook never
-- fires. See feedback_vt2_class_hook_derived.
mod:hook_safe("MenuWorldPreviewer", "equip_item", function(self, item_name, slot, backend_id, skin, skip_wield_anim)
    if item_name ~= "wh_brace_of_pistols" then return end
    local career = self._current_career_name
    if not career or career:sub(1, 3) ~= "es_" then return end

    local slot_type = (type(slot) == "table" and slot.type) or nil
    if not slot_type then return end
    local info = self._item_info_by_slot and self._item_info_by_slot[slot_type]
    if not info or not info.spawn_data then return end

    local new_spawn_data = {}
    local swapped = false
    for _, entry in ipairs(info.spawn_data) do
        if entry.right_hand then
            entry.unit_name = _BRACE_REPEATER_3P_UNIT
            entry.despawn_both_hands_units = nil
            new_spawn_data[#new_spawn_data + 1] = entry
            swapped = true
        elseif entry.left_hand then
            -- drop; brace's left pistol would clip the repeater body
        else
            new_spawn_data[#new_spawn_data + 1] = entry
        end
    end
    info.spawn_data = new_spawn_data

    if swapped then
        mod:info("[wt brace-3p-swap preview] swapped preview 3P brace → repeater on career=%s", career)
    end
end)

-- Inventory preview swap for Saltzpyre's es_longbow → crossbow visual.
-- Same MenuWorldPreviewer.equip_item pattern as the brace hook above
-- (NOT HeroPreviewer — see comment block above the brace hook). Mutates
-- the left_hand spawn_data entry's `unit_name` to point at the crossbow
-- 3P unit. No ammo swap in preview path because vanilla preview doesn't
-- spawn the bow's arrow (`world_hero_previewer.lua:680-712` only handles
-- left_hand/right_hand entries; ammo_unit isn't fed through the preview
-- spawn pipeline — see line 689 conditional that's about is_ammo_weapon
-- THROWN items like javelins, not about arrows on bows).
mod:hook_safe("MenuWorldPreviewer", "equip_item", function(self, item_name, slot, backend_id, skin, skip_wield_anim)
    if item_name ~= "es_longbow" then return end
    local career = self._current_career_name
    if not career or career:sub(1, 3) ~= "wh_" then return end

    local slot_type = (type(slot) == "table" and slot.type) or nil
    if not slot_type then return end
    local info = self._item_info_by_slot and self._item_info_by_slot[slot_type]
    if not info or not info.spawn_data then return end

    local swapped = false
    for _, entry in ipairs(info.spawn_data) do
        if entry.left_hand then
            entry.unit_name = _SP_CROSSBOW_3P_UNIT
            swapped = true
        end
    end

    if swapped then
        mod:info("[wt sp-longbow-crossbow preview] swapped preview 3P bow → crossbow on career=%s", career)
    end
end)

-- Apply scale/offset to the inventory character preview.
-- The keep inventory uses MenuWorldPreviewer (see notes above the
-- brace-3P swap hook — class() copies parent methods, so hooks on
-- HeroPreviewer.equip_item never fire on MenuWorldPreviewer instances).
local function _is_unit(v) return type(v) == "userdata" and pcall(Unit.alive, v) end

-- _spawn_item_unit only sees the weapon template (e.g. we_one_hand_axe_template),
-- not the inventory item, so its item_data.name is NOT the weapon key. We
-- capture the mapping (per previewer, weak-keyed so it doesn't pin the
-- previewer in memory) at equip time and look it up at spawn.
local _mwp_pending_keys = setmetatable({}, { __mode = "k" })

mod:hook_safe("MenuWorldPreviewer", "equip_item", function(self, item_key, slot, backend_id, skin, skip_wield_anim)
    -- Store weapon key for MenuWorldPreviewer._spawn_item_unit lookup
    if item_key and type(item_key) == "string" then
        local slot_name = (type(slot) == "table" and slot.name) or (type(slot) == "string" and slot)
        if slot_name then
            local slot_type = slot_name:gsub("^slot_", "")
            local map = _mwp_pending_keys[self]
            if not map then map = {}; _mwp_pending_keys[self] = map end
            map[slot_type] = item_key
        end
    end
end)

mod:hook_safe("MenuWorldPreviewer", "_spawn_item_unit", function(self, unit, slot_type, item_data, ...)
    if not unit or not _is_unit(unit) then return end
    local map = _mwp_pending_keys[self]
    local weapon_key = map and map[slot_type]
    if not weapon_key then return end
    local career_name = _local_career_name() or self._character_name
                        or (self._profile and self._profile.name)
    if not career_name then return end

    local fake_slot = { right_unit_3p = unit }
    _scale_weapon_units(fake_slot, weapon_key, career_name)
    _offset_weapon_units(fake_slot, weapon_key, career_name)
end)

--[[
WEAPON-TRAIT POOL FILTERING
---------------------------
Lets the user enable/disable individual weapon traits from the VMF settings.
Adventure traits default ON (vanilla behaviour); Chaos Wastes traits default
OFF and only show in the UI when the `crafting_in_modded` mod is installed.

Mechanism: rewrite `WeaponTraits.combinations[pool]` (the table that
`crafting_in_modded` reads when rolling a trait on a crafted/rerolled weapon).
Every CW trait already lives in `WeaponTraits.traits` and `BuffTemplates`
because `weapon_traits_morris.lua` merges them in at load — they only fail to
appear in adventure because the vanilla `combinations.melee` / `.ranged_*`
pools don't list them. Adding them to those pools is sufficient.

`crafting_in_modded` does NOT hardcode any trait keys; it picks from
`WeaponTraits.combinations[master.trait_table_name]` at runtime
(see standard_forge.lua _reroll_traits + _make_craft_synth). So mutating
those tables here propagates to cim's reroll/craft UI automatically.

NOTE on file ordering: this block must come BEFORE the lifecycle callbacks
(`on_game_state_changed`, `on_setting_changed`, `on_disabled`) below — Lua 5.1
locals aren't hoisted, so a callback declared above us couldn't see these
local functions and would resolve to a nil global lookup at call time.
]]

-- Trait-key membership per pool. The toggle for a trait controls every pool
-- it can appear in. CW-cross-pool traits (headhunter, stagger_aoe_on_crit,
-- shield_splinters, deus_crit_chain_lightning) are listed once per pool they
-- belong to so the rebuilder can pick them up; the user-facing widget is a
-- single checkbox under whichever group is most natural.
local _trait_pool_sources = {
    melee = {
        vanilla = {
            "melee_attack_speed_on_crit",
            "melee_timed_block_cost",
            "melee_counter_push_power",
            "melee_increase_damage_on_block",
            "melee_reduce_cooldown_on_crit",
            "melee_shield_on_assist",
        },
        cw = {
            "stagger_aoe_on_crit",
            "armor_breaker",
            "shield_of_isha",
            "bloodthirst",
            "headhunter",
            "home_run",
            "shield_splinters",
            "serrated_blade",
            "crescendo_strike",
            "follow_up",
            "always_blocking",
            "deus_big_swing_stagger",
            "deus_crit_chain_lightning",
            "deus_collateral_damage_on_melee_killing_blow",
            "melee_heal_on_crit",
        },
    },
    ranged_ammo = {
        vanilla = {
            "ranged_restore_stamina_headshot",
            "ranged_replenish_ammo_headshot",
            "ranged_reduce_cooldown_on_crit",
            "ranged_replenish_ammo_on_crit",
            "ranged_increase_power_level_vs_armour_crit",
            "ranged_consecutive_hits_increase_power",
        },
        cw = {
            "headhunter",
            "stagger_aoe_on_crit",
            "shield_splinters",
            "refilling_shot",
            "piercing_projectiles",
            "deus_extra_shot",
            "deus_crit_chain_lightning",
            "deus_ranged_crit_explosion",
            "deus_ammo_pickup_reload_speed",
        },
    },
    ranged_heat = {
        vanilla = {
            "ranged_restore_stamina_headshot",
            "ranged_reduced_overcharge",
            "ranged_reduce_cooldown_on_crit",
            "ranged_remove_overcharge_on_crit",
            "ranged_increase_power_level_vs_armour_crit",
            "ranged_consecutive_hits_increase_power",
        },
        cw = {
            "headhunter",
            "stagger_aoe_on_crit",
            "shield_splinters",
            "piercing_projectiles",
            "deus_extra_shot",
            "deus_crit_chain_lightning",
            "deus_ranged_crit_explosion",
        },
    },
    trollhammer_torpedo = {
        vanilla = {
            "ranged_restore_stamina_headshot",
            "ranged_reduce_cooldown_on_crit",
            "ranged_increase_power_level_vs_armour_crit",
            "ranged_consecutive_hits_increase_power",
            "melee_timed_block_cost",
            "melee_increase_damage_on_block",
        },
        cw = {
            "headhunter",
            "stagger_aoe_on_crit",
            "shield_splinters",
            "refilling_shot",
            "piercing_projectiles",
            "deus_extra_shot",
            "deus_crit_chain_lightning",
            "deus_ranged_crit_explosion",
            "deus_ammo_pickup_reload_speed",
        },
    },
}

-- Snapshot of vanilla pools. Captured the first time apply_trait_filters runs
-- (so DLC/morris additions are already merged in). Used to revert on
-- on_disabled and to detect "no managed pool yet" cases.
local _initial_trait_pools = nil

local function _snapshot_trait_pools()
    if _initial_trait_pools then return end
    if not WeaponTraits or not WeaponTraits.combinations then return end
    _initial_trait_pools = {}
    for pool_key, _ in pairs(_trait_pool_sources) do
        local existing = WeaponTraits.combinations[pool_key]
        if existing then
            local copy = {}
            for i, entry in ipairs(existing) do
                copy[i] = { entry[1] }
            end
            _initial_trait_pools[pool_key] = copy
        end
    end
end

local function _trait_enabled(trait_key, is_cw)
    local prefix = is_cw and "cw_trait_" or "trait_"
    return mod:get(prefix .. trait_key) == true
end

local function apply_trait_filters()
    if not WeaponTraits or not WeaponTraits.combinations then return end
    _snapshot_trait_pools()
    if not _initial_trait_pools then return end

    for pool_key, sources in pairs(_trait_pool_sources) do
        local current = WeaponTraits.combinations[pool_key]
        if current then
            local seen = {}
            local rebuilt = {}
            local function _push(trait_key, is_cw)
                if seen[trait_key] then return end
                if not _trait_enabled(trait_key, is_cw) then return end
                if not WeaponTraits.traits[trait_key] then return end
                seen[trait_key] = true
                rebuilt[#rebuilt + 1] = { trait_key }
            end
            for _, t in ipairs(sources.vanilla) do _push(t, false) end
            for _, t in ipairs(sources.cw) do _push(t, true) end

            -- Empty pool → fall back to vanilla snapshot to avoid "no traits
            -- to roll" stalls in cim. Users who want zero traits can disable
            -- the mod outright.
            if #rebuilt == 0 and _initial_trait_pools[pool_key] then
                for i, entry in ipairs(_initial_trait_pools[pool_key]) do
                    rebuilt[i] = { entry[1] }
                end
            end

            -- Mutate in place so any code holding a reference to the pool
            -- table sees the new contents.
            for i = #current, 1, -1 do current[i] = nil end
            for i, entry in ipairs(rebuilt) do current[i] = entry end
        end
    end
end

local function revert_trait_pools()
    if not _initial_trait_pools then return end
    if not WeaponTraits or not WeaponTraits.combinations then return end
    for pool_key, snapshot in pairs(_initial_trait_pools) do
        local current = WeaponTraits.combinations[pool_key]
        if current then
            for i = #current, 1, -1 do current[i] = nil end
            for i, entry in ipairs(snapshot) do current[i] = { entry[1] } end
        end
    end
end

mod._apply_trait_filters = apply_trait_filters
mod._revert_trait_pools = revert_trait_pools

-- CLARIFY: VMF lifecycle callback. Fires on every game state transition
-- (StateLoading -> StateIngame, etc.) — re-applies the can_wield mutations
-- in case some other mod or game code reset ItemMasterList between states.
-- Idempotent (apply_weapon_unlocks strips before adding).
mod.on_game_state_changed = function()
    mod:info("Weapon Tweaker: Baseline Active")
    apply_weapon_unlocks()
    patch_career_actions_on_weapons()
    apply_trait_filters()
end

-- Clean disable: strip every cross-career career name this mod added to ItemMasterList[*].can_wield
-- and every ability action it injected into Weapons[*].actions. Without this, disabling the mod
-- via VMF would leave cross-career unlocks active on every affected weapon until game restart.
-- The restore-and-mutate phases of apply_weapon_unlocks / patch_career_actions_on_weapons already
-- handle the strip step on every call, so we just clear the management state and re-call: every
-- mod:get("unlock_*") read returns nil/false post-disable, so the add-back phase contributes nothing.
local function clear_weapon_unlocks()
    if not ItemMasterList then return end
    for career, weapons in pairs(weapon_unlock_map) do
        for _, weapon_key in ipairs(weapons) do
            local item = rawget(ItemMasterList, weapon_key)
            if item and item.can_wield then
                for i = #item.can_wield, 1, -1 do
                    if item.can_wield[i] == career then
                        table.remove(item.can_wield, i)
                    end
                end
            end
        end
    end
end

local function clear_career_action_injections()
    if not Weapons then return end
    for tmpl_key, actions in pairs(_career_action_injections) do
        local tmpl = Weapons[tmpl_key]
        if tmpl and tmpl.actions then
            for action_name in pairs(actions) do
                tmpl.actions[action_name] = nil
            end
        end
    end
    _career_action_injections = {}
end

mod.on_disabled = function()
    clear_weapon_unlocks()
    clear_career_action_injections()
    revert_trait_pools()
    mod:info("Weapon Tweaker disabled — cross-career unlocks, ability action injections, and trait-pool filters reverted")
end

mod.on_setting_changed = function(setting_id)
    if setting_id and (setting_id:find("^unlock_") or setting_id == "debug") then
        apply_weapon_unlocks()
        patch_career_actions_on_weapons()
        weapon_backend.refresh_on_setting_change(mod)
    elseif setting_id and (setting_id:find("^trait_") or setting_id:find("^cw_trait_")) then
        apply_trait_filters()
    end
end

mod:command("dump", "Dump equipped item data to log", function()
    local player = Managers.player:local_player()
    if not player then
        mod:echo("No local player found")
        return
    end

    local profile_index = player:profile_index()
    local profile = SPProfiles[profile_index]
    local career_index = player:career_index()
    local career = profile.careers[career_index]
    local career_name = career.name

    mod:echo("Career: " .. tostring(career_name))
    mod:info("=== EQUIPPED ITEM DUMP for %s ===", career_name)

    local inventory_ext = ScriptUnit.extension(player.player_unit, "inventory_system")
    local equipment = inventory_ext and inventory_ext:equipment()
    if not equipment or not equipment.slots then
        mod:echo("No equipment data available")
        return
    end

    for slot_name, slot_data in pairs(equipment.slots) do
        if slot_data.item_data then
            local item = slot_data.item_data
            local key = item.key or "?"
            local item_type = item.item_type or item.data and item.data.item_type or "?"
            local template = item.template or item.data and item.data.template or "?"
            local rarity = item.rarity or "?"
            local left = item.left_hand_unit or item.data and item.data.left_hand_unit or "none"
            local right = item.right_hand_unit or item.data and item.data.right_hand_unit or "none"

            mod:echo("%s: %s (%s)", slot_name, key, item_type)
            mod:info("[%s] key=%s  item_type=%s  template=%s  rarity=%s", slot_name, key, item_type, template, rarity)
            mod:info("[%s] left_hand_unit=%s", slot_name, left)
            mod:info("[%s] right_hand_unit=%s", slot_name, right)

            if item.can_wield then
                mod:info("[%s] can_wield=%s", slot_name, table.concat(item.can_wield, ", "))
            end

            if item.data then
                for data_key, data_val in pairs(item.data) do
                    if type(data_val) ~= "table" then
                        mod:info("[%s] data.%s=%s", slot_name, tostring(data_key), tostring(data_val))
                    end
                end
            end
        end
    end

    mod:info("=== END EQUIPPED ITEM DUMP ===")
    mod:echo("Dump written to log")
end)

mod:command("dump_actions", "Dump weapon action anim events (usage: wt dump_actions [pattern])", function(pattern)
    pattern = pattern or ""
    if not Weapons then mod:echo("Weapons not loaded yet.") return end
    local tmpl_count = 0
    local action_count = 0
    local sorted_keys = {}
    for tmpl_key, _ in pairs(Weapons) do
        if tmpl_key:find(pattern, 1, true) then
            sorted_keys[#sorted_keys + 1] = tmpl_key
        end
    end
    table.sort(sorted_keys)
    for _, tmpl_key in ipairs(sorted_keys) do
        local tmpl = Weapons[tmpl_key]
        local header = "=== " .. tmpl_key .. " (wield_anim=" .. tostring(tmpl.wield_anim) .. ") ==="
        mod:echo(header)
        mod:info(header)
        tmpl_count = tmpl_count + 1
        if tmpl.actions then
            for action_name, action_data in pairs(tmpl.actions) do
                for sub_name, sub in pairs(action_data) do
                    if type(sub) == "table" and (sub.anim_event or sub.anim_event_3p) then
                        local ae = tostring(sub.anim_event or "-")
                        local ae3 = tostring(sub.anim_event_3p or "-")
                        local line = "  " .. action_name .. "." .. sub_name .. "  1P=" .. ae .. "  3P=" .. ae3
                        mod:echo(line)
                        mod:info(line)
                        action_count = action_count + 1
                    end
                end
            end
        end
    end
    local summary = "dump_actions: " .. tmpl_count .. " templates, " .. action_count .. " actions"
    mod:echo(summary)
    mod:info(summary)
end)

mod:command("dump_weapons", "Dump all weapons with native careers and localized names", function()
    if not ItemMasterList then mod:echo("ItemMasterList not loaded.") return end
    local Localize = Localize
    local count = 0
    local total = 0
    local types_seen = {}
    local sorted = {}
    for key, item in pairs(ItemMasterList) do
        total = total + 1
        local t = item.item_type or item.slot_type or "nil"
        types_seen[t] = (types_seen[t] or 0) + 1
        if item.can_wield then
            sorted[#sorted + 1] = key
        end
    end
    table.sort(sorted)
    mod:echo("ItemMasterList: " .. total .. " total, " .. #sorted .. " with can_wield")
    local type_parts = {}
    for t, c in pairs(types_seen) do type_parts[#type_parts + 1] = t .. "=" .. c end
    mod:info("Types: " .. table.concat(type_parts, ", "))
    mod:info("=== WEAPON DUMP: key | item_type | slot_type | display_name | can_wield ===")
    for _, key in ipairs(sorted) do
        local item = ItemMasterList[key]
        local display = key
        if item.display_name then
            local ok, loc = pcall(Localize, item.display_name)
            if ok and loc then display = loc end
        end
        local wield = table.concat(item.can_wield, ",")
        local it = tostring(item.item_type or "nil")
        local st = tostring(item.slot_type or "nil")
        local line = key .. " | " .. it .. " | " .. st .. " | " .. display .. " | " .. wield
        mod:info(line)
        count = count + 1
    end
    mod:info("=== END WEAPON DUMP: %d weapons ===", count)
    mod:echo("Dumped " .. count .. " weapons to log")
end)

-- Install basic backend hooks (UI filtering and can_wield override)
weapon_backend.install(mod, weapon_unlock_map, apply_weapon_unlocks)
mod.weapon_unlock_map = weapon_unlock_map

-- Run trait-pool filtering once at module load. on_game_state_changed will
-- re-run later if pools weren't ready yet (e.g. WeaponTraits not loaded).
apply_trait_filters()

