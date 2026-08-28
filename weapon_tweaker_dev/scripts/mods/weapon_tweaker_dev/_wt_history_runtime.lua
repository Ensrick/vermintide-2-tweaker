-- Restart-bound Patch 5.2 historical weapon-state owner (#1436).
--
-- Composition is fixed:
--   current engine baseline -> selected historical state -> ordinary WT tweaks.
-- Private historical damage profiles are registered unconditionally before
-- #431 fingerprints the catalog. Assignment remains parity-gated and falls
-- back to the native profile for mixed or mismatched peers.
local M = {}

local function log_info(_, format, ...)
    local printer = rawget(_G, "printf")
    if type(printer) == "function" then
        pcall(printer, format, ...)
    end
end

local function log_error(format, ...)
    local printer = rawget(_G, "printf")
    if type(printer) == "function" then
        pcall(printer, "[wt:1436] ERROR " .. format, ...)
    end
end

local function sorted_keys(value)
    local keys = {}
    for key in pairs(value or {}) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end

local route_key_type_order = { number = 1, string = 2, boolean = 3 }
local function route_key_less(left, right)
    local left_type, right_type = type(left), type(right)
    local left_order = route_key_type_order[left_type]
    local right_order = route_key_type_order[right_type]
    assert(left_order and right_order, "unsupported profile-route key type")
    if left_order ~= right_order then return left_order < right_order end
    if left_type == "boolean" then return left == false and right == true end
    return left < right
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

local function derive_no_damage(source)
    local copy = clone(source)
    for _, target in ipairs(copy.targets or {}) do
        local distribution = type(target) == "table" and target.power_distribution
        if type(distribution) == "table" and distribution.attack ~= nil then
            distribution.attack = 0
        end
    end
    local default = copy.default_target
    local distribution = type(default) == "table" and default.power_distribution
    if type(distribution) == "table" and distribution.attack ~= nil then
        distribution.attack = 0
    end
    return copy
end

local function valid_lookup_row(lookup, name)
    local index = type(lookup) == "table" and rawget(lookup, name)
    return type(index) == "number" and index > 0 and math.floor(index) == index
        and rawget(lookup, index) == name
end

local function register_private_profiles(mod, catalog, policy)
    local profiles = rawget(_G, "DamageProfileTemplates")
    local lookup_root = rawget(_G, "NetworkLookup")
    local lookup = lookup_root and lookup_root.damage_profiles
    if type(profiles) ~= "table" or type(lookup) ~= "table" then
        return nil, "DamageProfileTemplates/NetworkLookup unavailable"
    end

    local prepared, private_by_state_name = {}, {}
    for state_id, specs in pairs(catalog.profile_specs or {}) do
        private_by_state_name[state_id] = private_by_state_name[state_id] or {}
        for native_name, spec in pairs(specs) do
            if not valid_lookup_row(lookup, native_name)
                    or type(rawget(profiles, native_name)) ~= "table" then
                return nil, "native profile unavailable " .. native_name
            end
            local profile = clone(spec.historical_profile)
            profile.name = spec.private_name
            prepared[spec.private_name] = {
                fallback = native_name,
                profile = profile,
                state_id = state_id,
            }
            private_by_state_name[state_id][native_name] = spec.private_name
        end
    end
    for state_id, specs in pairs(catalog.derived_profiles or {}) do
        private_by_state_name[state_id] = private_by_state_name[state_id] or {}
        for native_name, spec in pairs(specs) do
            local source_private = private_by_state_name[state_id][spec.source_profile]
            local source = source_private and prepared[source_private]
            if not source or spec.derivation ~= "native_no_damage_clone"
                    or not valid_lookup_row(lookup, native_name) then
                return nil, "derived profile source unavailable " .. native_name
            end
            local profile = derive_no_damage(source.profile)
            profile.name = spec.private_name
            prepared[spec.private_name] = {
                fallback = native_name,
                profile = profile,
                state_id = state_id,
            }
            private_by_state_name[state_id][native_name] = spec.private_name
        end
    end

    local names = sorted_keys(prepared)
    local fallback_map = mod._wt431_custom_profile_fallback
    if fallback_map ~= nil and type(fallback_map) ~= "table" then
        return nil, "custom-profile fallback registry is not a table"
    end
    fallback_map = fallback_map or {}
    local additions = {}
    for _, private_name in ipairs(names) do
        local row = prepared[private_name]
        local existing_profile = rawget(profiles, private_name)
        local existing_index = rawget(lookup, private_name)
        if existing_profile ~= nil
                and (type(existing_profile) ~= "table"
                    or not policy.deep_equal(existing_profile, row.profile)) then
            return nil, "private profile content collision " .. private_name
        end
        if existing_index ~= nil and not valid_lookup_row(lookup, private_name) then
            return nil, "private lookup collision " .. private_name
        end
        local existing_fallback = rawget(fallback_map, private_name)
        if existing_fallback ~= nil and existing_fallback ~= row.fallback then
            return nil, "private fallback collision " .. private_name
        end
    end

    for _, private_name in ipairs(names) do
        local row = prepared[private_name]
        local added_profile, added_lookup = false, false
        if rawget(profiles, private_name) == nil then
            local ok, write_error = pcall(rawset, profiles, private_name, row.profile)
            if not ok then
                for index = #additions, 1, -1 do
                    local prior = additions[index]
                    if prior.lookup then
                        rawset(lookup, prior.index, nil)
                        rawset(lookup, prior.name, nil)
                    end
                    if prior.profile then rawset(profiles, prior.name, nil) end
                end
                return nil, "private profile write failed: " .. tostring(write_error)
            end
            added_profile = true
        end
        if rawget(lookup, private_name) == nil then
            local index = #lookup + 1
            rawset(lookup, index, private_name)
            rawset(lookup, private_name, index)
            added_lookup = true
        end
        additions[#additions + 1] = {
            index = rawget(lookup, private_name),
            lookup = added_lookup,
            name = private_name,
            profile = added_profile,
        }
        rawset(fallback_map, private_name, row.fallback)
    end
    mod._wt431_custom_profile_fallback = fallback_map
    return {
        count = #names,
        names = names,
        private_by_state_name = private_by_state_name,
    }
end

local function collect_profile_routes(template, template_name, family, state_id,
        wanted, found)
    local routes, active = {}, {}
    local function walk(node, path)
        if type(node) ~= "table" or active[node] then return end
        active[node] = true
        local keys = {}
        for key in pairs(node) do
            if route_key_type_order[type(key)] then keys[#keys + 1] = key end
        end
        table.sort(keys, route_key_less)
        for _, key in ipairs(keys) do
            local child = rawget(node, key)
            local child_path = {}
            for index = 1, #path do child_path[index] = path[index] end
            child_path[#child_path + 1] = key
            if type(key) == "string" and key:find("damage_profile", 1, true)
                    and type(child) == "string" and wanted[child] then
                found[child] = true
                routes[#routes + 1] = {
                    expected_current = child,
                    expected_present = true,
                    family_id = family.id,
                    path = child_path,
                    result = child,
                    result_present = true,
                    root = "Weapons",
                    state_id = state_id,
                    synthetic_profile_route = true,
                    template = template_name,
                }
            elseif type(child) == "table" then
                walk(child, child_path)
            end
        end
        active[node] = nil
    end
    walk(template, {})
    return routes
end

function M.install(config)
    local mod = assert(config.mod, "mod required")
    local catalog = assert(config.catalog, "catalog required")
    local policy = assert(config.policy, "policy required")
    local roots_provider = assert(config.roots, "roots required")

    local runtime = {
        active = {},
        boot_selections = {},
        catalog = catalog,
        fatal_error = nil,
        last_error = nil,
        ledgers = {},
        mod = mod,
        pending = {},
        policy = policy,
        roots = {},
        setting_ids = {},
    }

    local valid, validation_error = policy.validate(catalog)
    if not valid then
        runtime.fatal_error = validation_error
        runtime.last_error = validation_error
        log_error("catalog rejected: %s", tostring(validation_error))
    end

    local registration
    if not runtime.fatal_error then
        local registration_error
        registration, registration_error = register_private_profiles(mod, catalog, policy)
        if not registration then
            runtime.fatal_error = registration_error
            runtime.last_error = registration_error
            log_error("profile catalog rejected: %s", tostring(registration_error))
        end
    end
    runtime.registration = registration or {
        count = 0, names = {}, private_by_state_name = {},
    }

    local family_by_id = {}
    for _, family in ipairs(catalog.families or {}) do
        family_by_id[family.id] = family
        runtime.setting_ids[family.setting_id] = true
        local selected = catalog.current_id
        if not runtime.fatal_error and type(mod.get) == "function" then
            local ok, value = pcall(mod.get, mod, family.setting_id)
            if ok and value ~= nil then selected = value end
        end
        if selected ~= catalog.current_id
                and not (type(family.states) == "table" and family.states[selected]) then
            log_error("invalid saved selection %s=%s; using Current",
                family.setting_id, tostring(selected))
            selected = catalog.current_id
        end
        runtime.boot_selections[family.setting_id] = selected
    end

    function runtime:_refresh_roots()
        local roots = roots_provider
        if type(roots_provider) == "function" then
            local ok, value = pcall(roots_provider)
            if not ok or type(value) ~= "table" then
                return nil, "history roots unavailable: " .. tostring(value)
            end
            roots = value
        end
        if type(roots) ~= "table" then return nil, "history roots unavailable" end
        self.roots = roots
        return roots
    end

    function runtime:_profiles_allowed()
        if type(self.mod._wt431_profiles_allowed) ~= "function" then return false end
        local ok, allowed = pcall(self.mod._wt431_profiles_allowed)
        return ok and allowed == true
    end

    function runtime:_transform(state_id, profile_names, parity, operation, value)
        local final_key = operation.path and operation.path[#operation.path]
        local scalar_profile_field = type(final_key) == "string"
            and final_key:find("damage_profile", 1, true) ~= nil
        if scalar_profile_field and type(value) == "string" and profile_names[value] then
            local private = self.registration.private_by_state_name[state_id]
                and self.registration.private_by_state_name[state_id][value]
            if not private then return nil, "private profile unavailable " .. value end
            return parity and private or value
        end
        if type(value) ~= "table" then return value end
        local function transform_table(node, seen, parent_key)
            local profile_field = type(parent_key) == "string"
                and parent_key:find("damage_profile", 1, true) ~= nil
            if profile_field and type(node) == "string" and profile_names[node] then
                local private = self.registration.private_by_state_name[state_id]
                    and self.registration.private_by_state_name[state_id][node]
                if not private then return nil, "private profile unavailable " .. node end
                return parity and private or node
            end
            if type(node) ~= "table" then return node end
            seen = seen or {}
            if seen[node] then return seen[node] end
            local copy = {}
            seen[node] = copy
            for key, child in pairs(node) do
                local transformed, transform_error = transform_table(child, seen, key)
                if transform_error then return nil, transform_error end
                copy[key] = transformed
            end
            return copy
        end
        return transform_table(value, nil, final_key)
    end

    function runtime:_extra_operations(family, state_id, state)
        local weapons = self.roots and self.roots.Weapons
        local private = self.registration.private_by_state_name[state_id] or {}
        local found, result, wanted = {}, {}, {}
        for _, native_name in ipairs(state.direct_profile_names or {}) do
            wanted[native_name] = true
            if not private[native_name] then
                return nil, "private profile route missing " .. native_name
            end
        end
        if next(wanted) == nil then return result end
        for _, template_name in ipairs(family.templates) do
            local template = type(weapons) == "table" and rawget(weapons, template_name)
            if type(template) == "table" then
                local routes = collect_profile_routes(
                    template, template_name, family, state_id, wanted, found)
                for _, route in ipairs(routes) do result[#result + 1] = route end
            end
        end
        for native_name in pairs(wanted) do
            if not found[native_name] then
                return nil, "native profile route not found " .. native_name
            end
        end
        return result
    end

    function runtime:_restore_family(family_id)
        local ledger = self.ledgers[family_id]
        if not ledger or #ledger == 0 then
            self.ledgers[family_id] = {}
            self.active[family_id] = nil
            return true
        end
        local restored, restore_error = self.policy.restore(ledger)
        if not restored then return nil, restore_error end
        self.ledgers[family_id] = {}
        self.active[family_id] = nil
        return true
    end

    function runtime:_apply_family(family, force_current)
        local selected = force_current and self.catalog.current_id
            or self.boot_selections[family.setting_id] or self.catalog.current_id
        local parity = self:_profiles_allowed()
        local ledger = self.ledgers[family.id] or {}
        local active = self.active[family.id]
        local status = #ledger > 0 and self.policy.ledger_status(ledger, self.roots) or "none"

        if selected == self.catalog.current_id then
            if #ledger == 0 then return true, false, selected, parity end
            if status == "drift" then return nil, "restore ownership lost", selected, parity end
            local restored, restore_error = self:_restore_family(family.id)
            return restored, restored and true or restore_error, selected, parity
        end
        if #ledger > 0 and status == "same" and active
                and active.state == selected and active.parity == parity then
            return true, false, selected, parity
        end
        if #ledger > 0 then
            if status == "drift" then
                return nil, "historical projection ownership drift", selected, parity
            end
            local restored, restore_error = self:_restore_family(family.id)
            if not restored then return nil, restore_error, selected, parity end
        end

        local state = family.states[selected]
        local profile_names = {}
        for _, name in ipairs(state.profile_names or {}) do profile_names[name] = true end
        local plan, plan_error = self.policy.build_family_plan(
            self.catalog, family, selected, self.roots, {
                validated = true,
                transform = function(operation, value)
                    return self:_transform(selected, profile_names, parity, operation, value)
                end,
                extra_operations = function()
                    return self:_extra_operations(family, selected, state)
                end,
            })
        if not plan then return nil, plan_error, selected, parity end
        local committed, commit_error = self.policy.commit(plan)
        if not committed then return nil, commit_error, selected, parity end
        self.ledgers[family.id] = committed
        self.active[family.id] = { state = selected, parity = parity }
        return true, true, selected, parity
    end

    function runtime:_apply_all(force_current)
        if self.fatal_error then return nil, self.fatal_error end
        local roots, roots_error = self:_refresh_roots()
        if not roots then self.last_error = roots_error; return nil, roots_error end
        local changed, historical, gated, refused, writes = false, 0, 0, 0, 0
        for _, family in ipairs(self.catalog.families) do
            local ok, changed_or_error, state, parity = self:_apply_family(
                family, force_current == true)
            if not ok then
                refused = refused + 1
                self.last_error = changed_or_error
                log_error("%s projection refused: %s", family.id,
                    tostring(changed_or_error))
            else
                if changed_or_error == true then changed = true end
                if state ~= self.catalog.current_id then
                    historical = historical + 1
                    if not parity then gated = gated + 1 end
                    writes = writes + #(self.ledgers[family.id] or {})
                end
            end
        end
        if refused == 0 then self.last_error = nil end
        log_info(self.mod,
            "[wt:1436] catalog=%s historical=%d refused=%d profile_gated=%d writes=%d restart_bound=true",
            tostring(self.catalog.catalog_id), historical, refused, gated, writes)
        return {
            changed = changed,
            gated = gated,
            historical = historical,
            refused = refused,
            writes = writes,
        }
    end

    function runtime:reapply()
        return self:_apply_all(false)
    end

    function runtime:restore()
        return self:_apply_all(true)
    end

    function runtime:is_setting(setting_id)
        return self.setting_ids[setting_id] == true
    end

    function runtime:on_setting_changed(setting_id)
        if not self:is_setting(setting_id) then return false end
        local saved = self.catalog.current_id
        if type(self.mod.get) == "function" then
            local ok, value = pcall(self.mod.get, self.mod, setting_id)
            if ok and value ~= nil then saved = value end
        end
        local pending = saved ~= self.boot_selections[setting_id]
        self.pending[setting_id] = pending or nil
        if pending then
            log_info(self.mod,
                "[wt:1436] %s saved as %s; restart required (boot=%s)",
                setting_id, tostring(saved),
                tostring(self.boot_selections[setting_id]))
        end
        return true
    end

    function runtime:on_settings_batch_changed(setting_ids)
        local handled = 0
        for _, setting_id in ipairs(setting_ids or {}) do
            if self:on_setting_changed(setting_id) then handled = handled + 1 end
        end
        return handled
    end

    function runtime:private_profiles_for_family(family_id)
        local family = family_by_id[family_id]
        if type(family) ~= "table" then return {} end
        local rows, seen = {}, {}
        for _, state_id in ipairs(family.state_order or {}) do
            local state = family.states and family.states[state_id]
            local mapping = self.registration.private_by_state_name[state_id] or {}
            for _, native_name in ipairs(state and state.profile_names or {}) do
                local private_name = mapping[native_name]
                if type(private_name) == "string" and not seen[private_name] then
                    seen[private_name] = true
                    rows[#rows + 1] = private_name
                end
            end
        end
        table.sort(rows)
        return rows
    end

    function runtime:verify()
        if self.fatal_error then return self.fatal_error end
        if self.last_error then return self.last_error end
        for _, family in ipairs(self.catalog.families) do
            local selected = self.boot_selections[family.setting_id]
            local ledger = self.ledgers[family.id] or {}
            if selected == self.catalog.current_id then
                if #ledger ~= 0 then return "Current selection has gameplay writes" end
            else
                if #ledger == 0 then return family.id .. " historical selection has no ledger" end
                if self.policy.ledger_status(ledger, self.roots) ~= "same" then
                    return family.id .. " history ledger drifted"
                end
            end
        end
        return nil
    end

    runtime.family_by_id = family_by_id
    if not runtime.fatal_error then runtime:_apply_all(false) end
    return runtime
end

return M
