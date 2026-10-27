-- _wt_history_profile_transaction.lua -- Atomic local historical profile publication.
--
-- Owns the sorted historical profile/lookup/fallback batch and its retained proof.
-- The ordered entry manifest loads this pure module once and injects it privately
-- through the history owner. It loads no modules and installs no hook or command.
-- Local tuple ownership does not establish peer parity or network capacity.
--
-- Owned by: Weapon Tweaker public/Dev entry point.
-- Consumed via: entry mod:dofile("scripts/mods/weapon_tweaker/_wt_history_profile_transaction") and private history-owner config.
local M = {}
local FALLBACK = "_wt431_custom_profile_fallback"
local installed = setmetatable({}, { __mode = "k" })
-- Reuse only objects this module actually published, never merely equal rows.
local published = setmetatable({}, { __mode = "k" })

local function copy(value, active)
    if type(value) ~= "table" then return value end
    active = active or {}; assert(not active[value], "profile-cycle")
    assert(getmetatable(value) == nil, "profile-metatable")
    active[value] = true
    local result = {}
    for key, item in next, value do
        assert(type(key) == "string" or type(key) == "number", "profile-key")
        result[key] = copy(item, active)
    end
    active[value] = nil
    return result
end

local function shallow(value)
    local result = {}; for key, item in next, value do result[key] = item end
    return result
end

local function same(left, right)
    for key, item in next, left do if rawget(right, key) ~= item then return false end end
    for key in next, right do if rawget(left, key) == nil then return false end end
    return true
end

local function snapshot(target)
    return { target = target, fields = shallow(target), meta = getmetatable(target) }
end

local function restore(before)
    local target = before.target
    for key in next, target do rawset(target, key, nil) end
    for key, item in next, before.fields do rawset(target, key, item) end
    if getmetatable(target) ~= before.meta then setmetatable(target, before.meta) end
end

function M.install(mod, catalog, policy, dependencies)
    local deps = dependencies or {}
    local globals, read, write = deps.globals or _G, deps.read or rawget, deps.write or rawset
    local helper = deps.lookup
    local register = type(helper) == "table" and rawget(helper, "register")
    local equal = type(policy) == "table" and rawget(policy, "deep_equal")
    local retained = installed[mod]
    if retained then
        local ok, ready = pcall(retained.validate)
        if ok and ready and retained.catalog == catalog then
            return retained.registration, retained.validate
        end
        return nil, nil, "retained history registration lost"
    end

    local ok, plan = pcall(function()
        assert(type(register) == "function", "history lookup helper missing")
        assert(type(equal) == "function", "history comparison policy missing")
        local profiles, network = read(globals, "DamageProfileTemplates"), read(globals, "NetworkLookup")
        assert(type(profiles) == "table" and type(network) == "table", "history registries unavailable")
        local lookup = read(network, "damage_profiles")
        assert(type(lookup) == "table", "history lookup unavailable")
        local fallback = rawget(mod, FALLBACK)
        assert(fallback ~= nil or mod[FALLBACK] == nil, "history fallback inherited")
        assert(fallback == nil or type(fallback) == "table", "history fallback malformed")
        local prepared, mapping, natives = {}, {}, {}
        local function add(state_id, native_name, spec, profile)
            assert(prepared[spec.private_name] == nil, "duplicate private profile")
            profile.name = spec.private_name
            prepared[spec.private_name] = { profile = profile, native = native_name }
            mapping[state_id] = mapping[state_id] or {}
            mapping[state_id][native_name] = spec.private_name
            natives[native_name] = true
        end
        for state_id, specs in pairs(catalog.profile_specs or {}) do
            for native_name, spec in pairs(specs) do
                assert(type(rawget(profiles, native_name)) == "table", "native profile unavailable " .. native_name)
                add(state_id, native_name, spec, copy(spec.historical_profile))
            end
        end
        for state_id, specs in pairs(catalog.derived_profiles or {}) do
            for native_name, spec in pairs(specs) do
                local source = mapping[state_id] and mapping[state_id][spec.source_profile]
                assert(source and prepared[source] and spec.derivation == "native_no_damage_clone", "derived profile source unavailable " .. native_name)
                local profile = copy(prepared[source].profile)
                for _, target in ipairs(profile.targets or {}) do
                    local distribution = type(target) == "table" and target.power_distribution
                    if type(distribution) == "table" and distribution.attack ~= nil then distribution.attack = 0 end
                end
                local distribution = profile.default_target and profile.default_target.power_distribution
                if type(distribution) == "table" and distribution.attack ~= nil then distribution.attack = 0 end
                add(state_id, native_name, spec, profile)
            end
        end
        local names = {}; for name in pairs(prepared) do names[#names + 1] = name end; table.sort(names)
        local before, shadow = shallow(lookup), shallow(lookup)
        -- The unchanged primitive validates the entire raw lookup even for an existing native pair.
        for native in pairs(natives) do
            local index, inserted = register(shadow, native)
            assert(index and inserted == false and rawget(profiles, native), "native pair unavailable " .. native)
        end
        local rows = {}
        for _, name in ipairs(names) do
            local row = prepared[name]
            local existing = rawget(profiles, name)
            local old_index = rawget(before, name)
            local old_fallback = fallback and rawget(fallback, name)
            local proof = type(existing) == "table" and published[existing]
            if existing ~= nil or old_index ~= nil or old_fallback ~= nil then
                assert(proof and proof.lookup == lookup and proof.index == old_index
                    and proof.native == row.native and equal(proof.expected, row.profile)
                    and (old_fallback == nil or old_fallback == row.native), "private history tuple partial or foreign " .. name)
                row.profile = existing
            end
            local index, inserted = register(shadow, name)
            assert(type(index) == "number" and index > 0 and index % 1 == 0
                and rawget(shadow, name) == index and rawget(shadow, index) == name
                and inserted == (old_index == nil), "history lookup plan rejected " .. name)
            row.index, row.name, row.expected = index, name, copy(prepared[name].profile)
            rows[#rows + 1] = row
        end
        local stripped = shallow(shadow)
        for _, row in ipairs(rows) do
            if rawget(before, row.name) == nil then rawset(stripped, row.name, nil); rawset(stripped, row.index, nil) end
        end
        assert(same(stripped, before), "history lookup plan changed foreign rows")
        return { profiles=profiles, network=network, lookup=lookup, before=before,
            fallback=fallback or {}, fallback_before=fallback, rows=rows, names=names,
            mapping=mapping, mapping_before=copy(mapping), profiles_meta=getmetatable(profiles),
            lookup_meta=getmetatable(lookup), fallback_meta=fallback and getmetatable(fallback) }
    end)
    if not ok then return nil, nil, tostring(plan) end

    local ready = false
    local registration = { count=#plan.names, names=plan.names, private_by_state_name=plan.mapping }
    local names_before = shallow(plan.names)
    local function authority()
        if not ready or read(globals, "DamageProfileTemplates") ~= plan.profiles
            or read(globals, "NetworkLookup") ~= plan.network or read(plan.network, "damage_profiles") ~= plan.lookup
            or rawget(mod, FALLBACK) ~= plan.fallback or getmetatable(plan.profiles) ~= plan.profiles_meta
            or getmetatable(plan.lookup) ~= plan.lookup_meta or getmetatable(plan.fallback) ~= plan.fallback_meta
            or registration.count ~= #plan.rows or registration.names ~= plan.names
            or registration.private_by_state_name ~= plan.mapping or not same(plan.names, names_before)
            or not equal(plan.mapping, plan.mapping_before)
            or rawget(helper,"register") ~= register then return false end
        local shadow = shallow(plan.lookup)
        for _, row in ipairs(plan.rows) do
            -- Combat contents remain mutable for later tuning; tuple identity is immutable.
            if rawget(plan.profiles, row.name) ~= row.profile or rawget(plan.fallback, row.name) ~= row.native then return false end
            local index, inserted = register(shadow, row.name)
            if index ~= row.index or inserted ~= false then return false end
            local native_index = rawget(plan.lookup, row.native)
            if type(native_index) ~= "number" or rawget(plan.lookup, native_index) ~= row.native
                or type(rawget(plan.profiles, row.native)) ~= "table" then return false end
        end
        return same(shadow, plan.lookup)
    end
    local validate = function() local safe, value = pcall(authority); return safe and value == true end
    local snapshots = { snapshot(plan.profiles), snapshot(plan.lookup), snapshot(plan.fallback), snapshot(mod) }
    local committed, problem = pcall(function()
        local function put(target, key, value)
            write(target, key, value); assert(rawget(target, key) == value, "history write discarded")
        end
        for _, row in ipairs(plan.rows) do
            if rawget(plan.profiles, row.name) == nil then put(plan.profiles, row.name, row.profile) end
            if rawget(plan.lookup, row.name) == nil then
                put(plan.lookup, row.index, row.name); put(plan.lookup, row.name, row.index)
            end
            put(plan.fallback, row.name, row.native)
            assert(equal(row.profile, row.expected), "history profile content readback failed")
        end
        put(mod, FALLBACK, plan.fallback)
        ready = true
        assert(authority(), "history tuple readback failed")
    end)
    if not committed then
        ready = false
        for index=#snapshots,1,-1 do restore(snapshots[index]) end
        return nil, nil, tostring(problem)
    end
    for _, row in ipairs(plan.rows) do
        if not published[row.profile] then
            published[row.profile] = { lookup=plan.lookup, index=row.index, native=row.native, expected=row.expected }
        end
    end
    installed[mod] = { catalog=catalog, registration=registration, validate=validate }
    return registration, validate
end

return M
