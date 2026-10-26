-- #942 injected application seam. This candidate deliberately does not install
-- hooks or claim a live peer-settings protocol. Entry integration is pending.
local M = {}
local function pack(...) return { n = select("#", ...), ... } end
local function result(row) return unpack(row, 1, row.n) end

function M.new(mod, deps)
    local policy = assert(deps.policy, "#942 policy missing")
    local allowed = assert(deps.catalog_allows, "#942 exact catalog gate missing")
    local agrees = assert(deps.configuration_agrees, "#942 configuration proof missing")
    assert(type(allowed) == "function" and type(agrees) == "function", "#942 proof dependency invalid")
    local extension = assert(deps.extension, "#942 extension reader missing")
    local alive = assert(deps.alive, "#942 alive reader missing")
    local state = policy.new(deps.weapons, deps.profiles, deps.clone,
        deps.register, deps.fallbacks, deps.armor_reference)
    local runtime = { state = state, context = nil, force_off = false }
    local function configuration()
        return policy.config(function(id) return mod:get(id) end)
    end
    local function active(config)
        if runtime.force_off or not config or not config.enabled then return false end
        local ok, verdict = pcall(function()
            return allowed() == true and agrees(config) == true
        end)
        return ok and verdict == true
    end
    local function heat(unit) return policy.heat(unit, extension, alive) end

    function runtime:apply(force_off)
        self.force_off = force_off == true
        local config = configuration()
        local enabled = active(config)
        return self.state:project(enabled), enabled
    end

    -- Shared by the exact Sweep and ShieldSlam start adapters. Native varargs,
    -- arbitrary result tuples and original error objects survive unchanged.
    function runtime:start_action(func, self_action, action, ...)
        local args = pack(...)
        -- Native args after new_action: t, chain, power, action_init_data.
        local config, prepared, context = configuration(), action, nil
        if active(config) then
            prepared, context = state:prepare(action, heat(self_action.owner_unit), config, args[4])
        end
        local previous = self.context
        self.context = context -- a nested unrelated start suppresses outer context
        local call = pack(pcall(func, self_action, prepared, unpack(args, 1, args.n)))
        self.context = previous
        if not call[1] then error(call[2], 0) end
        return unpack(call, 2, call.n)
    end

    function runtime:max_targets(func, profile, power, ...)
        local context = self.context
        if context and context.selected[profile] and policy.finite(power)
                and active(context.config) then
            power = power * (1 + context.config.cleave * context.heat)
        end
        return func(profile, power, ...)
    end

    -- This must be called from WT's existing singleton calculate_damage hook.
    -- Never register a second hook. Proof failures select native donor data,
    -- including for a private armor profile latched before a parity/config flip.
    function runtime:calculate_damage(func, damage_output, target, attacker,
            hit_zone, power, curve, boost, critical, profile, ...)
        local original = state:source_profile(profile)
        if not original then
            return func(damage_output, target, attacker, hit_zone, power, curve,
                boost, critical, profile, ...)
        end
        local config = configuration()
        local enabled = active(config)
        local amount = enabled and heat(attacker) or 0
        local selected = state:damage_profile(profile, amount, config, enabled)
        local values = pack(func(damage_output, target, attacker, hit_zone, power,
            curve, boost, critical, selected, ...))
        if enabled and amount > 0 and policy.finite(values[1]) then
            values[1] = values[1] * (1 + config.damage * amount)
        end
        return result(values)
    end
    return runtime
end
return M
