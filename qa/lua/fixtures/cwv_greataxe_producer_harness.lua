-- Required QA-only real Greataxe producer installation; no external fallback.
-- One helper owns first/next case plumbing, never a producer implementation.
-- Owned by: test_cwv_greataxe_producer.lua. Consumed via: its literal dofile.
local M = {}
local FIELD, SETTING = "additional_critical_strike_chance", "wt_greataxe_light_crit"
local NAMES = { "light_attack_left", "light_attack_right", "light_attack_up", "light_attack_bopp" }
local function read(file)
    local input = assert(io.open(file, "rb"), "required Greataxe producer source missing: " .. file)
    local value = assert(input:read("*a")); input:close(); return value
end
function M.install(H, c, private, id, initial, replace)
    -- Original first-batch callers pass their exact fixed resolver map.
    if type(id) == "table" then
        H.truthy(rawequal(id, c.next_mods), "same actual resolver map")
        id = "wt"
    end
    assert(id == "wt" or id == "wt_dev")
    assert(replace or rawget(c.next_mods, id) == nil, "one real installation per fixed slot unless testing replacement")
    local settings, requested = { value = initial }, {}
    local mod = { get = function(_, key)
        requested[key] = (requested[key] or 0) + 1
        if key == SETTING then return settings.value end
    end }
    c.next_mods[id] = mod
    local stream = id == "wt" and "weapon_tweaker" or "weapon_tweaker_dev"
    local policy = c.T.run(read(c.root .. "/" .. stream .. "/scripts/mods/" .. stream .. "/_wt_axe_balance.lua"),
        c.env, "complete-actual-WT-policy-install:" .. id)
    H.equal(type(rawget(policy, "install")), "function")
    local state = policy.install(mod)
    H.truthy(requested[SETTING], "real install consulted the setting")
    if initial == nil then H.equal(state.greataxe_crit_enabled, true) end
    H.equal(type(rawget(mod, "_wt_apply_axe_balance")), "function")
    H.equal(type(rawget(mod, "_wt_reset_axe_balance_baselines")), "function")
    H.equal(type(rawget(mod, "_wt_query_greataxe_light_crit")), "function")
    local value = { mod = mod, state = state, settings = settings, requested = requested, policy = policy }
    c.next_producers[id] = value
    if id == "wt" then c.first_producer = value end
    return value
end
function M.new(H, root, private, options)
    local before_first = options == true
    if type(options) == "boolean" then options = {} end
    options = options or {}
    local F = dofile(root .. "/qa/lua/fixtures/cwv_greataxe_construction_harness.lua")
    local mods, producers = {}, {}
    local c = F.new(H, root, {
        get_mod = function(id)
            if options.resolve then return options.resolve(id, mods) end
            return rawget(mods, id)
        end,
        before = function(context)
            context.root, context.next_mods, context.next_producers = root, mods, producers
            context.first_mods = mods
            if before_first then M.install(H, context, private, "wt", nil) end
            if options.before then options.before(context) end
        end,
        mechanics = options.mechanics,
        after_prepare = options.after_prepare,
        options = options.owner_options,
    })
    c.root, c.next_mods, c.next_producers, c.first_mods = root, mods, producers, mods
    return c
end
function M.apply(c, id, enabled, force_off)
    local p = assert(c.next_producers[id]); p.settings.value = enabled
    p.mod._wt_apply_axe_balance(SETTING, force_off == true)
end
function M.off_all(c, id)
    local p = assert(c.next_producers[id]); p.settings.value = false
    p.mod._wt_apply_axe_balance(nil, true)
end
function M.admission(H, c, want, phase)
    local _, item, seed = c.greataxe_items()
    local verdict = c.greataxe_owner.check()
    io.write("PRODUCER|", phase, "|item=", tostring(item ~= nil), "|seed=", tostring(seed ~= nil), "|check=", tostring(verdict), "\n")
    if want then
        H.truthy(item, phase .. ": actual private item")
        H.truthy(seed, phase .. ": actual acquisition seed")
        H.equal(verdict, nil, phase .. ": actual retained check")
    else
        H.equal(item, nil, phase .. ": denied actual private item")
        H.equal(seed, nil, phase .. ": denied actual acquisition seed")
        H.truthy(verdict, phase .. ": explicit refusal")
    end
    return item, seed, verdict
end
M.output = M.admission
function M.query(H, c, id, key)
    if id ~= "wt" and id ~= "wt_dev" then key, id = id, "wt" end
    key = key or "two_handed_axes_template_1"
    local value, why = c.next_producers[id].mod._wt_query_greataxe_light_crit(c.env.Weapons, key, rawget(c.env.Weapons, key))
    H.truthy(value, "real query: " .. tostring(why))
    H.equal(value.schema, "wt.greataxe_light_crit.v1")
    return value
end
function M.actions(template) return assert(rawget(assert(rawget(template, "actions")), "action_one")) end
function M.ready(H, root, private, options)
    local c = M.new(H, root, private, options)
    M.install(H, c, private, "wt", nil)
    M.admission(H, c, true, "case-setup-real-installed")
    return c
end
M.field, M.setting, M.names = FIELD, SETTING, NAMES
-- Real settings/history lifecycle additions; existing producer APIs remain unchanged.
-- QA-only closure: complete real WT expressions, selected genuine catalog.
-- No whole-entry/default13 runtime/profile-registration/engine ABI claim.
local LIFECYCLE_DIR = "weapon_tweaker"
local LIFECYCLE_PREFIX = "scripts/mods/weapon_tweaker/"
local function lifecycle_once(source, marker)
    local first = assert(source:find(marker, 1, true), "required complete entry marker " .. marker)
    assert(not source:find(marker, first + #marker, true), "ambiguous complete entry marker " .. marker)
    return first
end
local function lifecycle_expression(source, first, last)
    local a, z = lifecycle_once(source, first), lifecycle_once(source, last)
    assert(z > a, "actual complete expression source order")
    return source:sub(a, z + #last - 1)
end
function M.lifecycle_metadata(H, root, private)
    local loads, ordered = {}, {}
    local mod = {}
    mod.dofile = function(_, name)
        loads[name] = (loads[name] or 0) + 1
        ordered[#ordered + 1] = name
        return private.dofile(root .. "/" .. LIFECYCLE_DIR .. "/" .. name .. ".lua")
    end
    local catalog_module = mod:dofile(LIFECYCLE_PREFIX .. "_wt_history_catalog")
    local catalog, problem = catalog_module.load(mod)
    H.truthy(catalog, "actual default13 Catalog.load: " .. tostring(problem))
    H.equal(catalog.schema, 2)
    H.equal(#ordered, 15, "one loader plus13 actual catalogs plus completeness ledger")
    H.equal(ordered[15], LIFECYCLE_PREFIX .. "_wt_history_completeness_ledger")
    for _, name in ipairs(ordered) do H.equal(loads[name], 1, "actual metadata single load " .. name) end
    local families, templates = 0, 0
    for _, family in ipairs(catalog.families) do
        families = families + 1
        H.truthy(family.setting_id ~= SETTING, "no invented Greataxe history setting")
        for _, template in ipairs(family.templates) do
            templates = templates + 1
            H.truthy(template ~= "two_handed_axes_template_1" and template ~= "cwv_greataxe_template",
                "actual merged default catalogs do not target Greataxe")
        end
    end
    H.truthy(families > 0 and templates > 0, "actual merged metadata was inspected")
    H.truthy(rawequal(mod._wt_history_catalog_schema2_cache.catalog, catalog))
    io.write("LIFECYCLE_METADATA|loads=", #ordered, "|families=", families,
        "|template_targets=", templates, "|greataxe_family=false\n")
end
local function lifecycle_install(H, root, private, c, mods, selected)
    H.equal(rawget(mods, "wt"), nil, "one real WT mod object")
    local settings, reads, writes, loads, events = {}, {}, {}, {}, {}
    local baselines = { two_handed_axes_template_1 = {} }
    for index, name in ipairs(NAMES) do
        local action = assert(rawget(rawget(c.greataxe_source, "actions").action_one, name))
        baselines.two_handed_axes_template_1[index] = { value = rawget(action, FIELD) }
    end
    settings.wt_history_sienna_dagger = selected
    settings.wt_history_axe_and_falchion = "current"
    local mod = { _wt = {} }
    mod.get = function(_, key)
        reads[key] = (reads[key] or 0) + 1
        return rawget(settings, key)
    end
    mod.set = function(_, key, value, notify)
        H.equal(notify, false, "real rework persistence remains non-notifying")
        writes[#writes + 1] = { key = key, value = value, notify = notify }
        rawset(settings, key, value)
    end
    mod.warning = function(_, format, ...)
        error("unexpected real rework warning: " .. string.format(format, ...))
    end
    mods.wt = mod
    local canonical, selected_calls
    selected_calls = 0
    local function load(name)
        H.truthy(name:sub(1, #LIFECYCLE_PREFIX) == LIFECYCLE_PREFIX, "fixed real WT module namespace")
        loads[name] = (loads[name] or 0) + 1
        events[#events + 1] = name
        return c.T.run(private.READ(root .. "/" .. LIFECYCLE_DIR .. "/" .. name .. ".lua"), c.env, name)
    end
    mod.dofile = function(_, name)
        local value = load(name)
        if name == LIFECYCLE_PREFIX .. "_wt_history_catalog" then
            canonical = value
            return { load = function(actual_mod)
                H.truthy(rawequal(actual_mod, mod), "selected facade keeps actual mod identity")
                selected_calls = selected_calls + 1
                local catalog, problem = canonical.load(actual_mod, { LIFECYCLE_PREFIX .. "_wt_history_6_11_2_catalog" })
                if not catalog then return nil, problem end
                -- Genuine complete catalog, normalized by the actual merger.
                -- This is NOT default13 completeness/profile-registration coverage.
                return canonical.merge({ catalog })
            end }
        end
        return value
    end
    local entry = private.READ(root .. "/weapon_tweaker/scripts/mods/weapon_tweaker/weapon_tweaker.lua"):gsub("\r\n", "\n")
    local history = lifecycle_expression(entry, "local _wt_history_owner, _wt_history_verify = mod:dofile(",
        "local _wt_history_runtime = _wt_history_owner.runtime")
    local invoke_history = c.T.run("return function(mod)\n" .. history
        .. "\nreturn _wt_history_owner, _wt_history_verify, _wt_history_runtime end", c.env,
        "actual-complete-WT-entry-owner-expression")
    local owner, verify, runtime = invoke_history(mod)
    H.truthy(owner and runtime, "actual owner/runtime publication")
    H.truthy(rawequal(owner.runtime, runtime) and rawequal(rawget(mod, "_wt_history_runtime"), runtime))
    H.equal(runtime.fatal_error, nil)
    H.equal(runtime.last_error, nil)
    H.equal(verify(), nil, "actual verifier before restore")
    H.equal(runtime.registration.count, 0, "genuine catalog has no custom-profile specifications")
    H.equal(next(runtime.registration.names), nil)
    H.equal(selected_calls, 1)
    local balance_policy = load(LIFECYCLE_PREFIX .. "_wt_axe_balance")
    local rework_policy = load(LIFECYCLE_PREFIX .. "_wt_rework_master_policy")
    local rework_module = load(LIFECYCLE_PREFIX .. "_wt_rework_master_runtime")
    local bolt_policy = load(LIFECYCLE_PREFIX .. "_wt_bolt_staff_overcharge")
    local lifecycle = lifecycle_expression(entry, "local _wt_rework_runtime = _wt_rework_master_runtime_module.new(",
        "_wt_axe_balance_policy.install(mod)")
    local invoke_lifecycle = c.T.run("return function(mod, _wt_history_runtime, _wt_axe_balance_policy, "
        .. "_wt_rework_master_runtime_module, _wt_rework_master, _wt_bolt_staff_overcharge)\n"
        .. lifecycle .. "\nreturn _wt_rework_runtime end", c.env,
        "actual-complete-WT-entry-rework-settings-balance-expression")
    local rework = invoke_lifecycle(mod, runtime, balance_policy, rework_module, rework_policy, bolt_policy)
    H.truthy(rawequal(mod._wt.rework_master_runtime, rework))
    H.equal(type(mod.on_setting_changed), "function")
    H.equal(type(mod._wt_query_greataxe_light_crit), "function")
    local record = { mod = mod, settings = settings, reads = reads, writes = writes,
        loads = loads, events = events, owner = owner, runtime = runtime, verify = verify,
        rework = rework, rework_policy = rework_policy, balance_policy = balance_policy,
        query = mod._wt_query_greataxe_light_crit, apply = mod._wt_apply_axe_balance,
        reset = mod._wt_reset_axe_balance_baselines, baselines = baselines }
    H.equal(loads[LIFECYCLE_PREFIX .. "_wt_history_owner"], 1)
    H.equal(loads[LIFECYCLE_PREFIX .. "_wt_settings_runtime"], 1)
    H.equal(loads[LIFECYCLE_PREFIX .. "_wt_history_profile_transaction"], 1)
    H.equal(loads[LIFECYCLE_PREFIX .. "_lib_network_lookup"], 1)
    return record
end
function M.lifecycle_new(H, root, private, selected)
    local record
    local c = M.new(H, root, private, { before = function(context)
        record = lifecycle_install(H, root, private, context, context.next_mods, selected)
    end })
    c.lifecycle = record
    H.truthy(rawequal(c.next_mods.wt, record.mod), "same unified-helper resolver map")
    record.baselines.cwv_greataxe_template = {}
    for index, name in ipairs(NAMES) do
        local action = assert(rawget(rawget(c.greataxe_template, "actions").action_one, name))
        record.baselines.cwv_greataxe_template[index] = { value = rawget(action, FIELD) }
    end
    return c
end
function M.lifecycle_crit(H, c, on, phase)
    for _, key in ipairs({ "two_handed_axes_template_1", "cwv_greataxe_template" }) do
        local template = assert(rawget(c.env.Weapons, key))
        local rows, problem = c.lifecycle.query(c.env.Weapons, key, template)
        H.truthy(rows, phase .. ": actual copied query " .. tostring(problem))
        H.equal(rows.enabled, on)
        for index, name in ipairs(NAMES) do
            local action = assert(rawget(rawget(template, "actions").action_one, name))
            H.truthy(rawequal(rows.rows[index].action, action))
            local baseline = c.lifecycle.baselines[key][index].value
            local expected = baseline
            if on then expected = math.max(baseline or 0, 0.10) end
            H.equal(rawget(action, FIELD), expected, phase .. ": raw crit " .. key .. "/" .. name)
            H.equal(rows.rows[index].value, expected, phase .. ": real query raw value")
            if rows.rows[index].claimed then H.equal(rows.rows[index].baseline_value, baseline) end
        end
    end
    H.truthy(rawequal(c.lifecycle.mod._wt_query_greataxe_light_crit, c.lifecycle.query))
    H.truthy(rawequal(c.lifecycle.mod._wt_apply_axe_balance, c.lifecycle.apply))
    H.truthy(rawequal(c.lifecycle.mod._wt_reset_axe_balance_baselines, c.lifecycle.reset))
end
function M.lifecycle_dagger(c)
    return assert(rawget(rawget(rawget(rawget(c.env.Weapons, "one_handed_daggers_template_1"),
        "actions"), "action_one"), "heavy_attack_right"))
end

return M
