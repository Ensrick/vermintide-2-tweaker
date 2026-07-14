-- Observation-only spawn census for progressive elite modifiers (#323).
local mod = get_mod("ct_dev")
local Policy = mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_progressive_elite_policy")
local M = { rt_checks = {} }
local CAP, captures = 7, 0
local census = { completed = 0, elite = 0, special = 0, elite_selected = 0, special_selected = 0 }

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

local function _reset()
    census = {
        completed = _completed(),
        elite = 0,
        special = 0,
        elite_selected = 0,
        special_selected = 0,
    }
end

local function _report(reason)
    if captures >= CAP then return end
    captures = captures + 1
    local catalog = Policy.inspect_catalog(rawget(_G, "BreedEnhancements"),
        rawget(_G, "BossGrudgeMarks"))
    local completed = census.completed
    printf("[ct:323] audit=%d/%d reason=%s completed=%d rate=%d elite=%d selected=%d special=%d selected_special=%d catalog=%d templates=%d boss_only=%d boss_enabled=%d elite_source_proven=%d missing=%d activation=disabled",
        captures, CAP, tostring(reason), completed, Policy.rate(completed),
        census.elite, census.elite_selected, census.special, census.special_selected,
        catalog.total, catalog.templates, catalog.boss_catalog, catalog.boss_registered,
        catalog.elite_source_proven, #catalog.missing)
end

-- Pre-flight grep found no CT hook on this pair. Post-spawn observation cannot
-- alter optional_data before vanilla applies it, so this remains diagnostic.
mod:hook_safe("ConflictDirector", "_post_spawn_unit", function(self, ai_unit, go_id,
        breed, spawn_pos, spawn_category, spawn_animation, optional_data,
        spawn_type, spawn_queue_id)
    if not _controller() then return end
    local kind = Policy.classify_breed(breed)
    if kind == "other" then return end
    census[kind] = census[kind] + 1
    if Policy.would_apply(spawn_queue_id, breed and breed.name, census.completed) then
        census[kind .. "_selected"] = census[kind .. "_selected"] + 1
    end
end)

mod:command("ct_progressive_elite_audit", "Capture progressive elite feasibility (#323)", function()
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
    end,
}

if type(mod._ct_rt_register) == "function" then
    for _, check in ipairs(M.rt_checks) do mod._ct_rt_register(check.name, check.fn) end
end

return M
