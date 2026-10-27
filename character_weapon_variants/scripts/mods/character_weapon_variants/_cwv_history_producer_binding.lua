-- _cwv_history_producer_binding.lua -- Shared pure WT runtime-reference proof.
--
-- Owns only fixed WT discovery and captured runtime/catalog/policy/registration
-- identities, including shared fallback identity/meta and history-owned cells.
-- Family leaves own their different route/value/ledger semantics. No registry,
-- hook, loader, writer, graph recapture or gameplay-body attestation lives here.
-- Owned by: character_weapon_variants.lua entry point.
-- Consumed via: one manifest load, private core capture/return and value binds.
local M = {}
local function plain(value)
    return type(value) == "table" and getmetatable(value) == nil
end
local function dense(value, limit)
    if not plain(value) then return nil end
    local count = 0
    for key in next, value do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 or key > limit then return nil end
        count = count + 1
    end
    for index = 1, count do if rawget(value, index) == nil then return nil end end
    return count
end
function M.bind(graph, resolve_mod)
    local capture, intact = assert(graph.capture), assert(graph.intact)
    local function make(mod, runtime)
        if type(mod) ~= "table" or not plain(runtime) or not rawequal(rawget(runtime, "mod"), mod) then return nil end
        local catalog, policy, families = rawget(runtime, "catalog"), rawget(runtime, "policy"), rawget(runtime, "family_by_id")
        if not plain(catalog) or rawget(catalog, "schema") ~= 2 or rawget(catalog, "current_id") ~= "current"
                or not plain(policy) or not plain(families) or type(rawget(runtime, "verify")) ~= "function" then return nil end
        for _, key in ipairs({ "validate", "build_family_plan", "commit", "ledger_status", "restore", "deep_equal" }) do
            if type(rawget(policy, key)) ~= "function" then return nil end
        end
        local list, source = rawget(catalog, "families"), rawget(catalog, "current_source")
        if not dense(list, 128) or not plain(source)
                or rawget(source, "revision") ~= "93dea911a4cc464a0eb51cfdc3a443297bfc4550" then return nil end
        local registration, fallback = rawget(runtime, "registration"), rawget(mod, "_wt431_custom_profile_fallback")
        local policy_snapshot, registration_snapshot = capture(policy, 32, 256), capture(registration, 8192, 65536)
        local names = plain(registration) and rawget(registration, "names")
        local count = dense(names, 4096)
        if not policy_snapshot or not registration_snapshot or type(fallback) ~= "table" or count == nil
                or rawget(registration, "count") ~= count or not plain(rawget(registration, "private_by_state_name")) then return nil end
        local fallback_rows, seen = {}, {}
        for index = 1, count do
            local name = rawget(names, index)
            if type(name) ~= "string" or seen[name] then return nil end
            local native = rawget(fallback, name)
            if type(native) ~= "string" then return nil end
            seen[name] = true; fallback_rows[index] = { name, native }
        end
        return { mod = mod, mod_meta = getmetatable(mod), runtime = runtime, catalog = catalog, policy = policy,
            families = families, list = list, source = source, verify = rawget(runtime, "verify"),
            registration = registration, fallback = fallback, policy_snapshot = policy_snapshot,
            registration_snapshot = registration_snapshot, fallback_meta = getmetatable(fallback), fallback_rows = fallback_rows }
    end
    local function valid(b, weapons)
        local r, c = b.runtime, b.catalog
        if not plain(r) or not rawequal(getmetatable(b.mod), b.mod_meta)
                or not rawequal(rawget(b.mod, "_wt_history_runtime"), r) or not rawequal(rawget(r, "mod"), b.mod)
                or not rawequal(rawget(r, "catalog"), c) or not plain(c) or rawget(c, "schema") ~= 2 or rawget(c, "current_id") ~= "current"
                or not rawequal(rawget(c, "current_source"), b.source) or not plain(b.source)
                or rawget(b.source, "revision") ~= "93dea911a4cc464a0eb51cfdc3a443297bfc4550"
                or not rawequal(rawget(c, "families"), b.list) or not dense(b.list, 128)
                or not rawequal(rawget(r, "family_by_id"), b.families) or not plain(b.families)
                or not rawequal(rawget(r, "policy"), b.policy) or not intact(b.policy_snapshot)
                or not rawequal(rawget(r, "verify"), b.verify) or not rawequal(rawget(r, "registration"), b.registration)
                or not intact(b.registration_snapshot) or not rawequal(rawget(b.mod, "_wt431_custom_profile_fallback"), b.fallback)
                or not rawequal(getmetatable(b.fallback), b.fallback_meta) then return false end
        for _, row in ipairs(b.fallback_rows) do if rawget(b.fallback, row[1]) ~= row[2] then return false end end
        local roots, ledgers, active, boot = rawget(r, "roots"), rawget(r, "ledgers"), rawget(r, "active"), rawget(r, "boot_selections")
        return plain(roots) and rawequal(rawget(roots, "Weapons"), weapons)
            and plain(ledgers) and plain(active) and plain(boot)
    end
    return { capture_runtime = make, intact_runtime = valid, plain = plain, dense = dense,
        resolve = function(id)
            if (id ~= "wt" and id ~= "wt_dev") or type(resolve_mod) ~= "function" then return false, nil end
            return pcall(resolve_mod, id)
        end }
end
return M
