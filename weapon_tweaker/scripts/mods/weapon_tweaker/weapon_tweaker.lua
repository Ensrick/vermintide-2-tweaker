local mod = get_mod("wt")
local weapon_backend = mod:dofile("scripts/mods/weapon_tweaker/weapon_tweaker_backend")

local MOD_VERSION = "0.8.0-dev"
mod:info("Weapon Tweaker v%s loaded", MOD_VERSION)
mod:echo("Weapon Tweaker v" .. MOD_VERSION)

local weapon_unlock_map = {
    -- Kruber (es_1h_sword, es_1h_mace, dr_1h_axe are native)
    es_mercenary      = { "dr_1h_axe", "es_sword_shield_breton", "bw_sword", "wh_1h_falchion", "wh_1h_axe", "we_1h_sword", "dr_1h_hammer", "dr_shield_hammer", "bw_1h_crowbill", "wh_1h_hammer", "wh_hammer_shield", "wh_2h_sword", "es_1h_flail", "bw_1h_flail_flaming", "we_longbow", "we_spear", "wh_2h_billhook", "we_1h_spears_shield", "we_2h_sword", "dr_2h_axe", "dr_2h_hammer", "dr_handgun" },
    es_huntsman       = { "bw_sword", "wh_1h_falchion", "wh_1h_axe", "we_1h_sword", "dr_1h_hammer", "dr_shield_hammer", "bw_1h_crowbill", "wh_1h_hammer", "wh_hammer_shield", "wh_2h_sword", "es_1h_flail", "bw_1h_flail_flaming", "we_longbow", "we_spear", "wh_2h_billhook", "we_1h_spears_shield", "we_2h_sword", "dr_2h_axe", "dr_2h_hammer", "dr_handgun" },
    es_knight         = { "bw_sword", "wh_1h_falchion", "wh_1h_axe", "we_1h_sword", "dr_1h_hammer", "es_2h_heavy_spear", "dr_shield_hammer", "bw_1h_crowbill", "wh_1h_hammer", "wh_hammer_shield", "wh_2h_sword", "es_1h_flail", "bw_1h_flail_flaming", "we_longbow", "we_spear", "wh_2h_billhook", "we_1h_spears_shield", "we_2h_sword", "dr_2h_axe", "dr_2h_hammer", "dr_handgun" },
    es_questingknight = { "bw_sword", "wh_1h_falchion", "wh_1h_axe", "we_1h_sword", "dr_1h_hammer", "es_2h_heavy_spear", "es_deus_01", "es_halberd", "dr_shield_hammer", "bw_1h_crowbill", "wh_1h_hammer", "wh_hammer_shield", "wh_2h_sword", "es_1h_flail", "bw_1h_flail_flaming", "we_longbow", "es_longbow", "es_handgun", "es_repeating_handgun", "es_blunderbuss", "we_spear", "wh_2h_billhook", "we_1h_spears_shield", "we_2h_sword", "dr_2h_axe", "dr_2h_hammer", "dr_handgun" },
    -- Bardin (dr_1h_hammer, dr_1h_axe are native)
    dr_ranger         = { "es_1h_sword", "es_1h_mace", "bw_sword", "wh_1h_falchion", "wh_1h_axe", "we_1h_sword", "es_mace_shield", "bw_1h_crowbill", "wh_1h_hammer", "wh_hammer_shield", "dr_dual_wield_axes", "wh_crossbow", "dr_deus_01", "es_2h_hammer", "wh_dual_hammer", "es_handgun" },
    dr_ironbreaker    = { "es_1h_sword", "es_1h_mace", "bw_sword", "wh_1h_falchion", "wh_1h_axe", "we_1h_sword", "es_mace_shield", "bw_1h_crowbill", "wh_1h_hammer", "wh_hammer_shield", "dr_dual_wield_axes", "wh_crossbow", "dr_1h_throwing_axes", "es_2h_hammer", "wh_dual_hammer", "es_handgun" },
    dr_slayer         = { "es_1h_sword", "es_1h_mace", "bw_sword", "wh_1h_falchion", "wh_1h_axe", "we_1h_sword", "es_mace_shield", "dr_shield_axe", "dr_shield_hammer", "bw_1h_crowbill", "wh_1h_hammer", "wh_hammer_shield", "wh_crossbow", "dr_crossbow", "dr_1h_throwing_axes", "dr_deus_01", "dr_handgun", "dr_rakegun", "dr_steam_pistol", "es_2h_hammer", "wh_dual_hammer", "es_handgun" },
    dr_engineer       = { "es_1h_sword", "es_1h_mace", "bw_sword", "wh_1h_falchion", "wh_1h_axe", "we_1h_sword", "es_mace_shield", "bw_1h_crowbill", "wh_1h_hammer", "wh_hammer_shield", "dr_dual_wield_axes", "wh_crossbow", "dr_crossbow", "dr_1h_throwing_axes", "es_2h_hammer", "wh_dual_hammer", "es_handgun" },
    -- Kerillian (we_1h_sword is native)
    we_waywatcher     = { "es_1h_sword", "es_1h_mace", "bw_sword", "wh_1h_falchion", "dr_1h_axe", "wh_1h_axe", "dr_1h_hammer", "we_1h_spears_shield", "bw_1h_crowbill", "wh_1h_hammer", "we_crossbow_repeater", "wh_crossbow_repeater", "es_longbow", "es_2h_heavy_spear", "es_halberd", "es_deus_01", "es_2h_sword", "wh_2h_sword" },
    we_maidenguard    = { "es_1h_sword", "es_1h_mace", "bw_sword", "wh_1h_falchion", "dr_1h_axe", "wh_1h_axe", "dr_1h_hammer", "bw_1h_crowbill", "wh_1h_hammer", "we_crossbow_repeater", "wh_crossbow_repeater", "es_longbow", "es_2h_heavy_spear", "es_halberd", "es_deus_01", "es_2h_sword", "wh_2h_sword" },
    we_shade          = { "es_1h_sword", "es_1h_mace", "bw_sword", "wh_1h_falchion", "dr_1h_axe", "wh_1h_axe", "dr_1h_hammer", "we_1h_spears_shield", "bw_1h_crowbill", "wh_1h_hammer", "wh_crossbow_repeater", "es_longbow", "es_2h_heavy_spear", "es_halberd", "es_deus_01", "es_2h_sword", "wh_2h_sword" },
    we_thornsister    = { "es_1h_sword", "es_1h_mace", "bw_sword", "wh_1h_falchion", "dr_1h_axe", "wh_1h_axe", "dr_1h_hammer", "we_1h_spears_shield", "bw_1h_crowbill", "wh_1h_hammer", "we_crossbow_repeater", "wh_crossbow_repeater", "es_longbow", "es_2h_heavy_spear", "es_halberd", "es_deus_01", "es_2h_sword", "wh_2h_sword" },
    -- Saltzpyre (wh_1h_falchion, wh_1h_axe are native)
    wh_captain        = { "es_1h_sword", "es_1h_mace", "bw_sword", "dr_1h_axe", "we_1h_sword", "dr_1h_hammer", "bw_1h_crowbill", "wh_1h_hammer", "es_2h_sword", "we_2h_sword", "bw_1h_flail_flaming", "dr_crossbow", "we_crossbow_repeater", "we_spear", "es_2h_heavy_spear", "es_halberd", "wh_2h_hammer", "wh_dual_hammer", "dr_dual_wield_hammers" },
    wh_bountyhunter   = { "es_1h_sword", "es_1h_mace", "bw_sword", "dr_1h_axe", "we_1h_sword", "dr_1h_hammer", "bw_1h_crowbill", "wh_1h_hammer", "es_2h_sword", "we_2h_sword", "bw_1h_flail_flaming", "dr_crossbow", "we_crossbow_repeater", "we_spear", "es_2h_heavy_spear", "es_halberd", "wh_2h_hammer", "wh_dual_hammer", "dr_dual_wield_hammers" },
    wh_zealot         = { "es_1h_sword", "es_1h_mace", "bw_sword", "dr_1h_axe", "we_1h_sword", "dr_1h_hammer", "bw_1h_crowbill", "wh_1h_hammer", "es_2h_sword", "we_2h_sword", "bw_1h_flail_flaming", "dr_crossbow", "we_crossbow_repeater", "we_spear", "es_2h_heavy_spear", "es_halberd", "wh_2h_hammer", "wh_dual_hammer", "dr_dual_wield_hammers" },
    wh_priest         = { "es_1h_sword", "es_1h_mace", "bw_sword", "dr_1h_axe", "wh_1h_axe", "wh_1h_falchion", "we_1h_sword", "dr_1h_hammer", "bw_1h_crowbill", "wh_1h_hammer", "es_1h_flail", "bw_1h_flail_flaming", "es_mace_shield", "dr_shield_hammer", "we_crossbow_repeater", "we_spear", "es_2h_heavy_spear", "es_halberd", "wh_2h_billhook", "dr_dual_wield_hammers" },
    -- Sienna (bw_sword is native)
    bw_adept          = { "es_1h_sword", "es_1h_mace", "wh_1h_falchion", "dr_1h_axe", "wh_1h_axe", "we_1h_sword", "dr_1h_hammer", "wh_1h_hammer", "es_1h_flail" },
    bw_scholar        = { "es_1h_sword", "es_1h_mace", "wh_1h_falchion", "dr_1h_axe", "wh_1h_axe", "we_1h_sword", "dr_1h_hammer", "wh_1h_hammer", "es_1h_flail" },
    bw_unchained      = { "es_1h_sword", "es_1h_mace", "wh_1h_falchion", "dr_1h_axe", "wh_1h_axe", "we_1h_sword", "dr_1h_hammer", "wh_1h_hammer", "es_1h_flail" },
    bw_necromancer    = { "es_1h_sword", "es_1h_mace", "wh_1h_falchion", "dr_1h_axe", "wh_1h_axe", "we_1h_sword", "dr_1h_hammer", "wh_1h_hammer", "es_1h_flail" },
}

local original_can_wield = {}
local original_can_wield_saved = {}

local function feature_enabled(setting_id, default_value)
    local value = mod:get(setting_id)
    if value == nil then return default_value ~= false end
    return value == true
end

local function apply_weapon_unlocks()
    if not ItemMasterList then return end

    -- Collect every weapon key this mod might touch.
    local all_weapon_keys = {}
    for _, weapons in pairs(weapon_unlock_map) do
        for _, weapon_key in ipairs(weapons) do
            all_weapon_keys[weapon_key] = true
        end
    end

    -- Restore and Save logic
    for weapon_key in pairs(all_weapon_keys) do
        local item = ItemMasterList[weapon_key]
        if item then
            if not original_can_wield_saved[weapon_key] then
                original_can_wield_saved[weapon_key] = true
                if item.can_wield then
                    local original = {}
                    for index, value in ipairs(item.can_wield) do
                        original[index] = value
                    end
                    original_can_wield[weapon_key] = original
                end
            end

            local original = original_can_wield[weapon_key]
            if original then
                if not item.can_wield then item.can_wield = {} end
                while #item.can_wield > 0 do table.remove(item.can_wield) end
                for _, value in ipairs(original) do
                    item.can_wield[#item.can_wield + 1] = value
                end
            else
                item.can_wield = nil
            end
        end
    end

    -- Apply unlocks
    for career, weapons in pairs(weapon_unlock_map) do
        for _, weapon_key in ipairs(weapons) do
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

local _career_action_injections = {}

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

local _cached_career = nil
local function _local_career_name()
    local pm = Managers.player
    if not pm then return _cached_career end
    local pl = pm:local_player()
    if not pl then return _cached_career end
    local career = pl:career_name()
    if career then _cached_career = career; return career end
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
local _career_anim_redirect = {
    to_longbow                       = { alt = "to_es_longbow",                 prefix = "we_" },
    to_longbow_noammo                = { alt = "to_es_longbow_noammo",          prefix = "we_" },
    to_repeating_crossbow_elf        = { alt = "to_repeating_crossbow",         prefix = "we_" },
    to_repeating_crossbow_elf_noammo = { alt = "to_repeating_crossbow_noammo",  prefix = "we_" },
    to_1h_falchion                    = { alt = "to_1h_hammer",                   prefix = "wh_priest", invert = true },
    to_1h_sword                      = { alt = "to_1h_hammer",                   prefix = "wh_priest", invert = true },
    to_1h_axe                        = { alt = "to_1h_sword",                   prefix = "bw_", invert = true,
                                         overrides = { wh_priest = "to_1h_hammer" } },
    to_1h_crowbill                   = { alt = "to_1h_sword",                   prefix = "bw_",
                                         overrides = { wh_priest = "to_1h_hammer" } },
    to_1h_hammer_shield_priest       = { alt = "to_1h_hammer_shield",           prefix = "wh_priest" },
    to_spear                         = { alt = "to_spear",                     prefix = "we_",
                                         overrides = { wh_captain = "to_2h_billhook", wh_bountyhunter = "to_2h_billhook", wh_zealot = "to_2h_billhook", wh_priest = "to_1h_hammer" } },
    to_polearm                       = { alt = "to_spear",                     prefix = "es_",
                                         overrides = { wh_captain = "to_2h_billhook", wh_bountyhunter = "to_2h_billhook", wh_zealot = "to_2h_billhook", wh_priest = "to_1h_hammer" } },
    to_2h_billhook                   = { alt = "to_polearm",                   prefix = "wh_",
                                         overrides = { es_mercenary = "to_polearm", es_huntsman = "to_polearm", es_knight = "to_polearm", es_questingknight = "to_polearm", wh_priest = "to_1h_hammer" } },
}

-- Suffix-based animation redirect: when an event ending in a weapon suffix
-- doesn't exist on the skeleton, swap the suffix based on career.
-- Checked longest-first to avoid e.g. "_spear" matching "_2h_heavy_spear".
local _suffix_order = { "_2h_billhook", "_polearm", "_spear" }
local _suffix_career_map = {
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

local function _try_suffix_redirect(unit, event_name, career)
    for _, suffix in ipairs(_suffix_order) do
        local slen = #suffix
        if event_name:sub(-slen) == suffix then
            local map = _suffix_career_map[suffix]
            local target_suffix = map and map[career]
            if target_suffix then
                local base = event_name:sub(1, -(slen + 1))
                local target = base .. target_suffix
                if Unit.has_animation_event(unit, target) then
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
local _3p_remap_spear_to_billhook = {
    attack_swing_charge_right    = "attack_swing_stab_charge",
    attack_swing_charge_left     = "attack_swing_charge_left_diagonal",
    attack_swing_down_right      = "attack_swing_stab",
    attack_swing_down_left_axe   = "attack_swing_left_diagonal",
    attack_swing_down_left       = "attack_swing_stab",
    attack_swing_right           = "attack_swing_left_diagonal",
    attack_swing_heavy_right     = "attack_swing_heavy_left_diagonal",
    attack_swing_heavy           = "attack_swing_heavy_stab",
    push_stab                    = "attack_swing_left_diagonal",
}

local _3p_remap_triggers = {
    to_spear    = _3p_remap_spear_to_billhook,
    to_polearm  = _3p_remap_spear_to_billhook,
}

local _3p_weapon_remap = nil

local _log_anims = false
local _last_3p_unit = nil
local _original_animation_event = nil

mod:command("status", "Show current weapon tweaker state", function()
    mod:echo("Weapon Tweaker v" .. MOD_VERSION)
    local career = _local_career_name()
    mod:echo("Career: " .. (career or "unknown"))
    local remap_name = "none"
    if _3p_weapon_remap then
        for trigger, tbl in pairs(_3p_remap_triggers) do
            if tbl == _3p_weapon_remap then remap_name = trigger; break end
        end
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

mod:command("force3p", "Force a 3P animation event (usage: wt force3p attack_swing_charge_stab)", function(event)
    if not event then mod:echo("Usage: wt force3p <event_name>") return end
    if not _last_3p_unit then mod:echo("No 3P unit tracked yet — swing once first.") return end
    local has = Unit.has_animation_event(_last_3p_unit, event)
    mod:echo("force3p: " .. event .. " (exists=" .. tostring(has) .. ")")
    if has then
        if _original_animation_event then
            pcall(_original_animation_event, _last_3p_unit, event)
        else
            pcall(Unit.animation_event, _last_3p_unit, event)
        end
        mod:echo("  -> fired")
    else
        mod:echo("  -> event not found on 3P unit")
    end
end)

local function _is_local_player_unit(unit)
    local pm = Managers.player
    if not pm then return false end
    local ok, player = pcall(pm.local_player, pm)
    if not ok or not player then return false end
    return player.player_unit == unit
end

mod:hook("Unit", "animation_event", function(func, unit, event_name, ...)
    if not _original_animation_event then _original_animation_event = func end

    if not event_name then return func(unit, event_name, ...) end

    if not feature_enabled("enable_weapon_animation_redirects", true) then
        return func(unit, event_name, ...)
    end

    local is_local = _is_local_player_unit(unit)
    if not is_local then _last_3p_unit = unit end
    local career = _local_career_name()

    if _log_anims then
        local exists = Unit.has_animation_event(unit, event_name)
        local tag = is_local and "1P" or "3P"
        mod:echo(tag .. " " .. event_name .. (exists and "" or " [MISSING]"))
    end

    -- Clear 3P weapon remap only on actual weapon switches
    if _career_anim_redirect[event_name] or event_name == "to_crossbow_loaded"
        or event_name == "to_grenade" or event_name == "to_2h_billhook" then
        _3p_weapon_remap = nil
    end

    -- 3P body attack remap: player_unit IS the 3P body, remap its attack events
    if is_local and _3p_weapon_remap then
        local target = _3p_weapon_remap[event_name]
        if target and Unit.has_animation_event(unit, target) then
            if _log_anims then mod:echo("  3P REMAP -> " .. target) end
            pcall(func, unit, target, ...)
            return
        end
    end

    -- Career-aware redirects: phantom events exist on all skeletons but only play
    -- real animations on the correct character. Redirect by career prefix.
    local career_redir = _career_anim_redirect[event_name]
    if career_redir then
        if career_redir.overrides and career and career_redir.overrides[career] then
            local target = career_redir.overrides[career]
            if Unit.has_animation_event(unit, target) then
                if _3p_remap_triggers[event_name] then
                    _3p_weapon_remap = _3p_remap_triggers[event_name]
                end
                if _log_anims then mod:echo("  REDIR -> " .. target) end
                pcall(func, unit, target, ...)
                return
            elseif _log_anims then
                mod:echo("  REDIR FAIL: " .. target .. " not on unit")
            end
        end
        local matches_prefix = career and career:sub(1, #career_redir.prefix) == career_redir.prefix
        local should_redirect = career_redir.invert and matches_prefix or (not career_redir.invert and not matches_prefix)
        if should_redirect then
            if Unit.has_animation_event(unit, career_redir.alt) then
                if _log_anims then mod:echo("  REDIR -> " .. career_redir.alt) end
                pcall(func, unit, career_redir.alt, ...)
                return
            elseif _log_anims then
                mod:echo("  REDIR FAIL: " .. career_redir.alt .. " not on unit")
            end
        end
        pcall(func, unit, event_name, ...)
        return
    end

    -- Standard redirect: only fire if original event is missing from skeleton.
    local alt = _anim_redirect[event_name]
    if alt then
        if Unit.has_animation_event(unit, event_name) then
            return func(unit, event_name, ...)
        end
        if Unit.has_animation_event(unit, alt) then
            pcall(func, unit, alt, ...)
            return
        end
    end

    -- Suffix-based redirect: swap weapon suffix based on career.
    if career then
        local target = _try_suffix_redirect(unit, event_name, career)
        if target then
            if _log_anims then mod:echo("  SUFFIX -> " .. target) end
            pcall(func, unit, target, ...)
            return
        end
    end

    return func(unit, event_name, ...)
end)

-- ============================================================
-- Weapon Scale Overrides
-- ============================================================
-- Scale factors for cross-character weapons that look too small/large.
-- Keys: weapon_key. Values: table of career_prefix -> scale factor.
-- A weapon only gets scaled when equipped on a career matching one of
-- the listed prefixes. Native-character entries are omitted (scale 1.0).

local _weapon_scale_overrides = {
    -- Elf swords look small on bigger characters
    we_1h_sword  = { es_ = 1.15, wh_ = 1.15, dr_ = 1.10 },
    -- Sienna's sword is also small on bigger frames
    bw_sword     = { es_ = 1.15, wh_ = 1.15, dr_ = 1.10 },
    bw_1h_crowbill = { es_ = 1.10, wh_ = 1.10, dr_ = 1.05 },
}

local function _scale_weapon_units(slot_data, weapon_key, career_name)
    if not weapon_key or not career_name then return end

    local overrides = _weapon_scale_overrides[weapon_key]
    if not overrides then return end

    local scale_factor = nil
    for prefix, factor in pairs(overrides) do
        if career_name:sub(1, #prefix) == prefix then
            scale_factor = factor
            break
        end
    end
    if not scale_factor then return end

    local scale = Vector3(scale_factor, scale_factor, scale_factor)
    local unit_fields = { "left_unit_1p", "right_unit_1p", "left_unit_3p", "right_unit_3p" }
    for _, field in ipairs(unit_fields) do
        local unit = slot_data[field]
        if unit then
            pcall(Unit.set_local_scale, unit, 0, scale)
        end
    end
    mod:info("Scaled %s on %s by %.2fx", weapon_key, career_name, scale_factor)
end

mod:hook("GearUtils", "create_equipment", function(func, world, slot_name, item_data, unit_1p, unit_3p, is_bot, unit_template, extra_extension_data, ammo_percent, override_item_template, override_item_units, career_name)
    local result = func(world, slot_name, item_data, unit_1p, unit_3p, is_bot, unit_template, extra_extension_data, ammo_percent, override_item_template, override_item_units, career_name)
    if result and item_data then
        local weapon_key = item_data.name
        _scale_weapon_units(result, weapon_key, career_name)
    end
    return result
end)

mod.on_game_state_changed = function(status, state_name)
    mod:info("Weapon Tweaker: Baseline Active")
    apply_weapon_unlocks()
    patch_career_actions_on_weapons()
end

mod.on_setting_changed = function(setting_id)
    if setting_id and (setting_id:find("^unlock_") or setting_id == "debug") then
        apply_weapon_unlocks()
        patch_career_actions_on_weapons()
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

-- Install basic backend hooks (UI filtering and can_wield override)
weapon_backend.install(mod, weapon_unlock_map, apply_weapon_unlocks)
