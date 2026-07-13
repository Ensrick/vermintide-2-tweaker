local mod = get_mod("enemy_tweaker")

-- _et_pacing.lua — spawn pacing (v0.7.0-dev SpawnTweaks parity) + #213 freeze guard
--
-- Five engine knobs that control spawn FREQUENCY and CONCURRENT CAPS, as
-- opposed to per-spawn enemy counts (the four 0-15x sliders). SpawnTweaks's
-- "save vanilla value -> apply override -> call vanilla -> restore" pattern
-- is what we mimic: the engine globals are read by many systems, so our
-- override only takes effect during the specific vanilla function that
-- consumes them. Outside those windows the engine sees vanilla values.
--
-- ISSUE 479 (v0.7.31-dev): the ConflictDirector.update wrap is the mod's one
-- TICK-LEVEL hook and is NOT re-runnable — vanilla's spawn-queue bookkeeping
-- runs AFTER _spawn_unit (ConflictDirector.update_spawn_queue,
-- conflict_director.lua:1835-1891), so a throwing spawn stays queued and a
-- vanilla re-run re-pops it, re-throws, and doubles partial state (the #470
-- crash session evidence, i470.log 158014-158017). It therefore uses
-- _hook_wrap_tick (skip the tick on inner error, NEVER re-run vanilla) and
-- _call_with_override (the max_grunts override is restored on BOTH the
-- success and the error path — pre-479 the restore was skipped on throw,
-- leaking the override for the session). Both helpers live in
-- _et_protect.lua. Also home of the #213 BreedFreezer double-freeze guard,
-- whose per-frame suppression counter is reset at the top of the CD tick.
--
-- Owned by: enemy_tweaker.lua entry point. No mod._et exports (the #479
-- helpers are exposed by _et_protect.lua as mod._et479_*).

local ET = mod._et
local rt_register    = ET.rt_register
local _dbg           = ET.dbg
local _dbg_alert     = ET.dbg_alert
local _et_probe      = ET.et_probe
local _hook_wrap     = ET.hook_wrap
local _hook_wrap_tick = ET.hook_wrap_tick
local _call_with_override = mod._et479_call_with_override

-- Helpers — read settings with a non-numeric guard so a typo'd value can't
-- override the cap to nil and crash the engine.
local function _read_num_setting(setting_id, default_val)
    local raw = mod:get(setting_id)
    if type(raw) == "number" then return raw end
    if raw == nil then return default_val end
    local n = tonumber(raw)
    if n == nil then
        _dbg_alert("setting %s has non-numeric value %s — using default %s",
            tostring(setting_id), tostring(raw), tostring(default_val))
        return default_val
    end
    return n
end

-- #479 recurrence (2026-07-13): TerrorEventMixer.start_event can append a
-- malformed one-element event and then throw at terror_event_mixer.lua:1800
-- after post_process_terror_event cleared elements[1]. EnemyRecycler advances
-- its main-path index only AFTER start_event returns, so the same event retries
-- every frame forever. For that exact source error only, reproduce the vanilla
-- post-return bookkeeping, remove the partial active event, and quarantine ET's
-- pacing overrides for the rest of the session. Unknown errors fail closed:
-- tick skipped, no guessed state mutation.
local function _quarantine_failed_main_path_event(conflict_director, err, mixer)
    err = tostring(err)
    if not err:find("terror_event_mixer.lua:1800", 1, true) then return false end
    mod._et_pacing_quarantined = true

    local recycler = conflict_director and conflict_director.enemy_recycler
    local id = recycler and recycler.current_main_path_event_id
    local events = recycler and recycler.main_path_events
    local event = events and id and events[id]
    local event_name = event and event[3] -- EnemyRecycler MP_TERROR_EVENT_NAME
    if type(event_name) ~= "string" then return false end

    mixer = mixer or rawget(_G, "TerrorEventMixer")
    local active = mixer and mixer.active_events
    if type(active) == "table" then
        for i = #active, 1, -1 do
            local candidate = active[i]
            if candidate and candidate.name == event_name and
                    (type(candidate.elements) ~= "table" or candidate.elements[1] == nil) then
                table.remove(active, i)
            end
        end
    end

    local next_id = id + 1
    local next_event = events[next_id]
    if next_event then
        recycler.current_main_path_event_id = next_id
        recycler.current_main_path_event_activation_dist = next_event[1] -- MP_TRAVEL_DIST
    else
        recycler.current_main_path_event_id = nil
    end
    pcall(printf, "[et:479] quarantined malformed main-path event=%s id=%d; pacing overrides disabled for session",
        event_name, id)
    return true, event_name
end
mod._et479_quarantine_main_path_event = _quarantine_failed_main_path_event

-- ConflictDirector.update — wraps the master tick that runs horde pacing,
-- mini-patrol, specials. We mutate RecycleSettings.max_grunts (the concurrent
-- alive trash cap) here so the engine reads our override during pacing
-- decisions, then restore on the way out. #479: registered via
-- _hook_wrap_tick, and vanilla runs under _call_with_override so the
-- override is restored even when vanilla throws mid-tick; the tick is then
-- SKIPPED (one [et:479] printf), never re-run.
if rawget(_G, "ConflictDirector") then
    _hook_wrap_tick("ConflictDirector", "update", "spawn_pacing.update",
            function(func, self, ...)
        -- #213: reset the per-frame double-freeze suppression counter at the top
        -- of the CD tick. deactivate_area -> destroy_unit -> try_mark_unit_for_freeze
        -- (the BreedFreezer guard below) all run inside this vanilla update, so a
        -- reset here brackets one frame's worth of suppressions for the probe.
        mod._et_freeze_suppress_this_frame = 0
        local RS = rawget(_G, "RecycleSettings")
        local override
        if RS and not mod._et_pacing_quarantined then
            local v = _read_num_setting("max_grunts_override", 90)
            if v ~= 90 then
                override = v
            end
        end
        local ok, r1, r2, r3, r4 = _call_with_override(RS, "max_grunts", override, func, self, ...)
        if not ok then
            _quarantine_failed_main_path_event(self, r1)
            -- Rethrow AFTER the override was restored: the tick guard logs the
            -- [et:479] line and skips the tick (no vanilla re-run).
            error(r1, 0)
        end
        return r1, r2, r3, r4
    end)

    -- ConflictDirector.update_horde_pacing — runs the paced-horde frequency
    -- decision. We override push_horde_if_num_alive_grunts_above and the
    -- horde_frequency tuple around this call.
    _hook_wrap("ConflictDirector", "update_horde_pacing", "spawn_pacing.update_horde_pacing",
            function(func, self, ...)
        if mod._et_pacing_quarantined then return func(self, ...) end
        local RS = rawget(_G, "RecycleSettings")
        local CP = rawget(_G, "CurrentPacing")
        local original_push, original_freq
        if RS then
            local push = _read_num_setting("horde_grunt_push_threshold", 60)
            if push ~= 60 then
                original_push = RS.push_horde_if_num_alive_grunts_above
                RS.push_horde_if_num_alive_grunts_above = push
            end
        end
        if CP then
            local fmin = _read_num_setting("horde_frequency_min", 50)
            local fmax = _read_num_setting("horde_frequency_max", 100)
            if fmin ~= 50 or fmax ~= 100 then
                if fmax < fmin then fmax = fmin end
                original_freq = CP.horde_frequency  -- shallow ref is fine; vanilla writes new tables
                CP.horde_frequency = { fmin, fmax }
            end
        end
        local r1, r2, r3, r4 = func(self, ...)
        if original_freq ~= nil then CP.horde_frequency = original_freq end
        if original_push ~= nil then RS.push_horde_if_num_alive_grunts_above = original_push end
        return r1, r2, r3, r4
    end)

    -- ConflictDirector.horde_killed — vanilla recomputes the next horde
    -- schedule here too; needs the same horde_frequency override or the
    -- frequency slider has no effect after the first horde dies.
    _hook_wrap("ConflictDirector", "horde_killed", "spawn_pacing.horde_killed",
            function(func, self, ...)
        if mod._et_pacing_quarantined then return func(self, ...) end
        local CP = rawget(_G, "CurrentPacing")
        local original_freq
        if CP then
            local fmin = _read_num_setting("horde_frequency_min", 50)
            local fmax = _read_num_setting("horde_frequency_max", 100)
            if fmin ~= 50 or fmax ~= 100 then
                if fmax < fmin then fmax = fmin end
                original_freq = CP.horde_frequency
                CP.horde_frequency = { fmin, fmax }
            end
        end
        local r1, r2, r3, r4 = func(self, ...)
        if original_freq ~= nil then CP.horde_frequency = original_freq end
        return r1, r2, r3, r4
    end)

    -- ConflictDirector.update_mini_patrol — ambient mini-patrol spawn pass.
    -- When ambients_ignore_threat is ON, raise the intensity gate to infinity
    -- and the grunt cap to infinity for the duration of vanilla, then restore.
    -- Both have to move together or the engine still bails on the cap check
    -- inside the function body.
    _hook_wrap("ConflictDirector", "update_mini_patrol", "spawn_pacing.update_mini_patrol",
            function(func, self, ...)
        if mod._et_pacing_quarantined or not mod:get("ambients_ignore_threat") then
            return func(self, ...)
        end
        local CP = rawget(_G, "CurrentPacing")
        local RS = rawget(_G, "RecycleSettings")
        local original_mp_threshold, original_max_grunts
        if CP and CP.mini_patrol then
            original_mp_threshold = CP.mini_patrol.only_spawn_below_intensity
            CP.mini_patrol.only_spawn_below_intensity = math.huge
        end
        if RS then
            original_max_grunts = RS.max_grunts
            RS.max_grunts = math.huge
        end
        local r1, r2, r3, r4 = func(self, ...)
        if original_max_grunts ~= nil then RS.max_grunts = original_max_grunts end
        if original_mp_threshold ~= nil then
            CP.mini_patrol.only_spawn_below_intensity = original_mp_threshold
        end
        return r1, r2, r3, r4
    end)

    -- ConflictDirector.calculate_threat_value (hook_safe — vanilla writes
    -- self.threat_value, we multiply afterward). spawn_pace_multiplier > 1
    -- means "MORE spawns" — we multiply threat by `mult` so the delay_*
    -- thresholds (delay_horde_threat_value < threat_value) trip sooner.
    -- mult < 1 reduces spawn pressure. SpawnTweaks's inverted semantics are
    -- normalized here (their lower = harder; ours higher = harder).
    mod:hook_safe(ConflictDirector, "calculate_threat_value", function(self)
        if mod._et_pacing_quarantined then return end
        local mult = _read_num_setting("spawn_pace_multiplier", 1)
        if mult == 1 then return end
        if type(self.threat_value) ~= "number" then return end
        self.threat_value = self.threat_value * mult
        local threat_value = self.threat_value
        -- Recompute delay flags with the new threat_value (vanilla already
        -- did this with the un-scaled value; we redo against the scaled one).
        if type(self.delay_horde_threat_value) == "number" then
            self.delay_horde = self.delay_horde_threat_value < threat_value
        end
        if type(self.delay_mini_patrol_threat_value) == "number" then
            self.delay_mini_patrol = self.delay_mini_patrol_threat_value < threat_value
        end
        if type(self.delay_specials_threat_value) == "number" then
            self.delay_specials = self.delay_specials_threat_value < threat_value
        end
    end)

    -- ConflictDirector.handle_alone_player -- the rush intervention (issue 449).
    -- VANILLA BUG: hordes (conflict_director.lua:893) and the speed-running
    -- intervention (:1103, early return inside handle_speed_runners) both stand
    -- down while pacing:get_state() == "pacing_frozen", but the rush
    -- intervention has NO freeze gate anywhere in its body (:1250-1330): with
    -- pacing frozen by a boss event it can still request a rushing-intervention
    -- special AND an ambush horde -- enemies attacking during The Enchanter's
    -- Lair cutscene. Stand it down while frozen, exactly like its two vanilla
    -- siblings. UNCONDITIONAL (vanilla-bug class, host-side spawn decision,
    -- same doctrine as ct's issue-470 rank-8 backfill); the caller retries
    -- every 1s (conflict_director.lua:1506-1510) so the [et:449] line logs once
    -- per freeze episode, not per retry. Sole et hook on this method.
    local _449_frozen_logged = false
    _hook_wrap("ConflictDirector", "handle_alone_player", "rush_intervention.freeze_gate",
            function(func, self, t, enemy_side)
        local pacing = self.pacing
        if pacing and pacing.get_state and pacing:get_state() == "pacing_frozen" then
            local data = self.rushing_intervention_data
            if data then
                -- Same debug-reason surface every vanilla early return writes.
                data.disabled = "No rush intervention, pacing is frozen (et issue 449 gate)"
            end
            if not _449_frozen_logged then
                _449_frozen_logged = true
                pcall(printf, "[et:449] rush intervention stood down: pacing_frozen (vanilla freeze-gates hordes and speed-run specials but not this path)")
            end
            return
        end
        if _449_frozen_logged then
            _449_frozen_logged = false
            pcall(printf, "[et:449] pacing unfrozen: rush intervention re-armed")
        end
        return func(self, t, enemy_side)
    end)

    rt_register("rush_intervention_freeze_gate", function()
        -- issue 449: drive the WRAPPED handle_alone_player with a frozen-pacing
        -- stub. The gate must return before vanilla touches the stub's missing
        -- fields (main_path_info is nil -> a dead gate makes vanilla throw, a
        -- live gate returns cleanly with the disabled reason written).
        local CD = rawget(_G, "ConflictDirector")
        if type(CD) ~= "table" or type(CD.handle_alone_player) ~= "function" then
            return "ConflictDirector.handle_alone_player missing (engine changed? issue 449 gate dead)"
        end
        local stub = {
            pacing = { get_state = function() return "pacing_frozen" end },
            rushing_intervention_data = {},
        }
        local fake_side = { ENEMY_PLAYER_AND_BOT_UNITS = {} }
        local ok, err = pcall(CD.handle_alone_player, stub, 0, fake_side)
        if not ok then
            return "frozen-pacing call reached the vanilla body (gate missing/reordered): " .. tostring(err)
        end
        local reason = stub.rushing_intervention_data.disabled
        if type(reason) ~= "string" or not reason:find("449", 1, true) then
            return "gate ran but did not write the issue-449 disabled reason (got: " .. tostring(reason) .. ")"
        end
    end)
end

-- Pacing.update (hook_safe) — Pacing maintains per-player intensity that
-- feeds into spawn-rate decisions. Multiply intensity by spawn_pace_multiplier
-- AFTER vanilla writes it so spawn-rate decisions see the scaled value on the
-- next pacing tick.
if rawget(_G, "Pacing") then
    mod:hook_safe(Pacing, "update", function(self, t, dt, alive_player_units) -- luacheck: ignore t dt
        if mod._et_pacing_quarantined then return end
        local mult = _read_num_setting("spawn_pace_multiplier", 1)
        if mult == 1 then return end
        if type(alive_player_units) ~= "table" then return end
        local n = #alive_player_units
        if n == 0 then return end
        if type(self.player_intensity) == "table" then
            for k = 1, n do
                if type(self.player_intensity[k]) == "number" then
                    self.player_intensity[k] = self.player_intensity[k] * mult
                end
            end
        end
        if type(self.total_intensity) == "number" then
            self.total_intensity = self.total_intensity * mult
        end
    end)
end

-- ============================================================
-- #213 double-freeze guard (BreedFreezer.try_mark_unit_for_freeze)
-- ============================================================
-- Symptom (Issue #213): engine "ERROR: Tried to freeze unit twice in the same
-- frame." from vanilla scripts/managers/conflict_director/breed_freezer.lua:253,
-- HOST-only, under EnemyRecycler.deactivate_area with our raised
-- RecycleSettings.max_grunts override (see the ConflictDirector.update hook).
-- Non-fatal but noisy, and it leaves the unit in a conflicting state.
--
-- Chain: EnemyRecycler.deactivate_area -> ConflictDirector.destroy_unit
-- (conflict_director.lua:2403) -> register_unit_destroyed (conflict_director.lua:2371)
-- -> BreedFreezer:try_mark_unit_for_freeze (called at conflict_director.lua:2386).
-- The actual freeze is DEFERRED to BreedFreezer.commit_freezes, so ALIVE[unit]
-- stays true between two same-frame destroy_unit calls on one unit; the second
-- call re-marks the same unit, vanilla finds it already in units_to_freeze and
-- prints the ERROR (line 253) AND -- because try_mark then returns false -- the
-- caller falls through to mark_for_deletion(unit) (conflict_director.lua:2387),
-- conflicting with the freeze already queued on the first call. Raising the grunt
-- cap packs more roaming trash into recycler areas, so the window opens far more
-- often than in vanilla.
--
-- Guard: replicate vanilla's OWN duplicate check (breed_freezer.lua:247-257)
-- BEFORE calling vanilla, reading vanilla's own self.units_to_freeze[breed] list.
-- That is the exact state vanilla checks, cleared on the exact same lifecycle
-- (commit_freezes), so there is no frame-boundary or unit-pooling guesswork. If
-- the unit is already queued this batch, return TRUE ("already marked / handled")
-- so register_unit_destroyed does NOT also mark_for_deletion it -- the unit stays
-- frozen exactly once and the double-freeze ERROR is suppressed. Fail-open: any
-- missing state (settings / breed / list not resolvable) falls through to vanilla,
-- so behavior is unchanged beyond suppressing the redundant second mark. No prior
-- et hook exists on BreedFreezer (grep-verified) -- new (Class, method) pair.
if rawget(_G, "BreedFreezer") then
    _hook_wrap("BreedFreezer", "try_mark_unit_for_freeze", "double_freeze_guard",
            function(func, self, breed, unit)
        local settings = self._breed_freezer_settings
        local breed_name = breed and breed.name
        if settings and breed_name and settings.breeds and settings.breeds[breed_name] ~= nil then
            local units_to_freeze = self.units_to_freeze and self.units_to_freeze[breed_name]
            if units_to_freeze then
                for i = 1, #units_to_freeze do
                    if units_to_freeze[i] == unit then
                        -- Already queued for freeze this batch: suppress the
                        -- double-mark. Return true so the caller skips
                        -- mark_for_deletion (conflict_director.lua:2386-2387).
                        local n = (mod._et_freeze_suppress_this_frame or 0) + 1
                        mod._et_freeze_suppress_this_frame = n
                        -- printf probe (visible with mod logging off). `queued` =
                        -- current freeze-batch depth for this breed (the meaningful
                        -- load signal at the freeze chokepoint; the recycler area
                        -- index is an unstable loop-local in _update_roaming_spawning,
                        -- reshuffled by fast_array_remove, so it is not reported).
                        _et_probe("213:freeze",
                            "[213:freeze] suppressed unit=%s queued=%d count_this_frame=%d",
                            tostring(breed_name), #units_to_freeze, n)
                        return true
                    end
                end
            end
        end
        return func(self, breed, unit)
    end)
end

rt_register("spawn_pacing_hook_targets_present", function()
    -- v0.7.0-dev SpawnTweaks parity pass — verifies every engine surface we
    -- mutate is hookable (catches engine API rename / removal at install
    -- time so spawn-pacing sliders never silently no-op).
    local missing = {}
    local CD = rawget(_G, "ConflictDirector")
    if not CD then return "ConflictDirector boot global missing (engine changed)" end
    if type(CD.update) ~= "function" then missing[#missing+1] = "ConflictDirector.update" end
    if type(CD.update_horde_pacing) ~= "function" then missing[#missing+1] = "ConflictDirector.update_horde_pacing" end
    if type(CD.horde_killed) ~= "function" then missing[#missing+1] = "ConflictDirector.horde_killed" end
    if type(CD.update_mini_patrol) ~= "function" then missing[#missing+1] = "ConflictDirector.update_mini_patrol" end
    if type(CD.calculate_threat_value) ~= "function" then missing[#missing+1] = "ConflictDirector.calculate_threat_value" end
    local P = rawget(_G, "Pacing")
    if not P or type(P.update) ~= "function" then missing[#missing+1] = "Pacing.update" end
    local RS = rawget(_G, "RecycleSettings")
    if type(RS) ~= "table" then missing[#missing+1] = "RecycleSettings table" end
    -- These two field names are what max_grunts_override and horde_grunt_push_threshold mutate.
    if RS and type(RS.max_grunts) ~= "number" then missing[#missing+1] = "RecycleSettings.max_grunts (field type changed)" end
    if RS and type(RS.push_horde_if_num_alive_grunts_above) ~= "number" then missing[#missing+1] = "RecycleSettings.push_horde_if_num_alive_grunts_above (field type changed)" end
    -- #512: the pacing FIELD paths are asserted against the STATIC
    -- PacingSettings.default table (boot global, conflict_settings.lua:2955),
    -- context-free and identical in keep and mission. The runtime CurrentPacing
    -- is re-cloned from the CURRENT director's pacing on every level
    -- (conflict_director.lua:878); at the keep that director's pacing is
    -- PacingSettings.disabled (conflict_settings.lua:3603-3628), which
    -- legitimately has NO mini_patrol block, so the pre-0.7.36 assert on
    -- CurrentPacing.mini_patrol false-FAILed every keep run. Every mission
    -- clone is table.clone'd FROM a static PacingSettings entry, so a rename /
    -- removal of the path (the regression this check locks - our
    -- update_mini_patrol hook mutates mini_patrol.only_spawn_below_intensity,
    -- conflict_settings.lua:3028) still trips the static assert everywhere.
    local PS = rawget(_G, "PacingSettings")
    if type(PS) ~= "table" or type(PS.default) ~= "table" then
        missing[#missing+1] = "PacingSettings.default table (renamed/removed)"
    else
        if type(PS.default.horde_frequency) ~= "table" then
            missing[#missing+1] = "PacingSettings.default.horde_frequency (field type changed)"
        end
        if type(PS.default.mini_patrol) ~= "table" or type(PS.default.mini_patrol.only_spawn_below_intensity) ~= "number" then
            missing[#missing+1] = "PacingSettings.default.mini_patrol.only_spawn_below_intensity (path changed)"
        end
    end
    -- Runtime clone, asserted only where the CURRENT context guarantees it.
    -- CurrentPacing always EXISTS: false at boot (conflict_settings.lua:5539),
    -- a table after any director refresh (keep included) - rawget nil means
    -- the global itself was renamed. horde_frequency is present in every
    -- PacingSettings entry INCLUDING disabled (conflict_settings.lua:3615);
    -- mini_patrol only exists when pacing is enabled, so that assert is gated
    -- on CP.disabled being falsy (mission director) - vanilla itself couples
    -- enabled pacing to mini_patrol via the unguarded read at
    -- conflict_director.lua:1379, so a FAIL inside that gate is a true positive.
    local CP = rawget(_G, "CurrentPacing")
    if CP == nil then
        missing[#missing+1] = "CurrentPacing global (renamed/removed)"
    elseif type(CP) == "table" then
        if type(CP.horde_frequency) ~= "table" then missing[#missing+1] = "CurrentPacing.horde_frequency (field type changed)" end
        if not CP.disabled and (type(CP.mini_patrol) ~= "table" or type(CP.mini_patrol.only_spawn_below_intensity) ~= "number") then
            missing[#missing+1] = "CurrentPacing.mini_patrol.only_spawn_below_intensity (path changed)"
        end
    end
    if #missing > 0 then return "spawn-pacing surface missing: " .. table.concat(missing, ", ") end
end)

rt_register("double_freeze_guard_wired", function()
    -- (#213) The engine "Tried to freeze unit twice in the same frame" ERROR under raised
    -- grunt caps is suppressed by a guard hook on BreedFreezer.try_mark_unit_for_freeze that
    -- replicates vanilla's own duplicate check and returns true when the unit is already
    -- queued this batch (so the caller skips the redundant mark_for_deletion). Verify via
    -- _et_protect's runtime wrap_registry: BreedFreezer is a BOOT global
    -- (breed_freezer.lua:77, `class(BreedFreezer)` at file scope -- confirmed by the boot
    -- "Hooking 'try_mark_unit_for_freeze' from [BreedFreezer]" log line), so the hook
    -- installs at mod load and the marker is set regardless of mission state. Sandbox-safe:
    -- REPLACES the pre-0.7.33 io.open source self-grep, which threw "attempt to index global
    -- 'io'" in the VMF sandbox and failed this check in-game (issue 479 log).
    local reg = ET.wrap_registry
    if type(reg) ~= "table" or type(reg.plain) ~= "table" then
        return "wrap_registry missing (#213 provenance tracking gone)"
    end
    if rawget(_G, "BreedFreezer") and not reg.plain["BreedFreezer.try_mark_unit_for_freeze"] then
        return "#213 REGRESSION: the double_freeze_guard hook on BreedFreezer.try_mark_unit_for_freeze is gone (the 'freeze unit twice' engine error returns under raised grunt caps)"
    end
end)

rt_register("issue479_cd_tick_no_rerun_and_restore", function()
    -- #479: (a) the tick guard must NEVER re-run vanilla after an inner error
    -- (the pre-479 _hook_wrap fallback re-ran ConflictDirector.update for the
    -- same tick, re-popping a throwing spawn off the still-unbooked queue);
    -- (b) the max_grunts override must be restored on BOTH the success and
    -- the error path (pre-479 the restore was skipped on throw).
    local make_guard = mod._et479_make_tick_guard
    local call_with_override = mod._et479_call_with_override
    if type(make_guard) ~= "function" then return "mod._et479_make_tick_guard missing" end
    if type(call_with_override) ~= "function" then return "mod._et479_call_with_override missing" end
    -- (a) no vanilla re-run: body calls func once, then errors.
    local calls = 0
    local guard = make_guard("C", "m", "rt479", function(func, self)
        func(self)
        error("rt479-inner")
    end)
    local stub = function() calls = calls + 1 end
    local r = guard(stub, nil)
    if calls ~= 1 then
        return string.format("vanilla ran %d time(s) on inner error — must be exactly 1 (no re-run)", calls)
    end
    if r ~= nil then return "tick guard must return nil when skipping the tick" end
    -- (b) restore on the ERROR path.
    local rs = { max_grunts = 90 }
    local ok2 = call_with_override(rs, "max_grunts", 200, function()
        if rs.max_grunts ~= 200 then error("override not applied during the call") end
        error("boom")
    end)
    if ok2 then return "override-call must report the inner error" end
    if rs.max_grunts ~= 90 then return "max_grunts NOT restored on the error path" end
    -- (b) restore + visibility on the SUCCESS path.
    local ok3, seen = call_with_override(rs, "max_grunts", 200, function() return rs.max_grunts end)
    if not ok3 or seen ~= 200 then return "override not visible to vanilla during the call" end
    if rs.max_grunts ~= 90 then return "max_grunts NOT restored on the success path" end
    -- (c) Wiring: the production CD.update hook must be registered through the
    -- NO-RE-RUN tick guard, and NOT through the re-running _hook_wrap. Runtime
    -- provenance from _et_protect's wrap_registry -- ConflictDirector is a boot
    -- global (conflict_director.lua:70), so the marker is set at mod load and is
    -- readable at the keep. REPLACES the pre-0.7.33 io.open source self-grep,
    -- which threw "attempt to index global 'io'" in the VMF sandbox and failed
    -- this check in-game (the "Failed." report on issue 479).
    local reg = ET.wrap_registry
    if type(reg) ~= "table" or type(reg.tick) ~= "table" or type(reg.plain) ~= "table" then
        return "wrap_registry missing (issue 479 provenance tracking gone)"
    end
    if rawget(_G, "ConflictDirector") then
        if not reg.tick["ConflictDirector.update"] then
            return "#479 REGRESSION: ConflictDirector.update is not registered via the no-re-run tick guard (_hook_wrap_tick)"
        end
        if reg.plain["ConflictDirector.update"] then
            return "#479 REGRESSION: ConflictDirector.update is also registered via _hook_wrap, which re-runs vanilla on inner error"
        end
    end
end)

rt_register("issue479_tick_fault_logging_bounded", function()
    local transition = mod._et479_tick_fault_transition
    if type(transition) ~= "function" then return "tick fault transition helper missing" end
    local state = { active = false, count = 0 }
    local first = transition(state, false, "boom")
    if first ~= "first" then return "first failure did not open one fault episode" end
    for _ = 1, 1172 do
        if transition(state, false, "boom") ~= "repeat" then
            return "repeat failure reopened/logged a new episode"
        end
    end
    local recovered, suppressed = transition(state, true)
    if recovered ~= "recovered" or suppressed ~= 1172 then
        return string.format("recovery summary mismatch: transition=%s suppressed=%s",
            tostring(recovered), tostring(suppressed))
    end
end)

rt_register("issue479_malformed_main_path_event_quarantined", function()
    local quarantine = mod._et479_quarantine_main_path_event
    if type(quarantine) ~= "function" then return "main-path quarantine helper missing" end
    local old_quarantined = mod._et_pacing_quarantined
    local recycler = {
        current_main_path_event_id = 1,
        current_main_path_event_activation_dist = 10,
        main_path_events = {
            { 10, false, "boss_event_chaos_spline_patrol" },
            { 20, false, "next_event" },
        },
    }
    local mixer = { active_events = {{
        name = "boss_event_chaos_spline_patrol",
        elements = {},
    }} }
    local ok, name = quarantine({ enemy_recycler = recycler },
        "scripts/managers/conflict_director/terror_event_mixer.lua:1800: attempt to index a nil value",
        mixer)
    local result
    if not ok or name ~= "boss_event_chaos_spline_patrol" then
        result = "known malformed event was not recognized"
    elseif #mixer.active_events ~= 0 then
        result = "partial TerrorEventMixer active event was not removed"
    elseif recycler.current_main_path_event_id ~= 2 or recycler.current_main_path_event_activation_dist ~= 20 then
        result = "EnemyRecycler did not receive vanilla post-return index bookkeeping"
    elseif not mod._et_pacing_quarantined then
        result = "ET pacing overrides were not quarantined"
    end
    mod._et_pacing_quarantined = old_quarantined
    return result
end)
