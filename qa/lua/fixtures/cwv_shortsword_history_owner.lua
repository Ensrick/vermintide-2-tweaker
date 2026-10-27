-- Actual complete WT Owner + runtime publication with one selected catalog.
-- The QA-only facade uses existing Catalog.load(mod,{path}); it does not claim
-- default all13-catalog/native-profile registration or whole-entry/VMF ABI.
local M = {}
local function read(path)
    local file = assert(io.open(path, "rb")); local text = file:read("*a"); file:close()
    return text:gsub("\r\n", "\n")
end
function M.new(H, root, options)
    options = options or {}
    local F = dofile(root .. "/qa/lua/fixtures/cwv_shortsword_construction_harness.lua")
    local reader, mods, records = options.read_source or read, {}, {}
    local function resolver(id)
        if options.resolve then return options.resolve(id, mods) end
        return rawget(mods, id)
    end
    local function install(c, id, state)
        assert(id == "wt" or id == "wt_dev", "fixed real WT identity")
        local dir = id == "wt" and "weapon_tweaker" or "weapon_tweaker_dev"
        local module_root = "scripts/mods/" .. dir .. "/"
        local mod = { get = function(_, key)
            if key == "wt_history_sienna_dagger" then return state or "6_11_1" end
            return "current"
        end, _wt431_profiles_allowed = function() return false end }
        local loads, canonical, selected_calls = {}, nil, 0
        mod.dofile = function(_, path)
            loads[path] = (loads[path] or 0) + 1
            local value = c.T.run(reader(root .. "/" .. dir .. "/" .. path .. ".lua"), c.env, path)
            if path == module_root .. "_wt_history_catalog" then
                canonical = value
                return { load = function(actual_mod)
                    H.truthy(rawequal(actual_mod, mod)); selected_calls = selected_calls + 1
                    local catalog, problem = canonical.load(actual_mod, { module_root .. "_wt_history_6_11_2_catalog" })
                    if not catalog then return nil, problem end
                    if options.project_catalog then return options.project_catalog(c, canonical, catalog, mod, module_root) end
                    return canonical.merge({ catalog })
                end }
            end
            return value
        end
        mods[id] = mod
        local source = reader(root .. "/" .. dir .. "/scripts/mods/" .. dir .. "/" .. dir .. ".lua"):gsub("\r\n", "\n")
        local marker = "local _wt_history_owner, _wt_history_verify = mod:dofile("
        local start = assert(source:find(marker, 1, true), "real entry owner expression absent")
        local ending = "local _wt_history_runtime = _wt_history_owner.runtime"
        local stop = assert(source:find(ending, start, true)) + #ending
        local complete = source:sub(start, stop)
        local invoke = c.T.run("return function(mod)\n" .. complete
            .. "\nreturn _wt_history_owner, _wt_history_verify, _wt_history_runtime end", c.env, "actual-WT-entry-history-install")
        local owner, verify, runtime = invoke(mod)
        H.truthy(owner); H.equal(owner.runtime, runtime); H.equal(rawget(mod, "_wt_history_runtime"), runtime)
        H.equal(runtime.fatal_error, nil); H.equal(runtime.last_error, nil); H.equal(verify(), nil)
        H.equal(runtime.registration.count, options.expected_registration_count or 0); H.equal(selected_calls, 1)
        H.equal(loads[module_root .. "_wt_history_owner"], 1)
        H.equal(loads[module_root .. "_wt_history_catalog"], 1)
        records[id] = { mod = mod, owner = owner, verify = verify, runtime = runtime, loads = loads,
            canonical = canonical, entry_expression = complete, selected_catalog_calls = selected_calls }
        return records[id]
    end
    local c = F.new(H, root, { read_source = reader, get_mod = resolver,
        before_core = function(context)
            if options.before then options.before(context, function(id, state) return install(context, id, state) end, mods) end
        end,
        options = options.construction_options,
    })
    c.history_mods, c.histories = mods, records
    c.install_history = function(id, state) return install(c, id, state) end
    return c
end
function M.admitted(H, c)
    local _, item, seed = c.items()
    local verdict = c.owner.check()
    H.truthy(item and seed, "actual Shortsword private item AND acquisition seed: " .. tostring(verdict))
    H.equal(c.owner.check(), nil)
    return item, seed
end
function M.denied(H, c)
    local _, item, seed = c.items()
    H.equal(item, nil, "actual Shortsword item denied"); H.equal(seed, nil, "actual Shortsword seed denied")
    H.truthy(c.owner.check())
end
return M
