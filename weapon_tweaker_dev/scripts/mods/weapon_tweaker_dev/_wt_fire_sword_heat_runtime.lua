-- #942 injected application/capture; _wt_fire_sword_owner installs callbacks.
-- This runtime registers no hooks: no logger, packet, native write or gate override.
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
    local capture, capture_context, serial = nil, nil, 0
    local function configuration()
        return policy.config(function(id) return mod:get(id) end)
    end
    local function text(value, limit)
        if type(value) ~= "string" then return "unknown" end
        if #value > limit then return "overflow" end
        if value == "" or value:find("[^A-Za-z0-9_./:%-]") then return "invalid" end
        return value
    end
    local function number(value)
        return policy.finite(value) and string.format("%.17g", value) or "unavailable"
    end
    local function boolean(value)
        return value == true and "1" or value == false and "0" or "unset"
    end
    local function config_text(config)
        if not config then return "invalid" end
        return "enabled:" .. boolean(config.enabled) .. ",armor:" .. boolean(config.armor)
            .. ",cleave:" .. number(config.cleave) .. ",damage:" .. number(config.damage)
            .. ",threshold:" .. number(config.threshold)
    end
    local function stop(reason)
        if capture and capture.armed then
            capture.armed, capture.unit, capture.reason = false, nil, text(reason, 32)
        end
    end
    local function live_capture()
        if not capture or not capture.armed then return nil end
        local ok, valid = pcall(function()
            return alive(capture.unit) == true
                and (not deps.capture_valid or deps.capture_valid(capture.unit) == true)
        end)
        if not ok or not valid then stop("owner-or-unit-lost"); return nil end
        return capture
    end
    local function active(config, trace)
        if trace then trace.catalog, trace.agreement = "not-evaluated", "not-evaluated" end
        if runtime.force_off or not config or not config.enabled then return false end
        local phase = "catalog"
        local ok, verdict = pcall(function()
            local catalog = allowed() == true
            if trace then trace.catalog = catalog and "true" or "false" end
            if not catalog then return false end
            phase = "agreement"
            local agreement = agrees(config) == true
            if trace then trace.agreement = agreement and "true" or "false" end
            return agreement
        end)
        if not ok and trace then trace[phase] = "error" end
        return ok and verdict == true
    end
    local function sample(unit)
        local amount, raw, maximum, status = policy.sample_heat(unit, extension, alive)
        return amount, { amount = amount, raw = raw, maximum = maximum, status = status }
    end
    local function diagnostic(unit)
        local _, observed = sample(unit)
        return observed
    end
    local function heat(unit) return policy.heat(unit, extension, alive) end
    local function heat_text(observed, used)
        return " heat_raw=" .. number(observed and observed.raw)
            .. " heat_clamped=" .. number(observed and observed.amount)
            .. " heat_max=" .. number(observed and observed.maximum)
            .. " heat_status=" .. text(observed and observed.status, 32)
            .. " heat_usage=" .. used
    end
    local function gates(trace)
        return " catalog=" .. text(trace and trace.catalog or "not-evaluated", 32)
            .. " agreement=" .. text(trace and trace.agreement or "not-evaluated", 32)
    end
    local function profile_text(profile)
        local owned = state.owned[profile]
        local key = state.labels[profile]
        local class = owned and "owned" or key and "native" or "unindexed"
        return text(key, 96), class, type(profile) == "table" and rawget(profile, "is_dot") == true,
            type(profile) == "table" and rawget(profile, "no_damage") == true
    end
    local function append(current, build)
        if capture ~= current or not current or not current.armed then return nil end
        local ok, row = pcall(build)
        if not ok or type(row) ~= "string" or #row > 960 or row:find("[^ -~]") then
            stop("observer-error"); return nil
        end
        local index = #current.rows + 1
        if index > 8 then stop("cap"); return nil end
        current.rows[index] = row
        if index == 8 then stop("cap") end
        return index
    end
    local function ratio(before, after)
        if not policy.finite(before) or not policy.finite(after) then return "unavailable" end
        if before == 0 then return "zero-input" end
        return number(after / before)
    end

    function runtime:capture_arm(unit, details)
        local config = configuration()
        if self.force_off or not config or unit == nil or serial >= 2147483647 then
            return false, "not-ready"
        end
        stop("rearmed")
        serial = serial + 1
        capture = { armed = true, unit = unit, rows = {}, pending = true, reason = "armed",
            session = serial, config = config_text(config),
            owner_committed = boolean(details and details.owner_committed),
            heavy = "sweep_opener:" .. boolean(details and details.sweep_opener)
                .. ",nova_slowdown:" .. boolean(details and details.nova_slowdown) }
        return true, "armed"
    end
    function runtime:capture_stop(reason) stop(reason) end
    function runtime:capture_clear()
        stop("cleared"); capture = nil
        return true, "cleared"
    end
    function runtime:capture_dump()
        if not capture or not capture.pending then return nil, "no-pending-capture" end
        live_capture()
        stop("dumped")
        capture.pending = false -- consume before any command output, never replay this buffer
        local rows = {}
        for index = 1, 8 do rows[index] = capture.rows[index] end
        return { count = #capture.rows, rows = rows,
            header = "session=" .. capture.session .. " count=" .. #capture.rows
                .. "/8 reason=" .. capture.reason .. " local=1 owner_committed_at_arm=" .. capture.owner_committed .. " config="
                .. capture.config .. " independent943=" .. capture.heavy }, "dump"
    end
    function runtime:apply(force_off)
        self.force_off = force_off == true
        if self.force_off then stop("owner-suspended") end
        local config = configuration()
        local enabled = active(config)
        return self.state:project(enabled), enabled
    end

    -- Native scope and diagnostic scope are independent. No last-action cache.
    function runtime:start_action(func, self_action, action, ...)
        local args = pack(...)
        local current = live_capture()
        local local_call = current and type(self_action) == "table"
            and rawequal(current.unit, rawget(self_action, "owner_unit"))
        local trace = local_call and {} or nil
        local config, prepared, context = configuration(), action, nil
        local observed, amount
        if active(config, trace) then
            if local_call then amount, observed = sample(self_action.owner_unit)
            else amount = heat(self_action.owner_unit) end
            prepared, context = state:prepare(action, amount, config, args[4])
        elseif local_call then
            observed = diagnostic(self_action.owner_unit) -- explicitly diagnostic-only, not gameplay
        end
        local observation
        if local_call then
            if current.config ~= config_text(config) then stop("configuration-changed") end
            local index = append(current, function()
                local aoe_key = type(prepared) == "table" and rawget(prepared, "damage_profile_aoe")
                local aoe = type(aoe_key) == "string" and rawget(state.profiles, aoe_key)
                return "phase=start action_context=sync action=" .. text(state.action_labels[action], 64)
                    .. " kind=" .. text(type(action) == "table" and rawget(action, "kind"), 32)
                    .. " init_hand=" .. text(type(args[4]) == "table" and rawget(args[4], "action_hand") or "unspecified", 32)
                    .. " source_profile_field=" .. text(type(action) == "table" and rawget(action, "damage_profile"), 96)
                    .. " prepared_profile_field=" .. text(type(prepared) == "table" and rawget(prepared, "damage_profile"), 96)
                    .. " prepared_right_field=" .. text(type(prepared) == "table" and rawget(prepared, "damage_profile_right"), 96)
                    .. " prepared_target_field=" .. text(type(prepared) == "table" and rawget(prepared, "damage_profile_target"), 96)
                    .. " prepared_aoe_field=" .. text(type(prepared) == "table" and rawget(prepared, "damage_profile_aoe"), 96)
                    .. " aoe_no_damage=" .. boolean(type(aoe) == "table" and rawget(aoe, "no_damage") == true)
                    .. heat_text(observed, amount ~= nil and "gameplay-read" or "diagnostic-only")
                    .. gates(trace) .. " config=" .. config_text(config)
            end)
            if index and state.action_labels[action] then observation = { action = text(state.action_labels[action], 64),
                scope = index, observed = observed, config = config_text(config) } end
        end
        local previous, previous_observation = self.context, capture_context
        self.context, capture_context = context, observation
        local call = pack(pcall(func, self_action, prepared, unpack(args, 1, args.n)))
        self.context, capture_context = previous, previous_observation
        if not call[1] then stop("native-error"); error(call[2], 0) end
        return unpack(call, 2, call.n)
    end

    function runtime:max_targets(func, profile, power, ...)
        local context = self.context
        local current, observation = live_capture(), capture_context
        local watching = current and observation
        local input, trace = power, watching and {} or nil
        if context and context.selected[profile] and policy.finite(power)
                and active(context.config, trace) then
            power = power * (1 + context.config.cleave * context.heat)
        end
        if not watching then return func(profile, power, ...) end
        local values = pack(func(profile, power, ...))
        append(current, function()
            local key, class, dot, no_damage = profile_text(profile)
            return "phase=cleave action_context=sync action=" .. observation.action
                .. " scope=" .. observation.scope .. " profile=" .. key .. " class=" .. class
                .. " dot=" .. boolean(dot) .. " no_damage=" .. boolean(no_damage)
                .. " input_power=" .. number(input) .. " passed_power=" .. number(power)
                .. " observed_power_ratio=" .. ratio(input, power)
                .. " native_attack_cleave=" .. number(values[1])
                .. " native_impact_cleave=" .. number(values[2])
                .. heat_text(observation.observed, "start-boundary")
                .. gates(trace) .. " config=" .. observation.config
        end)
        return result(values)
    end

    -- The delegated first result already includes #664; neither result is final HP loss.
    function runtime:calculate_damage(func, damage_output, target, attacker,
            hit_zone, power, curve, boost, critical, profile, ...)
        local original = state:source_profile(profile)
        local current = live_capture()
        local watching = current and rawequal(current.unit, attacker)
        if not original and not watching then
            return func(damage_output, target, attacker, hit_zone, power, curve,
                boost, critical, profile, ...)
        end
        local config, enabled, amount, observed, selected = nil, false, 0, nil, profile
        local trace = watching and {} or nil
        if original then
            config = configuration()
            enabled = active(config, trace)
            if enabled then
                if watching then amount, observed = sample(attacker) else amount = heat(attacker) end
            end
            selected = state:damage_profile(profile, amount, config, enabled)
        end
        if watching and not observed then observed = diagnostic(attacker) end
        local values = pack(func(damage_output, target, attacker, hit_zone, power,
            curve, boost, critical, selected, ...))
        local before = values[1]
        if enabled and amount > 0 and policy.finite(values[1]) then
            values[1] = values[1] * (1 + config.damage * amount)
        end
        if watching then
            if config and current.config ~= config_text(config) then stop("configuration-changed") end
            append(current, function()
                local key, class, dot, no_damage = profile_text(profile)
                local selected_key = profile_text(selected)
                local scope = capture_context
                return "phase=damage action_context=" .. (scope and "sync" or "none")
                    .. " action=" .. (scope and scope.action or "unknown")
                    .. " profile=" .. key .. " selected_profile=" .. selected_key .. " class=" .. class
                    .. " dot=" .. boolean(dot) .. " no_damage=" .. boolean(no_damage)
                    .. " same_profile=" .. boolean(rawequal(profile, selected))
                    .. " hit_zone=" .. text(hit_zone, 32) .. " critical=" .. boolean(critical)
                    .. " original_power=" .. number(power)
                    .. heat_text(observed, enabled and "gameplay-read" or "diagnostic-only")
                    .. gates(trace) .. " config=" .. (config and config_text(config) or "not-evaluated")
                    .. " pre_942_calculated_damage=" .. number(before)
                    .. " post_942_calculated_damage=" .. number(values[1])
                    .. " observed_damage_ratio=" .. ratio(before, values[1])
            end)
        end
        return result(values)
    end
    return runtime
end
return M
