local mod = get_mod("t")
local weapon_backend = mod:dofile("scripts/mods/tweaker/tweaker_weapon_backend")

local function _feature_enabled(setting_id, default_value)
    local value = mod:get(setting_id)
    if value == nil then
        return default_value ~= false
    end

    return value == true
end

local _ALL_CAREERS = {
    "dr_ironbreaker", "dr_slayer",  "dr_ranger",  "dr_engineer",
    "es_huntsman",    "es_knight",  "es_mercenary", "es_questingknight",
    "we_shade",       "we_maidenguard", "we_waywatcher", "we_thornsister",
    "wh_zealot",      "wh_bountyhunter", "wh_captain", "wh_priest",
    "bw_scholar",     "bw_adept",   "bw_unchained", "bw_necromancer",
}

-- ============================================================
-- Per-weapon career unlocks
-- ============================================================
-- Each setting unlock_CAREER_WEAPON adds that career to the weapon's
-- can_wield list so the career can equip the weapon normally.

-- Per-career weapon unlock map.
-- Each career lists only the weapons it doesn't normally have access to
-- but whose animations are known-safe to cross-equip.
-- Key: career name. Value: list of weapon item keys.
local _WEAPON_UNLOCK_MAP = {
    -- Kruber: other-faction weapons (native es_* weapons already equippable)
    -- es_spear/es_spear_shield/we_spear_shield don't exist in ItemMasterList; bw_fireball_staff key invalid
    es_mercenary      = { "dr_1h_axe", "wh_1h_axe", "dr_1h_hammer", "wh_1h_hammer", "dr_shield_hammer", "wh_hammer_shield", "bw_sword", "we_longbow", "es_sword_shield", "we_1h_sword",
                          "wh_crossbow", "wh_2h_sword", "dr_crossbow", "dr_handgun", "we_spear", "es_sword_shield_breton" },
    es_huntsman       = { "dr_1h_axe", "wh_1h_axe", "dr_1h_hammer", "wh_1h_hammer", "dr_shield_hammer", "wh_hammer_shield", "bw_sword", "we_longbow", "es_sword_shield", "we_1h_sword",
                          "wh_crossbow", "wh_2h_sword", "dr_crossbow", "dr_handgun", "we_spear", "es_sword_shield_breton" },
    es_knight         = { "dr_1h_axe", "wh_1h_axe", "dr_1h_hammer", "wh_1h_hammer", "dr_shield_hammer", "wh_hammer_shield", "bw_sword", "we_longbow", "es_sword_shield", "we_1h_sword",
                          "wh_crossbow", "wh_2h_sword", "dr_crossbow", "dr_handgun", "we_spear", "es_sword_shield_breton" },
    es_questingknight = { "dr_1h_axe", "wh_1h_axe", "dr_1h_hammer", "wh_1h_hammer", "dr_shield_hammer", "wh_hammer_shield", "bw_sword", "we_longbow", "we_1h_sword",
                          "wh_crossbow", "wh_2h_sword", "dr_crossbow", "dr_handgun", "we_spear" },
    -- Bardin
    dr_ranger      = { "es_1h_mace", "wh_1h_axe", "wh_1h_hammer", "es_mace_shield", "wh_hammer_shield", "es_1h_sword", "bw_sword", "bw_1h_crowbill", "we_1h_sword",
                       "es_2h_sword", "es_halberd", "es_handgun", "wh_crossbow", "wh_2h_sword", "we_spear" },
    dr_ironbreaker = { "es_1h_mace", "wh_1h_axe", "wh_1h_hammer", "es_mace_shield", "wh_hammer_shield", "es_1h_sword", "bw_sword", "bw_1h_crowbill", "we_1h_sword",
                       "es_2h_sword", "es_halberd", "es_handgun", "wh_crossbow", "wh_2h_sword", "we_spear" },
    dr_slayer      = { "es_1h_mace", "wh_1h_axe", "wh_1h_hammer", "es_mace_shield", "wh_hammer_shield", "es_1h_sword", "bw_sword", "bw_1h_crowbill", "we_1h_sword",
                       "es_2h_sword", "es_halberd", "es_handgun", "wh_crossbow", "wh_2h_sword", "we_spear" },
    dr_engineer    = { "es_1h_mace", "wh_1h_axe", "wh_1h_hammer", "es_mace_shield", "wh_hammer_shield", "es_1h_sword", "bw_sword", "bw_1h_crowbill", "we_1h_sword",
                       "es_2h_sword", "es_halberd", "es_handgun", "wh_crossbow", "wh_2h_sword", "we_spear" },
    -- Kerillian
    we_waywatcher  = { "es_longbow", "wh_fencing_sword", "wh_1h_falchion", "es_1h_flail", "es_1h_sword", "es_1h_mace", "dr_1h_axe", "dr_1h_hammer", "wh_1h_axe", "wh_1h_hammer", "bw_sword", "bw_1h_crowbill",
                       "es_2h_sword", "es_halberd", "es_handgun", "wh_crossbow", "wh_2h_sword", "dr_crossbow", "dr_handgun", "we_1h_spears_shield", "es_bastard_sword" },
    we_maidenguard = { "we_longbow", "es_longbow", "wh_fencing_sword", "wh_1h_falchion", "es_1h_flail", "es_1h_sword", "es_1h_mace", "dr_1h_axe", "dr_1h_hammer", "wh_1h_axe", "wh_1h_hammer", "bw_sword", "bw_1h_crowbill",
                       "es_2h_sword", "es_halberd", "es_handgun", "wh_crossbow", "wh_2h_sword", "dr_crossbow", "dr_handgun", "es_bastard_sword" },
    we_shade       = { "we_longbow", "es_longbow", "wh_fencing_sword", "wh_1h_falchion", "es_1h_flail", "es_1h_sword", "es_1h_mace", "dr_1h_axe", "dr_1h_hammer", "wh_1h_axe", "wh_1h_hammer", "bw_sword", "bw_1h_crowbill",
                       "es_2h_sword", "es_halberd", "es_handgun", "wh_crossbow", "wh_2h_sword", "dr_crossbow", "dr_handgun", "we_1h_spears_shield", "es_bastard_sword" },
    we_thornsister = { "we_longbow", "es_longbow", "wh_fencing_sword", "wh_1h_falchion", "es_1h_flail", "es_1h_sword", "es_1h_mace", "dr_1h_axe", "dr_1h_hammer", "wh_1h_axe", "wh_1h_hammer", "bw_sword", "bw_1h_crowbill",
                       "es_2h_sword", "es_halberd", "es_handgun", "wh_crossbow", "wh_2h_sword", "dr_crossbow", "dr_handgun", "we_1h_spears_shield", "es_bastard_sword" },
    -- Saltzpyre: wh_crossbow is native
    wh_captain      = { "es_1h_mace", "es_1h_sword", "es_longbow", "dr_1h_hammer", "dr_1h_axe", "bw_sword", "we_longbow", "bw_1h_crowbill", "we_1h_sword",
                        "es_2h_sword", "es_halberd", "es_handgun", "wh_2h_sword", "dr_crossbow", "dr_handgun", "we_spear" },
    wh_bountyhunter = { "es_1h_mace", "es_1h_sword", "es_longbow", "dr_1h_hammer", "dr_1h_axe", "bw_sword", "we_longbow", "bw_1h_crowbill", "we_1h_sword",
                        "es_2h_sword", "es_halberd", "es_handgun", "wh_2h_sword", "dr_crossbow", "dr_handgun", "we_spear" },
    wh_zealot       = { "es_1h_mace", "es_1h_sword", "es_longbow", "dr_1h_hammer", "dr_1h_axe", "bw_sword", "we_longbow", "bw_1h_crowbill", "we_1h_sword",
                        "es_2h_sword", "es_halberd", "es_handgun", "wh_2h_sword", "dr_crossbow", "dr_handgun", "we_spear" },
    wh_priest       = { "es_1h_mace", "es_1h_sword", "es_longbow", "dr_1h_hammer", "dr_1h_axe", "bw_sword", "we_longbow", "es_mace_shield", "dr_shield_hammer", "bw_1h_crowbill", "we_1h_sword",
                        "es_2h_sword", "es_halberd", "es_handgun", "wh_2h_sword", "dr_crossbow", "dr_handgun", "we_spear" },
    -- Sienna: bw_* are native
    bw_scholar    = { "es_1h_sword", "es_1h_mace", "we_1h_sword", "dr_1h_axe", "dr_1h_hammer", "wh_1h_axe", "wh_1h_hammer",
                      "es_2h_sword", "es_halberd", "es_handgun", "wh_crossbow", "wh_2h_sword", "dr_crossbow", "dr_handgun", "we_spear" },
    bw_adept      = { "es_1h_sword", "es_1h_mace", "we_1h_sword", "dr_1h_axe", "dr_1h_hammer", "wh_1h_axe", "wh_1h_hammer",
                      "es_2h_sword", "es_halberd", "es_handgun", "wh_crossbow", "wh_2h_sword", "dr_crossbow", "dr_handgun", "we_spear" },
    bw_unchained  = { "es_1h_sword", "es_1h_mace", "we_1h_sword", "dr_1h_axe", "dr_1h_hammer", "wh_1h_axe", "wh_1h_hammer",
                      "es_2h_sword", "es_halberd", "es_handgun", "wh_crossbow", "wh_2h_sword", "dr_crossbow", "dr_handgun", "we_spear" },
    bw_necromancer= { "es_1h_sword", "es_1h_mace", "we_1h_sword", "dr_1h_axe", "dr_1h_hammer", "wh_1h_axe", "wh_1h_hammer",
                      "es_2h_sword", "es_halberd", "es_handgun", "wh_crossbow", "wh_2h_sword", "dr_crossbow", "dr_handgun", "we_spear" },
}

-- Saved originals keyed by weapon_key. nil value means the original can_wield was nil.
-- Use _original_can_wield_saved[key]=true as the "has been saved" sentinel.
local _original_can_wield       = {}
local _original_can_wield_saved = {}

local function apply_weapon_unlocks()
    if not ItemMasterList then return end

    -- Collect every weapon key this mod might touch.
    local all_weapon_keys = {}
    for _, weapons in pairs(_WEAPON_UNLOCK_MAP) do
        for _, weapon_key in ipairs(weapons) do
            all_weapon_keys[weapon_key] = true
        end
    end

    for weapon_key in pairs(all_weapon_keys) do
        local item = ItemMasterList[weapon_key]
        if item then
            -- Save original once (including nil originals).
            if not _original_can_wield_saved[weapon_key] then
                _original_can_wield_saved[weapon_key] = true
                local real_orig = item.can_wield
                if real_orig then
                    local orig = {}
                    for i, v in ipairs(real_orig) do orig[i] = v end
                    _original_can_wield[weapon_key] = orig
                end
                -- else: _original_can_wield[weapon_key] stays nil (original was nil)
            end

            -- Restore in-place (or clear any table we created last call).
            local orig = _original_can_wield[weapon_key]
            if orig then
                if not item.can_wield then item.can_wield = {} end
                local t = item.can_wield
                while #t > 0 do table.remove(t) end
                for _, v in ipairs(orig) do t[#t + 1] = v end
            else
                -- Original was nil. Restore to nil.
                item.can_wield = nil
            end
        end
    end

    if not _feature_enabled("enable_weapon_unlocks_core", true) then
        return
    end

    -- Re-apply only currently-enabled unlocks.
    for career, weapons in pairs(_WEAPON_UNLOCK_MAP) do
        for _, weapon_key in ipairs(weapons) do
            local setting_key = "unlock_" .. career .. "_" .. weapon_key
            local val = mod:get(setting_key)
            
            if weapon_key == "es_sword_shield_breton" and _feature_enabled("force_bretonnian_shield_unlock", false) then
                val = true
                mod:info("FORCING UNLOCK: " .. setting_key)
            end

            if val then
                local item = ItemMasterList[weapon_key]
                if item then
                    -- Create can_wield if missing so we can add the career.
                    if not item.can_wield then item.can_wield = {} end
                    local already = false
                    for _, c in ipairs(item.can_wield) do
                        if c == career then already = true; break end
                    end
                    if not already then
                        item.can_wield[#item.can_wield + 1] = career
                        mod:echo("SUCCESS: Unlocked " .. weapon_key .. " for " .. career)
                    end
                else
                    mod:echo("ERROR: Weapon ID not found: " .. weapon_key)
                end
            end
        end
    end
end

-- Saltzpyre careers set — used by _safe_create_equipment for the 3P model swap.
local _saltzpyre_careers = {
    wh_bountyhunter = true, wh_captain = true,
    wh_zealot       = true, wh_priest  = true,
}

-- Log create_equipment calls to understand what unit_1p/unit_3p look like for husks.
-- Set to false once 3P swap behaviour is understood.
local _log_create_equipment = false
local _debug = mod:get("debug") == true  -- persists via settings; command toggles in-session

-- 3P model swap for Saltzpyre + longbow: when unit_1p == nil this is a husk/remote-player
-- (3P-only) call. We swap the longbow model to crossbow so other players see a crossbow.
-- 1P is unaffected because unit_1p is set for the local player's own call.
local function _safe_create_equipment(func, world, slot_name, item_data, unit_1p, unit_3p, is_bot, unit_template, extra_extension_data, ammo_percent, override_item_template, override_item_units, career_name)
    if not _feature_enabled("enable_weapon_create_equipment_guard", true) then
        return func(world, slot_name, item_data, unit_1p, unit_3p, is_bot, unit_template, extra_extension_data, ammo_percent, override_item_template, override_item_units, career_name)
    end

    local item_key = item_data and item_data.name
    if _log_create_equipment and item_key then
        local item_entry = ItemMasterList and ItemMasterList[item_key]
        local tmpl = item_entry and item_entry.template and Weapons and Weapons[item_entry.template]
        local wa = tmpl and tmpl.wield_anim or "?"
        if wa == "to_longbow" or _saltzpyre_careers[career_name] then
            mod:info("create_equipment: career=%s item=%s wield=%s 1p=%s 3p=%s",
                tostring(career_name), item_key, wa,
                tostring(unit_1p ~= nil), tostring(unit_3p ~= nil))
        end
    end

    -- TODO: The 3P model swap for longbow -> crossbow is bugging out on the Elf.
    -- Disabled for now. Revisit when Steam is back online.
    --[[
    if unit_1p == nil and _saltzpyre_careers[career_name] and ItemMasterList and Weapons then
        local item_entry = item_key and ItemMasterList[item_key]
        local tmpl       = item_entry and item_entry.template and Weapons[item_entry.template]
        if tmpl and tmpl.wield_anim == "to_longbow" then
            local has_unlock = mod:get("unlock_" .. career_name .. "_we_longbow")
                            or mod:get("unlock_" .. career_name .. "_es_longbow")
            if has_unlock then
                local xbow_path = ItemMasterList["wh_crossbow"] and ItemMasterList["wh_crossbow"].right_hand_unit
                if xbow_path then
                    if not override_item_units and BackendUtils then
                        local ok, units = pcall(BackendUtils.get_item_units, item_data, career_name, nil)
                        override_item_units = ok and type(units) == "table" and units or {}
                    end
                    override_item_units = override_item_units or {}
                    override_item_units.right_hand_unit = xbow_path
                    override_item_units.left_hand_unit  = nil
                    mod:info("3P model swap: Saltzpyre %s → crossbow", item_key)
                end
            end
        end
    end
    ]]

    local result
    local ok, err = pcall(function()
        result = func(world, slot_name, item_data, unit_1p, unit_3p, is_bot, unit_template, extra_extension_data, ammo_percent, override_item_template, override_item_units, career_name)
    end)
    if not ok then
        local iname = item_key or "?"
        mod:warning("create_equipment failed (career=%s item=%s slot=%s): %s", tostring(career_name), iname, tostring(slot_name), tostring(err))
    end
    return result
end

mod:hook("GearUtils", "create_equipment", _safe_create_equipment)

-- ============================================================
-- Talent & Ability Swapping
-- ============================================================
-- Directly mutates the live TalentTrees global (which is read every time the
-- game looks up a talent by tier/index) and the CareerSettings activated_ability
-- / passive_ability fields (read by career_extension:init at level load).
-- All originals are saved before mutation so the function is safe to call
-- repeatedly — it restores first, then re-applies the current settings.

local _talent_swap_originals = {}  -- [career_name] = { tree, activated_ability, passive_ability }

local function apply_talent_swaps()
    if not CareerSettings or not TalentTrees then return end

    -- Restore all previous overrides to their originals
    for career_name, orig in pairs(_talent_swap_originals) do
        local cs = CareerSettings[career_name]
        if cs then
            local trees = TalentTrees[cs.profile_name]
            if trees then trees[cs.talent_tree_index] = orig.tree end
            cs.activated_ability = orig.activated_ability
            cs.passive_ability   = orig.passive_ability
        end
    end
    _talent_swap_originals = {}

    -- Apply current settings
    for _, career_name in ipairs(_ALL_CAREERS) do
        local src_name = mod:get("talent_swap_" .. career_name)
        if src_name and src_name ~= "none" then
            local cs  = CareerSettings[career_name]
            local src = CareerSettings[src_name]
            if cs and src then
                -- Save originals before first modification
                _talent_swap_originals[career_name] = {
                    tree              = TalentTrees[cs.profile_name] and TalentTrees[cs.profile_name][cs.talent_tree_index],
                    activated_ability = cs.activated_ability,
                    passive_ability   = cs.passive_ability,
                }

                -- Swap talent tree slot (read in-place by TalentTrees[profile][tree_idx][tier][col])
                local dst_trees = TalentTrees[cs.profile_name]
                local src_trees = TalentTrees[src.profile_name]
                if dst_trees and src_trees then
                    dst_trees[cs.talent_tree_index] = src_trees[src.talent_tree_index]
                end

                -- Swap career ability and passive (read by CareerUtils at level spawn)
                cs.activated_ability = src.activated_ability
                cs.passive_ability   = src.passive_ability
            end
        end
    end
end

-- ============================================================
-- Career ability: inject action into non-native weapon templates
-- ============================================================
-- CharacterStateHelper._check_chain_action AND _get_chain_action_data both read
-- item_template.actions[action_name]. Non-native weapon templates lack the career
-- action, so the button is silently ignored. We persistently inject the action so
-- both lookups find it. Tracked in _career_action_injections for clean removal.
-- NOTE: BH with non-native ranged weapons has a second blocker — input_override
-- "action_career" isn't wired for non-native weapons. See WORK_ITEMS.md.
local _career_action_injections = {}  -- [tmpl_key][action_name] = true

local function patch_career_actions_on_weapons()
    if not Weapons or not CareerSettings or not ActionTemplates or not ItemMasterList then return end

    -- Remove all previously injected actions first
    for tmpl_key, actions in pairs(_career_action_injections) do
        local tmpl = Weapons[tmpl_key]
        if tmpl and tmpl.actions then
            for action_name in pairs(actions) do
                tmpl.actions[action_name] = nil
            end
        end
    end
    _career_action_injections = {}

    if not _feature_enabled("enable_weapon_career_action_injection", true) then
        return
    end

    for career, weapons in pairs(_WEAPON_UNLOCK_MAP) do
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

-- Cleared on each game-state change; tracks which wield events have been logged once.
local _anim_logged = {}

local _original_slot_2_allowed = {}
local function apply_slot_settings()
    if not CareerSettings then return end
    
    local allow_melee_in_ranged = mod:get("allow_melee_in_ranged_slot")
    
    for career_name, cs in pairs(CareerSettings) do
        if type(cs) == "table" and cs.item_types_allowed_in_slot_2 then
            if not _original_slot_2_allowed[career_name] then
                -- Save original
                local orig = {}
                for _, v in ipairs(cs.item_types_allowed_in_slot_2) do
                    orig[#orig + 1] = v
                end
                _original_slot_2_allowed[career_name] = orig
            end
            
            -- Restore original
            local t = cs.item_types_allowed_in_slot_2
            while #t > 0 do table.remove(t) end
            for _, v in ipairs(_original_slot_2_allowed[career_name]) do
                t[#t + 1] = v
            end
            
            -- Apply setting if needed
            if allow_melee_in_ranged then
                local has_melee = false
                for _, v in ipairs(t) do
                    if v == "melee" then has_melee = true; break end
                end
                if not has_melee then
                    t[#t + 1] = "melee"
                end
            end
        end
    end
end

-- Forward declarations so on_game_state_changed can call these before they're defined below.
local _tp_inst_patched = false
local _try_patch_tp_camera
local _debug_dump_level

mod.on_game_state_changed = function(status, state_name)
    _anim_logged      = {}
    _tp_inst_patched  = false   -- re-patch on each new level (camera object may change)
    _try_patch_tp_camera()
    apply_weapon_unlocks()
    apply_slot_settings()
    apply_talent_swaps()
    patch_career_actions_on_weapons()
    if _debug then _debug_dump_level() end
end

mod.on_setting_changed = function(setting_id)
    mod:echo("Setting changed: " .. tostring(setting_id))
    if setting_id == "debug" then
        _debug = mod:get("debug") == true
    end
    local is_weapon_feature_setting = setting_id:find("^enable_weapon_") or setting_id == "force_bretonnian_shield_unlock"
    if setting_id:find("^unlock_") or setting_id == "allow_melee_in_ranged_slot" or is_weapon_feature_setting then
        apply_weapon_unlocks()
        apply_slot_settings()
        patch_career_actions_on_weapons()

        if setting_id == "enable_weapon_backend_hooks" and mod.loadout_cache then
            mod.loadout_cache = {}
        end
    end
    if setting_id:find("^talent_swap_") then
        apply_talent_swaps()
    end
end

-- ============================================================
-- Missing skeleton node guard
-- ============================================================

mod:hook("Unit", "node", function(func, unit, node_name, ...)
    if not _feature_enabled("enable_weapon_runtime_guards", true) then
        return func(unit, node_name, ...)
    end

    if type(node_name) == "string" and not Unit.has_node(unit, node_name) then
        return 0
    end
    return func(unit, node_name, ...)
end)

-- Safety hook for animation variables.
-- Foreign weapons often look for unique variables (like parry windows) that don't exist on the skeleton.
-- Returning 0 instead of nil prevents the "bad argument #2 to animation_set_variable" crash.
mod:hook("Unit", "animation_find_variable", function(func, unit, name, ...)
    if not _feature_enabled("enable_weapon_runtime_guards", true) then
        return func(unit, name, ...)
    end

    local index = func(unit, name, ...)
    if not index and type(name) == "string" then
        return 0
    end
    return index
end)

mod:hook("Unit", "animation_set_variable", function(func, unit, index, value, ...)
    if not _feature_enabled("enable_weapon_runtime_guards", true) then
        return func(unit, index, value, ...)
    end

    if not index or not value then
        return
    end
    return func(unit, index, value, ...)
end)

-- Crash prevention: nil explosion template.
mod:hook("DamageUtils", "create_explosion", function(func, world, attacker_unit, position, rotation, explosion_template, ...)
    if not explosion_template then return end
    return func(world, attacker_unit, position, rotation, explosion_template, ...)
end)

mod:hook("AreaDamageSystem", "create_explosion", function(func, self, attacker_unit, position, rotation, explosion_template_name, ...)
    if not ExplosionTemplates or not ExplosionTemplates[explosion_template_name] then return false end
    return func(self, attacker_unit, position, rotation, explosion_template_name, ...)
end)

-- ============================================================
-- Cross-career wield animation substitution
-- ============================================================
-- When a career equips a weapon from a different character, the weapon template's
-- wield_anim event (e.g. "to_fencing_sword") doesn't exist on that career's 3P
-- skeleton, so nothing plays.  We intercept Unit.animation_event: if the event is
-- absent we try a chain of per-event fallbacks in order, using the first one the
-- unit actually has.  This is safe because the fallback only fires when the
-- original event is missing — it never redirects events the unit can already play.
-- Wield-anim substitution table.
-- Key = animation event the game tries to fire; value = ordered fallback list.
-- The hook below uses Unit.has_animation_event to pick the first fallback the
-- unit's skeleton actually has.  Only wield-anim events need entries here —
-- attack/aim/reload anims are driven by the weapon action system, not this hook.
--
-- Prefer these alternatives BEFORE the original event (fires even when original exists).
-- This overrides skeleton events that exist but play the wrong animation.
-- Rapier on elf: tries s&d variants first; elf natively has one, Saltzpyre doesn't so
--   he falls through to his own to_fencing_sword.
-- Flail on elf: prefer to_1h_sword over whatever the flail's native wield event is.
local _wield_anim_prefer = {
    -- to_fencing_sword is handled by _fencing_sword_anim (career-aware special case).
    to_1h_flail      = { "to_1h_sword" },
    to_flail         = { "to_1h_sword" },  -- cover alternate event name for es_1h_flail
}

-- Fall back to these only when the original event is MISSING from the skeleton.
-- to_longbow is NOT here — it exists on all 1P skeletons (phantom entry), so has_orig is
-- always true and fallback never fires. Handled by _longbow_anim special case instead.
local _wield_anim_fallback = {
    to_bastard_sword           = { "to_2h_sword_we", "to_2h_sword", "to_greatsword" },
    to_fencing_sword           = { "to_1h_sword" },
    to_flail_shield            = { "to_1h_sword" },
    to_1h_flail                = { "to_1h_sword" },
    to_flail                   = { "to_1h_sword" },
    to_1h_hammer_shield_priest = { "to_1h_hammer_shield" },       -- Skullsplitter on non-Priest careers
    to_es_longbow              = { "to_longbow" },                 -- Empire longbow on elf → elf bow anim
    to_halberd                 = { "to_2h_sword" },                -- handled by _billhook_anim for wh_*; fallback for others
    to_spear                   = { "to_1h_sword" },                -- handled by _billhook_anim for wh_*; fallback for others
    to_spear_shield            = { "to_1h_mace_shield", "to_1h_hammer_shield", "to_1h_sword" },
    to_fire_staff              = { "to_1h_sword" },                -- Sienna staff on non-Sienna
    to_staff                   = { "to_1h_sword" },                -- alternate staff event
    to_beam_staff              = { "to_1h_sword" },
    to_coruscation_staff       = { "to_1h_sword" },
    to_hagbane_shortbow        = { "to_longbow", "to_es_longbow" }, -- elf shortbow on non-Elf
    to_longrifle               = { "to_crossbow_loaded" },         -- Kruber handgun on non-Kruber
    to_dw_crossbow             = { "to_crossbow_loaded" },         -- Bardin crossbow if unique event
}

-- Returns the local player's career_name, or the last cached value if unavailable.
-- Tries two patterns: profile.career_name (direct) and Profiles[idx].careers[idx].name
-- (index-based, used when career_name is not a direct field on the profile object).
local _cached_career = nil
local function _local_career_name()
    local pm = Managers.player
    if not pm then return _cached_career end
    local pl = pm:local_player()
    if not pl then 
        -- Fallback: try to get it from the camera system's player unit
        local cam = Managers.state.camera
        local unit = cam and cam:follow_unit()
        if unit and Unit.alive(unit) then
            local career_ext = ScriptUnit.has_extension(unit, "career_system")
            if career_ext then return career_ext:career_name() end
        end
        return _cached_career 
    end
    
    local career = pl:career_name()
    if career then _cached_career = career; return career end
    
    local profile_idx = pl:profile_index()
    local career_idx = pl:career_index()
    if Profiles and profile_idx and career_idx then
        local prof = Profiles[profile_idx]
        local c = prof and prof.careers and prof.careers[career_idx]
        local n = c and c.name
        if n then _cached_career = n; return n end
    end
    return _cached_career
end

-- to_1h_crowbill exists on all skeletons but only has real animation data on Sienna (bw_*).
-- Redirect non-Sienna careers to to_1h_axe so they get a valid wield animation.
local function _crowbill_anim(func, unit)
    local career = _local_career_name()
    local is_sienna = career and career:sub(1, 2) == "bw"
    if not is_sienna then
        if Unit.has_animation_event(unit, "to_1h_axe") then
            pcall(func, unit, "to_1h_axe") ; return
        end
        if Unit.has_animation_event(unit, "to_1h_sword") then
            pcall(func, unit, "to_1h_sword") ; return
        end
    end
    pcall(func, unit, "to_1h_crowbill")
end

-- to_longbow exists as a phantom entry on all 1P skeletons (has_orig always true), so the
-- fallback table never fires for non-elf careers. Redirect non-elf to crossbow/es_longbow.
local function _longbow_anim(func, unit)
    local career = _local_career_name()
    local is_elf = career and career:sub(1, 3) == "we_"
    if not is_elf then
        if Unit.has_animation_event(unit, "to_crossbow_loaded") then
            pcall(func, unit, "to_crossbow_loaded"); return
        end
        if Unit.has_animation_event(unit, "to_es_longbow") then
            pcall(func, unit, "to_es_longbow"); return
        end
    end
    pcall(func, unit, "to_longbow")
end

-- to_fencing_sword: elf skeletons don't have this event natively (has_orig=false).
-- For elf try sword-and-dagger variants first, then fall back to to_1h_sword.
-- For WHC/BH/Zealot who have it natively: fire it directly.
-- When career is nil (unknown), rely on has_animation_event to distinguish.
local function _fencing_sword_anim(func, unit, ...)
    local career = _local_career_name()
    local is_elf = career and career:sub(1, 3) == "we_"
    if is_elf then
        local variants = { "to_dual_sword_dagger", "to_sword_and_dagger", "to_dagger_sword", "to_sword_dagger", "to_we_sword_dagger", "to_dagger" }
        for _, ev in ipairs(variants) do
            if Unit.has_animation_event(unit, ev) then
                pcall(func, unit, ev, ...); return
            end
        end
        if Unit.has_animation_event(unit, "to_1h_sword") then
            pcall(func, unit, "to_1h_sword", ...); return
        end
    end
    -- Non-elf or nil career: fire to_fencing_sword only if unit actually has it (WHC/BH/Zealot).
    -- If not (elf with nil career), fall back to to_1h_sword.
    if Unit.has_animation_event(unit, "to_fencing_sword") then
        pcall(func, unit, "to_fencing_sword", ...); return
    end
    if Unit.has_animation_event(unit, "to_1h_sword") then
        pcall(func, unit, "to_1h_sword", ...)
    end
end

-- to_halberd / to_spear: Saltzpyre skeletons have to_2h_billhook natively.
-- Use unit-based detection (has_animation_event) so this works even when career is nil.
-- Other careers fall through to the standard fallback (to_2h_sword / to_1h_sword).
local function _billhook_anim(func, unit, fallback_event, ...)
    -- If the unit natively has this event (e.g. Kerillian equipping her own spear), play it directly.
    if Unit.has_animation_event(unit, fallback_event) then
        if _debug then mod:info("billhook_anim: native %s → pass-through", fallback_event) end
        pcall(func, unit, fallback_event, ...); return
    end
    -- Saltzpyre has to_2h_billhook on his skeleton; other careers don't.
    -- Use this as career-agnostic detection — avoids dependency on _local_career_name().
    if Unit.has_animation_event(unit, "to_2h_billhook") then
        if _debug then mod:info("billhook_anim: has to_2h_billhook → billhook path for %s", fallback_event) end
        pcall(func, unit, "to_2h_billhook", ...); return
    end
    -- Fall back via the standard table (to_2h_sword for halberd, to_1h_sword for spear).
    local fallbacks = _wield_anim_fallback[fallback_event]
    if fallbacks then
        for _, fb in ipairs(fallbacks) do
            if Unit.has_animation_event(unit, fb) then
                if _debug then mod:info("billhook_anim: %s → fallback %s", fallback_event, fb) end
                pcall(func, unit, fb, ...); return
            end
        end
    end
    if _debug then mod:info("billhook_anim: %s → no match, firing raw", fallback_event) end
    pcall(func, unit, fallback_event, ...)
end

mod:hook("Unit", "animation_event", function(func, unit, event_name, ...)
    if not _feature_enabled("enable_weapon_animation_redirects", true) then
        return func(unit, event_name, ...)
    end

    -- Retry camera patch here: player_unit is guaranteed present when animations fire,
    -- whereas on_game_state_changed fires too early for the unit to exist.
    if not _tp_inst_patched then _try_patch_tp_camera() end

    -- Only instrument to_* wield events to keep log noise low.
    if type(event_name) == "string" and event_name:sub(1, 3) == "to_" then
        local in_table = _wield_anim_prefer[event_name] or _wield_anim_fallback[event_name]
        local has_orig = Unit.has_animation_event(unit, event_name)
        if _debug and not _anim_logged[event_name] then
            _anim_logged[event_name] = true
            mod:info("anim_event: %s  has_orig=%s  in_table=%s",
                event_name, tostring(has_orig), tostring(in_table ~= nil))
        end
    end

    if event_name == "to_1h_crowbill"   then _crowbill_anim(func, unit);                     return end
    if event_name == "to_longbow"       then _longbow_anim(func, unit);                     return end
    if event_name == "to_fencing_sword" then _fencing_sword_anim(func, unit, ...);          return end
    if event_name == "to_halberd"       then _billhook_anim(func, unit, "to_halberd", ...); return end
    if event_name == "to_spear"         then _billhook_anim(func, unit, "to_spear", ...);   return end

    -- 1. Try preferred alternatives first.
    local preferred = _wield_anim_prefer[event_name]
    if preferred then
        for _, ev in ipairs(preferred) do
            if Unit.has_animation_event(unit, ev) then
                if _debug and not _anim_logged["pref_" .. event_name] then
                    _anim_logged["pref_" .. event_name] = true
                    mod:info("anim_prefer: %s → %s", event_name, ev)
                end
                pcall(func, unit, ev, ...)
                return
            end
        end
    end

    -- 2. Try original.
    if Unit.has_animation_event(unit, event_name) then
        pcall(func, unit, event_name, ...)
        return
    end

    -- 3. Original missing — try fallback chain.
    local fallbacks = _wield_anim_fallback[event_name]
    if fallbacks then
        for _, fb in ipairs(fallbacks) do
            if Unit.has_animation_event(unit, fb) then
                if _debug and not _anim_logged["fb_" .. event_name] then
                    _anim_logged["fb_" .. event_name] = true
                    mod:info("anim_fallback: %s → %s", event_name, fb)
                end
                pcall(func, unit, fb, ...)
                return
            end
        end
        if _debug then mod:info("anim_fallback: %s → no usable fallback", event_name) end
    end
end)

-- Crash prevention: attachment node mismatches when equipping off-career weapons.
mod:hook("SimpleInventoryExtension", "_wield_slot", function(func, self, equipment, slot_data, unit_1p, unit_3p, buff_extension)
    if not _feature_enabled("enable_weapon_wield_slot_guard", true) then
        return func(self, equipment, slot_data, unit_1p, unit_3p, buff_extension)
    end

    local ret
    local ok, err = pcall(function() ret = func(self, equipment, slot_data, unit_1p, unit_3p, buff_extension) end)
    if not ok then
        mod:warning("_wield_slot error (slot=%s): %s", tostring(slot_data and slot_data.slot_name), tostring(err))
    end
    return ret
end)

mod:hook("SimpleHuskInventoryExtension", "_wield_slot", function(func, self, world, equipment, slot_name, unit_1p, unit_3p)
    if not _feature_enabled("enable_weapon_wield_slot_guard", true) then
        return func(self, world, equipment, slot_name, unit_1p, unit_3p)
    end

    local ret
    local ok, err = pcall(function() ret = func(self, world, equipment, slot_name, unit_1p, unit_3p) end)
    if not ok then
        mod:warning("_wield_slot (husk) error (slot=%s): %s", tostring(slot_name), tostring(err))
    end
    return ret
end)

-- ============================================================
-- Commands
-- ============================================================

mod:command("dump_all_items", "Dumps every ID in ItemMasterList to the console log, categorized", function()
    if not ItemMasterList then mod:echo("ItemMasterList not available.") return end
    
    local categories = {}
    local total = 0
    
    for key, data in pairs(ItemMasterList) do
        local slot = tostring(data.slot_type or "other")
        categories[slot] = categories[slot] or {}
        table.insert(categories[slot], key)
        total = total + 1
    end
    
    mod:info("=== TWEAKER ITEM DUMP START (Total: " .. total .. ") ===")
    
    -- Sort categories for cleaner logs
    local keys = {}
    for k in pairs(categories) do table.insert(keys, k) end
    table.sort(keys)
    
    for _, slot in ipairs(keys) do
        mod:info("CATEGORY: " .. slot)
        table.sort(categories[slot])
        for _, item_id in ipairs(categories[slot]) do
            mod:info("  " .. item_id)
        end
    end
    
    mod:info("=== TWEAKER ITEM DUMP END ===")
    mod:echo("Dumped " .. total .. " item IDs to the console log. Categories: " .. table.concat(keys, ", "))
end)

mod:command("t_version", "Show the build timestamp of the current mod version", function()
    mod:echo("Tweaker Build: 2026-04-21 14:11")
end)

mod:command("dump_animations", "Dumps all unique animation events from Items and Weapons", function()
    local anims = {}
    
    local function scan(t, source_name)
        if not t then return end
        for key, data in pairs(t) do
            if type(data) == "table" then
                -- Check top-level fields
                for k, v in pairs(data) do
                    if type(k) == "string" and string.find(k, "anim") and type(v) == "string" then
                        anims[v] = anims[v] or {}
                        table.insert(anims[v], string.format("%s[%s].%s", source_name, key, k))
                    end
                end
                -- Also check item.inventory_ad_data (ItemMasterList specific)
                if data.inventory_ad_data then
                    for k, v in pairs(data.inventory_ad_data) do
                        if type(k) == "string" and string.find(k, "anim") and type(v) == "string" then
                            anims[v] = anims[v] or {}
                            table.insert(anims[v], string.format("%s[%s].ad.%s", source_name, key, k))
                        end
                    end
                end
            end
        end
    end
    
    scan(ItemMasterList, "Item")
    scan(Weapons, "Weapon")
    scan(ActionTemplates, "Action")
    
    mod:echo("Dumping animations to log...")
    mod:info("=== WEAPON ANIMATION EVENTS START ===")
    local sorted = {}
    for a in pairs(anims) do table.insert(sorted, a) end
    table.sort(sorted)
    
    for _, a in ipairs(sorted) do
        mod:info(string.format("[%s] sources: %s", a, table.concat(anims[a], ", ")))
    end
    mod:info("=== WEAPON ANIMATION EVENTS END ===")
    mod:echo("Dump complete. Unique events: " .. #sorted)
end)

-- Probe what 3P animation events exist on the local player's character unit.
-- Run in-game as Saltzpyre to discover which wield anims his state machine supports.
mod:command("probe_3p", "List which ranged wield animation events exist on the local player's 3P unit", function()
    local pm = Managers.player
    local player = pm and pm:local_player()
    local unit = player and player.player_unit
    if not unit then mod:echo("No player unit (must be in a level).") return end

    local candidates = {
        -- Kruber longbow
        "to_es_longbow", "to_es_longbow_noammo",
        -- Elf longbow
        "to_longbow", "to_longbow_noammo",
        -- Saltzpyre crossbow
        "to_crossbow", "to_crossbow_loaded", "to_crossbow_noammo",
        -- Saltzpyre repeating crossbow
        "to_repeating_crossbow", "to_repeating_crossbow_noammo",
        -- Saltzpyre pistols
        "to_brace_of_pistols", "to_wh_brace_of_pistols",
        "to_flintlock_pistol", "to_wh_flintlock_pistol",
        -- Generic
        "to_ranged", "idle_ranged",
    }

    local found = {}
    local missing = {}
    for _, ev in ipairs(candidates) do
        if Unit.has_animation_event(unit, ev) then
            found[#found + 1] = ev
        else
            missing[#missing + 1] = ev
        end
    end

    mod:echo("=== 3P anim events FOUND ===")
    for _, ev in ipairs(found) do mod:echo("  YES: " .. ev) end
    mod:echo("=== MISSING ===")
    for _, ev in ipairs(missing) do mod:echo("  no:  " .. ev) end
end)

-- Lists every to_* wield animation event present/absent on the player's 3P unit.
-- Run on each career to build the full per-skeleton map before updating fallbacks.
mod:command("probe_wield_anims", "List all to_* wield animation events on the player 3P unit", function()
    local pm = Managers.player
    local player = pm and pm:local_player()
    local unit = player and player.player_unit
    if not unit then mod:echo("No player unit (must be in a level).") return end

    local candidates = {
        -- 1h melee (universal — all skeletons should have these)
        "to_1h_sword", "to_1h_axe", "to_1h_mace", "to_1h_hammer",
        -- 1h + shield
        "to_1h_sword_shield", "to_1h_sword_shield_breton", "to_mace_shield",
        -- 2h melee
        "to_2h_sword", "to_2h_axe", "to_2h_hammer", "to_2h_mace",
        "to_greatsword", "to_halberd", "to_spear",
        -- Special melee — sword & dagger variants (looking for elf's actual event name)
        "to_sword_and_dagger", "to_dagger_sword", "to_sword_dagger", "to_we_sword_dagger",
        "to_dagger", "to_fencing_sword",
        "to_1h_flail", "to_flail", "to_flail_shield",
        -- Ranged
        "to_longbow", "to_longbow_noammo",
        "to_es_longbow", "to_es_longbow_noammo",
        "to_crossbow_loaded", "to_crossbow_noammo",
        "to_repeating_crossbow", "to_repeating_crossbow_noammo",
        "to_brace_of_pistols", "to_flintlock_pistol",
        -- Staves
        "to_staff", "to_staff_beam", "to_staff_flamethrower",
    }
    local found, missing = {}, {}
    for _, ev in ipairs(candidates) do
        if Unit.has_animation_event(unit, ev) then
            found[#found + 1] = ev
        else
            missing[#missing + 1] = ev
        end
    end
    mod:echo("=== FOUND (" .. #found .. ") ===")
    for _, ev in ipairs(found) do mod:echo("  " .. ev) end
    mod:echo("=== MISSING (" .. #missing .. ") ===")
    for _, ev in ipairs(missing) do mod:echo("  " .. ev) end
end)

-- Probes the camera system to find the TP toggle API.
-- Run in a level and share the output.
mod:command("probe_camera", "Inspect Managers.state.camera fields and ScriptUnit camera extensions", function()
    -- Dump Managers.state.camera fields
    local cam = Managers.state and Managers.state.camera
    if cam then
        local bools, fns, others = {}, {}, {}
        for k, v in pairs(cam) do
            local t = type(v)
            if t == "boolean" then bools[#bools+1] = k .. "=" .. tostring(v)
            elseif t == "function" then fns[#fns+1] = k
            else others[#others+1] = k .. " (" .. t .. ")" end
        end
        table.sort(bools); table.sort(fns); table.sort(others)
        mod:echo("=== Managers.state.camera ===")
        mod:echo("  booleans: " .. (#bools > 0 and table.concat(bools, ", ") or "none"))
        mod:echo("  functions (" .. #fns .. "): " .. table.concat(fns, ", "))
        mod:echo("  other fields: " .. (#others > 0 and table.concat(others, ", ") or "none"))
        -- Also check metatable index
        local mt = getmetatable(cam)
        local idx = mt and rawget(mt, "__index")
        if type(idx) == "table" then
            local mfns = {}
            for k, v in pairs(idx) do
                if type(v) == "function" then mfns[#mfns+1] = k end
            end
            table.sort(mfns)
            mod:echo("  metatable functions (" .. #mfns .. "): " .. table.concat(mfns, ", "))
        end
    else
        mod:echo("Managers.state.camera is nil (must be in a level).")
    end
    -- Try ScriptUnit camera extensions (fixed pcall destructuring)
    local pm = Managers.player
    local player = pm and pm:local_player()
    local unit = player and player.player_unit
    if unit then
        mod:echo("=== ScriptUnit camera extensions ===")
        for _, name in ipairs({ "camera_system", "fp_camera", "camera", "camera_handler", "input" }) do
            local ok, ext = pcall(function() return ScriptUnit.extension(unit, name) end)
            mod:echo("  '" .. name .. "': " .. (ok and tostring(type(ext)) or "error"))
        end
    end
end)

mod:command("find_class", "Find global class names matching a pattern", function(pattern)
    pattern = pattern:lower()
    local found = {}
    for k, v in pairs(_G) do
        if type(k) == "string" and k:lower():find(pattern) then
            found[#found + 1] = k .. " (" .. type(v) .. ")"
        end
    end
    table.sort(found)
    for _, s in ipairs(found) do
        mod:echo(s)
    end
end)

mod:command("inspect", "List methods of a global class", function(name)
    local cls = _G[name]
    if not cls then mod:echo("Not found: " .. name) return end
    local found = {}
    for k, v in pairs(cls) do
        if type(v) == "function" then
            found[#found + 1] = k
        end
    end
    table.sort(found)
    for _, s in ipairs(found) do
        mod:echo(s)
    end
end)

-- Dump Weapons template entries matching a pattern and their wield_anim / wield_anim_3p fields.
-- Usage: t dump_templates fencing   (finds all templates whose key contains "fencing")
mod:command("dump_templates", "List Weapons templates matching a pattern with their wield_anim fields", function(pattern)
    pattern = pattern or ""
    if not Weapons then mod:echo("Weapons global not available (load a level first).") return end
    local found = {}
    for key, tmpl in pairs(Weapons) do
        if key:find(pattern) then
            local wield = tostring(tmpl.wield_anim or "nil")
            found[#found+1] = string.format("key=%-45s wield_anim=%s", key, wield)
        end
    end
    table.sort(found)
    if #found == 0 then
        mod:echo("No templates matching '" .. pattern .. "'.")
    else
        mod:echo(string.format("Found %d templates matching '%s':", #found, pattern))
        for _, s in ipairs(found) do mod:echo(s) end
    end
end)

-- Dump Weapons template entries whose key contains "crossbow" and their unit_3p paths.
-- Run in-game after a level loads (Weapons global is populated at level start).
mod:command("dump_crossbow", "Log crossbow weapon templates and their 3P unit paths", function()
    if not Weapons then mod:echo("Weapons global not available (load a level first).") return end
    local found = {}
    for key, tmpl in pairs(Weapons) do
        if key:find("crossbow") then
            found[#found+1] = string.format("key=%-40s unit_3p=%s", key, tostring(tmpl.unit_3p))
        end
    end
    table.sort(found)
    if #found == 0 then
        mod:echo("No crossbow entries found in Weapons global.")
    else
        mod:echo(string.format("Found %d crossbow templates:", #found))
        for _, s in ipairs(found) do mod:echo(s) end
    end
end)

-- Dump all career-exclusive weapons grouped by character faction prefix.
-- These are items locked to a single career — exactly what we need to unlock them.
-- Usage: t dump_exclusive  (no args)
mod:command("dump_exclusive", "List all career-exclusive weapons grouped by character faction", function()
    if not ItemMasterList then mod:echo("ItemMasterList not loaded yet.") return end
    local by_career = {}
    for key, item in pairs(ItemMasterList) do
        if item.can_wield and #item.can_wield == 1 then
            local career = item.can_wield[1]
            if not by_career[career] then by_career[career] = {} end
            by_career[career][#by_career[career]+1] = key
        end
    end
    local careers = {}
    for c in pairs(by_career) do careers[#careers+1] = c end
    table.sort(careers)
    for _, career in ipairs(careers) do
        local items = by_career[career]
        table.sort(items)
        mod:echo(career .. ":")
        for _, k in ipairs(items) do mod:echo("  " .. k) end
    end
end)

-- Dump ItemMasterList items with a single-career can_wield — these are typically
-- career ability weapons.
mod:command("dump_career_items", "Log items whose can_wield has exactly 1 entry (career ability weapons)", function()
    if not ItemMasterList then mod:echo("ItemMasterList not loaded yet.") return end
    local found = {}
    for key, item in pairs(ItemMasterList) do
        if item.can_wield and #item.can_wield == 1 then
            found[#found+1] = string.format("key=%-40s career=%s", key, item.can_wield[1])
        end
    end
    table.sort(found)
    mod:echo(string.format("Found %d single-career items:", #found))
    for _, s in ipairs(found) do mod:echo(s) end
end)

-- Dump all fields of an ItemMasterList entry to find where unit paths actually live.
mod:command("dump_item", "Dump all fields of an ItemMasterList entry", function(key)
    key = key or "wh_crossbow"
    if not ItemMasterList then mod:echo("ItemMasterList not loaded") return end
    local item = ItemMasterList[key]
    if not item then mod:echo("Key not found: " .. key) return end
    local function dump_table(t, prefix)
        for k, v in pairs(t) do
            local vtype = type(v)
            if vtype == "table" then
                mod:echo(prefix .. tostring(k) .. " = {table}")
                dump_table(v, prefix .. "  ")
            elseif vtype == "function" then
                mod:echo(prefix .. tostring(k) .. " = [function]")
            else
                mod:echo(prefix .. tostring(k) .. " = " .. tostring(v))
            end
        end
    end
    mod:echo("=== ItemMasterList['" .. key .. "'] ===")
    dump_table(item, "  ")
end)

-- Validate every item key in _WEAPON_UNLOCK_MAP against ItemMasterList.
-- MISSING = key not in ItemMasterList at all (wrong key name — use t list_items <prefix>)
-- NO_CAN_WIELD = key exists but can_wield is nil (now handled: we create the table)
mod:command("validate_weapons", "Check all weapon unlock keys against ItemMasterList", function()
    if not ItemMasterList then mod:echo("ItemMasterList not loaded (load a level first).") return end
    local missing, no_wield, ok_count = {}, {}, 0
    local seen = {}
    for career, weapons in pairs(_WEAPON_UNLOCK_MAP) do
        for _, key in ipairs(weapons) do
            if not seen[key] then
                seen[key] = true
                local item = ItemMasterList[key]
                if not item then
                    missing[#missing+1] = key
                elseif not item.can_wield then
                    no_wield[#no_wield+1] = key
                else
                    ok_count = ok_count + 1
                end
            end
        end
    end
    table.sort(missing); table.sort(no_wield)
    mod:echo(string.format("validate_weapons: %d ok, %d MISSING, %d no_can_wield", ok_count, #missing, #no_wield))
    for _, k in ipairs(missing) do
        -- Suggest keys that contain part of the missing key
        local prefix = k:match("^([a-z]+_)")
        local suggestions = {}
        if prefix then
            for ikey in pairs(ItemMasterList) do
                if ikey:find(prefix, 1, true) and ikey:find(k:gsub("^[a-z]+_", ""), 1, true) then
                    suggestions[#suggestions+1] = ikey
                end
            end
            table.sort(suggestions)
        end
        local hint = #suggestions > 0 and ("  → similar: " .. table.concat(suggestions, ", ")) or ""
        mod:echo("  MISSING: " .. k .. hint)
    end
    for _, k in ipairs(no_wield) do
        mod:echo("  NO_CAN_WIELD: " .. k .. "  (will create can_wield on first unlock)")
    end
    if #missing == 0 and #no_wield == 0 then mod:echo("  All keys valid.") end
end)

-- List all ItemMasterList keys whose name contains the given substring.
-- Usage: t list_items bw_  → shows all Sienna weapon keys
mod:command("list_items", "List ItemMasterList keys containing a substring", function(pattern)
    if not ItemMasterList then mod:echo("ItemMasterList not loaded (load a level first).") return end
    pattern = pattern or ""
    local found = {}
    for key, item in pairs(ItemMasterList) do
        if key:find(pattern, 1, true) then
            local wield_count = item.can_wield and #item.can_wield or 0
            found[#found+1] = string.format("%-40s  can_wield=%d  tmpl=%s", key, wield_count, tostring(item.template))
        end
    end
    table.sort(found)
    mod:echo(string.format("list_items '%s': %d results", pattern, #found))
    for _, s in ipairs(found) do mod:echo("  " .. s) end
end)

-- Dump player profile fields — run in-game to diagnose _local_career_name() failures.
mod:command("dump_career", "Dump player profile fields for career detection debugging", function()
    local pm = Managers.player
    if not pm then mod:echo("No PlayerManager") return end
    local ok1, pl = pcall(pm.local_player, pm)
    mod:echo("local_player: ok=" .. tostring(ok1) .. " type=" .. tostring(type(pl)))
    if not ok1 or not pl then return end
    local ok2, p = pcall(pl.profile, pl)
    mod:echo("profile: ok=" .. tostring(ok2) .. " type=" .. tostring(type(p)))
    if ok2 and type(p) == "table" then
        for k, v in pairs(p) do
            if type(v) ~= "function" and type(v) ~= "table" then
                mod:echo("  p." .. tostring(k) .. " = " .. tostring(v))
            end
        end
    end
    if Profiles then
        mod:echo("Profiles global: size=" .. tostring(#Profiles))
    else
        mod:echo("Profiles global: nil")
    end
    mod:echo("_local_career_name() = " .. tostring(_local_career_name()))
end)

-- Find ItemMasterList items whose key or wield_anim contains a pattern.
-- Usage: t find_items breton   or   t find_items sword_shield
mod:command("find_items", "Find ItemMasterList keys matching a pattern (key, template, or wield_anim)", function(pattern)
    if not ItemMasterList then mod:echo("ItemMasterList not loaded.") return end
    pattern = pattern or ""
    local found = {}
    for key, item in pairs(ItemMasterList) do
        local tmpl_name = tostring(item.template or "")
        local wa = ""
        if Weapons and item.template and Weapons[item.template] then
            wa = tostring(Weapons[item.template].wield_anim or "")
        end
        if key:find(pattern, 1, true) or tmpl_name:find(pattern, 1, true) or wa:find(pattern, 1, true) then
            local wc = item.can_wield and #item.can_wield or 0
            found[#found+1] = string.format("%-42s tmpl=%-30s wield_anim=%s can_wield=%d", key, tmpl_name, wa, wc)
        end
    end
    table.sort(found)
    mod:echo(string.format("find_items '%s': %d results", pattern, #found))
    for _, s in ipairs(found) do mod:echo("  " .. s) end
end)

-- Dump BH's activated_ability template structure
mod:command("dump_bh_ability", "Dump BH career ability template fields", function()
    if not CareerSettings then mod:echo("CareerSettings not loaded") return end
    local cs = CareerSettings["wh_bountyhunter"]
    if not cs then mod:echo("wh_bountyhunter not found") return end
    mod:echo("activated_ability type: " .. type(cs.activated_ability))
    if type(cs.activated_ability) == "table" then
        for k, v in pairs(cs.activated_ability) do
            mod:echo("  " .. tostring(k) .. " = " .. (type(v)=="function" and "[function]" or tostring(v)))
        end
    elseif type(cs.activated_ability) == "string" then
        mod:echo("  value: " .. cs.activated_ability)
    end
end)

mod:command("unstuck", "Teleport to nearest living teammate", function()
    local pm = Managers.player
    if not pm then mod:echo("Not in a level.") return end
    local player = pm:local_player()
    if not player then mod:echo("No local player.") return end
    local unit = player.player_unit
    if not unit then mod:echo("No player unit (dead?).") return end

    local target_pos = nil
    for _, p in pairs(pm:players()) do
        if p ~= player and p.player_unit and HEALTH_ALIVE[p.player_unit] then
            target_pos = Unit.local_position(p.player_unit, 0)
            break
        end
    end

    if target_pos then
        local mover = Unit.mover(unit)
        if mover then
            Mover.set_position(mover, target_pos + Vector3(0.5, 0, 0))
        end
        mod:echo("Unstuck!")
    else
        mod:echo("No living teammate found.")
    end
end)

local _godmode    = false
local _tp_enabled = false

-- ============================================================
-- TP camera
-- ============================================================
-- Part 1: first_person_mode_active → returns false → hides 1P arm mesh.
-- Part 2: per-frame set_offset on CameraManager to push camera 3 units
--         behind and 1.5 units above the player each tick.
-- camera_pose() is a getter/reader — overriding it does NOT move the render
-- camera. Only set_offset (or equivalent) has a visible effect.

local _tp_orig_fp_active  = nil
local _tp_offset_warned   = false
local _tp_cam_dumped      = false  -- dump camera methods once on first TP-on frame

local function _tp_fp_active_fn(self_ext)
    if _tp_enabled then return false end
    return _tp_orig_fp_active(self_ext)
end

_try_patch_tp_camera = function()
    if _tp_inst_patched then return end
    local pm = Managers.player
    if not pm then return end
    local ok_p, player = pcall(pm.local_player, pm)
    if not ok_p or not player or not player.player_unit then return end
    local punit = player.player_unit

    -- Hide 1P arm mesh by overriding first_person_mode_active.
    local fp_ext = ScriptUnit.has_extension(punit, "first_person_system")
    if fp_ext then
        local mt  = getmetatable(fp_ext)
        local idx = mt and rawget(mt, "__index")
        for _, name in ipairs({ "first_person_mode_active", "is_in_first_person_mode", "is_first_person_mode" }) do
            if type(idx) == "table" and type(rawget(idx, name)) == "function" then
                _tp_orig_fp_active = rawget(idx, name)
                local ok_s = pcall(rawset, fp_ext, name, _tp_fp_active_fn)
                if ok_s then
                    _tp_inst_patched = true
                    mod:info("TP: patched fp_ext.%s", name)
                end
                break
            end
        end
    end
end

-- Per-frame camera offset for TP view.
mod:hook_safe("StateInGameRunning", "update", function(self, dt)
    local cm = Managers.state and Managers.state.camera
    if not cm then return end

    -- Dump all camera manager methods once on the first frame TP is enabled,
    -- so we know exactly what API is available without a manual command.
    if _tp_enabled and not _tp_cam_dumped then
        _tp_cam_dumped = true
        local fns = {}
        -- instance fields
        for k, v in pairs(cm) do
            if type(v) == "function" then fns[#fns+1] = k .. "(inst)" end
        end
        -- metatable __index
        local mt  = getmetatable(cm)
        local idx = mt and rawget(mt, "__index")
        if type(idx) == "table" then
            for k, v in pairs(idx) do
                if type(v) == "function" then fns[#fns+1] = k end
            end
        end
        table.sort(fns)
        mod:info("TP cam dump (%d methods): %s", #fns, table.concat(fns, ", "))
    end

    if not _tp_enabled then
        if type(cm.set_offset) == "function" then
            pcall(cm.set_offset, cm, Vector3(0, 0, 0))
        end
        return
    end
    local pm = Managers.player
    if not pm then return end
    local ok, player = pcall(pm.local_player, pm)
    if not ok or not player or not player.player_unit then return end
    local punit = player.player_unit
    local ok2, rot = pcall(Unit.world_rotation, punit, 0)
    if not ok2 then return end
    local fwd    = Quaternion.forward(rot)
    local offset = fwd * (-3) + Vector3(0, 0, 1.5)
    if type(cm.set_offset) == "function" then
        pcall(cm.set_offset, cm, offset)
    elseif not _tp_offset_warned then
        _tp_offset_warned = true
        mod:info("TP: set_offset not found — see cam dump above for available methods")
    end
end)

-- ============================================================
-- Debug auto-dump
-- ============================================================

-- Dumps career name and validate_weapons results; called on every game-state change when
-- _debug is on.  ItemMasterList may still be nil at early states — guard against that.
_debug_dump_level = function()
    local career = _local_career_name()
    mod:info("debug_level: career=%s", tostring(career))
    if not ItemMasterList then
        mod:info("debug_level: ItemMasterList not ready yet")
        return
    end
    local missing, no_wield, ok_count = {}, {}, 0
    local seen = {}
    for _, weapons in pairs(_WEAPON_UNLOCK_MAP) do
        for _, key in ipairs(weapons) do
            if not seen[key] then
                seen[key] = true
                local item = ItemMasterList[key]
                if not item then
                    missing[#missing+1] = key
                elseif not item.can_wield then
                    no_wield[#no_wield+1] = key
                else
                    ok_count = ok_count + 1
                end
            end
        end
    end
    table.sort(missing); table.sort(no_wield)
    mod:info("debug_level: weapons ok=%d missing=%d no_can_wield=%d", ok_count, #missing, #no_wield)
    for _, k in ipairs(missing)   do mod:info("debug_level: MISSING %s", k)   end
    for _, k in ipairs(no_wield)  do mod:info("debug_level: NO_WIELD %s", k)  end
end

-- Logs unit paths for every weapon equipped or inspected by the backend.
-- Right-hand and left-hand model paths tell us what 3P models are actually loaded.
--[[
mod:hook("BackendUtils", "get_item_units", function(func, item_data, career_name, item_skin)
    local ret = { func(item_data, career_name, item_skin) }
    local units = ret[1]

    -- TODO: The 3P model swap for longbow -> crossbow is bugging out on the Elf.
    -- Disabled for now. Revisit when Steam is back online.
    --[[
    -- Swap longbow 3P model to crossbow for Saltzpyre careers.
    -- Longbow has no crossbow-compatible animations on Saltzpyre's skeleton; the
    -- wield anim already redirects to to_crossbow_loaded, so the model should match.
    if type(units) == "table" and item_data and item_data.name then
        local name = tostring(item_data.name)
        local is_longbow = name:find("longbow") ~= nil
        local local_career = _local_career_name()
        local is_wh = local_career and local_career:sub(1, 3) == "wh_"
        -- Always log longbow calls so we can see the raw career_name param vs local career.
        if is_longbow and _debug then
            mod:info("get_item_units longbow: item=%s param_career=%s local_career=%s is_wh=%s",
                name, tostring(career_name), tostring(local_career), tostring(is_wh))
        end
        if is_longbow and is_wh then
            local xbow_item = ItemMasterList and ItemMasterList["wh_crossbow"]
            if xbow_item then
                -- Clone the original units table so we keep skin, ammo_unit, icon, etc.
                local swapped = {}
                for k, v in pairs(units) do swapped[k] = v end
                -- Crossbow has only left_hand_unit (confirmed from log); right_hand_unit is nil on both.
                swapped.left_hand_unit  = xbow_item.left_hand_unit
                swapped.right_hand_unit = xbow_item.right_hand_unit  -- nil is fine
                units = swapped
                ret[1] = units
                if _debug then
                    mod:info("get_item_units: swapped %s→crossbow lhu=%s", name, tostring(xbow_item.left_hand_unit))
                end
            elseif _debug then
                mod:info("get_item_units: longbow swap wanted for %s but wh_crossbow not in ItemMasterList", name)
            end
        end
    end
    ]]

    if _debug and item_data then
        local name = tostring(item_data.name)
        if name:find("longbow") or name:find("crossbow") or name:find("bow") then
            mod:info("get_item_units [%s] career=%s:", name, tostring(career_name))
            if units then
                for k, v in pairs(units) do
                    mod:info("  units.%s = %s", tostring(k), tostring(v))
                end
            else
                mod:info("  units = nil")
            end
            -- Also dump ItemMasterList entry for the crossbow so we know what fields exist.
            local xbow = ItemMasterList and ItemMasterList["wh_crossbow"]
            if xbow then
                mod:info("  ItemMasterList[wh_crossbow] fields:")
                for k, v in pairs(xbow) do
                    if type(v) ~= "function" and type(v) ~= "table" then
                        mod:info("    .%s = %s", tostring(k), tostring(v))
                    end
                end
            end
        end
    end
    
    return unpack(ret)
end)
]]

-- Dumps the chest view's field list when it opens, so we can find the background node name.
mod:hook_safe("DeusCursedChestView", "on_enter", function(self)
    if not _debug then return end
    local fields = {}
    for k, v in pairs(self) do
        local t = type(v)
        if t ~= "function" then
            fields[#fields+1] = string.format("  %s (%s) = %s", tostring(k), t,
                t == "table" and "{table}" or tostring(v))
        end
    end
    table.sort(fields)
    mod:info("DeusCursedChestView:on_enter fields (%d):", #fields)
    for _, s in ipairs(fields) do mod:info(s) end
end)

mod:command("debug", "Toggle debug auto-dump (weapon units, anim events, chest view, level info)", function()
    _debug = not _debug
    mod:echo("Debug mode " .. (_debug and "ON" or "OFF"))
    if _debug then
        mod:echo("Auto-dumping to log: weapon units on equip, anim events on wield, chest fields on open, level info on load")
    end
end)

mod:command("god", "Toggle godmode (invincibility)", function()
    _godmode = not _godmode
    mod:echo("Godmode " .. (_godmode and "ON" or "OFF"))
end)

mod:command("win", "Complete the current map", function()
    if Managers.state and Managers.state.game_mode then
        Managers.state.game_mode:complete_level()
    else
        mod:echo("No active game mode.")
    end
end)

-- Toggle third-person camera via instance-patch on the first_person_system extension.
mod:command("tp", "Toggle third-person view", function()
    _tp_enabled = not _tp_enabled
    mod:echo("Third-person: " .. (_tp_enabled and "ON" or "OFF"))
end)

-- ============================================================
-- Godmode
-- ============================================================

mod:hook("DamageUtils", "add_damage_network", function(func, attacked_unit, ...)
    if _godmode then
        local pm = Managers.player
        local player = pm and pm:local_player()
        local local_unit = player and player.player_unit
        if local_unit and attacked_unit == local_unit then
            return 0
        end
    end
    return func(attacked_unit, ...)
end)

-- ============================================================
-- Coin Multiplier
-- ============================================================

local _granting_starting_coins = false

mod:hook("DeusRunController", "on_soft_currency_picked_up", function(func, self, ...)
    local args = { ... }
    local raw_amount = args[1]

    if type(raw_amount) == "number" and not _granting_starting_coins then
        local multiplier = mod:get("coin_multiplier")
        args[1] = math.max(1, math.floor(raw_amount * multiplier))
        mod:info("Coin pickup: %d -> %d (x%.2f)", raw_amount, args[1], multiplier)
    end

    return func(self, unpack(args))
end)

-- ============================================================
-- Starting Coins
-- ============================================================
-- setup_run fires exactly once when a brand-new Chaos Wastes run begins
-- (not on each map transition or post-game). Perfect hook for run-start grants.

mod:hook_safe("DeusRunController", "setup_run", function(self)
    local starting = mod:get("starting_coins")
    if starting and starting > 0 then
        if self.on_soft_currency_picked_up then
            mod:info("Starting coins: granting %d", starting)
            _granting_starting_coins = true
            self:on_soft_currency_picked_up(starting)
            _granting_starting_coins = false
        end
    end
end)

-- ============================================================
-- Boon Options Count + Boon Filtering
-- ============================================================
-- generate_random_power_ups is called for both shrines (default 4 options)
-- and chests (default 3 options). We distinguish by the count arg value.
-- We also filter disabled boons from the result and support a dump command
-- to discover boon IDs by inspecting the live pool.

local SHRINE_DEFAULT = 4
local CHEST_DEFAULT  = 3

mod._dump_boons = false  -- set true by "t dump_boons" command

mod:command("dump_boons", "Log all boon IDs from the next shrine/chest roll", function()
    mod._dump_boons = true
    mod:echo("Boon dump enabled - open a shrine or chest to capture IDs.")
end)

mod:hook("DeusPowerUpUtils", "generate_random_power_ups", function(func, ...)
    local args = { ... }

    -- Modify count (existing logic)
    local count_idx = nil
    for i, v in ipairs(args) do
        if type(v) == "number" and v >= 1 and v <= 10 then
            count_idx = i
            break
        end
    end

    if count_idx then
        local original = args[count_idx]
        local custom_count

        if original == SHRINE_DEFAULT then
            custom_count = mod:get("shrine_boon_count")
        elseif original == CHEST_DEFAULT then
            custom_count = mod:get("chest_boon_count")
        end

        if custom_count and custom_count ~= original then
            mod:info("Boon options: args[%d]=%d -> %d", count_idx, original, custom_count)
            args[count_idx] = custom_count
        end
    else
        mod:info("Boon options: could not find count arg: %s %s %s %s",
            tostring(args[1]), tostring(args[2]), tostring(args[3]), tostring(args[4]))
    end

    -- Dump input pool for ID discovery
    if mod._dump_boons then
        mod:info("=== BOON POOL DUMP: %d args ===", #args)
        for i, v in ipairs(args) do
            if type(v) == "table" then
                local n = 0
                for _ in pairs(v) do n = n + 1 end
                mod:info("  args[%d] = table (%d entries)", i, n)
                for j, entry in ipairs(v) do
                    if type(entry) == "table" then
                        mod:info("    [%d] name=%s rarity=%s", j,
                            tostring(entry.name), tostring(entry.rarity))
                    else
                        mod:info("    [%d] = %s (%s)", j, tostring(entry), type(entry))
                    end
                end
            else
                mod:info("  args[%d] = %s (%s)", i, tostring(v), type(v))
            end
        end
    end

    -- Remove disabled boons from the draw pool before calling func.
    -- This ensures disabled boons are never drawn in the first place, so the
    -- returned count is always accurate — not reduced by post-draw filtering.
    -- Covers all availability types:
    --   shrine         → shrine shops
    --   cursed_chest   → Chests of Trials
    --   weapon_chest   → in-mission boon altars (power_up type) AND end-of-level grants
    --   terror_event   → terror event rewards
    -- Note: actual weapon generation goes through DeusWeaponGeneration.generate_weapon,
    -- which never calls generate_random_power_ups, so no special-casing is needed.
    local removed_main   = {}  -- {index, boon} removed from DeusPowerUpsArray
    local removed_rarity = {}  -- per-rarity removals from DeusPowerUpsArrayByRarity

    if DeusPowerUpsArray then
        for i = #DeusPowerUpsArray, 1, -1 do
            local boon = DeusPowerUpsArray[i]
            local key  = boon and boon.name and ("disable_boon_" .. boon.name)
            if key and mod:get(key) then
                table.remove(DeusPowerUpsArray, i)
                removed_main[#removed_main + 1] = { index = i, boon = boon }
                mod:info("Pool remove: %s", boon.name)
            end
        end
        if DeusPowerUpsArrayByRarity then
            for rarity, arr in pairs(DeusPowerUpsArrayByRarity) do
                removed_rarity[rarity] = {}
                for i = #arr, 1, -1 do
                    local boon = arr[i]
                    local key  = boon and boon.name and ("disable_boon_" .. boon.name)
                    if key and mod:get(key) then
                        table.remove(arr, i)
                        removed_rarity[rarity][#removed_rarity[rarity] + 1] = { index = i, boon = boon }
                    end
                end
            end
        end
    end

    -- Call original — returns (seed, new_power_ups)
    local new_seed, new_power_ups = func(unpack(args))

    -- Restore removed boons (iterate in reverse to preserve original indices)
    for i = #removed_main, 1, -1 do
        local e = removed_main[i]
        table.insert(DeusPowerUpsArray, e.index, e.boon)
    end
    for rarity, removed in pairs(removed_rarity) do
        local arr = DeusPowerUpsArrayByRarity[rarity]
        for i = #removed, 1, -1 do
            local e = removed[i]
            table.insert(arr, e.index, e.boon)
        end
    end

    -- Dump result for ID discovery
    if mod._dump_boons and type(new_power_ups) == "table" then
        mod:info("=== BOON RESULT DUMP ===")
        for i, boon in ipairs(new_power_ups) do
            if type(boon) == "table" then
                mod:info("  [%d] name=%s rarity=%s", i,
                    tostring(boon.name), tostring(boon.rarity))
            end
        end
        mod._dump_boons = false
        mod:echo("Boon dump complete - check the log for IDs.")
    end

    return new_seed, new_power_ups
end)

-- ============================================================
-- Arc Layout: NaN Fix + Spacing Expansion for Chest of Trials
-- ============================================================
-- The boon arc places N items evenly across a fixed angular span.
-- With a fixed span, more items = smaller gaps → hitbox overlap → crash.
--
-- Shrine (DeusShopView): _shop_item_widgets. Already sized for 4-5; only needs NaN fix.
-- Chest (DeusCursedChestView): _power_up_widgets. Sized for 3; needs expansion for 4-5.
--
-- Expansion formula: each widget offset *= (n-1)/(n_default-1).
-- This stretches the arc so adjacent-item spacing matches the default-count spacing.
-- The background may clip slightly but items will NOT overlap (no crash).

local function fix_arc_nan(widgets)
    -- NaN fix: count=1 → (count-1)=0 → game divides by zero → NaN offset → crash.
    if not widgets or #widgets ~= 1 then return end
    local w = widgets[1]
    if w and w.offset then
        if w.offset[1] ~= w.offset[1] then w.offset[1] = 0 end
        if w.offset[2] ~= w.offset[2] then w.offset[2] = 0 end
    end
end

mod:hook_safe("DeusShopView", "_create_ui_elements", function(self)
    -- Shrine is already sized generously; only guard against the NaN crash.
    fix_arc_nan(self._shop_item_widgets)
end)

-- TODO: Chest background panel clips when boon count > 3. Need to scale up the
-- background scenegraph node to match the expanded arc. Use `t dump_chest_view`
-- then open a chest to find the node names and sizes. See also: DeusShopView for
-- how the shrine handles 4-5 items (its background is already wide enough).
mod:hook_safe("DeusCursedChestView", "create_ui_elements", function(self)
    fix_arc_nan(self._power_up_widgets)
    if mod._dump_chest_view then
        mod._dump_chest_view = false
        mod:info("=== DeusCursedChestView scenegraph ===")
        if self._ui_scenegraph then
            for k, v in pairs(self._ui_scenegraph) do
                if type(v) == "table" then
                    local sx = v.size and v.size[1] or "?"
                    local sy = v.size and v.size[2] or "?"
                    local px = v.position and v.position[1] or "?"
                    local py = v.position and v.position[2] or "?"
                    mod:info("  scenegraph[%s]: size=(%s,%s) pos=(%s,%s)", tostring(k), tostring(sx), tostring(sy), tostring(px), tostring(py))
                else
                    mod:info("  scenegraph[%s] = %s", tostring(k), tostring(v))
                end
            end
        else
            mod:info("  _ui_scenegraph is nil")
        end
        mod:info("=== DeusCursedChestView widget list ===")
        if self._widgets then
            for i, w in ipairs(self._widgets) do
                mod:info("  widget[%d]: name=%s", i, tostring(w and w.name or "?"))
            end
        else
            mod:info("  _widgets is nil")
        end
        mod:info("=== power_up_widgets count: %d ===", self._power_up_widgets and #self._power_up_widgets or 0)
        mod:echo("dump_chest_view complete - check the log.")
    end
end)

mod:command("dump_chest_view", "Dump DeusCursedChestView scenegraph and widget names on next open", function()
    mod._dump_chest_view = true
    mod:echo("dump_chest_view armed - open a Chest of Trials to capture layout data.")
end)

-- ============================================================
-- Friendly Fire Toggle
-- ============================================================
-- On Champion+, ranged FF is on by default. Hook the two gate functions
-- that everything else calls through to suppress it when toggled off.

mod:hook("DamageUtils", "allow_friendly_fire_ranged", function(func, ...)
    if mod:get("disable_friendly_fire") then return false end
    return func(...)
end)

mod:hook("DamageUtils", "allow_friendly_fire_melee", function(func, ...)
    if mod:get("disable_friendly_fire") then return false end
    return func(...)
end)

-- ============================================================
-- Duplicate Career Allowance
-- ============================================================
-- By default the game reserves each hero (profile) for exactly one player.
-- When a joining player's wanted hero is taken, they get redirected to a free
-- one. Three hooks suppress that enforcement:
--
-- 1. ProfileSynchronizer.get_profile_index_reservation — make the wanted hero
--    always appear unoccupied so handle_profile_delegation_for_joining_player
--    keeps the player on their chosen hero.
-- 2. ProfileSynchronizer.try_reserve_profile_for_peer — if the reservation
--    state still rejects the request (another peer holds the slot in state),
--    return true anyway so assign_full_profile proceeds per-peer correctly.
-- 3. ProfileSynchronizer.is_free_in_lobby — unblock the profile picker UI so
--    players can select an already-chosen hero from the lobby popup.

mod:hook("ProfileSynchronizer", "get_profile_index_reservation", function(func, self, party_id, profile_index)
    if mod:get("allow_duplicate_careers") then return nil, nil end
    return func(self, party_id, profile_index)
end)

mod:hook("ProfileSynchronizer", "try_reserve_profile_for_peer", function(func, self, party_id, peer_id, profile_index, career_index)
    local result = func(self, party_id, peer_id, profile_index, career_index)
    if result then return true end
    -- func returned false: profile is reserved by another peer.
    -- When duplicate careers are allowed, let it proceed without touching state.
    if mod:get("allow_duplicate_careers") then return true end
    return false
end)

mod:hook("ProfileSynchronizer", "is_free_in_lobby", function(func, profile_index, lobby_data, optional_party_id)
    if mod:get("allow_duplicate_careers") then return true end
    return func(profile_index, lobby_data, optional_party_id)
end)

-- ============================================================
-- Curse Disabling
-- ============================================================

local function is_curse_disabled(curse_name)
    if type(curse_name) ~= "string" or not curse_name:find("^curse_") then return false end
    local key = "disable_curse_" .. curse_name:gsub("^curse_", "")
    return mod:get(key) == true
end

-- Gate 1: MutatorHandler._activate_mutator — suppresses the curse effect itself.
mod:hook("MutatorHandler", "_activate_mutator", function(func, self, name, ...)
    if is_curse_disabled(name) then
        mod:echo("Suppressed curse: " .. name)
        return
    end
    return func(self, name, ...)
end)

-- Gate 2: DeusMechanism.get_current_node_curse — suppresses the popup (DeusCurseUI)
-- and prevents flow_callback_set_deus_curse_active from ever activating the curse.
mod:hook("DeusMechanism", "get_current_node_curse", function(func, self, ...)
    local curse = func(self, ...)
    if is_curse_disabled(curse) then return nil end
    return curse
end)

-- Gate 3: DeusMapDecisionView._enable_hover — hides the chaos god icon/text in
-- the map tooltip for nodes whose curse is disabled.
-- Gate 4: DeusMechanism._transition_next_node — clears current_node.curse before
-- get_next_level_data runs so curse packages are never loaded (prevents sky/env effects).
mod:hook("DeusMechanism", "_transition_next_node", function(func, self, next_node_key, ...)
    local drc = self._deus_run_controller
    local graph_data = drc and drc:get_graph_data()
    local node = graph_data and graph_data[next_node_key]
    local saved_curse = node and node.curse

    if saved_curse and is_curse_disabled(saved_curse) then
        mod:info("Clearing curse from node before level load: %s", saved_curse)
        node.curse = nil
    end

    local results = { func(self, next_node_key, ...) }

    if saved_curse and is_curse_disabled(saved_curse) then
        node.curse = saved_curse
    end

    return unpack(results)
end)

-- Gate 5: DeusMechanism.start_next_round — clears current_node.curse before the
-- mutators list is built so the curse mutator is never activated in-game.
-- Also clears current_node.theme to suppress god-themed sky/shader mutators
-- that load from DeusThemeSettings[theme].mutators. Theme is reset to "wastes"
-- (the neutral no-god theme) so the visual effects don't load either.
mod:hook("DeusMechanism", "start_next_round", function(func, self, ...)
    local drc = self._deus_run_controller
    local current_node = drc and drc:get_current_node()
    local saved_curse = current_node and current_node.curse
    local saved_theme = current_node and current_node.theme

    if saved_curse and is_curse_disabled(saved_curse) then
        mod:info("Clearing curse+theme from node before mutator build: %s", saved_curse)
        current_node.curse = nil
        current_node.theme = "wastes"
    end

    local results = { func(self, ...) }

    if saved_curse and is_curse_disabled(saved_curse) then
        current_node.curse = saved_curse
        current_node.theme = saved_theme
    end

    return unpack(results)
end)

mod:hook("DeusMapDecisionView", "_enable_hover", function(func, self, node_key, ...)
    local graph_data = self._deus_run_controller and self._deus_run_controller:get_graph_data()
    local node = graph_data and graph_data[node_key]
    if node and is_curse_disabled(node.curse) then
        local saved_theme = node.theme
        node.theme = nil
        func(self, node_key, ...)
        node.theme = saved_theme
        return
    end
    return func(self, node_key, ...)
end)

-- ============================================================
-- Boon Localization — auto-name from game data
-- ============================================================
-- DeusPowerUpTemplates[name].display_name is the real in-game localization key.
-- Managers.localization:append_backend_localizations() writes directly into the
-- table that Localize() checks first, so subsequent mod:localize(setting_id)
-- calls (which VMF falls back to Localize() for unknown keys) return correct names.
-- Also patches mod._localization directly in case VMF uses its own lookup table.

local _boon_loc_patched = false

local function patch_boon_localization()
    if _boon_loc_patched then return end
    if not DeusPowerUpTemplates or not DeusPowerUpsArray then return end
    _boon_loc_patched = true

    local injections = {}
    for _, entry in ipairs(DeusPowerUpsArray) do
        local name = entry.name
        if name then
            local template = DeusPowerUpTemplates[name]
            local display_key = template and template.display_name
            local display_name
            if display_key then
                local raw = Localize(display_key)
                -- Localize returns "<key>" when not found; discard that
                if raw ~= "<" .. display_key .. ">" then
                    display_name = raw
                end
            end
            display_name = display_name or name
            injections["disable_boon_" .. name] = display_name
            injections["start_boon_"   .. name] = display_name
        end
    end

    -- Inject into game's localization backend (VMF falls back to Localize())
    if Managers.localization then
        Managers.localization:append_backend_localizations(injections)
    end

    -- Also patch VMF's own localization table directly, in case it doesn't
    -- fall back to Localize() for settings it already has entries for.
    if type(mod._localization) == "table" then
        for key, display_name in pairs(injections) do
            if not mod._localization[key] then
                mod._localization[key] = {}
            end
            mod._localization[key].en = display_name
        end
    end
end

mod:hook_safe("DeusRunController", "init", function()
    patch_boon_localization()
end)

-- ============================================================
-- Starting Boons
-- ============================================================
-- Runs after _add_initial_power_ups so career talents are already set.
-- Looks up rarity from DeusPowerUpsArray (the live boon pool) — disabled boons
-- are only removed from the pool during generate_random_power_ups calls and
-- always restored immediately, so the pool is complete here. This means
-- a boon can be in both the disable list and the start list: it won't appear
-- at shrines/chests, but the player still receives it at run start.

mod:hook_safe("DeusRunController", "_add_initial_power_ups", function(self, peer_id, local_player_id, profile_index, career_index)
    local run_state = self._run_state
    local own_peer_id = run_state and run_state:get_own_peer_id()

    -- On the server: grant boons for any peer (host's own init + client inits via rpc_deus_set_initial_setup).
    -- On a client: only grant for own peer (local path; host will authoritative-set anyway).
    if not run_state:is_server() and peer_id ~= own_peer_id then return end
    if not DeusPowerUpsArray or not DeusPowerUpUtils then return end

    -- Build rarity lookup from the live pool so we never need a hardcoded map.
    local rarity_of = {}
    for _, entry in ipairs(DeusPowerUpsArray) do
        local name = entry.name
        if name and not rarity_of[name] then
            rarity_of[name] = entry.rarity
        end
    end

    local extra = {}
    for _, entry in ipairs(DeusPowerUpsArray) do
        local name = entry.name
        if name and mod:get("start_boon_" .. name) then
            extra[#extra + 1] = DeusPowerUpUtils.generate_specific_power_up(name, entry.rarity)
            mod:info("Starting boon: %s (%s)", name, entry.rarity)
        end
    end

    if #extra == 0 then return end

    local skip_metatable = true
    local existing = run_state:get_player_power_ups(peer_id, local_player_id, profile_index, career_index)
    local new_power_ups = table.clone(existing, skip_metatable)
    table.append(new_power_ups, extra)
    run_state:set_player_power_ups(peer_id, local_player_id, profile_index, career_index, new_power_ups)
    mod:echo(string.format("Granted %d starting boon(s).", #extra))
end)

-- ============================================================
-- Weapon Chest Distribution
-- ============================================================
-- Each level's in-mission weapon chests are lazily typed when first opened.
-- The type list (upgrade/swap_melee/swap_ranged/power_up) is built from
-- LevelSettings[level_key].deus_weapon_chest_distribution on first use, then
-- cached in self._deus_weapon_chest_distribution for the rest of that level.
-- We intercept the rebuild step to substitute our own counts.

mod:hook("DeusRunController", "get_deus_weapon_chest_type", function(func, self)
    local chest_distribution = self._deus_weapon_chest_distribution

    if (not chest_distribution or #chest_distribution == 0) and DEUS_CHEST_TYPES then
        local upgrade  = mod:get("chest_upgrade_count")
        local swap_m   = mod:get("chest_swap_melee_count")
        local swap_r   = mod:get("chest_swap_ranged_count")
        local power_up = mod:get("chest_power_up_count")

        -- Only override if any count differs from the original defaults
        local sig_default = { upgrade = 1, swap_melee = 1, swap_ranged = 1, power_up = 2 }
        local is_custom = upgrade  ~= sig_default.upgrade
                       or swap_m   ~= sig_default.swap_melee
                       or swap_r   ~= sig_default.swap_ranged
                       or power_up ~= sig_default.power_up

        if is_custom then
            local dist = {}
            for _ = 1, upgrade  do dist[#dist + 1] = DEUS_CHEST_TYPES.upgrade    end
            for _ = 1, swap_m   do dist[#dist + 1] = DEUS_CHEST_TYPES.swap_melee end
            for _ = 1, swap_r   do dist[#dist + 1] = DEUS_CHEST_TYPES.swap_ranged end
            for _ = 1, power_up do dist[#dist + 1] = DEUS_CHEST_TYPES.power_up   end

            if #dist > 0 then
                local run_state = self._run_state
                local node_key  = run_state and run_state:get_current_node_key()
                local path_graph = self:_get_graph_data()
                local node = path_graph and node_key and path_graph[node_key]
                local seed  = node and HashUtils and HashUtils.fnv32_hash(node.level_seed) or 0
                table.shuffle(dist, seed)

                self._deus_weapon_chest_distribution = dist
                local chest_type = dist[#dist]
                dist[#dist] = nil
                return chest_type
            end
        end
    end

    return func(self)
end)

-- ============================================================
-- Banned Weapon Traits + Any Trait on Any Weapon
-- ============================================================
-- Before generation/upgrade, temporarily replace each weapon's
-- baked_trait_combinations with a (possibly expanded, possibly filtered) pool,
-- then restore immediately after.
--
-- any_trait_any_weapon: gives every weapon the union of all weapons' combos.
-- ban_trait_*: strips combos containing that trait from the effective pool.

local _all_trait_combos_cache = nil

local function get_all_trait_combos()
    if _all_trait_combos_cache then return _all_trait_combos_cache end
    if not DeusWeapons then return nil end
    local all_combos = {}
    local seen = {}
    for _, data in pairs(DeusWeapons) do
        local combos = data.baked_trait_combinations
        if combos then
            for _, combo in ipairs(combos) do
                local key = table.concat(combo, "\0")
                if not seen[key] then
                    seen[key] = true
                    all_combos[#all_combos + 1] = combo
                end
            end
        end
    end
    _all_trait_combos_cache = all_combos
    return all_combos
end

local function apply_weapon_trait_filter()
    if not DeusWeapons then return {} end
    local any_trait = mod:get("any_trait_any_weapon")
    local expanded_pool = any_trait and get_all_trait_combos()
    local saved = {}

    for item_key, data in pairs(DeusWeapons) do
        local original = data.baked_trait_combinations
        local base = expanded_pool or original
        if not base then break end

        -- Apply ban filter to the effective pool
        local filtered = {}
        for _, combo in ipairs(base) do
            local ok = true
            for _, trait in ipairs(combo) do
                if mod:get("ban_trait_" .. trait) then
                    ok = false
                    break
                end
            end
            if ok then
                filtered[#filtered + 1] = combo
            end
        end

        -- Determine new value to install:
        --   filtered if we removed some AND alternatives remain
        --   base     if any_trait expanded it but nothing was banned
        --   nil      if nothing changed
        local new_val
        if #filtered < #base and #filtered > 0 then
            new_val = filtered                   -- filtered down
        elseif #filtered == 0 then
            new_val = base                       -- all banned: safety, keep original pool
        elseif base ~= original then
            new_val = base                       -- expanded by any_trait, no bans
        end

        if new_val and new_val ~= original then
            saved[item_key] = original
            data.baked_trait_combinations = new_val
        end
    end
    return saved
end

local function restore_weapon_trait_filter(saved)
    if not DeusWeapons then return end
    for item_key, original in pairs(saved) do
        DeusWeapons[item_key].baked_trait_combinations = original
    end
end

mod:hook("DeusWeaponGeneration", "generate_weapon", function(func, ...)
    local saved = apply_weapon_trait_filter()
    local result = func(...)
    restore_weapon_trait_filter(saved)
    return result
end)

mod:hook("DeusWeaponGeneration", "generate_weapon_for_slot", function(func, ...)
    local saved = apply_weapon_trait_filter()
    local result = func(...)
    restore_weapon_trait_filter(saved)
    return result
end)

mod:hook("DeusWeaponGeneration", "upgrade_item", function(func, ...)
    local saved = apply_weapon_trait_filter()
    local result = func(...)
    restore_weapon_trait_filter(saved)
    return result
end)

-- ============================================================
-- Run Structure: Force Belakor + Finale God Override
-- ============================================================
-- _setup_run is called on the host immediately after the run parameters are
-- resolved (dominant_god from vote/backend, with_belakor from backend cycle).
-- We intercept on the host (is_server=true) to override those values before
-- they are synced to clients via rpc_deus_setup_run.
--
-- Dominant god values: 1=Nurgle, 2=Tzeentch, 3=Khorne, 4=Slaanesh, 0=default.

local _FINALE_GODS = { "nurgle", "tzeentch", "khorne", "slaanesh" }

mod:hook("DeusMechanism", "_setup_run", function(func, self, run_id, run_seed, is_server, server_peer_id, difficulty, journey_name, dominant_god, with_belakor, mutators, boons)
    if is_server then
        if mod:get("force_belakor") then
            with_belakor = true
        end

        local god_idx = mod:get("finale_dominant_god")
        if god_idx and god_idx > 0 then
            local god = _FINALE_GODS[god_idx]
            if god then
                dominant_god = god
                mod:info("Finale god override: %s", god)
            end
        end
    end

    return func(self, run_id, run_seed, is_server, server_peer_id, difficulty, journey_name, dominant_god, with_belakor, mutators, boons)
end)

-- ============================================================
-- Pickup Spawn Counts (Weapon Altars, Chests of Trials, Arena Ammo)
-- + Campaign Potions in Chaos Wastes
-- ============================================================
-- Altar/chest counts: patch DEUS_LEVEL_PICKUP_SETTINGS presets.
-- Arena ammo: patch the current level's pickup_settings via LevelHelper
--   (handles both shared default_arena_pickup_settings and arena_belakor's
--   inline table); arena = primary with no deus_weapon_chest field.
-- Campaign potions: temporarily inject damage/speed/cooldown potions into
--   Pickups.deus_potions so they can appear alongside Chaos Wastes potions.
--   All three have spawn_weighting=0.2 (same as deus potions), safe to add.

mod:hook("PickupSystem", "populate_pickups", function(func, self, ...)
    if not LevelHelper then return func(self, ...) end

    local altar_total  = mod:get("chest_upgrade_count")
                       + mod:get("chest_swap_melee_count")
                       + mod:get("chest_swap_ranged_count")
                       + mod:get("chest_power_up_count")
    local cursed_count = mod:get("cursed_chest_count")
    local arena_ammo   = mod:get("arena_ammo_count")
    local potions_on   = mod:get("enable_campaign_potions")

    local altar_custom  = altar_total  ~= 5  -- default: 1+1+1+2
    local cursed_custom = cursed_count ~= 1  -- default: 1
    local ammo_custom   = arena_ammo   ~= 2  -- default: 2

    if not altar_custom and not cursed_custom and not ammo_custom and not potions_on then
        return func(self, ...)
    end

    -- Patch via LevelHelper:current_level_settings() — works for both preset
    -- references (e.g. default_signature_pickup_settings) and inline tables
    -- (e.g. arena_belakor). This is the same table populate_pickups will read.
    -- Arenas are identified by absence of deus_weapon_chest (no altars on arenas).
    local saved = {}
    local cur = LevelHelper:current_level_settings()
    local cur_ps = cur and cur.pickup_settings
    if cur_ps then
        for _, diff_data in pairs(cur_ps) do
            if type(diff_data) == "table" and diff_data.primary then
                local p = diff_data.primary
                local is_arena = p.deus_weapon_chest == nil
                local entry = { tbl = p }

                if not is_arena then
                    if altar_custom and p.deus_weapon_chest ~= nil then
                        entry.deus_weapon_chest = p.deus_weapon_chest
                        p.deus_weapon_chest = altar_total
                    end
                    if cursed_custom and p.deus_cursed_chest ~= nil then
                        entry.deus_cursed_chest = p.deus_cursed_chest
                        p.deus_cursed_chest = cursed_count
                    end
                else
                    if ammo_custom and p.ammo ~= nil then
                        entry.ammo = p.ammo
                        p.ammo = arena_ammo
                    end
                end

                if entry.deus_weapon_chest ~= nil
                or entry.deus_cursed_chest ~= nil
                or entry.ammo            ~= nil then
                    saved[#saved + 1] = entry
                end
            end
        end
    end

    -- Inject campaign potions into Pickups.deus_potions.
    local added_potions = {}
    if potions_on and Pickups and Pickups.deus_potions and Pickups.potions then
        for _, name in ipairs({ "damage_boost_potion", "speed_boost_potion", "cooldown_reduction_potion" }) do
            if Pickups.potions[name] and not Pickups.deus_potions[name] then
                Pickups.deus_potions[name] = Pickups.potions[name]
                added_potions[#added_potions + 1] = name
            end
        end
    end

    local results = { func(self, ...) }

    -- Restore everything.
    for _, entry in ipairs(saved) do
        local p = entry.tbl
        if entry.deus_weapon_chest ~= nil then p.deus_weapon_chest = entry.deus_weapon_chest end
        if entry.deus_cursed_chest ~= nil then p.deus_cursed_chest = entry.deus_cursed_chest end
        if entry.ammo              ~= nil then p.ammo              = entry.ammo              end
    end
    for _, name in ipairs(added_potions) do
        Pickups.deus_potions[name] = nil
    end

    return unpack(results)
end)

weapon_backend.install(mod, _WEAPON_UNLOCK_MAP, apply_weapon_unlocks)
