local mod = get_mod("enemy_tweaker")

-- _et_event_size.lua — terror-event horde size (v0.6.0-dev)
--
-- SpawnerSystem.spawn_horde_from_terror_event_ids resolves HordeCompositions
-- entries into per-breed amounts at runtime, then asks HordeSpawner to spawn
-- each. We hook the function and stash the per-call scale on
-- mod._et_event_breed_scale; the ACTUAL scaling happens inside
-- _et_swaps.lua's compose_blob_horde_spawn_list hook, gated on that flag.
-- Single point — respects per-breed max_active_enemies engine caps
-- automatically. HordeSpawner.spawn_horde is also instrumented (debug-only)
-- so we have a log breadcrumb for every event-triggered horde call.
--
-- Owned by: enemy_tweaker.lua entry point (dofile'd after _et_swaps, whose
-- compose hook consumes the flag). No mod._et exports.

local ET = mod._et
local _dbg_alert       = ET.dbg_alert
local _spawn_dbg       = ET.spawn_dbg
local _spawn_dbg_alert = ET.spawn_dbg_alert
local _hook_wrap       = ET.hook_wrap
local _mult            = ET.mult
local rt_register      = ET.rt_register

-- The signature/internals can vary across game versions, so we accept any
-- second-arg shape (a table of resolved per-breed amounts) and only mutate
-- entries whose values are numbers. If the function returns a count or a
-- list shape we don't recognize, we _dbg_alert and pass through unchanged.
if rawget(_G, "SpawnerSystem") then
    _hook_wrap("SpawnerSystem", "spawn_horde_from_terror_event_ids",
            "spawn_horde_from_terror_event_ids", function(func, self, ...)
        local mult, is_zero = _mult("event_size_multiplier")
        if mult and mult > 5 then mult = 5 end   -- v0.7.11-dev: cap event hordes at 5x (clamps a stale saved >5)
        if mult == 1 then
            _spawn_dbg("event", "spawn_horde_from_terror_event_ids passthrough mult=1.0")
            return func(self, ...)
        end
        if is_zero then
            -- Suppress entirely — early-return without invoking vanilla.
            -- Caveat (PROJECT_STANDARDS § 4.2 "guard ≠ bail"): vanilla's
            -- side effect here is "spawn the horde". Skipping spawn IS the
            -- intended behavior at multiplier=0; user explicitly asked for
            -- zero. Logged loudly so it's visible.
            _spawn_dbg_alert("event", "multiplier=0 — suppressing terror-event horde spawn entirely")
            return
        end
        -- Multiplier in (0, 1) U (1, 15]: stash the per-call scale on the
        -- mod table so the inner compose_blob_horde_spawn_list hook can
        -- read it and scale the spawn list. Wrapped in pcall + finally so
        -- a crash inside vanilla can't leak the flag into the next
        -- (potentially paced, not event) compose call.
        mod._et_event_breed_scale = mult
        local ok, r1, r2, r3, r4 = pcall(func, self, ...)
        mod._et_event_breed_scale = nil
        if not ok then
            mod:warning("[et:event] spawn_horde_from_terror_event_ids vanilla errored: %s — flag cleared, bailing",
                tostring(r1))
            _dbg_alert("event spawn vanilla errored: %s", tostring(r1))
            return nil
        end
        _spawn_dbg("event", "spawn_horde_from_terror_event_ids returned (mult=%.1f)", mult)
        return r1, r2, r3, r4
    end)
end

-- The actual event-size scaling happens inside compose_blob_horde_spawn_list
-- (_et_swaps.lua), gated on mod._et_event_breed_scale set by the SpawnerSystem
-- hook. HordeSpawner.spawn_horde is also instrumented (debug-only) so we have
-- a log breadcrumb for every event-triggered horde call, with composition
-- type and horde type visible.
if rawget(_G, "HordeSpawner") and type(rawget(_G, "HordeSpawner").spawn_horde) == "function" then
    _hook_wrap("HordeSpawner", "spawn_horde", "spawn_horde",
            function(func, self, side_id, composition_type, strictness, fill_type,
                     spread, horde_type, optional_data, ...)
        _spawn_dbg("event", "spawn_horde side=%s comp_type=%s horde_type=%s active_event_scale=%s",
            tostring(side_id), tostring(composition_type), tostring(horde_type),
            tostring(mod._et_event_breed_scale))
        return func(self, side_id, composition_type, strictness, fill_type,
            spread, horde_type, optional_data, ...)
    end)
end

rt_register("event_size_hook_target_present", function()
    -- The event-size scaling depends on SpawnerSystem.spawn_horde_from_terror_event_ids
    -- being hookable. If the engine ever renames it, ship-time would
    -- silently no-op event scaling.
    local SS = rawget(_G, "SpawnerSystem")
    if not SS then return "SpawnerSystem not loaded (run in keep)" end
    if type(SS.spawn_horde_from_terror_event_ids) ~= "function" then
        return "SpawnerSystem.spawn_horde_from_terror_event_ids missing — engine API moved"
    end
end)
