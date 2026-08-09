-- Pure exact-wire policy for Event Tweaker's managed Adventure curses.
--
-- The 11 curse names are vanilla, but their process-local numeric
-- NetworkLookup.mutator_templates ids can diverge when another mod changes
-- registration order. Package identity is equally load-bearing: every
-- managed template must retain its one authored mutator package before the
-- exact peer gate may authorize injection.

local M = {}

M.NAMESPACE = "event_tweaker.curse_mutator_templates.v1"

local function _expected_package(name)
    return "resource_packages/mutators/mutator_" .. name
end

local function _template_package_exact(name, templates)
    local template = type(templates) == "table" and rawget(templates, name)
    local packages = type(template) == "table" and rawget(template, "packages")
    if type(packages) ~= "table" then return false, "packages-missing:" .. name end

    local expected = _expected_package(name)
    local count = 0
    for key, package_name in pairs(packages) do
        count = count + 1
        if key ~= 1 or package_name ~= expected then
            return false, "packages-mismatch:" .. name
        end
    end
    if count ~= 1 then return false, "packages-mismatch:" .. name end
    return true
end

-- Returns an immutable proof snapshot used both as the exact transport
-- identity and as the allocation-free local-integrity floor at every later
-- injection/UI decision.
function M.capture(curses, templates, lookup, wire_catalog)
    if type(curses) ~= "table" or type(curses.MANAGED_CURSES) ~= "table"
            or type(lookup) ~= "table" or type(wire_catalog) ~= "table"
            or type(wire_catalog.build_identity) ~= "function" then
        return nil, "catalog-input-missing"
    end

    local entries, ids, count = {}, {}, 0
    for i = 1, #curses.MANAGED_CURSES do
        local name = curses.MANAGED_CURSES[i] and curses.MANAGED_CURSES[i].id
        if type(name) ~= "string" or name == "" or entries[name] then
            return nil, "managed-name-invalid-or-duplicate"
        end
        local packages_ok, packages_err = _template_package_exact(name, templates)
        if not packages_ok then return nil, packages_err end

        local id = rawget(lookup, name)
        if type(id) ~= "number" or id <= 0 or math.floor(id) ~= id
                or rawget(lookup, id) ~= name then
            return nil, "lookup-mismatch:" .. name
        end
        entries[name] = true
        ids[name] = id
        count = count + 1
    end
    if count ~= 11 then return nil, "managed-count-mismatch:" .. tostring(count) end

    local identity, identity_err, names = wire_catalog.build_identity(
        M.NAMESPACE, entries, lookup)
    if not identity then return nil, identity_err end
    if not names or #names ~= count then return nil, "identity-count-mismatch" end
    return { identity = identity, ids = ids, count = count }, nil
end

function M.integrity(curses, templates, lookup, proof)
    if type(curses) ~= "table" or type(curses.MANAGED_CURSES) ~= "table"
            or type(lookup) ~= "table" or type(proof) ~= "table"
            or type(proof.ids) ~= "table" or proof.count ~= 11 then
        return false, "proof-input-missing"
    end

    local count = 0
    for i = 1, #curses.MANAGED_CURSES do
        local name = curses.MANAGED_CURSES[i] and curses.MANAGED_CURSES[i].id
        if type(name) ~= "string" or name == "" then
            return false, "managed-name-invalid-or-duplicate"
        end
        -- This floor is read from the live selection path. Detect authored
        -- duplicates without allocating a new set on each decision.
        for prior = 1, i - 1 do
            if curses.MANAGED_CURSES[prior]
                    and curses.MANAGED_CURSES[prior].id == name then
                return false, "managed-name-invalid-or-duplicate"
            end
        end
        count = count + 1

        local id = rawget(proof.ids, name)
        if type(id) ~= "number" or rawget(lookup, name) ~= id
                or rawget(lookup, id) ~= name then
            return false, "lookup-drift:" .. name
        end
        local packages_ok, packages_err = _template_package_exact(name, templates)
        if not packages_ok then return false, packages_err end
    end
    if count ~= proof.count then return false, "managed-count-drift" end
    return true
end

-- Optional Mod Tweaker presentation bridge. Saved settings are never changed;
-- runtime injection remains protected independently when GUT is absent.
function M.runtime_gate_spec(mod_id, setting_ids, evaluate)
    if type(mod_id) ~= "string" or mod_id == ""
            or type(setting_ids) ~= "table" or type(evaluate) ~= "function" then
        return nil
    end
    local copied, seen = {}, {}
    for i = 1, #setting_ids do
        local setting_id = setting_ids[i]
        if type(setting_id) ~= "string" or setting_id == "" or seen[setting_id] then
            return nil
        end
        seen[setting_id] = true
        copied[#copied + 1] = setting_id
    end
    if #copied == 0 then return nil end
    return { mod_id = mod_id, setting_ids = copied, evaluate = evaluate }
end

function M.try_register_runtime_gate(get_mod_fn, gate_id, spec)
    if type(get_mod_fn) ~= "function" or type(gate_id) ~= "string"
            or gate_id == "" or type(spec) ~= "table" then
        return false, "runtime-gate-arguments-invalid"
    end
    for _, gut_id in ipairs({ "gut_dev", "gut" }) do
        local ok, gut = pcall(get_mod_fn, gut_id)
        local tweaker = ok and type(gut) == "table" and gut.mod_tweaker or nil
        if type(tweaker) == "table"
                and type(tweaker.register_runtime_gate) == "function" then
            local ok_register, registered = pcall(
                tweaker.register_runtime_gate, tweaker, gate_id, spec)
            if ok_register and registered == true then return true end
            -- A malformed optional dev GUI must not prevent the stable alias
            -- from owning presentation. The gameplay floor remains independent.
        end
    end
    return false, "mod-tweaker-unavailable"
end

return M
