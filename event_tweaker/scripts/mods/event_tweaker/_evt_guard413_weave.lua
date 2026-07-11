local mod = get_mod("event_tweaker")

-- _evt_guard413_weave.lua — issue 413: weave-only mutator injection gate
--
-- Seven of the eight cat_winds weave mutators are UNSAFE outside a real Weave
-- and must be dropped at the injection chokepoint (_evt_selection.lua's
-- gather_mutators() add()) before append_live_event_mutators broadcasts them
-- to every peer via rpc_activate_mutator_client. Fix shipped v0.4.24-dev;
-- regression check issue413_weave_only_mutators_gated; checklist slug
-- et-weave-only-mutator-gate. DO NOT REMOVE.
--
-- Owned by: event_tweaker.lua entry point (dofile'd before _evt_selection).
-- Consumed via mod._evt exports: WEAVE_ONLY_MUTATORS, weave_wind_active.

local ET = mod._evt
local rt_register = ET.rt_register

-- Managers.weave:get_active_wind_settings() returns nil unless a weave
-- template is active (weave_manager.lua:423-432), and:
--   shadow  -- client_update_function spawns
--             units/weapons/player/wpn_shadow_gargoyle_head then calls
--             Unit.light on it (mutator_shadow.lua:186-187; also the
--             respawn path :159-160). That unit is resident only in the
--             Weave context, so in Adventure the spawn is invalid and
--             Unit.light raises an ENGINE fatal (bypasses pcall). Runs on
--             every peer with a local client -- mutator_handler.lua:210
--             keys client update on _has_local_client, host included.
--             THE issue-413 crash (client CTD, is_server=false).
--   heavens -- server_start_function nil-indexes wind_settings
--             (mutator_heavens.lua:38). Host script-error crash.
--   light   -- same class (mutator_light.lua:182, also :193 nil objective).
--   death   -- same class (mutator_death.lua:210).
--   beasts  -- same class (mutator_beasts.lua:122).
--   fire    -- client_start_function nil-indexes wind_settings on every
--             peer with a local client (mutator_fire.lua:39).
--   life    -- nil-safe reads (WindSettings.life global), but spawn_bush
--             network-spawns the weave-package unit
--             units/weave/life/life_thorn_bushes_mutator
--             (mutator_life.lua:19-24) -- same non-resident-resource fatal
--             class as shadow, replicated to every peer via husk spawn.
-- metal is deliberately NOT listed: get_wind_strength() falls back to 1
-- (weave_manager.lua:679-683), it never indexes wind_settings, and it
-- spawns no units -- safe (if uneventful) in Adventure.
--
-- Real Weave missions do NOT get their wind mutators from this injection
-- path: GameModeWeave pulls them from the weave template via
-- Managers.weave:mutators() (game_mode_weave.lua:134-138). So dropping
-- these names from OUR live-event injection when no wind is active cannot
-- change Weave, Deus, or any vanilla behavior. Checkboxes stay visible
-- (visibility is user-dictated); the drop is injection-time only and is
-- announced via printf.
local WEAVE_ONLY_MUTATORS = {
    life = true, heavens = true, light = true, shadow = true,
    fire = true, death = true, beasts = true,
}

-- True only when a real weave wind is active -- the exact precondition the
-- mutators above need. pcall-guarded: any error reads as "no weave context"
-- (fail closed = never inject the crashers when in doubt).
local function _weave_wind_active()
    local ok, wind = pcall(function()
        local mgrs = rawget(_G, "Managers")
        local wm = mgrs and mgrs.weave
        return wm and wm:get_active_wind_settings() or nil
    end)
    return ok and wind ~= nil
end

ET.WEAVE_ONLY_MUTATORS = WEAVE_ONLY_MUTATORS
ET.weave_wind_active = _weave_wind_active

rt_register("issue413_weave_only_mutators_gated", function()
    -- The 7 weave-only cat_winds crashers must be blocklisted; metal must
    -- not be. And in the keep (where this harness runs; never a weave) the
    -- gate must read "no wind active" so gather_mutators() drops them
    -- before injection.
    local expected = { "life", "heavens", "light", "shadow", "fire", "death", "beasts" }
    for i = 1, #expected do
        if not WEAVE_ONLY_MUTATORS[expected[i]] then
            return "weave-only blocklist missing [" .. expected[i] .. "]"
        end
    end
    if WEAVE_ONLY_MUTATORS.metal then
        return "metal must NOT be blocklisted (nil-safe, spawns nothing)"
    end
    local mgrs = rawget(_G, "Managers")
    local wm = mgrs and mgrs.weave
    local really_in_weave = wm and wm._active_weave_name ~= nil
    if not really_in_weave and _weave_wind_active() then
        return "gate reports an active weave wind outside a weave -- shadow would leak into Adventure"
    end
end)
