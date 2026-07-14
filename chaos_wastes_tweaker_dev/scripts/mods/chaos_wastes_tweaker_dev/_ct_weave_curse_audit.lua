-- Bounded runtime feasibility audit for Weave winds as Chaos Wastes curses (#253).
local mod = get_mod("ct_dev")
local Policy = mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_weave_curse_policy")
local M = { rt_checks = {} }

local CAP, captures = 2, 0
local RESOURCE_UNITS = {
    "units/decals/decal_heavens_01",
    "units/weave/life/life_thorn_bushes_mutator",
    "units/weapons/player/wpn_shadow_gargoyle_head/wpn_shadow_gargoyle_head",
    "units/fx/vfx_static_shadow_01",
    "units/fx/vfx_animation_death_spirit_02",
    "units/weave/beasts/beast_totem_mutator",
}

local function _resident_resources()
    local app = rawget(_G, "Application")
    if not app or type(app.can_get) ~= "function" then return 0 end
    local ready = 0
    for _, unit_name in ipairs(RESOURCE_UNITS) do
        local ok, value = pcall(app.can_get, "unit", unit_name)
        if ok and value then ready = ready + 1 end
    end
    return ready
end

local function _report(reason)
    if captures >= CAP then return end
    captures = captures + 1
    local lookup = rawget(_G, "NetworkLookup")
    local result = Policy.inspect(rawget(_G, "WindSettings"),
        rawget(_G, "MutatorTemplates"), lookup and lookup.mutator_templates,
        _resident_resources())
    printf("[ct:253] audit=%d/%d reason=%s winds=%d settings=%d templates=%d wire=%d weave_context=%d objective_bound=%d resource_bound=%d declared_packages=%d resident_samples=%d/%d",
        captures, CAP, tostring(reason), result.total, result.settings,
        result.templates, result.wire, result.context_required,
        result.objective_required, result.resource_required,
        result.declared_packages, result.resources_ready, #RESOURCE_UNITS)
    printf("[ct:253] bridge_first=%s objective_bound=%s activation=per_level_deus_curse unsafe_direct_enable=true",
        table.concat(result.bridge_first, ","), table.concat(result.objective, ","))
end

mod:command("ct_weave_curse_audit", "Capture Weave-to-CW curse feasibility (#253)", function()
    _report("command")
end)

local prev_loaded = mod.on_all_mods_loaded
mod.on_all_mods_loaded = function(...)
    if prev_loaded then prev_loaded(...) end
    _report("all_mods_loaded")
end

local prev_state = mod.on_game_state_changed
mod.on_game_state_changed = function(status, state_name)
    if prev_state then prev_state(status, state_name) end
    if status == "enter" and state_name == "StateIngame" then
        _report("StateIngame")
    end
end

M.rt_checks[#M.rt_checks + 1] = {
    name = "issue253_weave_curse_feasibility",
    fn = function()
        local lookup = rawget(_G, "NetworkLookup")
        local result = Policy.inspect(rawget(_G, "WindSettings"),
            rawget(_G, "MutatorTemplates"), lookup and lookup.mutator_templates, 0)
        if result.total ~= 8 or result.settings ~= 8 or result.templates ~= 8
                or result.wire ~= 8 then
            return string.format("wind catalog drifted total/settings/templates/wire=%d/%d/%d/%d",
                result.total, result.settings, result.templates, result.wire)
        end
        if result.objective_required ~= 2
                or table.concat(result.objective, ",") ~= "beasts,light" then
            return "objective-bound classification drifted: "
                .. table.concat(result.objective, ",")
        end
        if result.declared_packages ~= 0 then
            return "vanilla wind mutators now declare packages; re-audit preload plan"
        end
    end,
}

if type(mod._ct_rt_register) == "function" then
    for _, check in ipairs(M.rt_checks) do
        mod._ct_rt_register(check.name, check.fn)
    end
end

return M
