local mod = get_mod("ct_dev")

-- ============================================================================
-- Mechanic tweaks (sliders; default = vanilla)
-- ============================================================================
-- Lives in its own chunk (dofile'd module) so its file-scope locals do NOT count
-- against the main file's Lua 5.1 200-locals-per-function cap. Mirrors the
-- shard-strike / anath-raema save-restore pattern from the main file. The two
-- sync functions are exposed on `mod` so the main file's sync_host_dependent_state
-- and on_setting_changed can re-apply them. Reads settings through the main
-- file's host-synced `effective_setting` (exposed as mod._ct_effective_setting)
-- so client peers gate on the HOST's value. Source citations verified 2026-06-17.

local function _effective(name)
    local f = mod._ct_effective_setting
    if f then
        return f(name)
    end
    return mod:get(name)
end

-- ----------------------------------------------------------------------------
-- #6 Adventure RNG "save a consumable" trait odds
-- ----------------------------------------------------------------------------
-- Home Brewer / Healers Touch / Grenadier are Adventure weapon traits with a
-- chance to NOT consume the potion / healing item / grenade on use. Vanilla odds
-- are 25% each:
--   WeaponTraits.buff_templates.trait_ring_not_consume_potion.buffs[1].proc_chance      = 0.25 (weapon_traits.lua:69)
--   WeaponTraits.buff_templates.trait_necklace_not_consume_healing.buffs[1].proc_chance = 0.25 (weapon_traits.lua:84)
--   WeaponTraits.buff_templates.trait_trinket_not_consume_grenade.buffs[1].proc_chance  = 0.25 (weapon_traits.lua:104)
-- The proc gate reads buffs[1].proc_chance at add_buff time (buff_extension.lua:642).
-- Adventure and CW are SEPARATE templates (CW boons live in DeusPowerUpBuffTemplates),
-- so this never touches CW. Mutates both WeaponTraits.buff_templates and
-- (defensively) the global BuffTemplates. Save/restore; default 25% = vanilla.
local ADV_SAVE_TRAITS = {
    "trait_ring_not_consume_potion",      -- Home Brewer
    "trait_necklace_not_consume_healing", -- Healers Touch
    "trait_trinket_not_consume_grenade",  -- Grenadier
}
local adv_save_originals = nil

local function _adv_save_buff_entries()
    local out = {}
    local wt = rawget(_G, "WeaponTraits")
    local bt = rawget(_G, "BuffTemplates")
    for _, key in ipairs(ADV_SAVE_TRAITS) do
        local wt_t = wt and wt.buff_templates and wt.buff_templates[key]
        local wt_buff = wt_t and wt_t.buffs and wt_t.buffs[1]
        if wt_buff then out[#out + 1] = wt_buff end
        local bt_t = bt and bt[key]
        local bt_buff = bt_t and bt_t.buffs and bt_t.buffs[1]
        if bt_buff then out[#out + 1] = bt_buff end
    end
    return out
end

local function revert_adv_save_traits()
    if not adv_save_originals then return end
    -- All three vanilla traits share proc_chance 0.25, so restoring the captured
    -- value to every entry is correct.
    for _, b in ipairs(_adv_save_buff_entries()) do
        b.proc_chance = adv_save_originals.proc_chance
    end
    adv_save_originals = nil
end

local function apply_adv_save_traits()
    local pct = _effective("tweak_adventure_save_trait_chance") or 25
    local target = math.max(0, math.min(100, pct)) / 100
    if math.abs(target - 0.25) < 0.001 then
        revert_adv_save_traits()
        return
    end
    local entries = _adv_save_buff_entries()
    if #entries == 0 then
        mod:info("[adv-save-traits] WeaponTraits.buff_templates not loaded yet; will retry on settings sync")
        return
    end
    if not adv_save_originals then
        adv_save_originals = { proc_chance = entries[1].proc_chance or 0.25 }
    end
    for _, b in ipairs(entries) do
        b.proc_chance = target
    end
end

mod._ct_sync_adv_save_traits = function()
    apply_adv_save_traits()
end

-- ----------------------------------------------------------------------------
-- #5 Shadow Homing Skulls curse — stun (overpowered disable) duration
-- ----------------------------------------------------------------------------
-- The "Shadow Homing Skulls" CW curse fires homing skulls; on impact
-- belakor_homing_skull_debuff applies belakor_homing_skull_debuff_delayed_stun_effect,
-- a hard "overpowered" disable lasting duration = 2.5s (belakor_buff_settings.lua:655,
-- perk buff_perks.overpowered -> set_overpowered_network). The disable is
-- server-authoritative (applied only `if is_server`), so the HOST's value governs;
-- _effective reads the host's synced value. Slider defaults to vanilla 2.5s.
-- NOTE: the OTHER skull curse, "Skulls of Fury", is a stagger (stagger_value=2),
-- not a timed disable -- no duration field to scale, so it's intentionally not covered.
local shadow_skull_originals = nil
local SHADOW_SKULL_STUN_BUFF = "belakor_homing_skull_debuff_delayed_stun_effect"

local function _shadow_skull_stun_entry()
    local bt = rawget(_G, "BuffTemplates")
    local tmpl = bt and bt[SHADOW_SKULL_STUN_BUFF]
    return tmpl and tmpl.buffs and tmpl.buffs[1]
end

local function revert_shadow_skull_stun()
    if not shadow_skull_originals then return end
    local e = _shadow_skull_stun_entry()
    if e then e.duration = shadow_skull_originals.duration end
    shadow_skull_originals = nil
end

local function apply_shadow_skull_stun()
    local seconds = _effective("tweak_shadow_skull_stun_sec") or 2.5
    if math.abs(seconds - 2.5) < 0.001 then
        revert_shadow_skull_stun()
        return
    end
    local e = _shadow_skull_stun_entry()
    if not e then
        mod:info("[shadow-skull] BuffTemplates.%s not loaded yet; will retry on settings sync", SHADOW_SKULL_STUN_BUFF)
        return
    end
    if not shadow_skull_originals then
        shadow_skull_originals = { duration = e.duration or 2.5 }
    end
    e.duration = seconds
end

mod._ct_sync_shadow_skull_stun = function()
    apply_shadow_skull_stun()
end

-- Apply both on load.
mod._ct_sync_adv_save_traits()
mod._ct_sync_shadow_skull_stun()
