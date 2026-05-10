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
    -- Stagger THP rework: doubles per-target THP (base_value 1 -> 2) but caps
    -- the per-swing target count at 3 instead of 5. Light/medium/heavy stagger
    -- heal 0.5 / 2 / 4 THP per target; a perfect heavy swing across 3 enemies
    -- caps at 12 THP, a typical medium swing across 3 caps at 6 THP. Trades the
    -- vanilla horde-feast (5 medium staggers = 5 THP) for a smaller-but-richer
    -- payout that also rewards light/heavy stagger more meaningfully.
    balance_stagger_thp_rework = {
        character = "any",
        career    = "any (Heal-on-Stagger talents)",
        patches   = {
            { buff = "thp_tank", field = "base_value",  value = 2 },
            { buff = "thp_tank", field = "max_targets", value = 3 },
        },
    },
    -- Compresses every breed's bloodlust_health (the THP-on-kill amount used
    -- by Heal-on-Kill traits, Bloodlust talents, and the Warrior Priest
    -- aftershock heal) around a pivot via a power law: each breed's value
    -- becomes pivot * (orig/pivot)^n. With pivot=10 and n=0.5 the vanilla
    -- 1..50 range collapses to ~3..22 — slave kills give meaningful THP and
    -- monster kills no longer fully top a player off. Each breed file
    -- copies its number out of BreedTweaks.bloodlust_health at game-load
    -- time (e.g. breed_chaos_warrior.lua:134), so we mutate breed tables
    -- directly. Snapshot per breed_name → restored on disable / re-toggle.
    balance_thp_breed_normalize = {
        character = "any",
        career    = "any (THP-on-kill traits/talents)",
        patches   = {},
        custom_apply = function(saved)
            if not Breeds then return end
            local pivot = 10
            local n = 0.5
            saved.breed_thp_originals = {}
            for breed_name, breed in pairs(Breeds) do
                local v = breed and breed.bloodlust_health
                if type(v) == "number" and v > 0 then
                    saved.breed_thp_originals[breed_name] = v
                    breed.bloodlust_health = pivot * (v / pivot) ^ n
                end
            end
        end,
        custom_restore = function(saved)
            if not Breeds or not saved.breed_thp_originals then return end
            for breed_name, original in pairs(saved.breed_thp_originals) do
                local breed = Breeds[breed_name]
                if breed then
                    breed.bloodlust_health = original
                end
            end
            saved.breed_thp_originals = nil
        end,
    },
}

-- ============================================================
-- Hook: Allow random crits alongside "crit every 5 hits"
-- ============================================================
-- Zealot and Mercenary talents have perks = { "no_random_crits" }.
-- ActionUtils.is_critical_strike checks has_talent_perk("no_random_crits")
-- and forces is_crit = false, bypassing normal crit RNG.
-- This hook suppresses that perk so natural crits can still proc.

-- Idempotent and reversible: the hook always reads the current setting via
-- mod:get, so toggling the checkbox takes effect on the very next call to
-- has_talent_perk (which is per-attack via ActionUtils.is_critical_strike).
-- No state to clean up on disable beyond what mod.on_disabled already does.
mod:hook("TalentExtension", "has_talent_perk", function(func, self, perk)
    if perk == "no_random_crits" and mod:get("balance_zealot_merc_allow_random_crits") then
        return false
    end
    return func(self, perk)
end)

-- ============================================================
-- Hook: Extend parry window when WHC parry-crit talent toggle is on
-- ============================================================
-- Vanilla parry window is 0.5s (hardcoded in ActionBlock and ActionMeleeStart).
-- Extended window doubles it to 1.0s when the toggle is enabled.
local _PARRY_WINDOW_EXTENDED_S = 1.0

-- ActionBlock.client_owner_start_action sets `status_extension.timed_block = t + 0.5`
-- (action_block.lua:45). hook_safe runs AFTER the original, so our overwrite to
-- t + _PARRY_WINDOW_EXTENDED_S lands last and wins.
mod:hook_safe("ActionBlock", "client_owner_start_action", function(self, new_action, t)
    if mod:get("balance_whc_parry_extended_window") then
        local status_extension = self._status_extension
        if status_extension and status_extension.timed_block then
            status_extension.timed_block = t + _PARRY_WINDOW_EXTENDED_S
        end
    end
end)

-- ActionMeleeStart's charge-block is set in client_owner_post_update (action_melee_start.lua:42)
-- via `status_extension.timed_block = t + 0.5`. We hook_safe the same method so our extended
-- write lands AFTER the original on every tick that the charge-block branch fires.
-- Note: ActionMeleeStart inherits from ActionDummy and stores its extension as
-- `self.status_extension` (no underscore — action_dummy.lua:9), unlike ActionBlock above.
mod:hook_safe("ActionMeleeStart", "client_owner_post_update", function(self, dt, t, world)
    if mod:get("balance_whc_parry_extended_window") then
        local status_extension = self.status_extension
        if status_extension and status_extension.timed_block then
            status_extension.timed_block = t + _PARRY_WINDOW_EXTENDED_S
        end
    end
end)

-- ============================================================
-- Field-patch apply/restore engine
-- ============================================================
-- REVIEW: Currently unused — both registered BALANCE_MODS have empty
-- patches{} and rely on hooks above. _originals will always be empty after
-- apply, and restore is a no-op. Keep if patch-based mods are planned.

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
