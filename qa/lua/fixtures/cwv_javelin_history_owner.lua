-- Complete real WT Owner/runtime publication, one verbatim projected family.
-- Existing Catalog.load/merge owns selection. This is not all13 registration,
-- full WT entry, peer parity, native callback ABI or historical-math execution.
local M = {}
local function read(path)
    local file = assert(io.open(path, "rb")); local text = file:read("*a"); file:close()
    return (text:gsub("\r\n", "\n"))
end
function M.new(H, root, options)
    options = options or {}
    local F = dofile(root .. "/qa/lua/fixtures/cwv_javelin_construction_harness.lua")
    local reader, mods, records = options.read_source or read, {}, {}
    local function resolver(id)
        if options.resolve then return options.resolve(id, mods) end
        return rawget(mods, id)
    end
    local function install(c, id, state, parity)
        assert(id == "wt" or id == "wt_dev")
        local dir = id == "wt" and "weapon_tweaker" or "weapon_tweaker_dev"
        local module_root, loads, selected_calls = "scripts/mods/" .. dir .. "/", {}, 0
        local allowed = parity ~= false
        local mod = { get = function(_, key)
            if key == "wt_history_javelin" then return state or "5_1_1" end
            return "current"
        end, _wt431_profiles_allowed = function() return allowed end }
        local canonical
        mod.dofile = function(_, path)
            loads[path] = (loads[path] or 0) + 1
            local value = c.T.run(reader(root .. "/" .. dir .. "/" .. path .. ".lua"), c.env, path)
            if path == module_root .. "_wt_history_catalog" then
                canonical = value
                return { load = function(actual_mod)
                    H.truthy(rawequal(actual_mod, mod)); selected_calls = selected_calls + 1
                    local original, problem = canonical.load(actual_mod, { module_root .. "_wt_history_5_2_catalog" })
                    if not original then return nil, problem end
                    local family
                    for _, row in ipairs(original.families) do if row.id == "javelin" then family = row end end
                    H.truthy(family); H.equal(#family.states["5_1_1"].operations, 0)
                    local projected = {}
                    for key, item in next, original do projected[key] = item end
                    projected.families, projected.states = { family }, { ["5_1_1"] = original.states["5_1_1"] }
                    projected.profile_specs, projected.derived_profiles = { ["5_1_1"] = {} }, {}
                    for _, name in ipairs(family.states["5_1_1"].profile_names) do
                        projected.profile_specs["5_1_1"][name] = assert(original.profile_specs["5_1_1"][name])
                    end
                    H.truthy(rawequal(projected.families[1], family))
                    return canonical.merge({ projected })
                end }
            end
            return value
        end
        mods[id] = mod
        local source = reader(root .. "/" .. dir .. "/" .. module_root .. dir .. ".lua"):gsub("\r\n", "\n")
        local start = assert(source:find("local _wt_history_owner, _wt_history_verify = mod:dofile(", 1, true))
        local ending = "local _wt_history_runtime = _wt_history_owner.runtime"
        local stop = assert(source:find(ending, start, true)) + #ending
        local invoke = c.T.run("return function(mod)\n" .. source:sub(start, stop)
            .. "\nreturn _wt_history_owner, _wt_history_verify, _wt_history_runtime end", c.env, "actual-WT-Javelin-owner-expression")
        local owner, verify, runtime = invoke(mod)
        H.truthy(owner); H.equal(owner.runtime, runtime); H.equal(rawget(mod, "_wt_history_runtime"), runtime)
        H.equal(runtime.fatal_error, nil); H.equal(runtime.last_error, nil); H.equal(verify(), nil)
        H.equal(runtime.registration.count, 4); H.equal(selected_calls, 1)
        H.equal(loads[module_root .. "_wt_history_owner"], 1)
        H.equal(loads[module_root .. "_wt_history_catalog"], 1)
        local row = { mod = mod, owner = owner, runtime = runtime, verify = verify, loads = loads,
            canonical = canonical, set_parity = function(value) allowed = value end }
        records[id] = row
        return row
    end
    local c = F.new(H, root, { get_mod = resolver, options = options.construction_options, prior = options.prior,
        owner = options.construction_owner,
        before = function(context)
            if options.before then options.before(context, function(id, state, parity) return install(context, id, state, parity) end, mods) end
        end })
    c.history_mods, c.histories = mods, records
    c.install_history = function(id, state, parity) return install(c, id, state, parity) end
    return c
end
local function entries(H, c, expected)
    -- Install the real singleton bootstrap once, then reuse its actual builder.
    -- Calling c.items() for every retained check would re-register its hook.
    if not c.history_item_binding then c.history_item_binding = { c.items() } end
    local definitions, build = c.history_item_binding[1], c.history_item_binding[2]
    local count = 0
    for _, def in ipairs(definitions) do
        if def.item_key == "cwv_es_javelin" or def.item_key == "cwv_wh_javelin" then
            count = count + 1
            local item = build(def)
            local seed = c.mod._cwv_acquisition.build_seed(def, build,
                function(value) return c.env.table.clone(value, true) end, function() return false end)
            H.equal(item ~= nil, expected, def.item_key .. " actual private item admission")
            H.equal(seed ~= nil, expected, def.item_key .. " actual acquisition seed admission")
        end
    end
    H.equal(count, 2)
    if expected then H.equal(c.owner.check(), nil) else H.truthy(c.owner.check()) end
end
function M.admitted(H, c) entries(H, c, true) end
function M.denied(H, c) entries(H, c, false) end
return M
