-- Pure schema, planning, and exact-restore policy for issue #1436.
--
-- No game globals, hooks, RPCs, or settings are read here. Every selected
-- family is fully preflighted before one write occurs. Restore retains the
-- exact original value references (including absence), so turning the mod off
-- cannot replace table-valued native leaves with merely equal clones.
local M = {}

local ALLOWED_ROOTS = {
    BuffTemplates = true,
    ExplosionTemplates = true,
    PlayerUnitStatusSettings = true,
    VortexTemplates = true,
    Weapons = true,
}
local ALLOWED_AUTHORITIES = {
    server = true,
}
local ALLOWED_CHANGE_CLASSES = {
    official_weapon_balance = true,
    source_anchor_drift = true,
}

local function deep_clone(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local copy = {}
    seen[value] = copy
    for key, nested in pairs(value) do
        copy[deep_clone(key, seen)] = deep_clone(nested, seen)
    end
    return copy
end

-- Presence cannot use Lua's `and/or` value-selection idiom: a present false
-- leaf would collapse to nil. Applied values and ownership snapshots call this
-- separately so table results remain independent clones.
local function clone_if_present(present, value)
    if present then
        return deep_clone(value)
    end
    return nil
end

-- Original values are retained by exact reference for rollback/restore. This
-- branch preserves both a present false scalar and native table identity.
local function original_if_present(present, value)
    if present then
        return value
    end
    return nil
end

local function deep_equal(left, right, seen)
    if left == right then return true end
    if type(left) ~= type(right) or type(left) ~= "table" then return false end
    seen = seen or {}
    seen[left] = seen[left] or {}
    if seen[left][right] then return true end
    seen[left][right] = true
    for key, value in pairs(left) do
        if not deep_equal(value, rawget(right, key), seen) then return false end
    end
    for key in pairs(right) do
        if rawget(left, key) == nil then return false end
    end
    return true
end

local function array_length(value)
    if type(value) ~= "table" then return nil end
    local count, maximum = 0, 0
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then return nil end
        count = count + 1
        maximum = math.max(maximum, key)
    end
    if count ~= maximum then return nil end
    return count
end

local function pure_data(value, active)
    local kind = type(value)
    if kind == "nil" or kind == "boolean" or kind == "number" or kind == "string" then
        return true
    end
    if kind ~= "table" or getmetatable(value) ~= nil then return false end
    active = active or {}
    if active[value] then return false end
    active[value] = true
    for key, nested in pairs(value) do
        if not pure_data(key, active) or not pure_data(nested, active) then
            active[value] = nil
            return false
        end
    end
    active[value] = nil
    return true
end

local function full_hash(value)
    return type(value) == "string" and #value == 40
        and value:match("^[0-9a-f]+$") ~= nil
end

local function safe_name(value)
    return type(value) == "string" and value ~= "" and #value <= 96
        and value:match("^[%w_%.:%-]+$") ~= nil
end

local function path_text(path)
    local parts = {}
    for index = 1, #path do parts[index] = tostring(path[index]) end
    return table.concat(parts, ".")
end

local function target_key(operation)
    return operation.root .. "/" .. tostring(operation.template or "<root>")
        .. "/" .. path_text(operation.path)
end

local function path_is_prefix(left, right)
    if #left >= #right then return false end
    for index = 1, #left do
        if left[index] ~= right[index] then return false end
    end
    return true
end

local function paths_equal(left, right)
    if #left ~= #right then return false end
    for index = 1, #left do
        if left[index] ~= right[index] then return false end
    end
    return true
end

local function fail(message)
    return nil, message
end

local function validate_operation(operation, family, state_id, family_templates)
    if type(operation) ~= "table"
            or not ALLOWED_ROOTS[operation.root]
            or operation.family_id ~= family.id
            or operation.state_id ~= state_id then
        return fail("invalid operation owner " .. family.id .. "/" .. state_id)
    end
    if operation.root == "Weapons" then
        if not family_templates[operation.template] then
            return fail("invalid template owner " .. target_key(operation))
        end
    elseif operation.template ~= nil then
        return fail("global operation carries a template " .. target_key(operation))
    end
    local path_count = array_length(operation.path)
    if not path_count or path_count == 0 then
        return fail("invalid operation path " .. family.id .. "/" .. state_id)
    end
    for path_index = 1, path_count do
        local key_kind = type(operation.path[path_index])
        if key_kind ~= "string" and key_kind ~= "number" then
            return fail("non-scalar operation path " .. target_key(operation))
        end
    end
    if type(operation.expected_present) ~= "boolean"
            or type(operation.result_present) ~= "boolean" then
        return fail("presence contract missing " .. target_key(operation))
    end
    if operation.expected_present and rawget(operation, "expected_current") == nil then
        return fail("expected-current guard missing " .. target_key(operation))
    end
    if operation.result_present and rawget(operation, "result") == nil then
        return fail("result missing " .. target_key(operation))
    end
    if not pure_data(operation.expected_current) or not pure_data(operation.result) then
        return fail("operation contains non-portable data " .. target_key(operation))
    end
    if not full_hash(operation.source_revision)
            or not full_hash(operation.source_blob)
            or not full_hash(operation.current_source_blob)
            or not ALLOWED_CHANGE_CLASSES[operation.change_class]
            or type(operation.official_change_id) ~= "string"
            or operation.official_change_id == ""
            or type(operation.official_summary) ~= "string"
            or operation.official_summary == ""
            or type(operation.source_path) ~= "string"
            or operation.source_path == "" then
        return fail("operation provenance incomplete " .. target_key(operation))
    end
    if operation.expected_present == operation.result_present
            and deep_equal(operation.expected_current, operation.result) then
        return fail("vacuous operation " .. target_key(operation))
    end
    return true
end

function M.validate(catalog)
    if type(catalog) ~= "table" then return fail("catalog is not a table") end
    if catalog.schema ~= 2 then return fail("unsupported history schema") end
    if catalog.current_id ~= "current" then
        return fail("current selector must be literal current")
    end
    if type(catalog.catalog_id) ~= "string" or catalog.catalog_id == "" then
        return fail("catalog_id missing")
    end
    if type(catalog.current_source) ~= "table"
            or not full_hash(catalog.current_source.revision)
            or type(catalog.current_source.display_name) ~= "string"
            or catalog.current_source.display_name == ""
            or type(catalog.current_source.label) ~= "string" then
        return fail("current source provenance incomplete")
    end

    local localization_keys = {
        wt_history_patch_versions = true,
        wt_history_patch_versions_description = true,
        wt_history_state_current = true,
    }
    local function claim_localization_key(key)
        if type(key) ~= "string" or key == "" then
            return fail("history localization key missing")
        end
        if localization_keys[key] then
            return fail("duplicate history localization key " .. key)
        end
        localization_keys[key] = true
        return true
    end

    local state_count = 0
    for state_id, state in pairs(catalog.states or {}) do
        state_count = state_count + 1
        if type(state_id) ~= "string" or state_id == "" or state_id == catalog.current_id then
            return fail("invalid state id")
        end
        if type(state) ~= "table"
                or not ALLOWED_CHANGE_CLASSES[state.change_class]
                or type(state.display_name) ~= "string" or state.display_name == ""
                or type(state.label_key) ~= "string" or state.label_key == ""
                or not full_hash(state.source_revision)
                or type(state.official_patch_notes) ~= "string"
                or not state.official_patch_notes:match("^https://") then
            return fail("state provenance incomplete: " .. tostring(state_id))
        end
        local claimed, claim_error = claim_localization_key(state.label_key)
        if not claimed then return nil, claim_error end
    end
    if state_count == 0 then return fail("catalog has no historical states") end

    local profile_names = {}
    for state_id, specs in pairs(catalog.profile_specs or {}) do
        if not catalog.states[state_id] or type(specs) ~= "table" then
            return fail("unknown profile state " .. tostring(state_id))
        end
        profile_names[state_id] = {}
        for native_name, spec in pairs(specs) do
            if type(spec) ~= "table" or spec.state_id ~= state_id
                    or spec.native_name ~= native_name
                    or not safe_name(native_name) or not safe_name(spec.private_name)
                    or not full_hash(spec.source_revision)
                    or not full_hash(spec.source_blob)
                    or not full_hash(spec.current_source_blob)
                    or not ALLOWED_CHANGE_CLASSES[spec.change_class]
                    or type(spec.source_path) ~= "string" or spec.source_path == ""
                    or type(spec.official_change_id) ~= "string"
                    or type(spec.official_summary) ~= "string"
                    or not pure_data(spec.historical_profile) then
                return fail("profile provenance incomplete " .. state_id .. "/"
                    .. tostring(native_name))
            end
            profile_names[state_id][native_name] = true
        end
    end
    for state_id, specs in pairs(catalog.derived_profiles or {}) do
        if not catalog.states[state_id] or type(specs) ~= "table" then
            return fail("unknown derived-profile state " .. tostring(state_id))
        end
        profile_names[state_id] = profile_names[state_id] or {}
        for native_name, spec in pairs(specs) do
            if type(spec) ~= "table" or spec.state_id ~= state_id
                    or spec.native_name ~= native_name
                    or spec.derivation ~= "native_no_damage_clone"
                    or not safe_name(native_name) or not safe_name(spec.private_name)
                    or not safe_name(spec.source_profile)
                    or not (catalog.profile_specs[state_id]
                        and catalog.profile_specs[state_id][spec.source_profile]) then
                return fail("derived-profile contract incomplete " .. state_id .. "/"
                    .. tostring(native_name))
            end
            profile_names[state_id][native_name] = true
        end
    end

    local family_count = array_length(catalog.families)
    if not family_count or family_count == 0 then
        return fail("families must be a non-empty array")
    end
    local family_ids, setting_ids, template_owners = {}, {}, {}
    local catalog_owned_paths = {}
    for family_index = 1, family_count do
        local family = catalog.families[family_index]
        if type(family) ~= "table" or type(family.id) ~= "string" or family.id == ""
                or type(family.display_name) ~= "string" or family.display_name == ""
                or type(family.setting_id) ~= "string" or family.setting_id == ""
                or type(family.label_key) ~= "string" then
            return fail("family identity incomplete at index " .. family_index)
        end
        if family.authority ~= nil and not ALLOWED_AUTHORITIES[family.authority] then
            return fail("unsupported family authority " .. family.id)
        end
        if family_ids[family.id] then return fail("duplicate family id " .. family.id) end
        if setting_ids[family.setting_id] then
            return fail("duplicate setting id " .. family.setting_id)
        end
        family_ids[family.id], setting_ids[family.setting_id] = true, true
        for _, key in ipairs({
            family.label_key,
            family.setting_id,
            family.setting_id .. "_description",
        }) do
            local claimed, claim_error = claim_localization_key(key)
            if not claimed then return nil, claim_error end
        end

        local template_count = array_length(family.templates)
        if not template_count or template_count == 0 then
            return fail("family has no templates: " .. family.id)
        end
        local family_templates = {}
        for index = 1, template_count do
            local template = family.templates[index]
            if type(template) ~= "string" or template == "" then
                return fail("invalid template in " .. family.id)
            end
            if family_templates[template] then
                return fail("duplicate family template " .. template)
            end
            if template_owners[template] and template_owners[template] ~= family.id then
                return fail("template assigned to two families: " .. template)
            end
            family_templates[template], template_owners[template] = true, family.id
        end

        local state_order_count = array_length(family.state_order)
        if not state_order_count or state_order_count == 0 then
            return fail("family has no state order: " .. family.id)
        end
        local family_states = {}
        for index = 1, state_order_count do
            local state_id = family.state_order[index]
            if family_states[state_id] then
                return fail("duplicate family state " .. family.id .. "/" .. tostring(state_id))
            end
            family_states[state_id] = true
            local state = type(family.states) == "table" and family.states[state_id]
            if not catalog.states[state_id] or type(state) ~= "table" then
                return fail("unknown family state " .. family.id .. "/" .. tostring(state_id))
            end
            local operation_count = array_length(state.operations) or 0
            local profile_count = array_length(state.profile_names) or 0
            local direct_profile_count = array_length(state.direct_profile_names)
            if direct_profile_count == nil then
                return fail("missing direct profile routes " .. family.id .. "/" .. state_id)
            end
            if operation_count == 0 and profile_count == 0 then
                return fail("vacuous family state " .. family.id .. "/" .. state_id)
            end
            if state.atomic_group ~= nil
                    and (type(state.atomic_group) ~= "string" or operation_count == 0) then
                return fail("invalid atomic group " .. family.id .. "/" .. state_id)
            end
            local family_profile_names = {}
            for profile_index = 1, profile_count do
                local name = state.profile_names[profile_index]
                if family_profile_names[name] then
                    return fail("duplicate family profile " .. family.id .. "/"
                        .. state_id .. "/" .. tostring(name))
                end
                if not (profile_names[state_id] and profile_names[state_id][name]) then
                    return fail("unknown family profile " .. family.id .. "/" .. state_id
                        .. "/" .. tostring(name))
                end
                family_profile_names[name] = true
            end
            local seen_direct = {}
            for profile_index = 1, direct_profile_count do
                local name = state.direct_profile_names[profile_index]
                if not family_profile_names[name] or seen_direct[name] then
                    return fail("invalid direct family profile " .. family.id .. "/"
                        .. state_id .. "/" .. tostring(name))
                end
                seen_direct[name] = true
            end

            local seen_targets, seen_paths = {}, {}
            for operation_index = 1, operation_count do
                local operation = state.operations[operation_index]
                local valid, operation_error = validate_operation(
                    operation, family, state_id, family_templates)
                if not valid then return nil, operation_error end
                local key = target_key(operation)
                if seen_targets[key] then return fail("duplicate operation target " .. key) end
                for _, prior in ipairs(seen_paths) do
                    if prior.root == operation.root and prior.template == operation.template
                            and (path_is_prefix(prior.path, operation.path)
                                or path_is_prefix(operation.path, prior.path)) then
                        return fail("ancestor/descendant operation conflict " .. key)
                    end
                end
                seen_targets[key] = true
                seen_paths[#seen_paths + 1] = operation
                for _, prior in ipairs(catalog_owned_paths) do
                    if prior.family_id ~= family.id
                            and prior.operation.root == operation.root
                            and prior.operation.template == operation.template then
                        if paths_equal(prior.operation.path, operation.path) then
                            return fail("cross-family target collision " .. key)
                        end
                        if path_is_prefix(prior.operation.path, operation.path)
                                or path_is_prefix(operation.path, prior.operation.path) then
                            return fail("cross-family ancestor/descendant target conflict "
                                .. key)
                        end
                    end
                end
                catalog_owned_paths[#catalog_owned_paths + 1] = {
                    family_id = family.id,
                    operation = operation,
                }
            end
        end
        for state_id in pairs(family.states or {}) do
            if not family_states[state_id] then
                return fail("family state missing from order " .. family.id .. "/"
                    .. tostring(state_id))
            end
        end
    end
    return true
end

local function locate(roots, operation)
    local root = type(roots) == "table" and rawget(roots, operation.root)
    if type(root) ~= "table" then return nil, "missing root " .. operation.root end
    local owner = root
    if operation.root == "Weapons" then
        owner = rawget(root, operation.template)
        if type(owner) ~= "table" then
            return nil, "missing template " .. tostring(operation.template)
        end
    end
    local parent = owner
    for index = 1, #operation.path - 1 do
        parent = rawget(parent, operation.path[index])
        if type(parent) ~= "table" then
            return nil, "missing parent " .. target_key(operation)
        end
    end
    return {
        key = operation.path[#operation.path],
        owner = owner,
        parent = parent,
        root = root,
    }
end

local function append_operation(plan, seen, roots, operation, transform)
    local key = target_key(operation)
    if seen[key] then return nil, "duplicate planned target " .. key end
    local location, location_error = locate(roots, operation)
    if not location then return nil, location_error end
    local current = rawget(location.parent, location.key)
    local present = current ~= nil
    if present ~= operation.expected_present
            or (present and not deep_equal(current, operation.expected_current)) then
        return nil, "current guard mismatch " .. key
    end
    local applied = operation.result
    if operation.result_present and transform then
        local transformed, transform_error = transform(operation, applied)
        if transform_error then return nil, transform_error end
        if transformed == nil then
            return nil, "transform removed a present result " .. key
        end
        applied = transformed
    end
    local applied_value = clone_if_present(operation.result_present, applied)
    local entry = {
        applied_snapshot = clone_if_present(operation.result_present, applied),
        applied_value = applied_value,
        key = location.key,
        operation = operation,
        original_present = present,
        original_value = current,
        owner_object = location.owner,
        parent = location.parent,
        root_name = operation.root,
        root_object = location.root,
        template_name = operation.template,
    }
    plan[#plan + 1] = entry
    seen[key] = true
    return true
end

function M.build_family_plan(catalog, family, selected, roots, options)
    options = options or {}
    if options.validated ~= true then
        local valid, validation_error = M.validate(catalog)
        if not valid then return nil, validation_error end
    end
    selected = selected or catalog.current_id
    if selected == catalog.current_id then return {} end
    local state = family.states and family.states[selected]
    if type(state) ~= "table" then
        return nil, "unknown selection " .. family.setting_id .. "=" .. tostring(selected)
    end
    local plan, seen = {}, {}
    for _, operation in ipairs(state.operations or {}) do
        local ok, operation_error = append_operation(
            plan, seen, roots, operation, options.transform)
        if not ok then return nil, operation_error end
    end
    local extras, extras_error
    if options.extra_operations then
        extras, extras_error = options.extra_operations(family, selected, state)
        if extras == nil and extras_error ~= nil then
            return nil, extras_error
        end
        if extras ~= nil and type(extras) ~= "table" then
            return nil, "extra operations are not a table"
        end
    end
    for _, operation in ipairs(extras or {}) do
        local ok, operation_error = append_operation(
            plan, seen, roots, operation, options.transform)
        if not ok then return nil, operation_error end
    end
    if #plan == 0 then return nil, "selected family plan is vacuous " .. family.id end
    return plan
end

function M.build_plan(catalog, selections, roots, options)
    local valid, validation_error = M.validate(catalog)
    if not valid then return nil, validation_error end
    local family_options = {}
    for key, value in pairs(options or {}) do family_options[key] = value end
    family_options.validated = true
    local plan, seen = {}, {}
    for _, family in ipairs(catalog.families) do
        local selected = selections and selections[family.setting_id] or catalog.current_id
        if selected ~= catalog.current_id then
            local family_plan, plan_error = M.build_family_plan(
                catalog, family, selected, roots, family_options)
            if not family_plan then return nil, plan_error end
            for _, entry in ipairs(family_plan) do
                local key = target_key(entry.operation)
                if seen[key] then return nil, "cross-family target collision " .. key end
                seen[key] = true
                plan[#plan + 1] = entry
            end
        end
    end
    return plan
end

function M.commit(plan)
    if type(plan) ~= "table" then return nil, "plan is not a table" end
    local applied = 0
    for index, entry in ipairs(plan) do
        local ok, write_error = pcall(rawset, entry.parent, entry.key,
            entry.applied_value)
        if not ok then
            for rollback = applied, 1, -1 do
                local prior = plan[rollback]
                pcall(rawset, prior.parent, prior.key,
                    original_if_present(prior.original_present, prior.original_value))
            end
            return nil, "history commit failed at " .. tostring(index) .. ": "
                .. tostring(write_error)
        end
        applied = applied + 1
    end
    return plan
end

function M.ledger_status(ledger, roots)
    if type(ledger) ~= "table" then return "none" end
    for _, entry in ipairs(ledger) do
        local root = type(roots) == "table" and rawget(roots, entry.root_name)
        if root ~= entry.root_object then return "replacement" end
        local owner = root
        if entry.root_name == "Weapons" then
            owner = type(root) == "table" and rawget(root, entry.template_name)
        end
        if owner ~= entry.owner_object then return "replacement" end
        local parent = owner
        for index = 1, #entry.operation.path - 1 do
            parent = type(parent) == "table" and rawget(parent, entry.operation.path[index])
        end
        if parent ~= entry.parent then return "replacement" end
        local live = rawget(entry.parent, entry.key)
        if live ~= entry.applied_value then return "drift" end
        if type(live) == "table"
                and not deep_equal(live, entry.applied_snapshot) then
            return "drift"
        end
    end
    return "same"
end

function M.restore(ledger)
    if type(ledger) ~= "table" then return true end
    for _, entry in ipairs(ledger) do
        local live = rawget(entry.parent, entry.key)
        if live ~= entry.applied_value
                or (type(live) == "table"
                    and not deep_equal(live, entry.applied_snapshot)) then
            return nil, "restore ownership lost " .. target_key(entry.operation)
        end
    end
    for index = #ledger, 1, -1 do
        local entry = ledger[index]
        local ok, restore_error = pcall(rawset, entry.parent, entry.key,
            original_if_present(entry.original_present, entry.original_value))
        if not ok then
            return nil, "restore failed " .. target_key(entry.operation) .. ": "
                .. tostring(restore_error)
        end
    end
    return true
end

M.ALLOWED_ROOTS = ALLOWED_ROOTS
M.ALLOWED_AUTHORITIES = ALLOWED_AUTHORITIES
M.deep_clone = deep_clone
M.deep_equal = deep_equal
M.path_text = path_text
M.target_key = target_key

return M
