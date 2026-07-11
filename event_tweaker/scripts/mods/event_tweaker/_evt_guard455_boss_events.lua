local mod = get_mod("event_tweaker")

-- _evt_guard455_boss_events.lua — issue 455: boss-event mutator guard
--
-- Three vanilla mutators index CurrentBossSettings.boss_events with no nil
-- check: multiple_bosses (server_initialize_function + update_conflict_settings,
-- mutator_multiple_bosses.lua:8/:13), blessing_of_grimnir (server_start_function,
-- mutator_blessing_of_grimnir.lua:60), deus_pacing_tweak (server_start_function,
-- mutator_deus_pacing_tweak.lua:482/:498). CurrentBossSettings is rebuilt per
-- level from the conflict director's `boss` block (conflict_director.lua:879),
-- and fixed-end-boss levels (crash evidence: warcamp) ship a boss block with NO
-- boss_events table -- so hosting such a level with the mutator injected is an
-- instant host fatal at the dispatch sites MutatorHandler._initialize_mutator
-- (mutator_handler.lua:644-645) / conflict_director_updated_settings
-- (mutator_handler.lua:578-579) / activate (server.start_function).
--
-- Fix (shipped v0.4.25-dev; DO NOT REMOVE): when gather_mutators()'s add()
-- (_evt_selection.lua) injects one of these names, wrap the template's live
-- dispatch fields (the engine folds server_*_function into template.server.*
-- at boot; update_conflict_settings dispatches off the template root) with a
-- guard that no-ops via an [et:455] printf when boss_events is absent. The
-- check runs at dispatch time, against the CURRENT level's settings, so the
-- mutator still works everywhere boss events exist. Skipping is strictly
-- better than the vanilla crash on the levels it fires (divert flow, not
-- delegate -- issue 270 lesson). Host-side only: all three sites are server
-- dispatch paths. Regression check issue455_boss_event_mutators_guarded;
-- checklist slug et-boss-event-mutator-guard.
--
-- Owned by: event_tweaker.lua entry point (dofile'd before _evt_selection).
-- Consumed via mod fields (resolved at call time by gather_mutators):
-- mod._et455_guard_boss_event_mutator, mod._et455_boss_events_present.

local ET = mod._evt
local rt_register = ET.rt_register

-- name -> list of dispatch-field paths that index boss_events unguarded.
local BOSS_EVENT_GUARDS = {
    multiple_bosses     = { { "server", "initialize_function" }, { "update_conflict_settings" } },
    blessing_of_grimnir = { { "server", "start_function" } },
    deus_pacing_tweak   = { { "server", "start_function" } },
}

-- Pure + testable: pass a table to test, omit to read the live global.
local function _boss_events_present(cbs)
    if cbs == nil then
        cbs = rawget(_G, "CurrentBossSettings")
    end
    return type(cbs) == "table" and type(cbs.boss_events) == "table"
end
mod._et455_boss_events_present = _boss_events_present

local function _wrap(name, field_label, fn)
    return function(...)
        if not _boss_events_present() then
            pcall(printf, "[et:455] skipped " .. name .. "." .. field_label
                .. " - this level's boss settings have no boss_events")
            return
        end
        return fn(...)
    end
end

-- Idempotent: templates are global and persist across missions, so wrap
-- once and mark. Called from gather_mutators()'s add() for every injected
-- name; non-listed names return immediately.
function mod._et455_guard_boss_event_mutator(name)
    local paths = BOSS_EVENT_GUARDS[name]
    if not paths then
        return
    end
    local MT = rawget(_G, "MutatorTemplates")
    local template = MT and rawget(MT, name)
    if not template or template.__et455_guarded then
        return
    end
    template.__et455_guarded = true
    for i = 1, #paths do
        local path = paths[i]
        local holder, field = template, path[1]
        if path[2] then
            holder, field = template[path[1]], path[2]
        end
        if type(holder) == "table" and type(holder[field]) == "function" then
            holder[field] = _wrap(name, table.concat(path, "."), holder[field])
        end
    end
end

rt_register("issue455_boss_event_mutators_guarded", function()
    -- The presence predicate must fail closed on a boss block without
    -- boss_events (the warcamp shape) and pass on one with it; and once
    -- multiple_bosses is guarded, the template must carry the marker so the
    -- wrap is provably installed and idempotent.
    if mod._et455_boss_events_present({}) then
        return "predicate passed a boss block with no boss_events (warcamp shape)"
    end
    if not mod._et455_boss_events_present({ boss_events = {} }) then
        return "predicate rejected a boss block WITH boss_events"
    end
    local MT = rawget(_G, "MutatorTemplates")
    local template = MT and rawget(MT, "multiple_bosses")
    if template then
        mod._et455_guard_boss_event_mutator("multiple_bosses")
        if not template.__et455_guarded then
            return "guard installer did not mark multiple_bosses as guarded"
        end
    end
end)
