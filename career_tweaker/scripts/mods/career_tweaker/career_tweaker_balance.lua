local mod = get_mod("crt")

-- ============================================================
-- Talent Rework Framework
-- ============================================================
-- Each entry in BALANCE_MODS is a user-togglable talent rework.
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
-- Hook-based reworks check their setting via mod:get() on every call,
-- so they activate/deactivate without needing apply/restore cycles.

-- Minimum value bloodlust_health gets clamped to when the
-- rework_general_thp_kill_minimum toggle is on. Vanilla minimum is skaven_horde
-- (slaves) at 1; beastmen_horde / chaos_horde sit at 1.5; skaven_roamer at 2.
-- Floor of 1.5 lifts slaves to match the other hordes without touching roamers
-- or anything above.
local _MIN_THP_ON_KILL = 1.5

-- Hellborg's Tutelage rework: how much to subtract from random crit chance
-- while the talent is selected. Mercenary's base crit chance is 5% (0.05),
-- so a flat 10% reduction zeroes the random-crit roll at base but stays
-- meaningfully positive once crit-chance stacking is applied (weapon traits,
-- properties, bench buffs).
local _HELLBORGS_CRIT_PENALTY = 0.10

-- ============================================================
-- Helper: stat-buff "double the small percent" reworks
-- ============================================================
-- The pattern across multiple talents is: a career-specific buff template
-- with a single sub-buff whose value is sourced from `buff_tweak_data.<name>`
-- and merged in at game-init via BuffUtils.apply_buff_tweak_data. The talent
-- tooltip's description_values[1].value is statically frozen on the talent
-- entry at the same init pass. To swap a 5% talent to 10%:
--   1. patch BuffTemplates[talent_name].buffs[1][buff_field] (runtime effect)
--   2. rewrite Talents[hero][id].description_values[1].value (tooltip text)
--
-- This builder factors both into a {patches, custom_apply, custom_restore}
-- triple compatible with the apply/restore engine below. Assumes the buff
-- template name matches the talent's `name` (true for victor_zealot_power,
-- bardin_ranger_attack_speed, kerillian_maidenguard_crit_chance — verify
-- before adding a new entry).
local function _build_stat_buff_rework(talent_name, buff_field, new_value)
    return {
        patches = {
            { buff = talent_name, field = buff_field, value = new_value },
        },
        custom_apply = function(saved)
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup[talent_name]
            if not lookup then return end
            local hero_talents = Talents[lookup.hero_name]
            local talent = hero_talents and hero_talents[lookup.talent_id]
            local dv = talent and talent.description_values and talent.description_values[1]
            if not dv then return end
            saved.tooltip_original = dv.value
            dv.value = new_value
        end,
        custom_restore = function(saved)
            if saved.tooltip_original == nil then return end
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup[talent_name]
            if not lookup then return end
            local hero_talents = Talents[lookup.hero_name]
            local talent = hero_talents and hero_talents[lookup.talent_id]
            local dv = talent and talent.description_values and talent.description_values[1]
            if not dv then return end
            dv.value = saved.tooltip_original
            saved.tooltip_original = nil
        end,
    }
end

local BALANCE_MODS = {
    rework_wh_zealot_smite_random_crits = {
        character = "victor",
        career    = "wh_zealot",
        patches   = {},
    },
    -- Zealot's row-1 +5% power talent (victor_zealot_power, multiplier 0.05).
    -- Career-specific template — patch doesn't bleed into other careers'
    -- equivalents.
    rework_wh_zealot_power_5_to_10 = _build_stat_buff_rework("victor_zealot_power", "multiplier", 0.10),
    -- Ranger Veteran's row-2 +5% attack speed talent
    -- (bardin_ranger_attack_speed, multiplier 0.05). Career-specific.
    rework_dr_ranger_attack_speed_5_to_10 = _build_stat_buff_rework("bardin_ranger_attack_speed", "multiplier", 0.10),
    -- Ranger Veteran's base HP pool: vanilla 100 → 125 (+25). Patches
    -- `CareerSettings.dr_ranger.attributes.max_hp`, the table that
    -- `PlayerUnitHealthExtension._get_base_max_health` reads via
    -- `SPProfiles[profile].careers[index].attributes.max_hp` — same table
    -- reference (SPProfiles.dwarf_ranger.careers entries are direct refs to
    -- CareerSettings.dr_* — see sp_profiles.lua:163). Takes effect on the
    -- next mission load / hero respawn (max health is recalculated in
    -- `PlayerUnitHealthExtension.init`); doesn't retroactively bump an
    -- already-spawned Ranger's max in the current mission.
    rework_dr_ranger_base_hp_plus_25 = {
        character = "bardin",
        career    = "dr_ranger",
        patches   = {},
        custom_apply = function(saved)
            local cs = CareerSettings and CareerSettings.dr_ranger
            local attrs = cs and cs.attributes
            if not attrs or type(attrs.max_hp) ~= "number" then return end
            saved.ranger_max_hp_original = attrs.max_hp
            attrs.max_hp = attrs.max_hp + 25
        end,
        custom_restore = function(saved)
            if saved.ranger_max_hp_original == nil then return end
            local cs = CareerSettings and CareerSettings.dr_ranger
            local attrs = cs and cs.attributes
            if not attrs then return end
            attrs.max_hp = saved.ranger_max_hp_original
            saved.ranger_max_hp_original = nil
        end,
    },
    -- Handmaiden's row-2 +5% crit chance talent
    -- (kerillian_maidenguard_crit_chance, bonus 0.05). Career-specific.
    -- Buff field is `bonus` not `multiplier` — critical_strike_chance stat_buff
    -- consumes bonus additively at the buff_extension level.
    rework_we_maidenguard_crit_chance_5_to_10 = _build_stat_buff_rework("kerillian_maidenguard_crit_chance", "bonus", 0.10),
    rework_es_mercenary_hellborgs_tutelage = {
        character = "markus",
        career    = "es_mercenary",
        patches   = {},
    },
    rework_wh_captain_parry_window = {
        character = "victor",
        career    = "wh_captain",
        patches   = {},
    },
    -- Double-Shotted (victor_bountyhunter_activated_ability_railgun): the
    -- talent's runtime effect is gated by the buff template's `multiplier`
    -- field on `victor_bountyhunter_activated_ability_railgun_delayed_add`
    -- (consumed by buff_function_templates.victor_bountyhunter_activated_ability_railgun_delayed,
    -- which calls career_extension:reduce_activated_ability_cooldown_percent(buff.multiplier)).
    -- Patching that template field 0.6 → 0.8 lifts the refund from 60% to 80%.
    --
    -- The displayed "60%" in the inventory talent tooltip is sourced from
    -- Talents.victor[talent_id].description_values[1].value (set at game-init
    -- from `buff_tweak_data.victor_bountyhunter_activated_ability_railgun.multiplier`,
    -- so by the time mods run that value is already frozen on the talent entry).
    -- The custom_apply hook walks TalentIDLookup to find the talent's table
    -- and rewrites the description_values entry in place; custom_restore puts
    -- it back. The tooltip refresh isn't instant — players need to close and
    -- re-enter the talent panel after toggling, same as Hellborg's Tutelage.
    rework_wh_bountyhunter_double_shotted_80 = {
        character = "victor",
        career    = "wh_bountyhunter",
        patches   = {
            { buff = "victor_bountyhunter_activated_ability_railgun_delayed_add", field = "multiplier", value = 0.8 },
        },
        custom_apply = function(saved)
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup["victor_bountyhunter_activated_ability_railgun"]
            if not lookup then return end
            local hero_talents = Talents[lookup.hero_name]
            local talent = hero_talents and hero_talents[lookup.talent_id]
            local dv = talent and talent.description_values and talent.description_values[1]
            if not dv then return end
            saved.double_shotted_tooltip_original = dv.value
            dv.value = 0.8
        end,
        custom_restore = function(saved)
            if saved.double_shotted_tooltip_original == nil then return end
            if not Talents or not TalentIDLookup then return end
            local lookup = TalentIDLookup["victor_bountyhunter_activated_ability_railgun"]
            if not lookup then return end
            local hero_talents = Talents[lookup.hero_name]
            local talent = hero_talents and hero_talents[lookup.talent_id]
            local dv = talent and talent.description_values and talent.description_values[1]
            if not dv then return end
            dv.value = saved.double_shotted_tooltip_original
            saved.double_shotted_tooltip_original = nil
        end,
    },
    -- Stagger THP rework: +50% per-target THP (base_value 1 -> 1.5) and caps
    -- the per-swing target count at 3 instead of 5. Light/medium/heavy stagger
    -- heal 0.375 / 1.5 / 3 THP per target; a perfect heavy swing across 3
    -- enemies caps at 9 THP, a typical medium swing across 3 caps at 4.5 THP.
    -- Trades the vanilla horde-feast (5 medium staggers = 5 THP) for a
    -- smaller-but-richer payout that also rewards light/heavy stagger more
    -- meaningfully without ballooning into the OP territory of the +100% rework.
    rework_general_stagger_thp = {
        character = "any",
        career    = "any (Heal-on-Stagger talents)",
        patches   = {
            { buff = "thp_tank", field = "base_value",  value = 1.5 },
            { buff = "thp_tank", field = "max_targets", value = 3 },
        },
    },
    -- Minimum THP-on-kill floor: clamps every breed's bloodlust_health (the
    -- per-enemy THP-on-kill amount used by Heal-on-Kill traits, Bloodlust
    -- talents, and the Warrior Priest aftershock heal) to at least
    -- _MIN_THP_ON_KILL. Vanilla slaves/hordes drop 0..1 THP which feels
    -- worthless; flooring at 1 gives any trash kill a meaningful payout
    -- without touching elites/specials/monsters. Each breed file copies its
    -- number out of BreedTweaks.bloodlust_health at game-load time
    -- (e.g. breed_chaos_warrior.lua:134), so we mutate breed tables directly.
    -- Snapshot per breed_name → restored on disable / re-toggle.
    rework_general_thp_kill_minimum = {
        character = "any",
        career    = "any (THP-on-kill traits/talents)",
        patches   = {},
        custom_apply = function(saved)
            if not Breeds then return end
            local floor = _MIN_THP_ON_KILL
            saved.breed_thp_originals = {}
            for breed_name, breed in pairs(Breeds) do
                local v = breed and breed.bloodlust_health
                if type(v) == "number" and v < floor then
                    saved.breed_thp_originals[breed_name] = v
                    breed.bloodlust_health = floor
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
-- Hook: per-career suppression of the no_random_crits perk
-- ============================================================
-- The Zealot (Smite) and Mercenary (Hellborg's Tutelage) "crit every 5 hits"
-- talents both attach the perk { "no_random_crits" }. ActionUtils.is_critical_strike
-- short-circuits the chance roll to false when this perk is present.
--
-- The hook differentiates by `self._career_name`: each rework toggle only
-- suppresses the perk for its own career, so Zealot's setting doesn't lift
-- Mercenary's restriction and vice versa. Both hooks idempotently re-read
-- mod:get() on every call, so toggling takes effect on the next attack.
mod:hook("TalentExtension", "has_talent_perk", function(func, self, perk)
    if perk == "no_random_crits" then
        local career = self._career_name
        if career == "wh_zealot" and mod:get("rework_wh_zealot_smite_random_crits") then
            return false
        end
        if career == "es_mercenary" and mod:get("rework_es_mercenary_hellborgs_tutelage") then
            return false
        end
    end
    return func(self, perk)
end)

-- ============================================================
-- Hook: Hellborg's Tutelage random crit-chance reduction
-- ============================================================
-- When the rework is active and the player is on Mercenary with Hellborg's
-- Tutelage (`markus_mercenary_crit_count`) selected, subtract
-- _HELLBORGS_CRIT_PENALTY from the final crit chance after vanilla buffs run.
-- The has_talent_perk hook above lifts the hard-zero short-circuit; this hook
-- supplies the trade-off (a smaller pool of random crits instead of none).
--
-- ActionUtils is a plain global table, so use table-form hooking per
-- CLAUDE.md hooking rules. Guard for load order — if the helper isn't
-- registered yet we skip the hook entirely (defensive; in practice the
-- helpers file loads at game boot, long before any VMF mod).
if ActionUtils and ActionUtils.get_critical_strike_chance then
    mod:hook(ActionUtils, "get_critical_strike_chance", function(func, unit, action, overrides)
        local chance = func(unit, action, overrides)
        if not mod:get("rework_es_mercenary_hellborgs_tutelage") then
            return chance
        end
        local talent_ext = ScriptUnit.has_extension(unit, "talent_system")
        if not talent_ext or talent_ext._career_name ~= "es_mercenary" then
            return chance
        end
        if not talent_ext:has_talent("markus_mercenary_crit_count") then
            return chance
        end
        local reduced = chance - _HELLBORGS_CRIT_PENALTY
        if reduced < 0 then reduced = 0 end
        return reduced
    end)
end

-- ============================================================
-- Hook: _G.Localize override for Hellborg's Tutelage description
-- ============================================================
-- The vanilla talent description text is rendered through Localize() and then
-- post-formatted by UIUtils.format_localized_description with the talent's
-- `description_values`. Mercenary crit_count has one description value
-- (buff_on_stacks = 5), so the override string takes one %d slot. Literal
-- percent signs MUST be `%%` because the result is re-fed through string.format
-- — a bare `%` becomes "[Invalid String Format]". See
-- feedback_vt2_localize_string_format_pipeline.md.
local _HELLBORGS_DESC_OVERRIDE =
    "Critical Strike every %d melee hits. Random Critical Strike chance reduced by 10%%."

mod:hook(_G, "Localize", function(func, key, ...)
    if type(key) == "string"
       and key == "markus_mercenary_crit_count_desc"
       and mod:get("rework_es_mercenary_hellborgs_tutelage") then
        return _HELLBORGS_DESC_OVERRIDE
    end
    return func(key, ...)
end)

-- ============================================================
-- Hook: Extend parry window when WHC parry-crit rework is on
-- ============================================================
-- Vanilla parry window is 0.5s (hardcoded in ActionBlock and ActionMeleeStart).
-- Extended window doubles it to 1.0s when the toggle is enabled.
local _PARRY_WINDOW_EXTENDED_S = 1.0

-- ActionBlock.client_owner_start_action sets `status_extension.timed_block = t + 0.5`
-- (action_block.lua:45). hook_safe runs AFTER the original, so our overwrite to
-- t + _PARRY_WINDOW_EXTENDED_S lands last and wins.
mod:hook_safe("ActionBlock", "client_owner_start_action", function(self, new_action, t)
    if mod:get("rework_wh_captain_parry_window") then
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
    if mod:get("rework_wh_captain_parry_window") then
        local status_extension = self.status_extension
        if status_extension and status_extension.timed_block then
            status_extension.timed_block = t + _PARRY_WINDOW_EXTENDED_S
        end
    end
end)

-- ============================================================
-- Hook: Zealot ability converts permanent → temporary health
-- ============================================================
-- When the toggle is on, every Zealot ability activation (Holy Fervour) moves
-- the player's current permanent (green) HP into temporary (white) HP. Uses
-- vanilla `PlayerUnitHealthExtension.convert_to_temp`, which self-routes:
--   * server  → mutates GameSession fields directly
--   * client  → sends `rpc_request_convert_temp` to the server, which calls
--               the server-side convert and the result replicates back.
-- Server-side `convert_to_temp` clamps via `math.min(current_health, amount)`,
-- so passing the read-back permanent value is safe (no overflow, no negative).
-- Existing THP is preserved (the field is added to, not overwritten).
--
-- hook_safe on `_run_ability` runs after vanilla has fired the ability buffs
-- and lunge — the conversion lands during the post-activation frame, so the
-- ignore-death talent (`victor_zealot_activated_ability_ignore_death`) is
-- already up if the player has it.
mod:hook_safe("CareerAbilityWHZealot", "_run_ability", function(self)
    if not mod:get("rework_wh_zealot_ability_green_to_thp") then return end
    local owner_unit = self._owner_unit
    if not owner_unit then return end
    local health_extension = ScriptUnit.has_extension(owner_unit, "health_system")
    if not health_extension then return end
    local permanent = health_extension:current_permanent_health()
    if permanent and permanent > 0 then
        health_extension:convert_to_temp(permanent)
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
