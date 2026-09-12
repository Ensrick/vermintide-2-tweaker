-- Bounded spawn census and receipt for progressive elite enhancements (#323).
local mod = get_mod("ct_dev")
local Policy = mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_progressive_elite_policy")
local M = { rt_checks = {} }
local CAP, captures = 7, 0
local census = {
    completed = 0,
    elite = 0,
    special = 0,
    elite_selected = 0,
    special_selected = 0,
    elite_applied = 0,
    special_applied = 0,
}

local function _controller()
    local manager = Managers and Managers.mechanism
    local mechanism = manager and manager.game_mechanism and manager:game_mechanism()
    return mechanism and mechanism.get_deus_run_controller
        and mechanism:get_deus_run_controller() or nil
end

local function _completed()
    local controller = _controller()
    return controller and controller.get_completed_level_count
        and controller:get_completed_level_count() or 0
end

local function _runtime()
    return mod._ct_progressive_elite_runtime_state
end

local function _step()
    local runtime = _runtime()
    return runtime and runtime.step and runtime.step() or Policy.DEFAULT_STEP_PERCENT
end

local function _reset()
    census = {
        completed = _completed(),
        elite = 0,
        special = 0,
        elite_selected = 0,
        special_selected = 0,
        elite_applied = 0,
        special_applied = 0,
    }
end

local function _report(reason)
    if captures >= CAP then return end
    captures = captures + 1
    local catalog = Policy.inspect_catalog(rawget(_G, "BreedEnhancements"),
        rawget(_G, "BossGrudgeMarks"))
    local runtime = _runtime()
    local activation = runtime and runtime.activation and runtime.activation() or "disabled"
    local step = _step()
    local completed = census.completed
    printf("[ct:323] audit=%d/%d reason=%s completed=%d rate=%d rates=%s step=%d elite=%d selected=%d applied=%d special=%d selected_special=%d applied_special=%d catalog=%d templates=%d boss_only=%d boss_enabled=%d elite_source_proven=%d missing=%d activation=%s",
        captures, CAP, tostring(reason), completed, Policy.rate(completed, step),
        Policy.rate_label(step), step,
        census.elite, census.elite_selected, census.elite_applied,
        census.special, census.special_selected, census.special_applied,
        catalog.total, catalog.templates, catalog.boss_catalog, catalog.boss_registered,
        catalog.elite_source_proven, #catalog.missing, activation)
end

-- The singleton (ConflictDirector, _post_spawn_unit) hook lives in
-- _ct_progressive_elite_runtime (`_ct_consolidated_post_spawn_unit_hook`).
-- This module only observes its post-vanilla callback and registers no hook of
-- its own; it never mutates the spawn payload. `applied_special` must stay 0:
-- the policy never selects a special, so any non-zero value is the #323
-- falsifier.
local function _observe(breed, spawn_queue_id, applied_recipe)
    if not _controller() then return end
    local kind = Policy.classify_breed(breed)
    if kind == "other" then return end
    census[kind] = census[kind] + 1
    if Policy.would_apply(spawn_queue_id, breed and breed.name, census.completed, _step()) then
        census[kind .. "_selected"] = census[kind .. "_selected"] + 1
    end
    if applied_recipe then
        census[kind .. "_applied"] = census[kind .. "_applied"] + 1
    end
end
M.observe = _observe

do
    local runtime = _runtime()
    if runtime and runtime.add_observer then
        runtime.add_observer(_observe)
    end
end

mod:command("ct_progressive_elite_audit", "Capture progressive elite receipt (#323)", function()
    _report("command")
end)

local previous_state_changed = mod.on_game_state_changed
mod.on_game_state_changed = function(status, state_name)
    -- Capture before an earlier callback can tear down the Deus mechanism.
    if state_name == "StateIngame" and status == "exit" and _controller() then
        _report("StateIngame_exit")
    end
    if previous_state_changed then previous_state_changed(status, state_name) end
    if state_name == "StateIngame" and status == "enter" then
        _reset()
    end
end

M.rt_checks[#M.rt_checks + 1] = {
    name = "issue323_progressive_elite_feasibility",
    fn = function()
        local catalog = Policy.inspect_catalog(rawget(_G, "BreedEnhancements"),
            rawget(_G, "BossGrudgeMarks"))
        if catalog.total ~= 15 or catalog.templates ~= 15
                or catalog.boss_catalog ~= 13
                or catalog.elite_source_proven ~= 2 then
            return string.format("enhancement catalog drift total/templates/boss/proven=%d/%d/%d/%d",
                catalog.total, catalog.templates, catalog.boss_catalog,
                catalog.elite_source_proven)
        end
        if Policy.rate(0) ~= 0 or Policy.rate(4) ~= 20 or Policy.rate(99) ~= 20 then
            return "progressive elite rate escaped the requested 0..20 percent curve"
        end
        if census.special_applied ~= 0 then
            return string.format("an enhancement was applied to %d special spawn(s)",
                census.special_applied)
        end
        local runtime = _runtime()
        if not runtime or not runtime.installed then
            return "progressive elite runtime is not installed"
        end
    end,
}

if type(mod._ct_rt_register) == "function" then
    for _, check in ipairs(M.rt_checks) do mod._ct_rt_register(check.name, check.fn) end
end

return M
