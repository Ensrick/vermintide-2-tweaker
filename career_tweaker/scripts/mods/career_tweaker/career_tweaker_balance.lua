local mod = get_mod("crt")

-- ============================================================
-- Talent Balance Modification Framework
-- ============================================================
-- Each entry in BALANCE_MODS is a user-togglable balance change.
-- The setting_id key must match a checkbox in career_tweaker_data.lua.
--
-- Structure:
--   patches = { { buff = "buff_template_name", field = "field_name", value = new_value }, ... }
--   custom_apply(originals)   — optional, for changes beyond simple field patches
--   custom_restore(originals) — optional, paired with custom_apply
--
-- Patches mutate BuffTemplates[buff].buffs[1][field] at runtime.
-- Changes take effect next time TalentExtension.apply_buffs_from_talents() runs
-- (i.e. next mission load or talent change).
--
-- Hook-based mods check their setting via mod:get() on every call,
-- so they activate/deactivate without needing apply/restore cycles.

local BALANCE_MODS = {
    balance_zealot_merc_allow_random_crits = {
        character = "victor/markus",
        career    = "wh_zealot / es_mercenary",
        patches   = {},
    },
    balance_whc_parry_extended_window = {
        character = "victor",
        career    = "wh_captain",
        patches   = {},
    },
}

-- ============================================================
-- Hook: Allow random crits alongside "crit every 5 hits"
-- ============================================================
-- Zealot and Mercenary talents have perks = { "no_random_crits" }.
-- ActionUtils.is_critical_strike checks has_talent_perk("no_random_crits")
-- and forces is_crit = false, bypassing normal crit RNG.
-- This hook suppresses that perk so natural crits can still proc.

mod:hook("TalentExtension", "has_talent_perk", function(func, self, perk)
    if perk == "no_random_crits" and mod:get("balance_zealot_merc_allow_random_crits") then
        return false
    end
    return func(self, perk)
end)

-- ============================================================
-- Hook: Extend parry window when WHC parry-crit talent toggle is on
-- ============================================================
-- The parry window is hardcoded to 0.5s in ActionBlock and ActionMeleeStart.
-- This doubles it to 1.0s when the toggle is enabled.

mod:hook_safe("ActionBlock", "client_owner_start_action", function(self, new_action, t)
    if mod:get("balance_whc_parry_extended_window") then
        local status_extension = self._status_extension
        if status_extension and status_extension.timed_block then
            status_extension.timed_block = t + 1.0
        end
    end
end)

mod:hook_safe("ActionMeleeStart", "client_owner_start_action", function(self, new_action, t)
    if mod:get("balance_whc_parry_extended_window") then
        local status_extension = self._status_extension
        if status_extension and status_extension.timed_block then
            status_extension.timed_block = t + 1.0
        end
    end
end)

-- ============================================================
-- Field-patch apply/restore engine
-- ============================================================

local _originals = {}

local function apply_balance_mods()
    if not BuffTemplates then return end

    for setting_id, saved in pairs(_originals) do
        for _, entry in ipairs(saved) do
            local template = BuffTemplates[entry.buff]
            if template and template.buffs and template.buffs[1] then
                template.buffs[1][entry.field] = entry.old_value
            end
        end
        local def = BALANCE_MODS[setting_id]
        if def and def.custom_restore then
            def.custom_restore(saved)
        end
    end
    _originals = {}

    for setting_id, def in pairs(BALANCE_MODS) do
        if mod:get(setting_id) then
            local saved = {}
            for _, patch in ipairs(def.patches) do
                local template = BuffTemplates[patch.buff]
                if template and template.buffs and template.buffs[1] then
                    saved[#saved + 1] = {
                        buff      = patch.buff,
                        field     = patch.field,
                        old_value = template.buffs[1][patch.field],
                    }
                    template.buffs[1][patch.field] = patch.value
                end
            end
            if def.custom_apply then
                def.custom_apply(saved)
            end
            _originals[setting_id] = saved
        end
    end
end

local function restore_all_balance_mods()
    if not BuffTemplates then return end

    for setting_id, saved in pairs(_originals) do
        local def = BALANCE_MODS[setting_id]
        if def and def.custom_restore then
            def.custom_restore(saved)
        end
        for _, entry in ipairs(saved) do
            local template = BuffTemplates[entry.buff]
            if template and template.buffs and template.buffs[1] then
                template.buffs[1][entry.field] = entry.old_value
            end
        end
    end
    _originals = {}
end

local function get_active_count()
    local count = 0
    for setting_id, _ in pairs(BALANCE_MODS) do
        if mod:get(setting_id) then
            count = count + 1
        end
    end
    return count
end

return {
    BALANCE_MODS = BALANCE_MODS,
    apply        = apply_balance_mods,
    restore      = restore_all_balance_mods,
    active_count = get_active_count,
}
