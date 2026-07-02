local mod = get_mod("ct_dev")

-- ============================================================================
-- Mechanic tweaks (sliders; default = vanilla)
-- ============================================================================
-- Lives in its own chunk (dofile'd module) so its file-scope locals do NOT count
-- against the main file's Lua 5.1 200-locals-per-function cap. Mirrors the
-- shard-strike / anath-raema save-restore pattern from the main file. The one
-- sync function (shadow-skull stun; the #6 adventure-trait slider moved to gt on
-- 2026-06-18) is exposed on `mod` so the main file's sync_host_dependent_state
-- and on_setting_changed can re-apply it. Reads settings through the main
-- file's host-synced `effective_setting` (exposed as mod._ct_effective_setting)
-- so client peers gate on the HOST's value. Source citations verified 2026-06-17.

local function _effective(name)
    local f = mod._ct_effective_setting
    if f then
        return f(name)
    end
    return mod:get(name)
end

-- #6 Adventure "save a consumable" trait odds — MOVED to general_tweaker (gt)
-- on 2026-06-18. Home Brewer / Healers Touch / Grenadier are ADVENTURE-mode
-- traits, not a Chaos Wastes feature, so the slider now lives in gt as
-- `gt_adventure_save_trait_chance`. Removed from ct.

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

-- Apply on load.
mod._ct_sync_shadow_skull_stun()
