local mod = get_mod("event_tweaker")

-- _evt_guard413_weave.lua — issue 413: weave-only mutator injection gate
--
-- Seven of the eight cat_winds weave mutators are UNSAFE on their stock path
-- outside a real Weave. Six are always dropped at the injection chokepoint.
-- Shadow is admitted only through _evt_shadow_adventure's asset-free adapter
-- after capability parity and the closed-roster fence are proven. The original
-- v0.4.24-dev crash floor remains the fail-closed fallback;
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
-- WHY NOT "just preload the package" (issue 413 follow-up, 2026-07-12).
-- The obvious fix -- preload the crashers' resource package on every peer, as
-- _evt_cursed_adventure.lua does for the Chaos Wastes curses -- does NOT apply
-- here. Those curses carry a loadable resource_packages/mutators/<name>
-- (mutator_curse_shadow_daggers.lua:151-153); the weave winds declare NO
-- packages field and have NO standalone loadable package. shadow's
-- wpn_shadow_gargoyle_head (item_master_list_local.lua:318;
-- Pickups.level_events pickups.lua:496-508) and vfx_static_shadow_01, and
-- life's units/weave/life/life_thorn_bushes_mutator (mutator_life.lua:20),
-- ship ONLY inside the weave LEVEL bundles (dlc_scorpion_*_shadow, weaves
-- 7/15/23/31/39), which Adventure never loads -- so there is nothing to
-- preload by name. Making shadow actually RUN in Adventure would require
-- event_tweaker to ship those units in its OWN resource package (which reaches
-- MODDED peers only) AND a server-side light_radius fallback -- server_update
-- does radius*radius with data.light_radius=nil outside a weave
-- (mutator_shadow.lua:80/87; the exact crash that already blacklists the
-- functionally-identical curse_belakors_shadows -- event_tweaker_curses.lua:38).
-- Even then a VANILLA client still runs the stock client_update spawn and CTDs,
-- and hot_join_sync re-broadcasts the activation to late joiners
-- (mutator_handler.lua:148-159). Therefore the stock path stays prohibited.
-- v0.4.37-dev's separate adapter proves a capability-specific all-mod roster,
-- omits both non-resident visual units, supplies radius 6, and locks hot joins.
-- If any proof fails, selection falls back to this original drop floor.
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

-- Host-visible skip notice (issue 413 follow-up). The drop in _evt_selection's
-- add() is silent to a host running mod-logging OFF: they tick a Winds-of-Magic
-- box, nothing happens, and the console-only [et:413] printf never reaches them
-- (the "not active or working" report). When the DROPPED name is one the host
-- explicitly enabled, echo ONCE per session so the skip reads as deliberate and
-- explained. Host-only by construction -- gather_mutators()/add() run only on
-- the injecting host -- and mod:echo is a LOCAL chat line, never networked, so
-- this adds zero vanilla-peer exposure. Session-level dedup (no per-mission
-- reset) keeps it to one line per name and needs no StateIngame.on_exit hook
-- (that pair is owned by _evt_cursed_adventure -- one hook per (Class,method)
-- mod-wide). pcall-wrapped: a cosmetic notice must never break injection.
local _notified_weave_drop = {}
local function _notify_weave_drop(name)
    if _notified_weave_drop[name] then return end
    _notified_weave_drop[name] = true
    pcall(function()
        mod:echo("[Events] '%s' skipped: Winds-of-Magic mutators only run inside a real Weave, not Adventure.", tostring(name))
    end)
end
ET.notify_weave_drop = _notify_weave_drop

rt_register("issue413_weave_only_mutators_gated", function()
    -- The 7 stock cat_winds crashers must stay classified; metal must not be.
    -- Shadow's later adapter is an explicit capability-gated exception, not a
    -- removal from the unsafe-stock-path classification.
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

rt_register("issue413_weave_drop_notice_dedups", function()
    -- The host-visible skip notice must fire at most ONCE per name per session,
    -- so the three live-event hooks' repeated gather_mutators() passes don't
    -- spam chat. mod:echo can't be intercepted cleanly here, so assert the
    -- testable invariant: the dedup set records the name on first call and a
    -- second call is a no-op. Probe key is cleaned up so it can't leak into a
    -- real drop notice.
    local probe = "__rt_probe_weave_drop__"
    _notified_weave_drop[probe] = nil
    _notify_weave_drop(probe)
    if not _notified_weave_drop[probe] then
        _notified_weave_drop[probe] = nil
        return "notify_weave_drop did not record the name (dedup set not populated)"
    end
    -- Second call must early-return (already recorded) and must not raise.
    local ok = pcall(_notify_weave_drop, probe)
    _notified_weave_drop[probe] = nil
    if not ok then
        return "notify_weave_drop raised on a repeat call"
    end
end)
