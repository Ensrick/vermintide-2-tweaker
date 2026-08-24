local mod = get_mod("event_tweaker")

-- _evt_diagnostics.lua — diagnostic chat commands + issue 393 / 1309 probes
--
-- Read-only surfaces for verifying what the mod is (or would be) injecting:
-- /event_probe, /event_active, /event_clear, the issue 393 diagnostics-armed
-- first-Pacing-update settled snapshot, and the issue 1309 bounded Tzeentch
-- Twins co-op receipts. No behavior changes live here; everything is
-- echo/printf output plus the /event_clear checkbox reset.
--
-- Owned by: event_tweaker.lua entry point (dofile'd after _evt_selection).
-- Consumes mod._evt: gather_mutators, suppress_live_event,
-- displayable_registered_mutators; requires the shared catalog/curses modules
-- for /event_clear's sweep and the two pure issue probes for their decision
-- rules. Exports issue1309_on_mutator_activated / issue1309_flush_summary,
-- which _evt_cursed_adventure.lua (dofile'd later) calls from the hooks it
-- already owns on MutatorHandler._activate_mutator and StateIngame.on_exit --
-- VMF drops a second hook on the same (class, method) pair, so the diagnostic
-- must ride those instead of installing its own.

local ET = mod._evt

local Catalog         = require("scripts/mods/event_tweaker/event_tweaker_catalog")
local MUTATOR_CATALOG = Catalog.CATEGORIES
local Curses          = require("scripts/mods/event_tweaker/event_tweaker_curses")
local MANAGED_CURSES  = Curses.MANAGED_CURSES
local Issue393        = require("scripts/mods/event_tweaker/_evt_diag_high_intensity")
local Issue1309       = require("scripts/mods/event_tweaker/_evt_diag_tzeentch_twins")

local gather_mutators                = ET.gather_mutators
local suppress_live_event            = ET.suppress_live_event
local displayable_registered_mutators = ET.displayable_registered_mutators

local function dump_list(label, list)
    if not list or #list == 0 then
        mod:echo("[event] %s: <empty>", label)
        return
    end
    for i = 1, #list do
        local v = list[i]
        if type(v) == "table" then
            local muts = v.mutators and table.concat(v.mutators, ",") or ""
            local lvls = v.level_keys and table.concat(v.level_keys, ",") or "all"
            mod:echo("[event] %s[%d]: weekly_event=%s mutators={%s} levels={%s}",
                label, i, tostring(v.weekly_event), muts, lvls)
        else
            mod:echo("[event] %s[%d]: %s", label, i, tostring(v))
        end
    end
end

mod:command("event_probe", "Dump live-event state from the host's backend interface", function()
    local interface = Managers.backend and Managers.backend:get_interface("live_events")
    if not interface then
        mod:echo("[event] no live_events interface yet")
        return
    end
    dump_list("active_events", interface:get_active_events())
    dump_list("special_events", interface:get_special_events())
    dump_list("weekly_events", interface:get_weekly_events())
    mod:echo("[event] preset: %s suppress=%s",
        tostring(mod:get("event_preset")),
        tostring(suppress_live_event()))
    local muts = gather_mutators()
    mod:echo("[event] would-inject mutators: {%s}", table.concat(muts, ","))
end)

mod:command("event_active", "List currently-active mutators in the loaded game mode", function()
    local game_mode = Managers.state and Managers.state.game_mode
    local handler = game_mode and game_mode._mutator_handler
    if not handler then
        mod:echo("[event] no mutator_handler (not in a level?)")
        return
    end
    local active = handler:activated_mutators()
    local n = 0
    for name, _ in pairs(active) do
        n = n + 1
        mod:echo("[event] active mutator: %s", name)
    end
    if n == 0 then
        mod:echo("[event] no active mutators")
    end
end)

mod:command("event_clear", "Uncheck every individual mutator (preset untouched)", function()
    local n, seen = 0, {}
    local function clear(id)
        if not seen[id] and mod:get("mut_" .. id) then
            seen[id] = true
            mod:set("mut_" .. id, false, false)
            n = n + 1
        end
    end
    for ci = 1, #MUTATOR_CATALOG do
        local cat = MUTATOR_CATALOG[ci]
        for mi = 1, #cat.mutators do
            clear(cat.mutators[mi])
        end
    end
    for id in pairs(displayable_registered_mutators()) do
        clear(id)
    end
    for i = 1, #MANAGED_CURSES do
        clear(MANAGED_CURSES[i].id)
    end
    mod:echo("[event] cleared %d mutators", n)
end)

-- ============================================================
-- Post-init conflict-settings snapshot (issue 393 diagnostics-armed)
-- ============================================================
-- Issue 386 (v0.4.22-dev) stopped the injected high_intensity mutator from
-- CRASHING ConflictDirector.init, but the mutator reportedly has little
-- observable in-mission effect. Hypothesis [unverified]: enemy_tweaker's own
-- conflict-director patch re-application runs on the SAME
-- refresh_conflict_director_patches chain (conflict_director.lua:886, dispatched
-- from ConflictDirector.init line 94) and overwrites the mutator's
-- CurrentIntensitySettings / CurrentPacing writes (mutator_high_intensity.lua:8-14
-- sets max_intensity=200, decay_per_second=10, decay_delay=0.5,
-- intensity_add_per_percent_dmg_taken=0.1, and the three delay_*_threat_value=200)
-- AFTER they land but before they take effect.
--
-- A ConflictDirector.init post-hook is not a reliable "final" boundary when
-- another mod wraps init and mutates settings after its inner call returns.
-- Instead, sample after the first Pacing.update: every init wrapper has returned
-- by then and the mission is consuming the resolved state. Print ONE line per
-- Pacing instance, snapshotting the four CurrentIntensitySettings fields
-- the mutator writes, the three CurrentPacing.delay_*_threat_value fields
-- (post-#386 sanitizer these are per-difficulty tables, summarized as
-- table:normal=<v>), and the converted self.delay_horde_threat_value the director
-- instance will actually pace against (conflict_director.lua:219). The injected
-- list is event_tweaker's own gather_mutators() -- the same builder the
-- [event-inject] special_events line uses.
--
-- What the line proves either way:
--   * injected list contains high_intensity but max_intensity reads a vanilla
--     default (not 200) and/or the delays are NOT table:normal=200 -> the
--     mutator's writes were STOMPED after landing (confirms the hypothesis;
--     next step is ordering enemy_tweaker's re-application vs the mutator).
--   * max_intensity=200 and delays table:normal=200 with high_intensity injected
--     -> the writes SURVIVED intact, so the "little effect" report is not a
--     stomped-settings problem and the search moves to how the pacing/intensity
--     values are consumed (or to a difficulty-scaling / perception issue).
-- The classifier explicitly reports `settings_stomp` vs `intact`; an intact
-- result is evidence that the remaining report is about vanilla semantics, not
-- hook ordering. Source audit: GenericStatusExtension hard-caps player pacing
-- intensity at 100, so the mutator's max_intensity=200 cannot itself raise the
-- observed intensity ceiling; its effect is indirect (decay/damage gain and the
-- director delay thresholds).
-- printf only (user logs OFF); guarded; one cheap line per mission, always on in
-- dev per the diagnostics doctrine. No behavior change.
local _issue393_seen = setmetatable({}, { __mode = "k" })
mod:hook_safe("Pacing", "update", function(self)
    if _issue393_seen[self] then return end
    _issue393_seen[self] = true
    pcall(function()
        local cis = rawget(_G, "CurrentIntensitySettings")
        local cp  = rawget(_G, "CurrentPacing")
        -- Pacing delay fields are per-difficulty tables after the #386 sanitizer
        -- (or in vanilla base form); a raw scalar means an un-sanitized write.
        local function _pac(v)
            if type(v) == "table" then return "table:normal=" .. tostring(v.normal) end
            return tostring(v)
        end
        local injected = gather_mutators()
        local cd = rawget(_G, "Managers") and Managers.state and Managers.state.conflict
        local cached = {
            delay_horde_threat_value = cd and cd.delay_horde_threat_value,
            delay_specials_threat_value = cd and cd.delay_specials_threat_value,
            delay_mini_patrol_threat_value = cd and cd.delay_mini_patrol_threat_value,
        }
        local verdict, evidence = Issue393.classify(injected, cis, cp, cached)
        if verdict == "not_injected" then return end
        local inj_str = (injected and #injected > 0) and table.concat(injected, ",") or "none"
        printf("[event-inject:393] settled verdict=%s evidence=%s | injected=[%s] max_intensity=%s decay_per_second=%s decay_delay=%s add_per_pct_dmg=%s delay_horde=%s delay_specials=%s delay_mini_patrol=%s cached_horde=%s cached_specials=%s cached_mini_patrol=%s",
            tostring(verdict), tostring(evidence),
            inj_str,
            tostring(cis and cis.max_intensity),
            tostring(cis and cis.decay_per_second),
            tostring(cis and cis.decay_delay),
            tostring(cis and cis.intensity_add_per_percent_dmg_taken),
            _pac(cp and cp.delay_horde_threat_value),
            _pac(cp and cp.delay_specials_threat_value),
            _pac(cp and cp.delay_mini_patrol_threat_value),
            tostring(cached.delay_horde_threat_value),
            tostring(cached.delay_specials_threat_value),
            tostring(cached.delay_mini_patrol_threat_value))
    end)
end)

ET.rt_register("issue393_high_intensity_settled_classifier", function()
    local injected = { "high_intensity" }
    local cis = {
        max_intensity = 200, decay_per_second = 10, decay_delay = 0.5,
        intensity_add_per_percent_dmg_taken = 0.1,
    }
    local cp = {
        delay_horde_threat_value = { normal = 200 },
        delay_specials_threat_value = { normal = 200 },
        delay_mini_patrol_threat_value = { normal = 200 },
    }
    local cached = {
        delay_horde_threat_value = 200,
        delay_specials_threat_value = 200,
        delay_mini_patrol_threat_value = 200,
    }
    local verdict = Issue393.classify(injected, cis, cp, cached)
    if verdict ~= "intact" then return "canonical mutator state did not classify intact" end
    cis.max_intensity = 100
    verdict = Issue393.classify(injected, cis, cp, cached)
    if verdict ~= "settings_stomp" then return "intensity overwrite was not detected" end
    cis.max_intensity = 200
    cached.delay_horde_threat_value = 75
    verdict = Issue393.classify(injected, cis, cp, cached)
    if verdict ~= "settings_stomp" then return "cached director overwrite was not detected" end
end)

-- ============================================================
-- Issue 1309: Tzeentch Twins co-op receipts (diagnostics-armed)
-- ============================================================
-- Nothing here changes behavior. It answers the one question #1309 cannot
-- answer from source: with the curse live in a co-op session, does the HOST
-- roll and enqueue splits at all, and does the CLIENT see the curse activate
-- and the split husks arrive? Everything is printf (user logs are OFF, and
-- mod:warning posts to chat) and every counter is capped by the probe module.
--
-- Where each receipt comes from:
--   * activation -- MutatorHandler._activate_mutator is the ONE code path both
--     peers run: the host reaches it from activate_mutators
--     (mutator_handler.lua:109) and the client from rpc_activate_mutator_client
--     (mutator_handler.lua:782). _evt_cursed_adventure.lua already wraps it, so
--     it calls into here rather than adding a second hook VMF would drop.
--   * per-kill -- MutatorHandler.ai_killed (mutator_handler.lua:254-271) runs on
--     BOTH peers for every AI death; only the `if is_server` branch inside it
--     reaches the curse's server_ai_killed_function. Reading data.seed and
--     #data.spawn_queue either side of the vanilla call is what turns "the
--     client sees nothing" into a located failure: no seed advance means the
--     roll never ran, an advance with a passing roll and zero enqueue means the
--     split path bailed (no lower-tier breed / no navmesh projection), and
--     enqueue with no client husk means the failure is in replication.
--   * client spawns -- UnitSpawner.spawn_unit_from_game_object
--     (unit_spawner.lua:470-490) is where a client materializes every
--     host-created network unit, so a split husk necessarily passes through it.
-- The two ai_killed / spawn hooks are wrapping (not hook_safe) because both need
-- state from around or out of the original call, and both exit on a single
-- boolean before touching anything when the curse is not live this mission.
--
-- Hook pre-flight (2026-08-16): event_tweaker had no hook on MutatorHandler
-- ai_killed or UnitSpawner spawn_unit_from_game_object before issue 1309.

local _tz = Issue1309.new_session()
local _tz_tier_map = nil

-- Materialize the base template's breed downgrade map so a CLIENT can name the
-- husk it should expect. server_start_function only writes into the data table
-- it is handed (mutator_splitting_enemies.lua:7-86), so calling it against a
-- scratch table is side-effect free; the client's own mutator_data never
-- receives it, because rpc_activate_mutator_client builds a fresh table with
-- nothing but the template (mutator_handler.lua:777-780).
local function _tier_map()
    if _tz_tier_map ~= nil then return _tz_tier_map ~= false and _tz_tier_map or nil end
    _tz_tier_map = false
    _tz.tier_map_state = "unavailable"
    local MT = rawget(_G, "MutatorTemplates")
    local template = MT and rawget(MT, Issue1309.CURSE)
    if type(template) ~= "table" then return nil end
    local starter = template.server_start_function
        or (type(template.server) == "table" and template.server.start_function)
    if type(starter) ~= "function" then return nil end
    local scratch = { template = template }
    local ok = pcall(starter, {}, scratch)
    if ok and type(scratch.breed_tier_list) == "table" then
        _tz_tier_map = scratch.breed_tier_list
        _tz.tier_map_state = "resolved"
        return _tz_tier_map
    end
    return nil
end

local function _breed_name(unit)
    local ok, breed = pcall(function() return Unit.get_data(unit, "breed") end)
    if ok and type(breed) == "table" and breed.name then return breed.name end
    local blackboards = rawget(_G, "BLACKBOARDS")
    local bb = type(blackboards) == "table" and blackboards[unit]
    local bb_breed = type(bb) == "table" and bb.breed
    if type(bb_breed) == "table" then return bb_breed.name end
end

local function _killer_peer(unit)
    local ok, peer = pcall(function()
        local player = Managers.player:owner(unit)
        return player and player.peer_id
    end)
    if ok and peer then return peer end
    return "ai"
end

local function _game_time()
    local ok, t = pcall(function() return Managers.time:time("game") end)
    if ok and type(t) == "number" then return t end
end

-- Called from _evt_cursed_adventure.lua's _activate_mutator wrapper, AFTER
-- vanilla has run: active_mutators[name] and the host's data.seed are both
-- populated by then (mutator_handler.lua:654,677-683).
function ET.issue1309_on_mutator_activated(name, is_server)
    if name ~= Issue1309.CURSE then return end
    pcall(function()
        local handler = Managers.state and Managers.state.game_mode
            and Managers.state.game_mode._mutator_handler
        local data = handler and handler._active_mutators and handler._active_mutators[name]
        local template_active = false
        if Managers.state and Managers.state.game_mode then
            local ok, active = pcall(
                Managers.state.game_mode.has_activated_mutator, Managers.state.game_mode, name)
            template_active = ok and active or false
        end
        local line = Issue1309.arm(
            _tz, Issue1309.role_name(is_server),
            type(data) == "table" and data.seed or nil, template_active)
        if line then pcall(printf, "%s", line) end
    end)
end

function ET.issue1309_flush_summary()
    local line = Issue1309.summary(_tz)
    if line then pcall(printf, "%s", line) end
    Issue1309.reset(_tz)
    _tz_tier_map = nil
end

mod:hook("MutatorHandler", "ai_killed", function(func, self, killed_unit, killer_unit, death_data, killing_blow)
    if not _tz.armed then
        return func(self, killed_unit, killer_unit, death_data, killing_blow)
    end

    local data = self._active_mutators and self._active_mutators[Issue1309.CURSE]
    if type(data) ~= "table" then
        return func(self, killed_unit, killer_unit, death_data, killing_blow)
    end

    if not self._is_server then
        pcall(function()
            local breed = _breed_name(killed_unit)
            local map = _tier_map()
            local expected = breed and map and map[breed]
            -- A tier entry may be a difficulty-indexed list
            -- (mutator_splitting_enemies.lua:44-50); the client cannot resolve
            -- which element the host picked, so it records no expectation.
            if type(expected) ~= "string" then expected = nil end
            local line = Issue1309.client_death(_tz, breed, expected, _game_time())
            if line then pcall(printf, "%s", line) end
        end)
        return func(self, killed_unit, killer_unit, death_data, killing_blow)
    end

    local seed_before, queued_before
    pcall(function()
        seed_before = data.seed
        queued_before = type(data.spawn_queue) == "table" and #data.spawn_queue or nil
    end)

    local a, b = func(self, killed_unit, killer_unit, death_data, killing_blow)

    pcall(function()
        local seed_after = data.seed
        local queued_after = type(data.spawn_queue) == "table" and #data.spawn_queue or nil
        local enqueued
        if queued_before and queued_after then enqueued = queued_after - queued_before end
        -- Math.next_random is a pure seeded step, so replaying seed_before
        -- reproduces the exact value the template compared without disturbing
        -- the live stream (mutator_curse_change_of_tzeentch.lua:21).
        local roll
        if seed_before ~= nil then
            local ok, _, value = pcall(Math.next_random, seed_before)
            if ok then roll = value end
        end
        local line = Issue1309.host_kill(
            _tz, _killer_peer(killer_unit), _breed_name(killed_unit),
            roll, enqueued, seed_before, seed_after)
        if line then pcall(printf, "%s", line) end
    end)

    return a, b
end)

mod:hook("UnitSpawner", "spawn_unit_from_game_object", function(func, self, ...)
    local unit = func(self, ...)
    if _tz.armed and _tz.role == "client" then
        pcall(function()
            local breed = _breed_name(unit)
            if breed then Issue1309.observe_spawn(_tz, breed, _game_time()) end
        end)
    end
    return unit
end)

ET.rt_register("issue1309_tzeentch_diag_armed", function()
    if Issue1309.PREFIX ~= "[et:1149t]" then
        return "receipt prefix drifted from the one #1309 names"
    end
    if Issue1309.CURSE ~= "curse_change_of_tzeentch" then
        return "diagnostic is pointed at the wrong curse"
    end
    if type(ET.issue1309_on_mutator_activated) ~= "function"
            or type(ET.issue1309_flush_summary) ~= "function" then
        return "the curse-adapter entry points are not exported"
    end

    -- The receipt budget must be hard-capped and the summary must fire once.
    local probe = Issue1309.new_session()
    if Issue1309.summary(probe) ~= nil then return "an unarmed session emitted a summary" end
    if Issue1309.arm(probe, "host", 4321, true) == nil then return "activation receipt was withheld" end
    if Issue1309.arm(probe, "host", 4321, true) ~= nil then return "activation receipt repeated" end
    local emitted = 0
    for i = 1, Issue1309.RECEIPT_CAP + 5 do
        if Issue1309.host_kill(probe, "peer", "skaven_clan_rat", 0.1, 2, i, i + 1) then
            emitted = emitted + 1
        end
    end
    if emitted ~= Issue1309.RECEIPT_CAP then
        return "per-kill receipts were not capped at " .. Issue1309.RECEIPT_CAP
    end
    if probe.kills_rolled ~= Issue1309.RECEIPT_CAP + 5 then
        return "capping the receipts also stopped counting kills"
    end
    if Issue1309.summary(probe) == nil then return "end-of-mission summary was withheld" end
    if Issue1309.summary(probe) ~= nil then return "end-of-mission summary repeated" end

    -- The curse must still be the clone whose roll the receipts reproduce.
    local MT = rawget(_G, "MutatorTemplates")
    local template = MT and rawget(MT, Issue1309.CURSE)
    if type(template) == "table" then
        local starter = template.server_start_function
            or (type(template.server) == "table" and template.server.start_function)
        if type(starter) ~= "function" then
            return "curse template lost its server start function"
        end
        local killed = template.server_ai_killed_function
            or (type(template.server) == "table" and template.server.ai_killed_function)
        if type(killed) ~= "function" then
            return "curse template lost its server ai-killed function"
        end
    end
end)
