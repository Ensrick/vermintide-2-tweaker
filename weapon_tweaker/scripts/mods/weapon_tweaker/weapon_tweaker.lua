local mod = get_mod("wt")
local weapon_backend = mod:dofile("scripts/mods/weapon_tweaker/weapon_tweaker_backend")

local MOD_VERSION = "0.11.17-dev"
mod:info("Weapon Tweaker v%s loaded", MOD_VERSION)
mod:echo("Weapon Tweaker v" .. MOD_VERSION)

-- CLARIFY: Patch NetworkLookup.rarities at module-load time so the "promo" rarity
-- (used by crafted items, see _equip_item hook ~L2384) round-trips through the
-- network table without crashing on unknown lookup. Idempotent; runs once per
-- script load. Must happen BEFORE any equip path can fire — see CHANGELOG 0.11.4
-- for the crash that prompted this.
local NL = rawget(_G, "NetworkLookup")
if NL and NL.rarities then
    local t = NL.rarities
    if not rawget(t, "promo") then
        local idx = #t + 1
        t[idx] = "promo"
        rawset(t, "promo", idx)
    end
end

local weapon_unlock_map = {
    -- Kruber
    es_mercenary      = { "dr_2h_axe", "dr_2h_hammer", "dr_1h_hammer", "dr_shield_hammer", "es_bastard_sword", "es_sword_shield_breton", "es_2h_sword_executioner", "es_2h_sword", "es_halberd", "we_2h_sword", "we_spear", "we_1h_spears_shield", "we_1h_sword", "es_1h_mace", "es_mace_shield", "es_dual_wield_hammer_sword", "wh_1h_axe", "wh_2h_billhook", "wh_1h_falchion", "es_1h_flail", "wh_1h_hammer", "wh_hammer_shield", "bw_1h_crowbill", "bw_1h_flail_flaming", "bw_sword", "es_deus_01", "es_1h_sword", "es_sword_shield", "es_2h_heavy_spear", "es_2h_hammer", "dr_handgun", "es_blunderbuss", "es_handgun", "we_longbow", "es_repeating_handgun" },
    es_huntsman       = { "dr_2h_axe", "dr_2h_hammer", "dr_1h_hammer", "dr_shield_hammer", "es_bastard_sword", "es_2h_sword_executioner", "es_2h_sword", "es_halberd", "we_2h_sword", "we_spear", "we_1h_spears_shield", "we_1h_sword", "es_1h_mace", "es_mace_shield", "es_dual_wield_hammer_sword", "wh_1h_axe", "wh_2h_billhook", "wh_1h_falchion", "es_1h_flail", "wh_1h_hammer", "wh_hammer_shield", "bw_1h_crowbill", "bw_1h_flail_flaming", "bw_sword", "es_deus_01", "es_1h_sword", "es_sword_shield", "es_2h_heavy_spear", "es_2h_hammer", "dr_handgun", "es_blunderbuss", "es_handgun", "we_longbow", "es_longbow", "es_repeating_handgun" },
    es_knight         = { "dr_2h_axe", "dr_2h_hammer", "dr_1h_hammer", "dr_shield_hammer", "es_bastard_sword", "es_2h_sword_executioner", "es_2h_sword", "es_halberd", "we_2h_sword", "we_spear", "we_1h_spears_shield", "we_1h_sword", "es_1h_mace", "es_mace_shield", "es_dual_wield_hammer_sword", "wh_1h_axe", "wh_2h_billhook", "wh_1h_falchion", "es_1h_flail", "wh_1h_hammer", "wh_hammer_shield", "bw_1h_crowbill", "bw_1h_flail_flaming", "bw_sword", "es_deus_01", "es_1h_sword", "es_sword_shield", "es_2h_heavy_spear", "es_2h_hammer", "dr_handgun", "es_blunderbuss", "es_handgun", "we_longbow", "es_repeating_handgun" },
    es_questingknight = { "dr_2h_axe", "dr_2h_hammer", "dr_1h_hammer", "dr_shield_hammer", "es_bastard_sword", "es_sword_shield_breton", "es_2h_sword_executioner", "es_2h_sword", "es_halberd", "we_2h_sword", "we_spear", "we_1h_spears_shield", "we_1h_sword", "es_1h_mace", "es_mace_shield", "es_dual_wield_hammer_sword", "wh_1h_axe", "wh_2h_billhook", "wh_1h_falchion", "es_1h_flail", "wh_1h_hammer", "wh_hammer_shield", "bw_1h_crowbill", "bw_1h_flail_flaming", "bw_sword", "es_deus_01", "es_1h_sword", "es_sword_shield", "es_2h_heavy_spear", "es_2h_hammer", "dr_handgun", "es_blunderbuss", "es_handgun", "we_longbow", "es_longbow", "es_repeating_handgun" },
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
    wh_captain        = { "wh_1h_axe", "wh_dual_wield_axe_falchion", "dr_1h_axe", "dr_dual_wield_hammers", "dr_1h_hammer", "wh_2h_billhook", "wh_dual_hammer", "wh_1h_falchion", "es_1h_flail", "wh_2h_sword", "wh_1h_hammer", "wh_2h_hammer", "we_2h_sword", "we_spear", "we_1h_sword", "es_halberd", "es_1h_mace", "es_1h_sword", "es_2h_heavy_spear", "wh_fencing_sword", "bw_1h_crowbill", "bw_1h_flail_flaming", "bw_sword", "dr_crossbow", "wh_brace_of_pistols", "wh_crossbow", "wh_deus_01", "we_crossbow_repeater", "wh_repeating_pistols", "wh_crossbow_repeater" },
    wh_bountyhunter   = { "wh_1h_axe", "wh_dual_wield_axe_falchion", "dr_1h_axe", "dr_dual_wield_hammers", "dr_1h_hammer", "wh_2h_billhook", "wh_dual_hammer", "wh_1h_falchion", "es_1h_flail", "wh_2h_sword", "wh_1h_hammer", "wh_2h_hammer", "we_2h_sword", "we_spear", "we_1h_sword", "es_halberd", "es_1h_mace", "es_1h_sword", "es_2h_heavy_spear", "wh_fencing_sword", "bw_1h_crowbill", "bw_1h_flail_flaming", "bw_sword", "dr_crossbow", "wh_brace_of_pistols", "wh_crossbow", "wh_deus_01", "we_crossbow_repeater", "wh_repeating_pistols", "wh_crossbow_repeater" },
    wh_zealot         = { "wh_1h_axe", "wh_dual_wield_axe_falchion", "dr_1h_axe", "dr_dual_wield_hammers", "dr_1h_hammer", "wh_2h_billhook", "wh_dual_hammer", "wh_1h_falchion", "es_1h_flail", "wh_2h_sword", "wh_1h_hammer", "wh_2h_hammer", "we_2h_sword", "we_spear", "we_1h_sword", "es_halberd", "es_1h_mace", "es_1h_sword", "es_2h_heavy_spear", "wh_fencing_sword", "bw_1h_crowbill", "bw_1h_flail_flaming", "bw_sword", "dr_crossbow", "wh_brace_of_pistols", "wh_crossbow", "wh_deus_01", "we_crossbow_repeater", "wh_repeating_pistols", "wh_crossbow_repeater" },
    wh_priest         = { "wh_1h_axe", "dr_1h_axe", "dr_dual_wield_hammers", "dr_1h_hammer", "dr_shield_hammer", "wh_2h_billhook", "wh_dual_hammer", "wh_1h_falchion", "es_1h_flail", "wh_flail_shield", "wh_1h_hammer", "wh_hammer_shield", "wh_hammer_book", "wh_2h_hammer", "we_spear", "we_1h_sword", "es_halberd", "es_1h_mace", "es_mace_shield", "es_1h_sword", "es_2h_heavy_spear", "bw_1h_crowbill", "bw_1h_flail_flaming", "bw_sword", "we_crossbow_repeater" },
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
    es_mercenary      = { wh_1h_axe = true },
    es_huntsman       = { wh_1h_axe = true },
    es_knight         = { wh_1h_axe = true },
    es_questingknight = { wh_1h_axe = true },
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

-- 3P body event remapping: player_unit IS the 3P body (receives anim_event_3p).
-- The non-player unit is the 1P hands (receives anim_event).
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

-- Apply scale/offset to the inventory character preview.
-- The new (post-WoM) inventory uses MenuWorldPreviewer instead of HeroPreviewer.
-- We probe both classes; whichever class owns the visible weapon should fire.
local _preview_probe_logged = false
local function _is_unit(v) return type(v) == "userdata" and pcall(Unit.alive, v) end

mod:hook_safe("HeroPreviewer", "equip_item", function(self, slot_name, item_data, ...)
    if not _preview_probe_logged then
        _preview_probe_logged = true
        mod:info("[preview_probe] FIRST CALL slot_name=%s item_data=%s", tostring(slot_name), tostring(item_data))
        if item_data then
            for k, v in pairs(item_data) do
                mod:info("[preview_probe]   item_data.%s = %s (%s)", tostring(k), tostring(v), type(v))
            end
        end
        for k, v in pairs(self) do
            local t = type(v)
            if t == "table" then
                mod:info("[preview_probe]   self.%s (table)", tostring(k))
            elseif _is_unit(v) then
                mod:info("[preview_probe]   self.%s (UNIT)", tostring(k))
            elseif t == "string" or t == "number" or t == "boolean" then
                mod:info("[preview_probe]   self.%s = %s", tostring(k), tostring(v))
            end
        end
    end
    if not item_data then return end
    local weapon_key = item_data.name or item_data.key
    if not weapon_key then return end
    local career_name = (self._career_name) or (self.career_name) or
                        (self._profile and self._profile.career) or
                        (self._character_name)
    if not career_name then return end

    -- Find the slot data by trying common storage patterns.
    local slot_data = nil
    for _, container in ipairs({"_equipment", "_items_spawn_data", "_equipped_items", "_spawned_items", "_previewer_units", "_units"}) do
        local c = self[container]
        if type(c) == "table" then
            if c[slot_name] and type(c[slot_name]) == "table" then
                slot_data = c[slot_name]
                break
            end
        end
    end

    -- Also probe top-level fields on self that look like slot tables containing unit fields.
    if not slot_data then
        for k, v in pairs(self) do
            if type(v) == "table" and (v.left_unit_1p or v.right_unit_1p or v.left_unit_3p or v.right_unit_3p) then
                slot_data = v
                break
            end
        end
    end

    if not _preview_probe_logged then
        _preview_probe_logged = true
        mod:info("[preview_probe] HeroPreviewer.equip_item slot=%s key=%s career=%s slot_data=%s",
                 tostring(slot_name), tostring(weapon_key), tostring(career_name), tostring(slot_data))
        for k, v in pairs(self) do
            if type(v) == "table" then
                mod:info("[preview_probe]   self.%s (table)", k)
            elseif _is_unit(v) then
                mod:info("[preview_probe]   self.%s (UNIT)", k)
            end
        end
        if slot_data then
            for k, v in pairs(slot_data) do
                mod:info("[preview_probe]   slot_data.%s = %s", k, type(v))
            end
        end
    end

    if slot_data then
        _scale_weapon_units(slot_data, weapon_key, career_name)
        _offset_weapon_units(slot_data, weapon_key, career_name)
    end
end)

-- MenuWorldPreviewer is the new inventory previewer. _spawn_item_unit fires
-- with the spawned unit as the first arg — we hook it to apply scale/offset.
-- MenuWorldPreviewer is the new (post-WoM) inventory previewer. It uses its
-- OWN spawned units, separate from the in-game keep player_unit's. Without
-- these hooks, scale/offset from _weapon_scale_overrides / _weapon_grip_offsets
-- only affect the in-game body and the menu preview shows unscaled weapons.
--
-- equip_item gets the actual weapon key as arg[1]; _spawn_item_unit only sees
-- the weapon template (e.g. we_one_hand_axe_template), not the inventory item,
-- so its item_data.name is NOT the weapon key. We capture the mapping
-- (per previewer, weak-keyed so it doesn't pin the previewer in memory) at
-- equip time and look it up at spawn.
local _mwp_pending_keys = setmetatable({}, { __mode = "k" })

-- equip_item is defined on HeroPreviewer (world_hero_previewer.lua:649) and inherited by
-- MenuWorldPreviewer. Hooking the parent guarantees the hook fires for both. HeroPreviewer
-- instances seed _mwp_pending_keys harmlessly — only MenuWorldPreviewer's _spawn_item_unit
-- hook below consumes the map, and entries are auto-cleared when the previewer GCs (weak keys).
mod:hook_safe("HeroPreviewer", "equip_item", function(self, item_key, slot, backend_id, skin, skip_wield_anim)
    if not item_key or type(item_key) ~= "string" then return end
    local slot_name = (type(slot) == "table" and slot.name) or (type(slot) == "string" and slot)
    if not slot_name then return end
    local slot_type = slot_name:gsub("^slot_", "")
    local map = _mwp_pending_keys[self]
    if not map then map = {}; _mwp_pending_keys[self] = map end
    map[slot_type] = item_key
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

-- CLARIFY: VMF lifecycle callback. Fires on every game state transition
-- (StateLoading -> StateIngame, etc.) — re-applies the can_wield mutations
-- in case some other mod or game code reset ItemMasterList between states.
-- Idempotent (apply_weapon_unlocks strips before adding).
mod.on_game_state_changed = function()
    mod:info("Weapon Tweaker: Baseline Active")
    apply_weapon_unlocks()
    patch_career_actions_on_weapons()
end

mod.on_setting_changed = function(setting_id)
    if setting_id and (setting_id:find("^unlock_") or setting_id == "debug") then
        apply_weapon_unlocks()
        patch_career_actions_on_weapons()
        weapon_backend.refresh_on_setting_change(mod)
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

-- ============================================================
-- Weapon Forge (Phase 1)
-- ============================================================
local _more_items_lib = nil
local _forge_pending = nil
local _forged_weapons = {}

local function _forge_detect_mil()
    if _more_items_lib then return true end
    local ok, lib = pcall(get_mod, "MoreItemsLibrary")
    if ok and lib then
        _more_items_lib = lib
        return true
    end
    return false
end

local function _forge_save()
    local save_data = {}
    for bid, w in pairs(_forged_weapons) do
        save_data[bid] = {
            item_key = w.item_key,
            properties = w.properties,
            trait = w.trait,
            traits = w.traits,
            skin = w.skin,
            power_level = w.power_level or 300,
            rarity = w.rarity,
        }
    end
    mod:set("forged_weapons", save_data)
end

local function _forge_load()
    local save_data = mod:get("forged_weapons")
    if not save_data or type(save_data) ~= "table" then return end
    _forged_weapons = {}
    for bid, w in pairs(save_data) do
        _forged_weapons[bid] = {
            item_key = w.item_key,
            properties = w.properties or {},
            trait = w.trait,
            traits = w.traits,
            skin = w.skin,
            power_level = w.power_level or 300,
            rarity = w.rarity,
        }
    end
end

local function _forge_create_item(weapon_data, backend_id)
    if not ItemMasterList then return nil end
    local item_key = weapon_data.item_key
    -- POTENTIAL BUG (LOW): per CLAUDE.md, ItemMasterList has a __index that
    -- calls `crashify` on unknown keys. `item_key` here comes from save data
    -- (`forged_weapons` setting) and could be stale if the user un-installed
    -- a DLC that defined the weapon. Use `rawget(ItemMasterList, item_key)`
    -- to defensively avoid the crashify path.
    local master = ItemMasterList[item_key]
    if not master then
        mod:echo("Forge: unknown weapon key '" .. tostring(item_key) .. "'")
        return nil
    end

    local props = weapon_data.properties or {}
    local trait = weapon_data.trait
    local traits_array = weapon_data.traits
    local skin = weapon_data.skin
    local power_level = weapon_data.power_level or 300

    local custom_props = "{"
    for k, v in pairs(props) do
        custom_props = custom_props .. '"' .. k .. '":' .. tostring(v) .. ','
    end
    custom_props = custom_props .. "}"

    local traits_table = {}
    if traits_array then
        for i, t in ipairs(traits_array) do traits_table[i] = t end
    elseif trait then
        traits_table[1] = trait
    end

    local custom_traits = "["
    for i, t in ipairs(traits_table) do
        if i > 1 then custom_traits = custom_traits .. "," end
        custom_traits = custom_traits .. '"' .. t .. '"'
    end
    custom_traits = custom_traits .. "]"

    local rarity = weapon_data.rarity or "exotic"

    local entry = table.clone(master, true)
    entry.mod_data = {
        backend_id = backend_id,
        ItemInstanceId = backend_id,
        CustomData = {
            traits = custom_traits,
            power_level = tostring(power_level),
            properties = custom_props,
            rarity = rarity,
        },
        rarity = rarity,
        traits = traits_table,
        power_level = power_level,
        properties = table.clone(props, true),
    }
    if skin then
        entry.mod_data.CustomData.skin = skin
        entry.mod_data.skin = skin
        if WeaponSkins and WeaponSkins.skins and WeaponSkins.skins[skin] then
            entry.mod_data.inventory_icon = WeaponSkins.skins[skin].inventory_icon
        end
    end
    entry.rarity = rarity

    return entry
end

local function _forge_inject_item(weapon_data, backend_id)
    if not _forge_detect_mil() then
        mod:echo("Forge: MoreItemsLibrary not found — install it from the Workshop")
        return false
    end

    local entry = _forge_create_item(weapon_data, backend_id)
    if not entry then return false end

    _more_items_lib:add_mod_items_to_local_backend({entry}, "weapon_tweaker")
    if Managers.backend then
        local items = Managers.backend:get_interface("items")
        if items then items:_refresh() end
    end
    if ItemHelper and ItemHelper.mark_backend_id_as_new then
        pcall(ItemHelper.mark_backend_id_as_new, backend_id)
    end
    return true
end

local function _forge_inject_all()
    if not _forge_detect_mil() then return end
    for bid, w in pairs(_forged_weapons) do
        -- Promo (Athanor-crafted) items go through `_athanor_inject_all` →
        -- backend_mirror:add_item, which produces an inventory-grade item with
        -- proper cosmetic/skin support. MIL is reserved for the legacy console
        -- `wt forge` flow (rarity = exotic).
        if w.rarity ~= "promo" then
            local entry = _forge_create_item(w, bid)
            if entry then
                _more_items_lib:add_mod_items_to_local_backend({entry}, "weapon_tweaker")
            end
        end
    end
    if Managers.backend then
        local items = Managers.backend:get_interface("items")
        if items then items:_refresh() end
    end
end

_forge_load()

-- CLARIFY: re-injects forged weapons after PlayFab's backend interfaces are
-- (re)created — this is the moment MoreItemsLibrary's items_interface accepts
-- new mod items. Without this, forged weapons saved across sessions would be
-- lost when the backend re-syncs at game start.
-- Using hook_safe (no return interception) because we don't need to wrap; we
-- just observe the lifecycle event.
mod:hook_safe("BackendManagerPlayFab", "_create_interfaces", function()
    _forge_load()
    _forge_inject_all()
    local count = 0
    for _ in pairs(_forged_weapons) do count = count + 1 end
    mod:info("Forge: restored %d forged weapons", count)
end)

-- ============================================================
-- Weapon Forge (Phase 2 — Athanor UI Hooks)
-- ============================================================
local _custom_forge_active = false
local _forge_loadout = {}
local _forge_item_props = {}
local _forge_panel_styled = false
local _forge_bg_colored = false

mod.open_forge = function()
    if not Managers.ui then
        mod:echo("Forge: UI not available")
        return
    end
    local ingame_ui = Managers.ui._ingame_ui
    if not ingame_ui then
        mod:echo("Forge: not in game")
        return
    end
    if ingame_ui:pending_transition() then return end
    _custom_forge_active = true
    _forge_loadout = {}
    _forge_item_props = {}
    ingame_ui:transition_with_fade("hero_view_force", {
        menu_state_name = "weave_forge",
    })
end

mod:hook_safe("HeroViewStateWeaveForge", "on_exit", function(self)
    _custom_forge_active = false
    _forge_loadout = {}
    _forge_item_props = {}
    _forge_panel_styled = false
    _forge_bg_colored = false
end)

-- --- Forge UI polish (runs each frame while forge is open) ---

local function _forge_get_widget(window, widget_name)
    local wbn = window and window._widgets_by_name
    return wbn and wbn[widget_name]
end

local function _forge_hide_widget(window, widget_name)
    local w = _forge_get_widget(window, widget_name)
    if w and w.content then w.content.visible = false end
end

local function _forge_set_text(window, widget_name, text)
    local w = _forge_get_widget(window, widget_name)
    if w and w.content then w.content.text = text end
end

local function _forge_set_style_color(window, widget_name, style_key, color)
    local w = _forge_get_widget(window, widget_name)
    if w and w.style and w.style[style_key] then
        w.style[style_key].color = color
    end
end

local function _forge_is_hovered(widget)
    if not widget or not widget.content then return false end
    local hs = widget.content.button_hotspot or widget.content.hotspot
    return hs and hs.is_hover
end

local function _forge_populate_item_panels(overview, item)
    if not item then return end
    local ow = overview._wt_overview_widget
    local pw = overview._wt_properties_widget
    local tw = overview._wt_trait_widget

    if ow then
        local inventory_icon, display_name = UIUtils.get_ui_information_from_item(item)
        local item_data = item.data
        local rarity = item.rarity or (item_data and item_data.rarity)
        local rarity_bg = UISettings.item_rarity_textures[rarity]
        local c = ow.content
        c.input_text = Localize(display_name or "")
        c.sub_title = item_data and Localize(item_data.slot_type or "") or ""
        c.icon_texture = inventory_icon or "icons_placeholder"
        c.icon_bg = rarity_bg or "icons_placeholder"
        c.item = item
        c.visible = true
    end

    if pw then
        local c = pw.content
        local count = 0
        if item.properties then
            for prop_key, prop_value in pairs(item.properties) do
                count = count + 1
                if count <= 2 then
                    local text = UIUtils.get_property_description(prop_key, prop_value)
                    c["button_hotspot_" .. count].disable_button = false
                    c["option_text_" .. count] = text or prop_key
                end
            end
        end
        for i = count + 1, 2 do
            c["button_hotspot_" .. i].disable_button = true
        end
        c.visible = true
    end

    if tw then
        local c = tw.content
        if item.traits and #item.traits > 0 then
            local trait_key = item.traits[1]
            local WeaponTraits = rawget(_G, "WeaponTraits")
            local trait_data = WeaponTraits and WeaponTraits.traits and WeaponTraits.traits[trait_key]
            if trait_data then
                c.icon_texture = trait_data.icon or "icons_placeholder"
                c.input_text = Localize(trait_data.display_name or "")
                c.sub_title = UIUtils.get_trait_description(trait_key) or ""
                c.locked = false
            end
        else
            c.locked = true
            c.input_text = ""
            c.sub_title = ""
        end
        c.visible = true
    end
end

local function _forge_hide_item_panels(overview)
    if overview._wt_overview_widget then overview._wt_overview_widget.content.visible = false end
    if overview._wt_properties_widget then overview._wt_properties_widget.content.visible = false end
    if overview._wt_trait_widget then overview._wt_trait_widget.content.visible = false end
end

local function _forge_apply_ui_polish(forge_state)
    local windows = forge_state._active_windows
    if not windows then return end

    local overview = nil
    local panel = nil
    local background = nil
    for _, win in pairs(windows) do
        local name = win.NAME
        if name == "HeroWindowWeaveForgeOverview" then overview = win
        elseif name == "HeroWindowWeaveForgePanel" then panel = win
        elseif name == "HeroWindowWeaveForgeBackground" then background = win
        end
    end

    -- === OVERVIEW: hide Athanor level, hide weapon level, fix power ===
    if overview then
        _forge_hide_widget(overview, "forge_level_title")
        _forge_hide_widget(overview, "forge_level_text")
        _forge_hide_widget(overview, "upgrade_button")
        _forge_hide_widget(overview, "upgrade_text")
        _forge_hide_widget(overview, "upgrade_bg")
        _forge_hide_widget(overview, "top_hdr_background_write_mask")

        for i = 1, 3 do
            _forge_hide_widget(overview, "viewport_level_title_" .. i)
            _forge_hide_widget(overview, "viewport_level_value_" .. i)
            _forge_hide_widget(overview, "viewport_panel_divider_" .. i)

            local highlight = _forge_get_widget(overview, "viewport_button_text_highlight_" .. i)
            if highlight and highlight.style then
                if highlight.style.background_top then
                    highlight.style.background_top.color = {255, 123, 123, 123}
                end
                if highlight.style.background_bottom then
                    highlight.style.background_bottom.color = {255, 123, 123, 123}
                end
                if highlight.style.background_top_light then
                    highlight.style.background_top_light.color = {200, 123, 123, 123}
                end
                if highlight.style.background_bottom_light then
                    highlight.style.background_bottom_light.color = {200, 123, 123, 123}
                end
            end

            local btn_highlight = _forge_get_widget(overview, "viewport_button_highlight_" .. i)
            if btn_highlight and btn_highlight.style then
                for sk, sv in pairs(btn_highlight.style) do
                    if type(sv) == "table" and sv.color then
                        sv.color = {sv.color[1], 123, 123, 123}
                    end
                end
            end
        end

        local items_backend = Managers.backend and Managers.backend:get_interface("items")
        if items_backend then
            local player = Managers.player and Managers.player:local_player()
            if player then
                local profile_index = player:profile_index()
                local profile = SPProfiles[profile_index]
                local career_index = player:career_index()
                local career = profile.careers[career_index]
                local career_name = career.name
                local slot_map = {[1] = "slot_melee", [3] = "slot_ranged"}
                for vp_idx, slot_name in pairs(slot_map) do
                    local bid = items_backend:get_loadout_item_id(career_name, slot_name)
                    if bid then
                        local item = items_backend:get_item_from_id(bid)
                        if item then
                            _forge_set_text(overview, "viewport_power_value_" .. vp_idx, tostring(item.power_level or 300))
                        end
                    end
                end
            end
        end
    end

    -- === VIEWPORT 2 (amulet): hide and show item detail panels on hover ===
    if overview then
        _forge_hide_widget(overview, "viewport_2")
        _forge_hide_widget(overview, "viewport_button_2")
        _forge_hide_widget(overview, "viewport_button_highlight_2")
        _forge_hide_widget(overview, "viewport_button_text_highlight_2")
        _forge_hide_widget(overview, "viewport_title_2")
        _forge_hide_widget(overview, "viewport_sub_title_2")
        _forge_hide_widget(overview, "viewport_power_title_2")
        _forge_hide_widget(overview, "viewport_power_value_2")
        _forge_hide_widget(overview, "change_button_2")
        _forge_hide_widget(overview, "panel_level_2")
        _forge_hide_widget(overview, "panel_power_2")

        if not overview._wt_panels_init then
            overview._wt_panels_init = true
            local UIWidgets = rawget(_G, "UIWidgets")
            local UIWidget = rawget(_G, "UIWidget")
            if UIWidgets and UIWidget and UIWidgets.create_item_option_overview then
                local panel_w = 430
                local ok1, ow_def = pcall(UIWidgets.create_item_option_overview, "viewport_panel_2", {panel_w, 130})
                local ok2, pw_def = pcall(UIWidgets.create_item_option_properties, "viewport_panel_2", {panel_w, 160})
                local ok3, tw_def = pcall(UIWidgets.create_item_option_trait, "viewport_panel_2", {panel_w, 160})

                if ok1 and ow_def then
                    local ok, ow = pcall(UIWidget.init, ow_def)
                    if ok and ow then
                        ow.offset = {10, 740, 20}
                        if ow.style then
                            if ow.style.icon_texture then ow.style.icon_texture.offset[2] = -20 end
                            if ow.style.icon_bg then ow.style.icon_bg.offset[2] = -20 end
                            if ow.style.input_text then ow.style.input_text.offset[2] = -53 end
                            if ow.style.input_text_shadow then ow.style.input_text_shadow.offset[2] = -55 end
                        end
                        ow.content.visible = false
                        overview._wt_overview_widget = ow
                    else
                        ok1 = false; ow_def = tostring(ow)
                    end
                end
                if ok2 and pw_def then
                    local ok, pw = pcall(UIWidget.init, pw_def)
                    if ok and pw then
                        pw.offset = {10, 500, 20}
                        if pw.style then
                            for _, suffix in ipairs({"option_text_", "option_text_shadow_", "option_text_disabled_", "option_text_disabled_shadow_", "icon_", "icon_disabled_"}) do
                                for i = 1, 2 do
                                    local s = pw.style[suffix .. i]
                                    if s and s.offset then s.offset[2] = s.offset[2] - 10 end
                                end
                            end
                        end
                        pw.content.visible = false
                        overview._wt_properties_widget = pw
                    else
                        ok2 = false; pw_def = tostring(pw)
                    end
                end
                if ok3 and tw_def then
                    local ok, tw = pcall(UIWidget.init, tw_def)
                    if ok and tw then
                        tw.offset = {10, 310, 20}
                        tw.content.visible = false
                        overview._wt_trait_widget = tw
                    else
                        ok3 = false; tw_def = tostring(tw)
                    end
                end

                local ow = overview._wt_overview_widget
                local pw = overview._wt_properties_widget
                local tw = overview._wt_trait_widget
                if overview._top_widgets then
                    if ow then overview._top_widgets[#overview._top_widgets + 1] = ow end
                    if pw then overview._top_widgets[#overview._top_widgets + 1] = pw end
                    if tw then overview._top_widgets[#overview._top_widgets + 1] = tw end
                end

                local created = (ok1 and "O" or "!O") .. (ok2 and "P" or "!P") .. (ok3 and "T" or "!T")
                mod:echo("Forge panels: " .. created)
                if not ok1 then mod:echo("Overview err: " .. tostring(ow_def)) end
                if not ok2 then mod:echo("Props err: " .. tostring(pw_def)) end
                if not ok3 then mod:echo("Trait err: " .. tostring(tw_def)) end
            else
                mod:echo("Forge panels: UIWidgets factory not available")
            end
        end

        local hovered_vp = nil
        local vp1_btn = _forge_get_widget(overview, "viewport_button_1")
        local vp3_btn = _forge_get_widget(overview, "viewport_button_3")
        if _forge_is_hovered(vp1_btn) then
            hovered_vp = 1
        elseif _forge_is_hovered(vp3_btn) then
            hovered_vp = 3
        end

        if hovered_vp then
            local slot_name = (hovered_vp == 1) and "slot_melee" or "slot_ranged"
            local items_backend = Managers.backend and Managers.backend:get_interface("items")
            local player = Managers.player and Managers.player:local_player()
            if player and items_backend then
                local profile_index = player:profile_index()
                local profile = SPProfiles[profile_index]
                local career_index = player:career_index()
                local career = profile.careers[career_index]
                local career_name = career.name
                local bid = items_backend:get_loadout_item_id(career_name, slot_name)
                local item = bid and items_backend:get_item_from_id(bid)
                if item then
                    _forge_populate_item_panels(overview, item)
                else
                    _forge_hide_item_panels(overview)
                end
            else
                _forge_hide_item_panels(overview)
            end
        else
            _forge_hide_item_panels(overview)
        end
    end

    -- === PANEL: hide essence, wheel rings, rebrand header ===
    if panel then
        _forge_hide_widget(panel, "essence_icon")
        _forge_hide_widget(panel, "essence_text")
        _forge_hide_widget(panel, "essence_panel")
        _forge_hide_widget(panel, "essence_tooltip")
        _forge_hide_widget(panel, "loadout_power_title")
        _forge_hide_widget(panel, "loadout_power_tooltip")

        local power_w = _forge_get_widget(panel, "loadout_power_text")
        if power_w and power_w.content then
            power_w.content.text = "MOD WEAPON CRAFTING"
            power_w.content.visible = true
            if power_w.style and power_w.style.text then
                power_w.style.text.font_size = 28
                power_w.style.text.text_color = {255, 255, 255, 255}
            end
            if power_w.style and power_w.style.text_shadow then
                power_w.style.text_shadow.font_size = 28
            end
        end

        _forge_hide_widget(panel, "background_wheel_1")
        _forge_hide_widget(panel, "hdr_background_wheel_1")
        for i = 1, 3 do
            _forge_hide_widget(panel, "wheel_ring_1_" .. i)
            _forge_hide_widget(panel, "wheel_ring_2_" .. i)
            _forge_hide_widget(panel, "hdr_wheel_ring_1_" .. i)
            _forge_hide_widget(panel, "hdr_wheel_ring_2_" .. i)
        end

        _forge_set_style_color(panel, "top_glow_smoke_1", "texture_id", {200, 180, 20, 10})
    end

    -- === BACKGROUND: change smoke colors to deep red ===
    if background and not _forge_bg_colored then
        _forge_set_style_color(background, "bottom_glow_smoke_1", "texture_id", {200, 180, 20, 10})
        _forge_set_style_color(background, "bottom_glow_smoke_2", "texture_id", {255, 200, 30, 10})
        _forge_set_style_color(background, "bottom_glow_smoke_3", "texture_id", {200, 180, 25, 15})
        _forge_set_style_color(background, "bottom_glow_embers_1", "texture_id", {130, 255, 60, 20})
        _forge_set_style_color(background, "bottom_glow_embers_3", "texture_id", {130, 255, 60, 20})
        _forge_bg_colored = true
    end

    -- === PROPERTIES sub-menu: hide level/mastery, fix power ===
    local properties_win = nil
    for _, win in pairs(windows) do
        if win.NAME == "HeroWindowWeaveProperties" then properties_win = win end
    end
    if properties_win then
        _forge_hide_widget(properties_win, "viewport_level_title")
        _forge_hide_widget(properties_win, "viewport_level_value")
        _forge_hide_widget(properties_win, "viewport_panel_divider")
        _forge_hide_widget(properties_win, "mastery_text")
        _forge_hide_widget(properties_win, "mastery_title_text")
        _forge_hide_widget(properties_win, "mastery_icon")
        _forge_hide_widget(properties_win, "mastery_tooltip")
        _forge_hide_widget(properties_win, "upgrade_button")
        _forge_hide_widget(properties_win, "upgrade_bg")
        _forge_hide_widget(properties_win, "upgrade_text")
        _forge_hide_widget(properties_win, "upgrade_essence_warning")
        _forge_hide_widget(properties_win, "background_wheel")
        _forge_hide_widget(properties_win, "hdr_background_wheel")
        for i = 1, 3 do
            _forge_hide_widget(properties_win, "wheel_ring_" .. i)
            _forge_hide_widget(properties_win, "hdr_wheel_ring_" .. i)
        end

        _forge_set_style_color(properties_win, "cluster_background_effect_1", "texture_id", {200, 180, 20, 10})

        local params = properties_win._params
        local sel_item = params and params.selected_item
        if sel_item and sel_item.backend_id then
            local items_backend = Managers.backend and Managers.backend:get_interface("items")
            if items_backend then
                local item = items_backend:get_item_from_id(sel_item.backend_id)
                if item then
                    _forge_set_text(properties_win, "viewport_power_value", tostring(item.power_level or 300))
                end
            end
        end
    end
end

mod:hook_safe("HeroViewStateWeaveForge", "update", function(self, dt, t)
    if _custom_forge_active then
        _forge_apply_ui_polish(self)
    end
end)

-- --- Backend safety hooks (prevent crashes for non-weave items) ---

-- CLARIFY: 16+ Weaves backend hooks below all follow the same pattern: when
-- our custom forge is active, return faked values (max forge level, infinite
-- essence, zero costs, etc.) so the Athanor UI doesn't gate on weave progression.
-- When the custom forge is NOT active, fall through to the original — leaves
-- vanilla Weaves mode untouched. The custom forge is opened only via our
-- `open_forge` keybind, so non-mod weaves play stays clean.
mod:hook("BackendInterfaceWeavesPlayFab", "get_forge_level", function(func, self)
    if _custom_forge_active then return 999 end
    return func(self)
end)

mod:hook("BackendInterfaceWeavesPlayFab", "get_essence", function(func, self)
    if _custom_forge_active then return 999999 end
    return func(self)
end)

mod:hook("BackendInterfaceWeavesPlayFab", "get_maximum_essence", function(func, self)
    if _custom_forge_active then return 999999 end
    return func(self)
end)

mod:hook("BackendInterfaceWeavesPlayFab", "get_total_essence", function(func, self)
    if _custom_forge_active then return 999999 end
    return func(self)
end)

mod:hook("BackendInterfaceWeavesPlayFab", "get_property_required_forge_level", function(func, self, property_name)
    if _custom_forge_active then return 0 end
    return func(self, property_name)
end)

mod:hook("BackendInterfaceWeavesPlayFab", "get_property_mastery_costs", function(func, self, property_name)
    if _custom_forge_active then return {0, 0, 0, 0, 0} end
    return func(self, property_name)
end)

mod:hook("BackendInterfaceWeavesPlayFab", "get_trait_required_forge_level", function(func, self, trait_key)
    if _custom_forge_active then return 0 end
    return func(self, trait_key)
end)

mod:hook("BackendInterfaceWeavesPlayFab", "get_trait_mastery_cost", function(func, self, trait_key)
    if _custom_forge_active then return 0 end
    return func(self, trait_key)
end)

mod:hook("BackendInterfaceWeavesPlayFab", "get_talent_mastery_cost", function(func, self, talent_name)
    if _custom_forge_active then return 0 end
    return func(self, talent_name)
end)

mod:hook("BackendInterfaceWeavesPlayFab", "get_career_magic_level", function(func, self, career_name)
    if _custom_forge_active then return 999 end
    local ok, result = pcall(func, self, career_name)
    if ok then return result end
    return 0
end)

mod:hook("BackendInterfaceWeavesPlayFab", "get_item_magic_level", function(func, self, item_backend_id)
    if _custom_forge_active then return 999 end
    local ok, result = pcall(func, self, item_backend_id)
    if ok then return result end
    return 0
end)

mod:hook("BackendInterfaceWeavesPlayFab", "max_magic_level", function(func, self)
    if _custom_forge_active then return 999 end
    return func(self)
end)

mod:hook("BackendInterfaceWeavesPlayFab", "forge_magic_level_cap", function(func, self)
    if _custom_forge_active then return 999 end
    return func(self)
end)

mod:hook("BackendInterfaceWeavesPlayFab", "magic_item_cost", function(func, self, item_key)
    if _custom_forge_active then return 0 end
    return func(self, item_key)
end)

mod:hook("BackendInterfaceWeavesPlayFab", "get_average_power_level", function(func, self, career_name)
    if _custom_forge_active then return 300 end
    local ok, result = pcall(func, self, career_name)
    if ok then return result end
    return 300
end)

mod:hook("BackendInterfaceWeavesPlayFab", "magic_item_upgrade_cost", function(func, self, num_levels, item_backend_id)
    if _custom_forge_active then return 0 end
    local ok, result = pcall(func, self, num_levels, item_backend_id)
    if ok then return result end
    return 0
end)

mod:hook("BackendInterfaceWeavesPlayFab", "career_upgrade_cost", function(func, self, num_levels, career_name)
    if _custom_forge_active then return 0 end
    local ok, result = pcall(func, self, num_levels, career_name)
    if ok then return result end
    return 0
end)

-- --- Forge loadout (redirect weave loadout to our own table) ---

mod:hook("BackendInterfaceWeavesPlayFab", "get_loadout_item_id", function(func, self, career_name, slot_name)
    if _custom_forge_active then
        local loadout = _forge_loadout[career_name]
        if loadout and loadout[slot_name] then
            return loadout[slot_name]
        end
        local items_backend = Managers.backend:get_interface("items")
        if items_backend then
            local ok, bid = pcall(items_backend.get_loadout_item_id, items_backend, career_name, slot_name)
            if ok then return bid end
        end
        return nil
    end
    return func(self, career_name, slot_name)
end)

mod:hook("BackendInterfaceWeavesPlayFab", "set_loadout_item", function(func, self, item_backend_id, career_name, slot_name)
    if _custom_forge_active then
        _forge_loadout[career_name] = _forge_loadout[career_name] or {}
        _forge_loadout[career_name][slot_name] = item_backend_id
        return true
    end
    return func(self, item_backend_id, career_name, slot_name)
end)

-- --- Property/trait/talent storage (redirect to our own data) ---

local function _forge_seed_item(career_name, item_backend_id)
    local key = (career_name or "") .. "|" .. (item_backend_id or "")
    if _forge_item_props[key] then return _forge_item_props[key] end

    local props = {}
    local traits = {}

    if item_backend_id then
        local items_backend = Managers.backend:get_interface("items")
        local item = items_backend and items_backend:get_item_from_id(item_backend_id)
        if item then
            if item.properties then
                local wp = rawget(_G, "WeaveProperties")
                local wp_props = wp and wp.properties
                local num_slots = 5
                local next_slot = 1
                for prop_key, value in pairs(item.properties) do
                    local weave_key = "weave_" .. prop_key
                    if wp_props and wp_props[weave_key] then
                        local filled = math.max(1, math.ceil(value * num_slots))
                        local indices = {}
                        for i = 1, filled do
                            indices[i] = next_slot
                            next_slot = next_slot + 1
                        end
                        props[weave_key] = indices
                    else
                        mod:info("Forge seed: no weave mapping for prop '%s' (tried '%s')", prop_key, weave_key)
                    end
                end
            end
            if item.traits then
                local wt = rawget(_G, "WeaveTraits")
                local wt_traits = wt and wt.traits
                for i, trait_key in ipairs(item.traits) do
                    local weave_key = "weave_" .. trait_key
                    if wt_traits and wt_traits[weave_key] then
                        traits[weave_key] = i
                    else
                        mod:info("Forge seed: no weave mapping for trait '%s' (tried '%s')", trait_key, weave_key)
                    end
                end
            end
        end
    end

    _forge_item_props[key] = {properties = props, traits = traits}
    return _forge_item_props[key]
end

local function _forge_apply_to_item(career_name, item_backend_id)
    if not item_backend_id then return end
    local items_backend = Managers.backend:get_interface("items")
    local item = items_backend and items_backend:get_item_from_id(item_backend_id)
    if not item then return end

    local data = _forge_seed_item(career_name, item_backend_id)
    local num_slots = 5

    local new_props = {}
    for weave_key, slots in pairs(data.properties) do
        local prop_key = weave_key:gsub("^weave_", "")
        local value = #slots / num_slots
        new_props[prop_key] = math.min(value, 1.0)
    end
    item.properties = new_props

    local new_traits = {}
    for weave_key, _ in pairs(data.traits) do
        local trait_key = weave_key:gsub("^weave_", "")
        new_traits[#new_traits + 1] = trait_key
    end
    item.traits = new_traits

    local cjson_mod = rawget(_G, "cjson")
    if cjson_mod and item.CustomData then
        item.CustomData.properties = cjson_mod.encode(new_props)
        item.CustomData.traits = cjson_mod.encode(new_traits)
    end

    -- Persist edits to bubble grid back into our forged_weapons save entry.
    local saved = _forged_weapons[item_backend_id]
    if saved then
        saved.properties = new_props
        saved.traits = new_traits
        saved.trait = new_traits[1]
        _forge_save()
    end
end

mod:hook("BackendInterfaceWeavesPlayFab", "get_loadout_properties", function(func, self, career_name, item_backend_id)
    if _custom_forge_active then
        local data = _forge_seed_item(career_name, item_backend_id)
        return data.properties
    end
    return func(self, career_name, item_backend_id)
end)

mod:hook("BackendInterfaceWeavesPlayFab", "get_loadout_traits", function(func, self, career_name, item_backend_id)
    if _custom_forge_active then
        local data = _forge_seed_item(career_name, item_backend_id)
        return data.traits
    end
    return func(self, career_name, item_backend_id)
end)

mod:hook("BackendInterfaceWeavesPlayFab", "get_loadout_talents", function(func, self, career_name)
    if _custom_forge_active then return {} end
    return func(self, career_name)
end)

mod:hook("BackendInterfaceWeavesPlayFab", "get_mastery", function(func, self, career_name, item_backend_id)
    if _custom_forge_active then return 0, 0 end
    local ok, a, b = pcall(func, self, career_name, item_backend_id)
    if ok then return a, b end
    return 0, 0
end)

mod:hook("BackendInterfaceWeavesPlayFab", "set_loadout_property", function(func, self, career_name, property_key, slot_index, item_backend_id)
    if _custom_forge_active then
        local data = _forge_seed_item(career_name, item_backend_id)
        local props = data.properties
        if not props[property_key] then
            props[property_key] = {}
        end
        props[property_key][#props[property_key] + 1] = slot_index
        _forge_apply_to_item(career_name, item_backend_id)
        return
    end
    return func(self, career_name, property_key, slot_index, item_backend_id)
end)

mod:hook("BackendInterfaceWeavesPlayFab", "remove_loadout_property", function(func, self, career_name, property_key, slot_index, item_backend_id)
    if _custom_forge_active then
        local data = _forge_seed_item(career_name, item_backend_id)
        local slots = data.properties[property_key]
        if slots then
            for i, s in ipairs(slots) do
                if s == slot_index then
                    table.remove(slots, i)
                    break
                end
            end
            if #slots == 0 then
                data.properties[property_key] = nil
            end
        end
        _forge_apply_to_item(career_name, item_backend_id)
        return
    end
    return func(self, career_name, property_key, slot_index, item_backend_id)
end)

mod:hook("BackendInterfaceWeavesPlayFab", "set_loadout_trait", function(func, self, career_name, trait_key, slot_index, item_backend_id)
    if _custom_forge_active then
        local data = _forge_seed_item(career_name, item_backend_id)
        data.traits[trait_key] = slot_index
        _forge_apply_to_item(career_name, item_backend_id)
        return
    end
    return func(self, career_name, trait_key, slot_index, item_backend_id)
end)

mod:hook("BackendInterfaceWeavesPlayFab", "remove_loadout_trait", function(func, self, career_name, trait_key, item_backend_id)
    if _custom_forge_active then
        local data = _forge_seed_item(career_name, item_backend_id)
        data.traits[trait_key] = nil
        _forge_apply_to_item(career_name, item_backend_id)
        return
    end
    return func(self, career_name, trait_key, item_backend_id)
end)

mod:hook("BackendInterfaceWeavesPlayFab", "set_loadout_talent", function(func, self, career_name, talent_key, slot_index)
    if _custom_forge_active then return end
    return func(self, career_name, talent_key, slot_index)
end)

mod:hook("BackendInterfaceWeavesPlayFab", "remove_loadout_talent", function(func, self, career_name, talent_key)
    if _custom_forge_active then return end
    return func(self, career_name, talent_key)
end)

-- CLARIFY: while the custom forge is open, suppress backend commits entirely
-- to prevent any of the simulated weave actions (set_loadout_property, trait
-- updates) from being persisted to PlayFab. Without this, exiting the forge
-- could leave the user's PlayFab profile in an inconsistent weave state.
-- POTENTIAL BUG (LOW): if the user opens our custom forge mid-session AFTER
-- having made legitimate changes that haven't yet committed, those legit
-- changes are also blocked while our forge is open. Probably negligible since
-- vanilla auto-commits, but worth noting.
mod:hook("BackendManagerPlayFab", "commit", function(func, self, skip_queue, commit_complete_callback)
    if _custom_forge_active then return end
    return func(self, skip_queue, commit_complete_callback)
end)

-- --- Weapon list: show ALL weapons, not just weave "magic" rarity ---

-- CLARIFY: replaces the vanilla "magic-rarity weave templates" list with the
-- full set of every weapon the current career can wield (including cross-career
-- unlocks added by `apply_weapon_unlocks`). Iterating `pairs(ItemMasterList)`
-- is safe vs the crashify __index (we only read existing keys).
mod:hook("HeroWindowWeaveForgeWeapons", "_setup_weapon_list", function(func, self)
    if not _custom_forge_active then return func(self) end

    local backend_items = Managers.backend:get_interface("items")
    local selected_slot_name = self._selected_slot_name
    local career_name = self._career_name
    local career_settings = CareerSettings[career_name]
    local item_slot_types = career_settings.item_slot_types_by_slot_name[selected_slot_name]
    local weapon_layout = {}

    for key, item_data in pairs(ItemMasterList) do
        local slot_type = item_data.slot_type
        if slot_type and table.contains(item_slot_types, slot_type) then
            local can_wield = item_data.can_wield
            if can_wield and table.contains(can_wield, career_name) then
                if item_data.item_type ~= "weapon_skin" and item_data.rarity ~= "magic" then
                    local item = backend_items:get_item_from_key(key)
                    weapon_layout[#weapon_layout + 1] = {
                        key = key,
                        item_data = item_data,
                        backend_id = item and item.backend_id,
                    }
                end
            end
        end
    end

    self:_populate_list(weapon_layout)

    -- Strip weave-specific "Magic Level: 100" and "1800" power text from each entry; this is just a crafting template list.
    local scrollbar_data = self._scrollbars and self._scrollbars.weapons
    local list_widgets = scrollbar_data and scrollbar_data.list_widgets
    if list_widgets then
        for _, widget in ipairs(list_widgets) do
            local c = widget.content
            c.level_title = ""
            c.power_text = ""
            c.power_title = ""
            c.magic_level = 0
            c.level_progress = 0
        end
    end
end)

-- Keep the level/power fields blank — vanilla `_sync_backend_loadout` repopulates them every refresh.
mod:hook("HeroWindowWeaveForgeWeapons", "_sync_backend_loadout", function(func, self)
    func(self)
    if not _custom_forge_active then return end
    local scrollbar_data = self._scrollbars and self._scrollbars.weapons
    local list_widgets = scrollbar_data and scrollbar_data.list_widgets
    if list_widgets then
        for _, widget in ipairs(list_widgets) do
            local c = widget.content
            c.level_title = ""
            c.power_text = ""
            c.power_title = ""
        end
    end
end)

-- --- Weapon select: present item without locked/essence state ---

mod:hook("HeroWindowWeaveForgeWeapons", "_present_item", function(func, self, item_key, activate_spin)
    if not _custom_forge_active then return func(self, item_key, activate_spin) end

    local viewport_data = self._viewport_data
    if viewport_data and viewport_data.item_previewer then
        viewport_data.item_previewer:destroy()
        viewport_data.item_previewer = nil
    end

    local backend_items = Managers.backend:get_interface("items")
    local item = backend_items:get_item_from_key(item_key)
    local display_item = item

    if not display_item then
        -- POTENTIAL BUG (LOW): unguarded ItemMasterList[item_key] read.
        -- item_key here comes from the weapon list populated in
        -- _setup_weapon_list (~L2241) which iterates `pairs(ItemMasterList)` so
        -- the key IS guaranteed to exist — so this is technically safe today.
        -- But fragile against future code changes (e.g. populating from a
        -- different source). Prefer `rawget(ItemMasterList, item_key)`.
        local item_data = table.clone(ItemMasterList[item_key])
        item_data.key = item_key
        display_item = { data = item_data, key = item_key }
    end

    local viewport_widget = viewport_data.widget
    local item_previewer = self:_create_item_previewer(viewport_widget, display_item, activate_spin)
    viewport_data.item_previewer = item_previewer
    viewport_data.item = display_item

    local item_data = display_item.data
    local power_level = display_item.power_level or 300

    local widgets_by_name = self._widgets_by_name
    widgets_by_name.viewport_level_value.content.visible = false
    widgets_by_name.viewport_level_title.content.visible = false
    widgets_by_name.viewport_power_value.content.text = tostring(power_level)
    widgets_by_name.viewport_power_title.content.visible = true
    widgets_by_name.viewport_power_value.content.visible = true
    widgets_by_name.viewport_title.content.text = Localize(item_data.display_name)
    widgets_by_name.viewport_sub_title.content.text = Localize(item_data.item_type)

    self:_set_presentation_locked_state(false)
    self._selected_item_locked = false
    self:_setup_weapon_stats(display_item)

    return item_key
end)

-- --- Weapon select: never show locked/unlock UI in custom forge ---

mod:hook("HeroWindowWeaveForgeWeapons", "_set_presentation_locked_state", function(func, self, locked)
    if not _custom_forge_active then return func(self, locked) end
    func(self, false)
end)

-- --- Weapon select: "CRAFT" button instead of "Equip" ---

mod:hook("HeroWindowWeaveForgeWeapons", "_update_equip_button_status", function(func, self, equipable_item, is_item_equipped)
    if not _custom_forge_active then return func(self, equipable_item, is_item_equipped) end

    local viewport_data = self._viewport_data
    if viewport_data then
        local equip_button = viewport_data.equip_button
        equip_button.content.button_hotspot.disable_button = not self._selected_item_id
        equip_button.content.title_text = "CRAFT"
    end
end)

-- --- Weapon select: on_list_index_selected — always enable craft button ---

mod:hook("HeroWindowWeaveForgeWeapons", "_on_list_index_selected", function(func, self, index)
    if not _custom_forge_active then return func(self, index) end

    local scrollbars = self._scrollbars
    local scrollbar_data = scrollbars.weapons
    local list_widgets = scrollbar_data.list_widgets

    for i, widget in ipairs(list_widgets) do
        local content = widget.content
        local hotspot = content.button_hotspot
        local is_selected = i == index

        hotspot.is_selected = is_selected

        if is_selected then
            self._selected_backend_id = self:_present_item(content.key)
            self._selected_item_id = content.key
        end
    end

    self._selected_list_index = index
    self:_update_equip_button_status(true, false)
end)

-- Build an Athanor-crafted item via the PlayFab backend mirror so it shows up
-- as a real inventory item (purple `promo` rarity, eligible for cosmetic skin
-- changes). Unlike MoreItemsLibrary's `add_mod_items_to_local_backend`, this
-- path doesn't tag the entry as a mod template — so the cosmetics screen and
-- skin swapper treat it as a normal owned weapon.
local function _athanor_inject_item(weapon_data, backend_id)
    local backend_mirror = Managers.backend and Managers.backend:get_backend_mirror()
    if not backend_mirror then return nil, "backend mirror not ready" end

    local cjson_mod = rawget(_G, "cjson")
    local props = weapon_data.properties or {}
    local traits = weapon_data.traits or (weapon_data.trait and {weapon_data.trait}) or {}

    local custom_data = {
        power_level = tostring(weapon_data.power_level or 300),
        rarity = weapon_data.rarity or "promo",
    }
    if cjson_mod then
        custom_data.properties = cjson_mod.encode(props)
        custom_data.traits = cjson_mod.encode(traits)
    end
    if weapon_data.skin then custom_data.skin = weapon_data.skin end

    local item = {
        ItemId = weapon_data.item_key,
        ItemInstanceId = backend_id,
        CustomData = custom_data,
    }

    local ok, err = pcall(backend_mirror.add_item, backend_mirror, backend_id, item)
    if not ok then return nil, err end
    return backend_id
end

-- Re-add every saved Athanor weapon (rarity=promo) to the live backend mirror
-- after PlayFab finishes its sync. Items not flagged promo go through the older
-- MIL path via `_forge_inject_all` instead.
local function _athanor_inject_all()
    local count = 0
    for bid, w in pairs(_forged_weapons) do
        if w.rarity == "promo" then
            local ok = _athanor_inject_item(w, bid)
            if ok then count = count + 1 end
        end
    end
    if count > 0 then mod:info("Athanor: restored %d crafted weapons", count) end
end

-- Replay saved Athanor weapons after PlayFab finishes its sync (same lifecycle
-- event as `_forge_inject_all`, but we hook separately to keep the logic local
-- to the Athanor section and avoid forward references).
mod:hook_safe("BackendManagerPlayFab", "_create_interfaces", function()
    _athanor_inject_all()
end)

-- --- Weapon select: craft item on equip press ---

mod:hook("HeroWindowWeaveForgeWeapons", "_equip_item", function(func, self, backend_id_or_key)
    if not _custom_forge_active then return func(self, backend_id_or_key) end

    local item_key = self._selected_item_id
    if not item_key then
        mod:echo("Craft failed: no weapon selected")
        return
    end

    local new_backend_id = Application.guid()
    local weapon_data = {
        item_key = item_key,
        properties = {},
        traits = {},
        power_level = 300,
        rarity = "promo",
    }

    local injected, err = _athanor_inject_item(weapon_data, new_backend_id)
    if not injected then
        mod:echo("Craft failed: " .. tostring(err))
        return
    end

    _forged_weapons[new_backend_id] = weapon_data
    _forge_save()

    local career_name = self._career_name
    local slot_name = self._selected_slot_name
    local backend_items = Managers.backend:get_interface("items")
    local ok2, err2 = pcall(backend_items.set_loadout_item, backend_items, new_backend_id, career_name, slot_name)
    if not ok2 then
        mod:echo("Equip failed: " .. tostring(err2))
    end

    -- POTENTIAL BUG (LOW): two unguarded reads — `ItemMasterList[item_key]`
    -- and chained `.display_name` access. item_key reaches here only after
    -- successful selection from the weapon list (which iterates pairs over
    -- ItemMasterList) so it's guaranteed to exist. Same caveat as line ~2307.
    mod:echo("Crafted & saved: " .. tostring(Localize(ItemMasterList[item_key].display_name)) .. " [" .. tostring(weapon_data.rarity) .. "]")

    self:_sync_backend_loadout()
    self._equip_pulse_duration = 0.5
end)

-- --- Overview: hide amulet, hide level, show real power ---

mod:hook("HeroWindowWeaveForgeOverview", "_initialize_viewports", function(func, self)
    if _custom_forge_active then
        self.amulet_introduced = false
    end
    return func(self)
end)

-- --- DIAGNOSTIC: dump forge UI widget data ---

local function _forge_dump_widgets(window_name, win)
    local w = win._widgets_by_name
    if not w then
        mod:info("DUMP [%s] _widgets_by_name=nil, checking fields:", window_name)
        for k, v in pairs(win) do
            if type(v) == "table" and k:find("widget") then
                mod:info("  field: %s (table, #%d)", k, #v)
            elseif type(v) ~= "function" then
                mod:info("  field: %s = %s", k, tostring(v))
            end
        end
        return
    end
    mod:info("=== DUMP [%s] ===", window_name)
    for name, widget in pairs(w) do
        local parts = {}
        if widget.content then
            for k, v in pairs(widget.content) do
                if type(v) == "string" and #v < 60 then
                    parts[#parts + 1] = k .. '="' .. v .. '"'
                elseif type(v) == "boolean" or type(v) == "number" then
                    parts[#parts + 1] = k .. "=" .. tostring(v)
                end
            end
        end
        local sparts = {}
        if widget.style then
            for sk, sv in pairs(widget.style) do
                if type(sv) == "table" then
                    if sv.color then
                        local c = sv.color
                        sparts[#sparts + 1] = sk .. ".color={" .. tostring(c[1]) .. "," .. tostring(c[2]) .. "," .. tostring(c[3]) .. "," .. tostring(c[4]) .. "}"
                    end
                    if sv.text_color then
                        local c = sv.text_color
                        sparts[#sparts + 1] = sk .. ".text_color={" .. tostring(c[1]) .. "," .. tostring(c[2]) .. "," .. tostring(c[3]) .. "," .. tostring(c[4]) .. "}"
                    end
                    if sv.font_size then
                        sparts[#sparts + 1] = sk .. ".font_size=" .. tostring(sv.font_size)
                    end
                end
            end
        end
        mod:info("  [%s] content: %s", name, table.concat(parts, ", "))
        if #sparts > 0 then
            mod:info("    style: %s", table.concat(sparts, ", "))
        end
    end
    mod:info("=== END [%s] ===", window_name)
end

mod:command("forge_dump", "Dump all forge window widget names to log", function()
    if not _custom_forge_active then
        mod:echo("Open the forge first (B key), then run this command")
        return
    end
    local ingame_ui = Managers.ui and Managers.ui._ingame_ui
    if not ingame_ui then
        mod:echo("No ingame_ui")
        return
    end
    local view_name = ingame_ui.current_view
    if not view_name then
        mod:echo("No current_view")
        return
    end
    local hero_view = ingame_ui.views and ingame_ui.views[view_name]
    if not hero_view then
        mod:echo("No view object for: " .. tostring(view_name))
        return
    end
    mod:info("=== FORGE UI DUMP ===")
    mod:info("current_view = %s", tostring(view_name))

    local forge_state = nil
    if hero_view._machine and hero_view._machine._state then
        forge_state = hero_view._machine._state
        mod:info("forge_state via _machine._state: %s (NAME=%s)", tostring(forge_state), tostring(forge_state.NAME))
    end
    if not forge_state then
        mod:echo("Could not find forge state on hero_view._machine._state")
        return
    end

    mod:info("--- forge_state fields ---")
    for k, v in pairs(forge_state) do
        if type(v) ~= "function" then
            local vstr = tostring(v)
            if type(v) == "table" then
                local count = 0
                for _ in pairs(v) do count = count + 1 end
                vstr = "table(" .. count .. ")"
            end
            mod:info("  state.%s = %s (%s)", k, vstr, type(v))
        end
    end

    local found = 0
    local active_windows = forge_state._active_windows
    if active_windows then
        mod:info("--- _active_windows ---")
        for idx, win in pairs(active_windows) do
            local win_name = win.NAME or win.__class_name or tostring(win)
            mod:info("Window[%s]: %s", tostring(idx), tostring(win_name))
            _forge_dump_widgets(tostring(idx) .. "_" .. tostring(win_name), win)
            found = found + 1
        end
    else
        mod:info("_active_windows is nil, scanning forge_state for _widgets_by_name:")
        for k, v in pairs(forge_state) do
            if type(v) == "table" and rawget(v, "_widgets_by_name") then
                mod:info("  Found _widgets_by_name on state.%s", k)
                _forge_dump_widgets(k, v)
                found = found + 1
            end
        end
    end
    mod:info("=== END FORGE UI DUMP (found %d windows) ===", found)
    mod:echo("Dump written to log (" .. found .. " windows found)")
end)

mod:command("forge_dump_props", "Dump properties sub-menu widgets and seed data", function()
    if not _custom_forge_active then
        mod:echo("Open the forge first (B key)")
        return
    end
    local ingame_ui = Managers.ui and Managers.ui._ingame_ui
    if not ingame_ui then mod:echo("No ingame_ui") return end
    local view_name = ingame_ui.current_view
    local hero_view = ingame_ui.views and ingame_ui.views[view_name]
    if not hero_view or not hero_view._machine then mod:echo("No hero_view") return end
    local forge_state = hero_view._machine._state
    if not forge_state then mod:echo("No forge_state") return end
    local windows = forge_state._active_windows
    if not windows then mod:echo("No _active_windows") return end

    mod:echo("Layout: " .. tostring(forge_state._selected_layout_name))
    local found_props = false
    for idx, win in pairs(windows) do
        mod:echo("Window[" .. tostring(idx) .. "]: " .. tostring(win.NAME))
        if win.NAME == "HeroWindowWeaveProperties" then
            found_props = true
            local wbn = win._widgets_by_name
            if wbn then
                local names = {}
                for name, widget in pairs(wbn) do
                    local info = name
                    if widget.content then
                        if widget.content.text then
                            info = info .. "=" .. tostring(widget.content.text)
                        end
                        if widget.content.visible == false then
                            info = info .. " [HIDDEN]"
                        end
                    end
                    names[#names + 1] = info
                end
                table.sort(names)
                for _, n in ipairs(names) do
                    mod:echo("  " .. n)
                end
            end
            mod:echo("_item_backend_id: " .. tostring(win._item_backend_id))
            mod:echo("_career_name: " .. tostring(win._career_name))
            local p = win._params
            if p then
                mod:echo("params.selected_item: " .. tostring(p.selected_item))
                if p.selected_item then
                    mod:echo("  .key: " .. tostring(p.selected_item.key or p.selected_item.data and p.selected_item.data.key))
                    mod:echo("  .backend_id: " .. tostring(p.selected_item.backend_id))
                end
                mod:echo("params.selected_unit_name: " .. tostring(p.selected_unit_name))
                mod:echo("params.selected_slot_name: " .. tostring(p.selected_slot_name))
            end
            mod:echo("_viewport_widget: " .. tostring(win._viewport_widget))
            mod:echo("_viewport_widget_definition: " .. tostring(win._viewport_widget_definition))
            mod:echo("_item_previewer: " .. tostring(win._item_previewer))
            mod:echo("_unit_previewer: " .. tostring(win._unit_previewer))
            mod:echo("_previewer_initialized: " .. tostring(win._previewer_initialized))
        end
    end
    if not found_props then
        mod:echo("HeroWindowWeaveProperties not active — click a weapon first")
    end

    local items_backend = Managers.backend and Managers.backend:get_interface("items")
    if items_backend then
        local player = Managers.player and Managers.player:local_player()
        if player then
            local pi = player:profile_index()
            local profile = SPProfiles[pi]
            local ci = player:career_index()
            local career_name = profile.careers[ci].name
            for _, slot in ipairs({"slot_melee", "slot_ranged"}) do
                local bid = items_backend:get_loadout_item_id(career_name, slot)
                if bid then
                    local item = items_backend:get_item_from_id(bid)
                    if item then
                        mod:echo(slot .. ": " .. tostring(item.key) .. " power=" .. tostring(item.power_level))
                        if item.properties then
                            for pk, pv in pairs(item.properties) do
                                local wk = "weave_" .. pk
                                local wp = rawget(_G, "WeaveProperties")
                                local mapped = wp and wp.properties and wp.properties[wk] and "YES" or "NO"
                                mod:echo("  prop: " .. pk .. "=" .. tostring(pv) .. " -> " .. wk .. " mapped=" .. mapped)
                            end
                        end
                        if item.traits then
                            for i, tk in ipairs(item.traits) do
                                local wk = "weave_" .. tk
                                local wt = rawget(_G, "WeaveTraits")
                                local mapped = wt and wt.traits and wt.traits[wk] and "YES" or "NO"
                                mod:echo("  trait: " .. tk .. " -> " .. wk .. " mapped=" .. mapped)
                            end
                        end
                    end
                end
            end
        end
    end
end)

mod:command("forge_dump_backend", "Dump forge backend hook returns to log", function()
    if not _custom_forge_active then
        mod:echo("Open the forge first (B key)")
        return
    end
    local weaves = Managers.backend and Managers.backend:get_interface("weaves")
    local items = Managers.backend and Managers.backend:get_interface("items")
    if not weaves or not items then
        mod:echo("Backend not available")
        return
    end
    local player = Managers.player:local_player()
    local profile_index = player:profile_index()
    local profile = SPProfiles[profile_index]
    local career_index = player:career_index()
    local career = profile.careers[career_index]
    local career_name = career.name
    mod:info("=== FORGE BACKEND DUMP career=%s ===", career_name)
    for _, slot in ipairs({"slot_melee", "slot_ranged"}) do
        local bid = weaves:get_loadout_item_id(career_name, slot)
        mod:info("  get_loadout_item_id(%s, %s) = %s", career_name, slot, tostring(bid))
        if bid then
            local item = items:get_item_from_id(bid)
            mod:info("  item from backend: %s", item and tostring(item.key) or "nil")
            if item then
                mod:info("    power_level: %s", tostring(item.power_level))
                mod:info("    rarity: %s", tostring(item.rarity))
                if item.properties then
                    for pk, pv in pairs(item.properties) do
                        mod:info("    prop: %s = %s", pk, tostring(pv))
                    end
                else
                    mod:info("    properties: nil")
                end
                if item.traits then
                    for i, t in ipairs(item.traits) do
                        mod:info("    trait[%d]: %s", i, tostring(t))
                    end
                else
                    mod:info("    traits: nil")
                end
            end
            local props = weaves:get_loadout_properties(career_name, bid)
            mod:info("  get_loadout_properties result:")
            if props then
                for pk, pv in pairs(props) do
                    mod:info("    %s = %s", pk, tostring(pv))
                end
            else
                mod:info("    nil")
            end
            local traits = weaves:get_loadout_traits(career_name, bid)
            mod:info("  get_loadout_traits result:")
            if traits then
                for tk, tv in pairs(traits) do
                    mod:info("    %s = %s", tostring(tk), tostring(tv))
                end
            else
                mod:info("    nil")
            end
        end
    end
    mod:info("  get_forge_level: %s", tostring(weaves:get_forge_level()))
    mod:info("  get_essence: %s", tostring(weaves:get_essence()))
    mod:info("=== END FORGE BACKEND DUMP ===")
    mod:echo("Backend dump written to log")
end)

-- Dump everything relevant to the equipped melee/ranged so we can reason about rarity/icons together.
mod:command("craft_dump", "Dump equipped item + rarity/localization/network data", function()
    local items = Managers.backend and Managers.backend:get_interface("items")
    local weaves = Managers.backend and Managers.backend:get_interface("weaves")
    local mirror = Managers.backend and Managers.backend:get_backend_mirror()
    if not items or not mirror then
        mod:echo("Backend not ready")
        return
    end
    local player = Managers.player:local_player()
    local profile_index = player:profile_index()
    local profile = SPProfiles[profile_index]
    local career_index = player:career_index()
    local career = profile.careers[career_index]
    local career_name = career.name

    local NL = rawget(_G, "NetworkLookup")
    local nl_rarities = NL and NL.rarities
    local nl_promo_idx = nl_rarities and rawget(nl_rarities, "promo")

    mod:info("=== CRAFT DUMP career=%s ===", career_name)
    mod:info("[NetworkLookup] rarities.promo index = %s", tostring(nl_promo_idx))
    mod:info("[UISettings.item_rarity_textures]")
    if UISettings and UISettings.item_rarity_textures then
        for _, r in ipairs({"plentiful","common","rare","exotic","unique","magic","promo","default"}) do
            mod:info("  [%s] = %s", r, tostring(UISettings.item_rarity_textures[r]))
        end
    end
    mod:info("[RaritySettings]")
    local RS = rawget(_G, "RaritySettings")
    if RS then
        for _, r in ipairs({"plentiful","common","rare","exotic","unique","magic","promo"}) do
            local entry = rawget(RS, r)
            mod:info("  [%s] exists=%s display=%s", r, tostring(entry ~= nil),
                entry and tostring(entry.display_name) or "<nil>")
        end
    end

    for _, slot in ipairs({"slot_melee","slot_ranged"}) do
        mod:info("--- slot=%s ---", slot)
        local items_bid = items:get_loadout_item_id(career_name, slot)
        local weaves_bid = weaves and weaves:get_loadout_item_id(career_name, slot)
        mod:info("  items.get_loadout_item_id  = %s", tostring(items_bid))
        mod:info("  weaves.get_loadout_item_id = %s", tostring(weaves_bid))
        local item = items_bid and items:get_item_from_id(items_bid)
        if item then
            local data = item.data or ItemMasterList[item.key] or {}
            mod:info("  item.key       = %s", tostring(item.key))
            mod:info("  item.ItemId    = %s", tostring(item.ItemId))
            mod:info("  item.rarity    = %s", tostring(item.rarity))
            mod:info("  data.rarity    = %s", tostring(data.rarity))
            mod:info("  display_name   = %s -> %s", tostring(data.display_name), tostring(Localize(data.display_name or "")))
            mod:info("  inventory_icon = %s", tostring(data.inventory_icon))
            mod:info("  power_level    = %s", tostring(item.power_level))
            local resolved_bg = UISettings and UISettings.item_rarity_textures and UISettings.item_rarity_textures[item.rarity]
            mod:info("  -> rarity_bg lookup = %s", tostring(resolved_bg))
            if item.CustomData then
                for k, v in pairs(item.CustomData) do
                    mod:info("  CustomData[%s] = %s", tostring(k), tostring(v))
                end
            else
                mod:info("  CustomData = nil")
            end
            if item.properties then
                for k, v in pairs(item.properties) do
                    mod:info("  properties[%s] = %s", tostring(k), tostring(v))
                end
            else
                mod:info("  properties = nil")
            end
            if item.traits then
                for i, t in ipairs(item.traits) do
                    mod:info("  traits[%d] = %s", i, tostring(t))
                end
            else
                mod:info("  traits = nil")
            end
        else
            mod:info("  no item resolved for backend_id=%s", tostring(items_bid))
        end
    end

    mod:info("--- recently-added items (rarity=promo) ---")
    local inv = mirror._inventory_items or {}
    local count = 0
    for bid, it in pairs(inv) do
        if it and it.rarity == "promo" then
            count = count + 1
            mod:info("  [%s] key=%s rarity=%s pl=%s", tostring(bid), tostring(it.key), tostring(it.rarity), tostring(it.power_level))
            if count >= 10 then mod:info("  ...truncated"); break end
        end
    end
    if count == 0 then mod:info("  (none found)") end
    mod:info("=== END CRAFT DUMP ===")
    mod:echo(string.format("Craft dump written. promo items: %d, NL.rarities.promo idx: %s", count, tostring(nl_promo_idx)))
end)

mod:command("forge", "Start forging a weapon (usage: wt forge <weapon_key>)", function(item_key)
    if not item_key then
        mod:echo("Usage: wt forge <weapon_key>")
        mod:echo("  Then: wt forge_trait <trait_name>")
        mod:echo("  Then: wt forge_props <prop1>=<value> <prop2>=<value>")
        mod:echo("  Then: wt forge_confirm")
        mod:echo("Use 'wt dump_weapons' to see available weapon keys.")
        return
    end
    if not ItemMasterList then
        mod:echo("Forge: ItemMasterList not loaded yet")
        return
    end
    -- ItemMasterList has a __index metamethod that calls Crashify on missing keys
    -- (CLAUDE.md). User-typed weapon keys via the `wt forge` command may not exist —
    -- use rawget so the guard doesn't crash itself.
    local master = rawget(ItemMasterList, item_key)
    if not master then
        mod:echo("Forge: unknown weapon key '" .. item_key .. "'")
        return
    end
    _forge_pending = {
        item_key = item_key,
        properties = {},
        trait = nil,
        skin = nil,
        power_level = 300,
    }
    local display = item_key
    if master.display_name then
        local ok, loc = pcall(Localize, master.display_name)
        if ok and loc then display = loc end
    end
    mod:echo("Forge: preparing " .. display .. " (" .. item_key .. ")")
    mod:echo("  Set trait: wt forge_trait <trait_name>")
    mod:echo("  Set props: wt forge_props <prop>=<0-1> ...")
    mod:echo("  Set skin:  wt forge_skin <skin_key>")
    mod:echo("  Set power: wt forge_power <1-300>")
    mod:echo("  Confirm:   wt forge_confirm")
    mod:echo("  Cancel:    wt forge_cancel")
end)

mod:command("forge_trait", "Set trait for pending forge (usage: wt forge_trait <trait_name>)", function(trait)
    if not _forge_pending then
        mod:echo("Forge: no weapon pending — run 'wt forge <weapon_key>' first")
        return
    end
    if not trait then
        mod:echo("Usage: wt forge_trait <trait_name>")
        return
    end
    _forge_pending.trait = trait
    mod:echo("Forge: trait set to " .. trait)
end)

mod:command("forge_props", "Set properties for pending forge (usage: wt forge_props crit_chance=0.5 attack_speed=1)", function(...)
    if not _forge_pending then
        mod:echo("Forge: no weapon pending — run 'wt forge <weapon_key>' first")
        return
    end
    local args = {...}
    if #args == 0 then
        mod:echo("Usage: wt forge_props <prop>=<value> ...")
        mod:echo("  Values are 0.0-1.0 (fraction of max)")
        return
    end
    for _, arg in ipairs(args) do
        local key, val = arg:match("^([^=]+)=(.+)$")
        if key and val then
            local num = tonumber(val)
            if num then
                _forge_pending.properties[key] = num
                mod:echo("  " .. key .. " = " .. tostring(num))
            else
                mod:echo("  Invalid value for " .. key .. ": " .. val)
            end
        else
            mod:echo("  Invalid format: " .. arg .. " (expected key=value)")
        end
    end
end)

mod:command("forge_skin", "Set skin for pending forge (usage: wt forge_skin <skin_key>)", function(skin)
    if not _forge_pending then
        mod:echo("Forge: no weapon pending — run 'wt forge <weapon_key>' first")
        return
    end
    if not skin then
        _forge_pending.skin = nil
        mod:echo("Forge: skin cleared")
        return
    end
    _forge_pending.skin = skin
    mod:echo("Forge: skin set to " .. skin)
end)

mod:command("forge_power", "Set power level for pending forge (usage: wt forge_power <1-300>)", function(val)
    if not _forge_pending then
        mod:echo("Forge: no weapon pending — run 'wt forge <weapon_key>' first")
        return
    end
    local num = tonumber(val)
    if not num or num < 1 or num > 300 then
        mod:echo("Usage: wt forge_power <1-300>")
        return
    end
    _forge_pending.power_level = math.floor(num)
    mod:echo("Forge: power level set to " .. _forge_pending.power_level)
end)

mod:command("forge_cancel", "Cancel pending forge", function()
    if not _forge_pending then
        mod:echo("Forge: nothing pending")
        return
    end
    _forge_pending = nil
    mod:echo("Forge: cancelled")
end)

mod:command("forge_confirm", "Create the forged weapon", function()
    if not _forge_pending then
        mod:echo("Forge: no weapon pending — run 'wt forge <weapon_key>' first")
        return
    end

    local rnd = math.random(1000000)
    local backend_id = _forge_pending.item_key .. "_" .. rnd .. "_forged"

    if _forge_inject_item(_forge_pending, backend_id) then
        _forged_weapons[backend_id] = {
            item_key = _forge_pending.item_key,
            properties = _forge_pending.properties,
            trait = _forge_pending.trait,
            skin = _forge_pending.skin,
            power_level = _forge_pending.power_level,
        }
        _forge_save()

        local master = ItemMasterList[_forge_pending.item_key]
        local display = _forge_pending.item_key
        if master and master.display_name then
            local ok, loc = pcall(Localize, master.display_name)
            if ok and loc then display = loc end
        end
        mod:echo("Forge: created " .. display .. " [" .. backend_id .. "]")
        _forge_pending = nil
    end
end)

mod:command("forge_list", "List all forged weapons", function()
    local count = 0
    for bid, w in pairs(_forged_weapons) do
        count = count + 1
        local display = w.item_key
        if ItemMasterList and ItemMasterList[w.item_key] and ItemMasterList[w.item_key].display_name then
            local ok, loc = pcall(Localize, ItemMasterList[w.item_key].display_name)
            if ok and loc then display = loc end
        end
        local parts = { display }
        if w.trait then parts[#parts + 1] = "trait=" .. w.trait end
        local prop_strs = {}
        for k, v in pairs(w.properties) do
            prop_strs[#prop_strs + 1] = k .. "=" .. tostring(v)
        end
        if #prop_strs > 0 then parts[#parts + 1] = table.concat(prop_strs, ", ") end
        parts[#parts + 1] = "power=" .. tostring(w.power_level or 300)
        mod:echo("[" .. count .. "] " .. table.concat(parts, " | ") .. "  id=" .. bid)
    end
    if count == 0 then
        mod:echo("Forge: no forged weapons")
    else
        mod:echo("Forge: " .. count .. " weapon(s)")
    end
end)

mod:command("forge_delete", "Delete a forged weapon (usage: wt forge_delete <backend_id or index>)", function(id_or_idx)
    if not id_or_idx then
        mod:echo("Usage: wt forge_delete <backend_id or index from forge_list>")
        return
    end

    local idx = tonumber(id_or_idx)
    local target_bid = nil

    if idx then
        local count = 0
        for bid, _ in pairs(_forged_weapons) do
            count = count + 1
            if count == idx then
                target_bid = bid
                break
            end
        end
        if not target_bid then
            mod:echo("Forge: no weapon at index " .. tostring(idx))
            return
        end
    else
        if _forged_weapons[id_or_idx] then
            target_bid = id_or_idx
        else
            mod:echo("Forge: no weapon with id '" .. id_or_idx .. "'")
            return
        end
    end

    if _forge_detect_mil() then
        pcall(_more_items_lib.remove_mod_items_from_local_backend, _more_items_lib, {target_bid}, "weapon_tweaker")
    end
    _forged_weapons[target_bid] = nil
    _forge_save()
    if Managers.backend then
        local items = Managers.backend:get_interface("items")
        if items then items:_refresh() end
    end
    mod:echo("Forge: deleted " .. target_bid)
end)

-- Install basic backend hooks (UI filtering and can_wield override)
weapon_backend.install(mod, weapon_unlock_map, apply_weapon_unlocks)
mod.weapon_unlock_map = weapon_unlock_map

