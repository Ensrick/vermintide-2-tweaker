-- _wt_availability.lua -- cross-character weapon availability control surface.
--
-- Owns the can_wield management + career-ability action injection split out of
-- the god file in the v0.12.209-dev Phase 1 OOP decomposition:
--   * apply_weapon_unlocks             -- strip/add mod-managed careers on ItemMasterList[*].can_wield
--   * patch_career_actions_on_weapons  -- inject the unlocking career's ability action onto the weapon template
--   * clear_weapon_unlocks             -- on_disabled revert of the can_wield additions
--   * clear_career_action_injections   -- on_disabled revert of the injected ability actions
-- plus the one-shot `_strip_removed_kruber_unlocks` cleanup and the shared
-- `_career_action_injections` bookkeeping table. No behavior change from the
-- pre-split god file -- the entry aliases each exported function as a file-local
-- (`local apply_weapon_unlocks = mod._wt.apply_weapon_unlocks`, ...) so every
-- lifecycle-callback / backend-install call site is byte-identical.
--
-- Owned by: weapon_tweaker.lua entry point. Consumed via: mod:dofile (after
-- wt_unlock_data.lua populates mod._wt.weapon_unlock_map / .cwv_managed, and
-- before the lifecycle callbacks that call these functions are defined).
-- Shared state: reads mod._wt.weapon_unlock_map + mod._wt.cwv_managed; exports
-- mod._wt.apply_weapon_unlocks / .patch_career_actions_on_weapons /
-- .clear_weapon_unlocks / .clear_career_action_injections. `feature_enabled`
-- stays in the entry (the anim funnel reads it on a hot path).

local mod = get_mod("wt")
local WT = mod._wt
local weapon_unlock_map = WT.weapon_unlock_map
local _cwv_managed       = WT.cwv_managed

-- v0.12.57-dev: pairs removed from `weapon_unlock_map`. Users who had the
-- corresponding `unlock_es_*_<weapon>` toggle = true before the removal will
-- have the career still in the weapon's `item.can_wield` list. The regular
-- strip-rebuild walk inside `apply_weapon_unlocks` only iterates pairs that
-- ARE in the map, so a removed pair would leak the can_wield entry forever.
-- This list keeps a one-shot cleanup invariant: every init pass strips the
-- removed Kruber careers from these weapons' can_wield, idempotently.
local _kruber_removed_pairs = {
    es_mercenary      = { "wh_1h_axe", "wh_hammer_shield", "dr_shield_hammer" },
    es_huntsman       = { "wh_1h_axe", "wh_hammer_shield", "dr_shield_hammer" },
    es_knight         = { "wh_1h_axe", "wh_hammer_shield", "dr_shield_hammer" },
    es_questingknight = { "wh_1h_axe", "wh_hammer_shield", "dr_shield_hammer" },
}

local function _strip_removed_kruber_unlocks()
    if not ItemMasterList then return end
    for career, weapons in pairs(_kruber_removed_pairs) do
        for _, weapon_key in ipairs(weapons) do
            -- Issue #8 (2026-05-23): defensive `rawget` — `weapon_key` here is
            -- from an internal literal table so a strict-metatable Crashify is
            -- unreachable today, but the convention is to never index
            -- ItemMasterList with a non-literal key. Cheap, future-proof.
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

-- CLARIFY: The strip-then-add pattern is required because this runs on
-- on_setting_changed too — toggling a checkbox off must REMOVE the career
-- from can_wield, not just leave it. Direct-modifying ItemMasterList is the
-- ONLY way (BackendUtils.can_wield_item is unhookable from split mods —
-- see DEVELOPMENT.md "Don't hook BackendUtils.can_wield_item").
local function apply_weapon_unlocks()
    if not ItemMasterList then return end

    -- Drop stale can_wield entries for pairs removed from `weapon_unlock_map`
    -- since the last release. Idempotent — runs every init + on_setting_changed.
    _strip_removed_kruber_unlocks()

    local has_cwv = get_mod("character_weapon_variants") ~= nil

    -- Strip all mod-managed careers from can_wield
    for career, weapons in pairs(weapon_unlock_map) do
        local cwv_skip = has_cwv and _cwv_managed[career]
        for _, weapon_key in ipairs(weapons) do
            if not (cwv_skip and cwv_skip[weapon_key]) then
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

    -- Add back only enabled ones
    for career, weapons in pairs(weapon_unlock_map) do
        local cwv_skip = has_cwv and _cwv_managed[career]
        for _, weapon_key in ipairs(weapons) do
            if not (cwv_skip and cwv_skip[weapon_key]) then
                if mod:get("unlock_" .. career .. "_" .. weapon_key) then
                    local item = rawget(ItemMasterList, weapon_key)
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
                        local item = rawget(ItemMasterList, weapon_key)
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

WT.apply_weapon_unlocks            = apply_weapon_unlocks
WT.patch_career_actions_on_weapons = patch_career_actions_on_weapons
WT.clear_weapon_unlocks            = clear_weapon_unlocks
WT.clear_career_action_injections  = clear_career_action_injections
