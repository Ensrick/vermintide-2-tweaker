-- _cwv_tuskgor_spear_family.lua -- Dormant retained Tuskgor construction owner.
--
-- Captures one real constructor only after the existing all-mods-loaded chain.
-- This is not a selectable family: no package, item, actor, resource, UI or
-- native-restoration admission is exported. Career/3P acceptance remains open.
-- Owned by: character_weapon_variants.lua through its private family handoff.
local M = {}
local KEY = "cwv_645_tuskgor_spear_style"
local CHECK = "issue645_tuskgor_retained_construction"
function M.bind(construction_module, history_module)
    local constructor_bind, history_bind = construction_module.bind, history_module.bind
    return function(ctx)
        local owner, attempted, failure, constructor = {}, false
        local construct, template, retained_check
        local graph, network, state = ctx.graph, ctx.network_lookup, ctx.om
        local producer, scalar = ctx.core.history_producer_binding, ctx.core.detached_scalar_factory
        local clone, profiles, levels = ctx.clone, ctx.profiles, ctx.power_levels
        local lookup, weapons = ctx.lookup, ctx.weapons
        assert(type(ctx.career) == "table" and type(ctx.career_actions) == "table",
            "Tuskgor installed career dependencies missing")
        -- Private by-value method binds survive later context/export replacement.
        local career = { capture = rawget(ctx.career, "capture"), intact = rawget(ctx.career, "intact") }
        local career_actions = { prepare_inherited_clone = rawget(ctx.career_actions, "prepare_inherited_clone") }
        local action_templates = ctx.action_templates
        assert(type(career.capture) == "function" and type(career.intact) == "function"
            and type(career_actions.prepare_inherited_clone) == "function"
            and type(action_templates) == "function", "Tuskgor installed career functions missing")
        local initialize, check, register_check
        local function interface_intact()
            return rawequal(rawget(owner, "initialize_once"), initialize)
                and rawequal(rawget(owner, "check"), check)
                and rawequal(rawget(owner, "register_check"), register_check)
        end
        check = function()
            if not interface_intact() then return "#645 Tuskgor retained owner interface drifted" end
            if failure then return failure end
            if not attempted then return "#645 Tuskgor retained bootstrap pending" end
            if not constructor then return "#645 Tuskgor retained constructor disconnected" end
            local ok, reason = pcall(retained_check)
            if not ok then return "#645 Tuskgor retained check errored" end
            if reason ~= nil then
                return type(reason) == "string" and reason or "#645 Tuskgor retained check malformed"
            end
            local named, name, value = pcall(template)
            local rooted, registry = pcall(weapons)
            if not named or name ~= KEY or type(value) ~= "table" or not rooted
                    or type(registry) ~= "table" or not rawequal(rawget(registry, KEY), value) then
                return "#645 Tuskgor retained template unavailable"
            end
        end
        initialize = function()
            if attempted then local reason = check(); return reason == nil, reason end
            attempted = true
            local ok, problem = pcall(function()
                assert(interface_intact(), "retained owner interface drifted")
                local envelope = history_bind(graph, producer)
                local factory = constructor_bind(network, graph, envelope, career, career_actions, action_templates)
                constructor = factory({
                    state = state, scalar_factory = scalar, clone = clone,
                    profiles = profiles, power_levels = levels, lookup = lookup, weapons = weapons,
                })
                assert(type(constructor) == "table", "constructor factory returned no owner")
                construct, template, retained_check = rawget(constructor, "construct"),
                    rawget(constructor, "template"), rawget(constructor, "check")
                assert(type(construct) == "function" and type(template) == "function"
                    and type(retained_check) == "function", "constructor owner methods missing")
                assert(construct() == true, retained_check() or "constructor refused")
                assert(check() == nil, "retained construction readback failed")
            end)
            if not ok then
                local printable, reason = pcall(tostring, problem)
                failure = "#645 Tuskgor retained initialization refused: "
                    .. (printable and reason or "<unprintable initialization failure>")
            end
            local reason = check()
            return reason == nil, reason
        end
        register_check = function(register)
            register(CHECK, check)
        end
        owner.initialize_once, owner.check, owner.register_check = initialize, check, register_check
        return owner
    end
end
return M
