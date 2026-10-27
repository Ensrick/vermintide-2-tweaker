-- Real WT Owner/publication and Catalog.load/merge, one projected finite family.
-- Not all13 registration, complete entry/VMF ABI or historical combat execution.
local M = {}
local function read(path)
    local f = assert(io.open(path, "rb")); local value = f:read("*a"); f:close()
    return (value:gsub("\r\n", "\n"))
end
function M.new(H, root, options)
    options = options or {}
    local F = dofile(root .. "/qa/lua/fixtures/cwv_elven_shield_construction_harness.lua")
    local mods, records, reader = {}, {}, options.read_source or read
    local function resolver(id)
        if options.resolve then return options.resolve(id, mods) end
        return rawget(mods, id)
    end
    local function install(c, id, state, parity)
        assert(id == "wt" or id == "wt_dev")
        local dir = id == "wt" and "weapon_tweaker" or "weapon_tweaker_dev"
        local module_root, loads = "scripts/mods/" .. dir .. "/", {}
        local enabled = parity ~= false
        local mod = { get = function(_, key)
            if key == "wt_history_kruber_sword_and_shield" then return state or "5_1_1" end
            return "current"
        end, _wt431_profiles_allowed = function() return enabled end }
        local canonical, calls
        calls = 0
        mod.dofile = function(_, name)
            loads[name] = (loads[name] or 0) + 1
            local value = c.T.run(reader(root .. "/" .. dir .. "/" .. name .. ".lua"), c.env, name)
            if name ~= module_root .. "_wt_history_catalog" then return value end
            canonical = value
            return { load = function(actual_mod)
                H.truthy(rawequal(actual_mod, mod)); calls = calls + 1
                local original, problem = canonical.load(actual_mod,
                    { module_root .. "_wt_history_5_2_catalog", module_root .. "_wt_history_6_0_catalog" })
                H.truthy(original, problem)
                local family
                for _, row in ipairs(original.families) do if row.id == "kruber_sword_and_shield" then family = row end end
                H.truthy(family)
                local selected = {}; for key, field in next, original do selected[key] = field end
                selected.families, selected.profile_specs, selected.derived_profiles = { family }, {}, {}
                selected.states = {}
                for _, state_id in ipairs(family.state_order) do
                    selected.states[state_id], selected.profile_specs[state_id] = original.states[state_id], {}
                    H.equal(#family.states[state_id].profile_names, 0)
                    H.equal(#family.states[state_id].direct_profile_names, 0)
                end
                return canonical.merge({ selected })
            end }
        end
        mods[id] = mod
        local source = reader(root .. "/" .. dir .. "/" .. module_root .. dir .. ".lua")
        local start = assert(source:find("local _wt_history_owner, _wt_history_verify = mod:dofile(", 1, true))
        local ending = "local _wt_history_runtime = _wt_history_owner.runtime"
        local stop = assert(source:find(ending, start, true)) + #ending
        local invoke = c.T.run("return function(mod)\n" .. source:sub(start, stop)
            .. "\nreturn _wt_history_owner, _wt_history_verify, _wt_history_runtime end", c.env,
            "actual-finite-Elven-WT-Owner-publication")
        local owner, verify, runtime = invoke(mod)
        H.truthy(owner); H.truthy(rawequal(owner.runtime, runtime))
        H.truthy(rawequal(rawget(mod, "_wt_history_runtime"), runtime))
        H.equal(runtime.fatal_error, nil); H.equal(runtime.last_error, nil); H.equal(verify(), nil)
        H.equal(runtime.registration.count, 0); H.equal(calls, 1)
        records[id] = { mod = mod, owner = owner, verify = verify, runtime = runtime, loads = loads,
            set_parity = function(value) enabled = value end }
        return records[id]
    end
    local c = F.new(H, root, { get_mod = resolver, prior = options.prior, options = options.construction_options,
        after_prepare = options.after_prepare,
        before = function(context)
            if options.before then options.before(context, function(id, state, parity) return install(context, id, state, parity) end, mods) end
        end })
    c.history_mods, c.histories = mods, records
    c.install_history = function(id, state, parity) return install(c, id, state, parity) end
    return c
end
function M.admitted(H, c)
    for _, row in ipairs(c.ess_items()) do
        H.truthy(row.item, row.def.item_key .. " actual item"); H.truthy(row.seed, row.def.item_key .. " actual seed")
    end
    H.equal(c.ess_owner.check(), nil)
end
function M.denied(H, c)
    for _, row in ipairs(c.ess_items()) do H.equal(row.item, nil); H.equal(row.seed, nil) end
    H.truthy(c.ess_owner.check())
end
return M
