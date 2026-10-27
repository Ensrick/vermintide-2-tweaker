-- _cwv_javelin_history_envelope.lua -- Seven native Javelin history routes.
--
-- Delegates these finite scalars to the real WT runtime and raw route ledger,
-- not to a setting or prefix. Historical combat bodies remain WT authority;
-- no writer-origin/cryptographic/body-safety attestation is claimed. Only a
-- detached clone is normalized; all other donor cells remain graph-owned.
-- Owned by: character_weapon_variants.lua entry point.
-- Consumed via: one manifest load and private fifth construction-factory bind.
local M = {}
local DONOR, FAMILY, SETTING, STATE = "javelin_template", "javelin", "wt_history_javelin", "5_1_1"
local NAMES = { "heavy_javelin_smiter_stab_bleed", "medium_javelin_smiter_stab", "medium_javelin_smiter_stab_bleed", "thrown_javelin" }
local ROUTES = {
    { "chain_stab_01", "medium_javelin_smiter_stab" },
    { "chain_stab_02", "medium_javelin_smiter_stab" },
    { "chain_stab_03", "medium_javelin_smiter_stab_bleed" },
    { "heavy_stab", "heavy_javelin_smiter_stab_bleed" },
    { "stab_01", "medium_javelin_smiter_stab" },
    { "stab_02", "medium_javelin_smiter_stab" },
    { "throw_charged", "thrown_javelin", "impact_data" },
}
function M.bind(graph, producer)
    local capture, intact, disjoint = assert(graph.capture), assert(graph.intact), assert(graph.disjoint)
    local make_binding, binding_intact, resolve = assert(producer.capture_runtime), assert(producer.intact_runtime), assert(producer.resolve)
    local plain, dense = assert(producer.plain), assert(producer.dense)
    local function pair(lookup, name, id)
        return type(id) == "number" and id > 0 and id % 1 == 0
            and rawget(lookup, name) == id and rawget(lookup, id) == name
    end
    local function binding(p, mod, runtime)
        local b = make_binding(mod, runtime)
        if not b then return nil end
        local family = rawget(b.families, FAMILY)
        if not plain(family) or rawget(family, "id") ~= FAMILY or rawget(family, "setting_id") ~= SETTING then return nil end
        local templates, states = rawget(family, "templates"), rawget(family, "states")
        local state = plain(states) and rawget(states, STATE)
        if dense(templates, 1) ~= 1 or rawget(templates, 1) ~= DONOR or not plain(state)
                or dense(rawget(state, "operations"), 0) ~= 0 then return nil end
        for _, field in ipairs({ "profile_names", "direct_profile_names" }) do
            local names = rawget(state, field)
            if dense(names, 4) ~= 4 then return nil end
            for index, name in ipairs(NAMES) do if rawget(names, index) ~= name then return nil end end
        end
        local count, found = dense(b.list, 128), 0
        for index = 1, count do if rawequal(rawget(b.list, index), family) then found = found + 1 end end
        local mapping = rawget(rawget(b.registration, "private_by_state_name"), STATE)
        local all_specs = rawget(b.catalog, "profile_specs")
        local specs = plain(all_specs) and rawget(all_specs, STATE)
        if found ~= 1 or not plain(mapping) or not plain(specs) then return nil end
        b.family, b.family_snapshot, b.mapping, b.specs = family, capture(family, 128, 1024), mapping, specs
        b.specs_snapshot, b.rows = capture(specs, 4096, 32768), {}
        if not b.family_snapshot or not b.specs_snapshot then return nil end
        for _, native in ipairs(NAMES) do
            local name, spec = rawget(mapping, native), rawget(specs, native)
            local profile = type(name) == "string" and rawget(p.profiles, name)
            local id = type(name) == "string" and rawget(p.lookup, name)
            if not plain(spec) or rawget(spec, "private_name") ~= name or rawget(spec, "native_name") ~= native
                    or type(profile) ~= "table" or not pair(p.lookup, name, id) or rawget(b.fallback, name) ~= native then return nil end
            b.rows[native] = { name = name, profile = profile, meta = getmetatable(profile), id = id }
        end
        return b
    end
    local function bound(p, b)
        if not binding_intact(b, p.weapons) or not rawequal(rawget(b.families, FAMILY), b.family)
                or not intact(b.family_snapshot) or not intact(b.specs_snapshot)
                or not rawequal(rawget(rawget(b.catalog, "profile_specs"), STATE), b.specs)
                or not rawequal(rawget(rawget(b.registration, "private_by_state_name"), STATE), b.mapping) then return false end
        local found = 0
        for index = 1, dense(b.list, 128) do if rawequal(rawget(b.list, index), b.family) then found = found + 1 end end
        if found ~= 1 then return false end
        for _, native in ipairs(NAMES) do
            local row = b.rows[native]
            if rawget(b.mapping, native) ~= row.name or not rawequal(rawget(p.profiles, row.name), row.profile)
                    or not rawequal(getmetatable(row.profile), row.meta) or not pair(p.lookup, row.name, row.id)
                    or rawget(b.fallback, row.name) ~= native then return false end
        end
        return true
    end
    local ROW_KEYS = { applied_snapshot = true, applied_value = true, key = true, operation = true,
        original_present = true, original_value = true, owner_object = true, parent = true,
        root_name = true, root_object = true, template_name = true }
    local OP_KEYS = { expected_current = true, expected_present = true, family_id = true, path = true,
        result = true, result_present = true, root = true, state_id = true, synthetic_profile_route = true, template = true }
    local function active_routes(p, b, ledger, active)
        if dense(ledger, 7) ~= 7 or not plain(active) or rawget(active, "state") ~= STATE
                or type(rawget(active, "parity")) ~= "boolean" or rawget(rawget(b.runtime, "boot_selections"), SETTING) ~= STATE then return false end
        for key in next, active do if key ~= "state" and key ~= "parity" then return false end end
        local seen = {}
        for index = 1, 7 do
            local row = rawget(ledger, index)
            if not plain(row) then return false end
            for key in next, row do if not ROW_KEYS[key] then return false end end
            local operation = rawget(row, "operation")
            if not plain(operation) then return false end
            for key in next, operation do if not OP_KEYS[key] then return false end end
            local route
            for _, candidate in ipairs(p.routes) do if rawequal(rawget(row, "parent"), candidate.parent) then route = candidate; break end end
            if not route or seen[route] then return false end
            seen[route] = true
            local path, native = rawget(operation, "path"), route.native
            if dense(path, 5) ~= #route.path then return false end
            for n, key in ipairs(route.path) do if rawget(path, n) ~= key then return false end end
            local value = rawget(active, "parity") and b.rows[native].name or native
            if not rawequal(rawget(row, "root_object"), p.weapons) or not rawequal(rawget(row, "owner_object"), p.source)
                    or rawget(row, "key") ~= "damage_profile" or rawget(row, "root_name") ~= "Weapons"
                    or rawget(row, "template_name") ~= DONOR or rawget(row, "original_present") ~= true
                    or rawget(row, "original_value") ~= native or rawget(row, "applied_value") ~= value
                    or rawget(row, "applied_snapshot") ~= value or rawget(route.parent, "damage_profile") ~= value
                    or rawget(operation, "expected_current") ~= native or rawget(operation, "expected_present") ~= true
                    or rawget(operation, "result") ~= native or rawget(operation, "result_present") ~= true
                    or rawget(operation, "family_id") ~= FAMILY or rawget(operation, "state_id") ~= STATE
                    or rawget(operation, "root") ~= "Weapons" or rawget(operation, "template") ~= DONOR
                    or rawget(operation, "synthetic_profile_route") ~= true then return false end
        end
        local ok, problem = pcall(b.verify)
        return ok and problem == nil
    end
    local function valid(p)
        if not p or not rawequal(rawget(p.weapons, DONOR), p.source)
                or not rawequal(getmetatable(p.profiles), p.profiles_meta)
                or not rawequal(getmetatable(p.lookup), p.lookup_meta) then return false end
        local native = true
        for _, route in ipairs(p.routes) do
            local parent = p.source
            for index = 1, #route.path - 1 do
                parent = type(parent) == "table" and rawget(parent, route.path[index])
                if not rawequal(parent, route.parents[index]) or not rawequal(getmetatable(parent), route.metas[index]) then return false end
            end
            if rawget(route.parent, "damage_profile") ~= route.native then native = false end
        end
        local authorized = false
        for _, id in ipairs({ "wt", "wt_dev" }) do
            local ok, mod = resolve(id)
            local prior = p.bindings[id]
            if ok and mod ~= nil then
                if type(mod) ~= "table" or (prior and not rawequal(prior.mod, mod)) then return false end
                local runtime = rawget(mod, "_wt_history_runtime")
                if runtime ~= nil then
                    local b = prior or binding(p, mod, runtime)
                    if not b or not bound(p, b) then return false end
                    if not prior then p.bindings[id] = b end
                    local ledger, active = rawget(rawget(runtime, "ledgers"), FAMILY), rawget(rawget(runtime, "active"), FAMILY)
                    local boot = rawget(rawget(runtime, "boot_selections"), SETTING)
                    if boot ~= "current" and boot ~= STATE then return false end
                    if active ~= nil or (ledger ~= nil and dense(ledger, 0) ~= 0) then
                        if not active_routes(p, b, ledger, active) then return false end
                        authorized = true
                    elseif not native then return false end
                elseif prior then return false end
            end
        end
        -- Exact native values also cover actual restore/removal. WT leaves its
        -- boot selection historical after restore; requiring verify=nil there
        -- would reject this supported state. Non-native values need a ledger.
        return native or authorized
    end
    local function make(source, weapons, profiles, lookup)
        if type(source) ~= "table" or type(weapons) ~= "table" or type(profiles) ~= "table" or type(lookup) ~= "table" then return nil end
        local nodes = capture(source, 4096, 32768)
        if not nodes then return nil end
        local p = { source = source, weapons = weapons, profiles = profiles, lookup = lookup, nodes = nodes,
            profiles_meta = getmetatable(profiles), lookup_meta = getmetatable(lookup), routes = {}, bindings = {} }
        for _, row in ipairs(ROUTES) do
            local path = { "actions", "action_one", row[1] }
            if row[3] then path[#path + 1] = row[3] end
            path[#path + 1] = "damage_profile"
            local parent, parents, metas = source, {}, {}
            for index = 1, #path - 1 do
                parent = type(parent) == "table" and rawget(parent, path[index])
                if type(parent) ~= "table" then return nil end
                parents[index], metas[index] = parent, getmetatable(parent)
            end
            p.routes[#p.routes + 1] = { path = path, parent = parent, native = row[2], parents = parents, metas = metas }
        end
        if not valid(p) then return nil end
        return p
    end
    local function prepare_clone(p, template)
        if not valid(p) or type(template) ~= "table" or rawequal(template, p.source) then return false end
        local nodes = capture(template, 4096, 32768)
        if not nodes or not disjoint(p.nodes, nodes) then return false end
        local cells = {}
        for _, route in ipairs(p.routes) do
            local parent = template
            for index = 1, #route.path - 1 do parent = type(parent) == "table" and rawget(parent, route.path[index]) end
            if type(parent) ~= "table" or rawget(parent, "damage_profile") ~= rawget(route.parent, "damage_profile") then return false end
            cells[#cells + 1] = { parent, route.native }
        end
        for _, cell in ipairs(cells) do rawset(cell[1], "damage_profile", cell[2]) end
        for _, cell in ipairs(cells) do if rawget(cell[1], "damage_profile") ~= cell[2] then return false end end
        return valid(p)
    end
    return { capture = make, intact = valid, prepare_clone = prepare_clone, include = function(p, t, key)
        if key == "damage_profile" then for _, route in ipairs(p.routes) do if rawequal(t, route.parent) then return false end end end
        return true
    end }
end
return M
