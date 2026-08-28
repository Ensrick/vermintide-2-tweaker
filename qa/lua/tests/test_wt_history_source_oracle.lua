-- Independent source-oracle coverage for Tweaker: Weapons #1436.
--
-- Unlike test_wt_history.lua, this suite never builds its baseline from the
-- generated runtime catalog. Historical/current leaves come from the preserved
-- source-extractor evidence, while route locations and Git blob identities come
-- from a separately regenerated immutable-source oracle.

local function register(H, repo_root)
    local oracle_root = repo_root .. "/tools/weapon-history/source_oracle/"
    local evidence_root = repo_root .. "/tools/weapon-history/evidence/patch_5_2/"
    local runtime_root = repo_root .. "/weapon_tweaker/scripts/mods/weapon_tweaker/"
    local spec = assert(loadfile(oracle_root .. "patch_5_2_source_spec.lua"))()
    local routes_oracle = assert(loadfile(
        oracle_root .. "patch_5_2_routes_oracle.lua"))()
    local source_catalog = assert(loadfile(
        evidence_root .. "_wt_history_5_2_source_catalog.lua"))()
    local catalog = assert(loadfile(runtime_root .. "_wt_history_5_2_catalog.lua"))()
    local Policy = assert(loadfile(runtime_root .. "_wt_history_policy.lua"))()
    local Runtime = assert(loadfile(runtime_root .. "_wt_history_runtime.lua"))()

    local function fail(message)
        error(message, 2)
    end

    local function number_token(value)
        if value ~= value then return "nan" end
        if value == math.huge then return "+inf" end
        if value == -math.huge then return "-inf" end
        if value == 0 then return 1 / value == -math.huge and "-0" or "+0" end
        local fraction, exponent = math.frexp(value)
        return string.format("%.0f", fraction * 9007199254740992)
            .. "p" .. tostring(exponent - 53)
    end

    local function deep_exact(left, right, seen)
        if type(left) ~= type(right) then return false end
        if type(left) == "number" then
            return number_token(left) == number_token(right)
        end
        if type(left) ~= "table" then return left == right end
        seen = seen or {}
        seen[left] = seen[left] or {}
        if seen[left][right] then return true end
        seen[left][right] = true
        for key, value in pairs(left) do
            local matching_key
            for candidate in pairs(right) do
                if deep_exact(key, candidate) then matching_key = candidate; break end
            end
            if matching_key == nil
                    or not deep_exact(value, rawget(right, matching_key), seen) then
                return false
            end
        end
        for key in pairs(right) do
            local present = false
            for candidate in pairs(left) do
                if deep_exact(key, candidate) then present = true; break end
            end
            if not present then return false end
        end
        return true
    end

    local function clone(value, seen)
        if type(value) ~= "table" then return value end
        seen = seen or {}
        if seen[value] then return seen[value] end
        local copy = {}
        seen[value] = copy
        for key, child in pairs(value) do copy[clone(key, seen)] = clone(child, seen) end
        return copy
    end

    local function path_text(path)
        local parts = {}
        for index = 1, #path do parts[index] = tostring(path[index]) end
        return table.concat(parts, ".")
    end

    local function operation_key(operation)
        return operation.root .. "|" .. tostring(operation.template or "<root>")
            .. "|" .. path_text(operation.path)
    end

    local template_family = {}
    local family_spec = {}
    local state_count = 0
    for _, family in ipairs(spec.families) do
        if family_spec[family.id] then fail("duplicate oracle family " .. family.id) end
        family_spec[family.id] = family
        for template in pairs(family.templates) do
            if template_family[template] then fail("duplicate template owner " .. template) end
            template_family[template] = family.id
        end
        for _ in pairs(family.states) do state_count = state_count + 1 end
    end

    local oracle_operations = {}
    local raw_counts, rejected_counts = {}, {}
    for state_id, file_names in pairs(spec.snapshot_files) do
        oracle_operations[state_id] = oracle_operations[state_id] or {}
        raw_counts[state_id], rejected_counts[state_id] = 0, 0
        for _, file_name in ipairs(file_names) do
            local snapshot = assert(loadfile(evidence_root .. file_name))()
            H.equal(snapshot.old_revision, spec.revisions[state_id]:sub(1, 8))
            H.equal(snapshot.new_revision, spec.revisions.current:sub(1, 8))
            for _, record in ipairs(snapshot.records or {}) do
                local owner = template_family[record.template]
                if not owner then fail("source record has no family: " .. record.template) end
                oracle_operations[state_id][owner] =
                    oracle_operations[state_id][owner] or {}
                for _, source_operation in ipairs(record.ops or {}) do
                    raw_counts[state_id] = raw_counts[state_id] + 1
                    local deny_key = record.template .. "|" .. path_text(source_operation.path)
                    if spec.rejected[deny_key] then
                        rejected_counts[state_id] = rejected_counts[state_id] + 1
                    else
                        local row = {
                            current_source_blob = assert(routes_oracle.source_blobs
                                [spec.revisions.current][record.source_path]),
                            expected_current = source_operation.expected_current,
                            expected_present = not source_operation.expected_current_unset,
                            family_id = owner,
                            path = source_operation.path,
                            result = source_operation.value,
                            result_present = not source_operation.unset,
                            root = "Weapons",
                            source_blob = assert(routes_oracle.source_blobs
                                [spec.revisions[state_id]][record.source_path]),
                            source_path = record.source_path,
                            source_revision = spec.revisions[state_id],
                            state_id = state_id,
                            template = record.template,
                        }
                        oracle_operations[state_id][owner][#oracle_operations[state_id][owner] + 1]
                            = row
                    end
                end
            end
        end
    end

    local global_count = 0
    for state_id, records in pairs(source_catalog.global_records or {}) do
        oracle_operations[state_id] = oracle_operations[state_id] or {}
        for _, source_operation in ipairs(records) do
            local owner = assert(source_operation.family_id)
            oracle_operations[state_id][owner] = oracle_operations[state_id][owner] or {}
            local row = {
                current_source_blob = assert(routes_oracle.source_blobs
                    [spec.revisions.current][source_operation.source_path]),
                expected_current = source_operation.expected_current,
                expected_present = true,
                family_id = owner,
                path = source_operation.path,
                result = source_operation.value,
                result_present = true,
                root = source_operation.root,
                source_blob = assert(routes_oracle.source_blobs
                    [spec.revisions[state_id]][source_operation.source_path]),
                source_path = source_operation.source_path,
                source_revision = spec.revisions[state_id],
                state_id = state_id,
            }
            oracle_operations[state_id][owner][#oracle_operations[state_id][owner] + 1] = row
            global_count = global_count + 1
        end
    end

    local function generated_family(id)
        for _, family in ipairs(catalog.families) do
            if family.id == id then return family end
        end
        return nil
    end

    local function operation_map(operations, context)
        local output = {}
        for _, operation in ipairs(operations or {}) do
            local key = operation_key(operation)
            if output[key] then fail("duplicate operation " .. context .. ": " .. key) end
            output[key] = operation
        end
        return output
    end

    local function compare_operation(expected, actual, context)
        local scalar_fields = {
            "root", "template", "family_id", "state_id", "source_revision",
            "source_blob", "current_source_blob", "source_path",
            "expected_present", "result_present",
        }
        for _, field in ipairs(scalar_fields) do
            if expected[field] ~= actual[field] then
                fail(context .. " differs at " .. field .. ": "
                    .. tostring(actual[field]) .. " ~= " .. tostring(expected[field]))
            end
        end
        if not deep_exact(expected.path, actual.path) then fail(context .. " path differs") end
        if expected.expected_present
                and not deep_exact(expected.expected_current, actual.expected_current) then
            fail(context .. " current source baseline differs")
        end
        if expected.result_present and not deep_exact(expected.result, actual.result) then
            fail(context .. " historical result differs")
        end
    end

    local profile_evidence = {}
    for state_id, file_names in pairs(spec.profile_files) do
        profile_evidence[state_id] = {}
        for _, file_name in ipairs(file_names) do
            local evidence = assert(loadfile(evidence_root .. file_name))()
            H.equal(evidence.old_revision, spec.revisions[state_id]:sub(1, 8))
            H.equal(evidence.new_revision, spec.revisions.current:sub(1, 8))
            for name, profile in pairs(evidence.profiles or {}) do
                if profile_evidence[state_id][name] then
                    fail("duplicate profile evidence " .. state_id .. "/" .. name)
                end
                profile_evidence[state_id][name] = profile
            end
        end
    end

    local function contains_profile_result(value, parent_key, wanted, seen)
        if type(parent_key) == "string" and parent_key:find("damage_profile", 1, true)
                and type(value) == "string" and value == wanted then return true end
        if type(value) ~= "table" then return false end
        seen = seen or {}
        if seen[value] then return false end
        seen[value] = true
        for key, child in pairs(value) do
            if contains_profile_result(child, key, wanted, seen) then return true end
        end
        return false
    end

    local function operation_carries_profile(operation, name)
        local final_key = operation.path[#operation.path]
        return operation.result_present
            and contains_profile_result(operation.result, final_key, name)
    end

    local function route_rows(family_id, state_id)
        return routes_oracle.routes[family_id]
            and routes_oracle.routes[family_id][state_id] or {}
    end

    local function put_current(roots, operation, value, present, originals)
        local parent = roots[operation.root]
        if operation.root == "Weapons" then
            parent[operation.template] = parent[operation.template] or {}
            parent = parent[operation.template]
        end
        for index = 1, #operation.path - 1 do
            local key = operation.path[index]
            local child = rawget(parent, key)
            if child == nil then child = {}; rawset(parent, key, child) end
            if type(child) ~= "table" then fail("baseline ancestor collision") end
            parent = child
        end
        local key = operation.path[#operation.path]
        local prior = rawget(parent, key)
        if prior ~= nil and (not present or not deep_exact(prior, value)) then
            fail("inconsistent independent baseline " .. operation_key(operation))
        end
        if present and prior == nil then rawset(parent, key, value) end
        originals[#originals + 1] = {
            key = key, parent = parent, present = present,
            value = present and rawget(parent, key) or nil,
        }
    end

    local function roots_for(family_id, state_id, operations)
        local roots = {
            BuffTemplates = {}, ExplosionTemplates = {},
            PlayerUnitStatusSettings = {}, Weapons = {},
        }
        local originals = {}
        for _, operation in ipairs(operations) do
            put_current(roots, operation, operation.expected_current,
                operation.expected_present, originals)
        end
        for _, route in ipairs(route_rows(family_id, state_id)) do
            put_current(roots, {
                root = "Weapons", template = route.template, path = route.path,
            }, route.native_name, true, originals)
        end
        return roots, originals
    end

    local function extra_route_operations(family_id, state_id)
        local operations = {}
        for _, route in ipairs(route_rows(family_id, state_id)) do
            operations[#operations + 1] = {
                expected_current = route.native_name,
                expected_present = true,
                family_id = family_id,
                path = route.path,
                result = route.native_name,
                result_present = true,
                root = "Weapons",
                state_id = state_id,
                synthetic_profile_route = true,
                template = route.template,
            }
        end
        return operations
    end

    local function with_profile_globals(body)
        local previous_profiles = rawget(_G, "DamageProfileTemplates")
        local previous_lookup = rawget(_G, "NetworkLookup")
        local previous_printf = rawget(_G, "printf")
        local profiles, lookup, names = {}, {}, {}
        for _, family in ipairs(catalog.families) do
            for _, state_id in ipairs(family.state_order) do
                for _, native_name in ipairs(family.states[state_id].profile_names or {}) do
                    names[native_name] = true
                end
            end
        end
        local ordered = {}
        for name in pairs(names) do ordered[#ordered + 1] = name end
        table.sort(ordered)
        for index, name in ipairs(ordered) do
            profiles[name] = { name = name, targets = {} }
            lookup[index], lookup[name] = name, index
        end
        rawset(_G, "DamageProfileTemplates", profiles)
        rawset(_G, "NetworkLookup", { damage_profiles = lookup })
        rawset(_G, "printf", function() end)
        local outcome = { xpcall(body, debug.traceback) }
        rawset(_G, "DamageProfileTemplates", previous_profiles)
        rawset(_G, "NetworkLookup", previous_lookup)
        rawset(_G, "printf", previous_printf)
        if not outcome[1] then error(outcome[2], 0) end
        return unpack(outcome, 2)
    end

    H.test("WT #1436 source oracle binds exact revisions, census, and route provenance", function()
        H.equal(spec.oracle_id, routes_oracle.oracle_id)
        H.equal(routes_oracle.current_revision, spec.revisions.current)
        H.equal(#spec.families, spec.expected.families)
        H.equal(state_count, spec.expected.family_states)
        H.equal(global_count, spec.expected.global_operations)
        local emitted = global_count
        for state_id, expected in pairs(spec.expected.raw_snapshot_operations) do
            H.equal(raw_counts[state_id], expected)
            H.equal(rejected_counts[state_id], spec.expected.rejected_occurrences[state_id])
            emitted = emitted + raw_counts[state_id] - rejected_counts[state_id]
        end
        H.equal(emitted - global_count, spec.expected.emitted_snapshot_operations)
        H.equal(emitted, spec.expected.emitted_operations)

        for _, family in ipairs(spec.families) do
            for state_id in pairs(family.states) do
                local blobs = routes_oracle.source_blobs[spec.revisions[state_id]]
                local current_blobs = routes_oracle.source_blobs[spec.revisions.current]
                for _, path in pairs(family.templates) do
                    H.truthy(blobs[path] and #blobs[path] == 40)
                    H.truthy(current_blobs[path] and #current_blobs[path] == 40)
                end
            end
        end
    end)

    H.test("WT #1436 all generated operations equal independent source evidence", function()
        local total = 0
        H.equal(#catalog.families, #spec.families)
        for _, expected_family in ipairs(spec.families) do
            local family = generated_family(expected_family.id)
            H.truthy(family, "generated family missing " .. expected_family.id)
            local generated_templates = {}
            for _, template in ipairs(family.templates) do generated_templates[template] = true end
            for template in pairs(expected_family.templates) do
                H.equal(generated_templates[template], true)
            end
            for state_id in pairs(expected_family.states) do
                local state = family.states[state_id]
                H.truthy(state, "generated state missing " .. expected_family.id .. "/" .. state_id)
                local expected = oracle_operations[state_id][expected_family.id] or {}
                local expected_map = operation_map(expected, "oracle")
                local actual_map = operation_map(state.operations, "generated")
                local count = 0
                for key, expected_operation in pairs(expected_map) do
                    local actual_operation = actual_map[key]
                    H.truthy(actual_operation, "generated operation missing " .. key)
                    compare_operation(expected_operation, actual_operation,
                        expected_family.id .. "/" .. state_id .. "/" .. key)
                    count = count + 1
                end
                for key in pairs(actual_map) do
                    H.truthy(expected_map[key], "generated operation not in source oracle " .. key)
                end
                H.equal(#state.operations, count)
                total = total + count
            end
        end
        H.equal(total, spec.expected.emitted_operations)
    end)

    H.test("WT #1436 profile payloads and uses equal source-backed evidence", function()
        local source_specs, derived_specs, declarations, references = 0, 0, 0, 0
        local seen_source_spec = {}
        for _, expected_family in ipairs(spec.families) do
            local family = assert(generated_family(expected_family.id))
            for state_id, expected_names in pairs(expected_family.states) do
                local state = assert(family.states[state_id])
                local actual_names = {}
                for _, name in ipairs(state.profile_names or {}) do actual_names[name] = true end
                H.equal(#state.profile_names, #expected_names)
                local direct_names, oracle_direct = {}, {}
                for _, name in ipairs(state.direct_profile_names or {}) do
                    direct_names[name] = true
                end
                for _, route in ipairs(route_rows(expected_family.id, state_id)) do
                    oracle_direct[route.native_name] = true
                end
                for name in pairs(direct_names) do
                    H.equal(oracle_direct[name], true,
                        "generated direct profile absent from current source route")
                end
                for name in pairs(oracle_direct) do
                    H.equal(direct_names[name], true,
                        "current source route absent from generated direct profiles")
                end
                for _, name in ipairs(expected_names) do
                    H.equal(actual_names[name], true)
                    references = references + 1
                    local derived = catalog.derived_profiles[state_id]
                        and catalog.derived_profiles[state_id][name]
                    if derived then
                        derived_specs = derived_specs + 1
                    else
                        declarations = declarations + 1
                        local profile_key = state_id .. "|" .. name
                        if not seen_source_spec[profile_key] then
                            seen_source_spec[profile_key] = true
                            source_specs = source_specs + 1
                            local generated = assert(catalog.profile_specs[state_id][name])
                            local evidence = assert(profile_evidence[state_id][name], profile_key)
                            H.truthy(deep_exact(evidence, generated.historical_profile),
                                "historical profile differs: " .. profile_key)
                            local path = assert(spec.profile_source_paths[name])
                            H.equal(generated.source_path, path)
                            H.equal(generated.source_revision, spec.revisions[state_id])
                            H.equal(generated.source_blob,
                                routes_oracle.source_blobs[spec.revisions[state_id]][path])
                            H.equal(generated.current_source_blob,
                                routes_oracle.source_blobs[spec.revisions.current][path])
                        end
                    end

                    local routed = false
                    for _, route in ipairs(route_rows(expected_family.id, state_id)) do
                        if route.native_name == name then routed = true; break end
                    end
                    local carried = false
                    for _, operation in ipairs(oracle_operations[state_id][expected_family.id] or {}) do
                        if operation_carries_profile(operation, name) then carried = true; break end
                    end
                    local source_only = spec.source_only_profiles[
                        expected_family.id .. "|" .. state_id .. "|" .. name] == true
                    H.truthy(routed or carried or source_only,
                        "profile is neither current-routed, history-carried, nor a donor: "
                            .. expected_family.id .. "/" .. state_id .. "/" .. name)
                end
            end
        end
        H.equal(source_specs, spec.expected.unique_source_profiles)
        H.equal(derived_specs, spec.expected.derived_profiles)
        H.equal(declarations, spec.expected.source_profile_routes)
        H.equal(references, spec.expected.family_profile_references)
    end)

    H.test("WT #1436 all 14 families and 22 states preflight against independent baselines", function()
        local preflighted = 0
        for _, expected_family in ipairs(spec.families) do
            local family = assert(generated_family(expected_family.id))
            for state_id in pairs(expected_family.states) do
                local expected_operations = oracle_operations[state_id][expected_family.id] or {}
                local roots, originals = roots_for(
                    expected_family.id, state_id, expected_operations)
                local before = clone(roots)
                local extras = extra_route_operations(expected_family.id, state_id)
                local plan, plan_error = Policy.build_family_plan(
                    catalog, family, state_id, roots, {
                        validated = true,
                        extra_operations = function() return extras end,
                    })
                H.truthy(plan, expected_family.id .. "/" .. state_id
                    .. " independent preflight failed: " .. tostring(plan_error))
                H.truthy(deep_exact(roots, before),
                    "preflight wrote gameplay state for " .. expected_family.id .. "/" .. state_id)
                H.equal(#plan, #expected_operations + #extras)
                local ledger = assert(Policy.commit(plan))
                H.equal(Policy.ledger_status(ledger, roots), "same")
                H.equal(Policy.restore(ledger), true)
                for _, original in ipairs(originals) do
                    H.equal(rawget(original.parent, original.key), original.value,
                        "restore lost exact baseline reference")
                end
                preflighted = preflighted + 1
            end
        end
        H.equal(preflighted, spec.expected.family_states)
    end)

    H.test("WT #1436 all source-backed states pass actual runtime and exact restore", function()
        with_profile_globals(function()
            local exercised = 0
            for _, expected_family in ipairs(spec.families) do
                local family = assert(generated_family(expected_family.id))
                for state_id in pairs(expected_family.states) do
                    local expected_operations = oracle_operations[state_id]
                        [expected_family.id] or {}
                    local roots, originals = roots_for(
                        expected_family.id, state_id, expected_operations)
                    local selections = { [family.setting_id] = state_id }
                    local mod = {}
                    function mod:get(setting_id) return selections[setting_id] end
                    function mod:info() end
                    mod._wt431_profiles_allowed = function() return true end
                    local runtime = Runtime.install({
                        catalog = catalog, mod = mod, policy = Policy, roots = roots,
                    })
                    H.equal(runtime.fatal_error, nil,
                        expected_family.id .. "/" .. state_id .. " fatal")
                    H.equal(runtime.last_error, nil,
                        expected_family.id .. "/" .. state_id .. " refused")
                    H.equal(runtime:verify(), nil,
                        expected_family.id .. "/" .. state_id .. " verify")
                    H.equal(#runtime.ledgers[expected_family.id],
                        #expected_operations + #route_rows(expected_family.id, state_id),
                        expected_family.id .. "/" .. state_id .. " write census")
                    local restored = assert(runtime:restore())
                    H.equal(restored.refused, 0)
                    for _, original in ipairs(originals) do
                        H.equal(rawget(original.parent, original.key), original.value,
                            "runtime restore lost exact source baseline reference")
                    end
                    exercised = exercised + 1
                end
            end
            H.equal(exercised, spec.expected.family_states)
        end)
    end)
end

return register
