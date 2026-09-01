-- _la_registration_owner.lua
--
-- Owns the all-or-nothing Loremaster's Armoury registration transaction. It
-- discovers clone rows and lookup additions off-table, validates both strict
-- lookup tables on shadows, snapshots every live publication surface, and
-- publishes LA readiness only after the complete commit succeeds.
--
-- Owned by: _la_bridge.lua. Consumed via: LA_BRIDGE.register_all().

local M = {}

local BRIDGE_REPLACE_FIELDS = {
    "unit_path_to_clones",
    "la_offhand_options_by_weapon_type",
    "_la_offhand_resolution",
    "la_path_to_parent_package",
}

local BRIDGE_MERGE_FIELDS = {
    "localization",
    "backend_to_armoury",
    "backend_to_vanilla",
    "armoury_to_backend",
}

local function valid_string(value)
    return type(value) == "string" and value ~= ""
end

local function shallow_copy(source)
    local copy = {}
    if type(source) == "table" then
        for key, value in next, source do
            rawset(copy, key, value)
        end
    end
    return copy
end

local function replace_contents(target, source)
    for key in next, target do
        rawset(target, key, nil)
    end
    for key, value in next, source do
        rawset(target, key, value)
    end
end

local function merge_contents(target, source)
    for key, value in next, source do
        rawset(target, key, value)
    end
end

local function sorted_keys(source)
    local keys = {}
    for key in next, source do
        if type(key) == "string" then
            keys[#keys + 1] = key
        end
    end
    table.sort(keys)
    return keys
end

local function append_unique(list, seen, value)
    if valid_string(value) and not seen[value] then
        seen[value] = true
        list[#list + 1] = value
    end
end

local function safe_call(method, self, ...)
    local args = { ... }
    local count = select("#", ...)
    return pcall(function()
        return method(self, unpack(args, 1, count))
    end)
end

local function persistent_table(owner, name)
    if type(owner) ~= "table" or type(owner.persistent_table) ~= "function" then
        return nil, "mil_persistent_api_missing"
    end
    local ok, value = safe_call(owner.persistent_table, owner, name)
    if not ok then
        return nil, "mil_persistent_read_failed"
    end
    if type(value) ~= "table" then
        return nil, "mil_persistent_table_missing"
    end
    return value, nil
end

local function snapshot_once(snapshots, seen, target)
    if type(target) ~= "table" or seen[target] then return end
    seen[target] = true
    snapshots[#snapshots + 1] = {
        target = target,
        contents = shallow_copy(target),
    }
end

local function restore_snapshots(snapshots)
    for i = #snapshots, 1, -1 do
        local row = snapshots[i]
        replace_contents(row.target, row.contents)
    end
end

local function snapshot_table_field(snapshots, seen, fields, owner, field)
    if type(owner) ~= "table" then return end
    local value = rawget(owner, field)
    fields[#fields + 1] = { owner = owner, field = field, value = value }
    snapshot_once(snapshots, seen, value)
end

local function restore_table_fields(fields)
    for i = #fields, 1, -1 do
        local row = fields[i]
        rawset(row.owner, row.field, row.value)
    end
end

local function build_plan(deps, skin_list, item_master_list)
    local plan = {
        entries = {},
        item_names = {},
        inventory_packages = {},
        skipped = {},
        localization = {},
        backend_to_armoury = {},
        backend_to_vanilla = {},
        armoury_to_backend = {},
        unit_path_to_clones = {},
        la_offhand_options_by_weapon_type = {},
        _la_offhand_resolution = {},
        la_path_to_parent_package = {},
    }

    local package_seen = {}
    local unit_index = deps.build_unit_index(item_master_list)
    local keys = sorted_keys(skin_list)

    -- Package discovery is unconditional on runtime residency. Every peer with
    -- the same LA catalog therefore plans the same numeric lookup additions.
    for i = 1, #keys do
        local variant = rawget(skin_list, keys[i])
        if type(variant) == "table" and variant.kind == "unit"
                and type(variant.new_units) == "table" then
            append_unique(plan.inventory_packages, package_seen, variant.new_units[1])
            append_unique(plan.inventory_packages, package_seen, variant.new_units[2])
        end
    end
    table.sort(plan.inventory_packages)

    for i = 1, #keys do
        local la_key = keys[i]
        local variant = rawget(skin_list, la_key)
        local hand = type(variant) == "table" and variant.swap_hand or nil
        if hand == "hat" or hand == "armor" then
            local vanilla_key, unit_path = deps.pick_vanilla_key(variant, unit_index)
            if not vanilla_key and hand == "armor" and valid_string(variant.cosmetic_key) then
                vanilla_key = variant.cosmetic_key
                if not rawget(item_master_list, vanilla_key) then vanilla_key = nil end
                if vanilla_key and type(variant.new_units) == "table" then
                    unit_path = variant.new_units[1]
                end
            end

            if vanilla_key then
                local backend_id = vanilla_key .. "_LA_" .. la_key
                local name_override = hand == "armor" and vanilla_key or nil
                local entry = deps.build_clone_entry(
                    vanilla_key, la_key, backend_id, name_override,
                    plan.localization, item_master_list)
                if entry then
                    plan.entries[#plan.entries + 1] = entry
                    plan.item_names[#plan.item_names + 1] = backend_id
                    plan.backend_to_armoury[backend_id] = la_key
                    plan.backend_to_vanilla[backend_id] = vanilla_key
                    plan.armoury_to_backend[la_key] = backend_id
                    if unit_path then
                        local clones = plan.unit_path_to_clones[unit_path]
                        if not clones then
                            clones = {}
                            plan.unit_path_to_clones[unit_path] = clones
                        end
                        clones[#clones + 1] = backend_id
                    end
                end
            else
                plan.skipped[#plan.skipped + 1] = la_key
            end
        end
    end
    table.sort(plan.item_names)
    table.sort(plan.skipped)

    local ok, reason = deps.plan_offhand_options(plan, skin_list)
    if ok == false then
        return nil, reason or "offhand_plan_rejected"
    end
    local parents = deps.plan_parent_packages(skin_list)
    if type(parents) ~= "table" then
        return nil, "parent_package_plan_rejected"
    end
    plan.la_path_to_parent_package = parents
    return plan, nil
end

local function plan_lookup(network_lookup_lib, live, names, label)
    if type(live) ~= "table" then
        return nil, label .. ":lookup_missing"
    end
    local shadow = shallow_copy(live)
    for i = 1, #names do
        local index, _, reason = network_lookup_lib.register(shadow, names[i])
        if not index then
            return nil, label .. ":" .. tostring(reason)
        end
    end
    return shadow, nil
end

local function validate_iml_targets(item_master_list, entries)
    local seen = {}
    for i = 1, #entries do
        local entry = entries[i]
        local key = entry and (entry.key or entry.name)
        if not valid_string(key) or seen[key] then
            return false, "iml_key_invalid"
        end
        seen[key] = true
        local existing = rawget(item_master_list, key)
        if existing ~= nil then
            if type(existing) ~= "table"
                    or existing.cos_la_armoury_key ~= entry.cos_la_armoury_key
                    or existing.cos_la_vanilla_key ~= entry.cos_la_vanilla_key then
                return false, "iml_conflict:" .. key
            end
        end
    end
    return true, nil
end

local function validate_backend_targets(backend_mod_items, entries)
    for i = 1, #entries do
        local entry = entries[i]
        local backend_id = entry.mod_data and entry.mod_data.backend_id
        local existing = backend_id and rawget(backend_mod_items, backend_id)
        if existing ~= nil and existing ~= false then
            local data = type(existing) == "table" and existing.data or nil
            if type(data) ~= "table"
                    or data.cos_la_armoury_key ~= entry.cos_la_armoury_key
                    or data.cos_la_vanilla_key ~= entry.cos_la_vanilla_key then
                return false, "mil_backend_conflict:" .. tostring(backend_id)
            end
        end
    end
    return true, nil
end

local function validate_bridge_merges(bridge, plan)
    for i = 1, #BRIDGE_MERGE_FIELDS do
        local field = BRIDGE_MERGE_FIELDS[i]
        local live = bridge[field]
        for key, value in next, plan[field] do
            local existing = rawget(live, key)
            if existing ~= nil and existing ~= value then
                return false, "bridge_conflict:" .. field .. ":" .. tostring(key)
            end
        end
    end
    return true, nil
end

local function verify_backend_rows(backend_mod_items, entries)
    for i = 1, #entries do
        local entry = entries[i]
        local mod_data = entry.mod_data or {}
        local backend_id = mod_data.backend_id
            or ("cosmetics_tweaker_" .. tostring(entry.name))
        local backend_item = rawget(backend_mod_items, backend_id)
        if type(backend_item) ~= "table" or backend_item.data ~= entry then
            return false, "mil_backend_row_missing:" .. tostring(backend_id)
        end
    end
    return true, nil
end

local function validate_dependencies(deps)
    local required_functions = {
        "get_la", "get_mil", "get_item_master_list", "get_network_lookup",
        "get_managers",
        "build_unit_index", "pick_vanilla_key", "build_clone_entry",
        "plan_offhand_options", "plan_parent_packages",
    }
    for i = 1, #required_functions do
        if type(deps[required_functions[i]]) ~= "function" then
            return false, "dependency_missing:" .. required_functions[i]
        end
    end
    if type(deps.bridge) ~= "table" then return false, "bridge_missing" end
    if type(deps.network_lookup_lib) ~= "table"
            or type(deps.network_lookup_lib.register) ~= "function" then
        return false, "network_lookup_lib_missing"
    end
    return true, nil
end

function M.new(deps)
    assert(type(deps) == "table", "LA registration owner requires dependencies")
    local valid, invalid_reason = validate_dependencies(deps)
    assert(valid, invalid_reason)

    local owner = {}

    function owner.register_all()
        local bridge = deps.bridge
        if bridge.la_registered then
            return true, "already_registered"
        end

        local la_mod = deps.get_la()
        local mil_mod = deps.get_mil()
        local item_master_list = deps.get_item_master_list()
        local network_lookup = deps.get_network_lookup()
        local skin_list = la_mod and la_mod.SKIN_LIST
        if type(la_mod) ~= "table" then return false, "la_missing" end
        if type(mil_mod) ~= "table" then return false, "mil_missing" end
        if type(mil_mod.add_mod_items_to_local_backend) ~= "function" then
            return false, "mil_add_api_missing"
        end
        if type(item_master_list) ~= "table" then return false, "iml_missing" end
        if type(skin_list) ~= "table" then return false, "skin_list_missing" end
        if type(network_lookup) ~= "table" then return false, "network_lookup_missing" end

        for i = 1, #BRIDGE_REPLACE_FIELDS do
            if type(bridge[BRIDGE_REPLACE_FIELDS[i]]) ~= "table" then
                return false, "bridge_table_missing:" .. BRIDGE_REPLACE_FIELDS[i]
            end
        end
        for i = 1, #BRIDGE_MERGE_FIELDS do
            if type(bridge[BRIDGE_MERGE_FIELDS[i]]) ~= "table" then
                return false, "bridge_table_missing:" .. BRIDGE_MERGE_FIELDS[i]
            end
        end

        local plan, plan_reason = build_plan(deps, skin_list, item_master_list)
        if not plan then return false, plan_reason end

        local iml_ok, iml_reason = validate_iml_targets(item_master_list, plan.entries)
        if not iml_ok then return false, iml_reason end

        local inventory_packages = rawget(network_lookup, "inventory_packages")
        local item_names = rawget(network_lookup, "item_names")
        local inventory_shadow, inventory_reason = plan_lookup(
            deps.network_lookup_lib, inventory_packages,
            plan.inventory_packages, "inventory_packages")
        if not inventory_shadow then return false, inventory_reason end
        local item_names_shadow, item_names_reason = plan_lookup(
            deps.network_lookup_lib, item_names, plan.item_names, "item_names")
        if not item_names_shadow then return false, item_names_reason end

        local backend_mod_items, backend_reason = persistent_table(
            mil_mod, "backend_mod_items")
        if not backend_mod_items then return false, backend_reason end
        local new_masterlist_entries, master_reason = persistent_table(
            mil_mod, "new_masterlist_entries")
        if not new_masterlist_entries then return false, master_reason end

        local backend_ok, backend_conflict = validate_backend_targets(
            backend_mod_items, plan.entries)
        if not backend_ok then return false, backend_conflict end
        local bridge_ok, bridge_conflict = validate_bridge_merges(bridge, plan)
        if not bridge_ok then return false, bridge_conflict end

        local managers_ok, managers = pcall(deps.get_managers)
        if not managers_ok then return false, "managers_read_failed" end
        local backend = type(managers) == "table" and managers.backend or nil
        if type(backend) ~= "table" then return false, "backend_missing" end
        local interfaces = rawget(backend, "_interfaces")
        local item_interface = type(interfaces) == "table"
            and rawget(interfaces, "items") or nil
        if type(backend.get_interface) == "function" then
            local interface_ok, resolved = safe_call(
                backend.get_interface, backend, "items")
            if not interface_ok then return false, "backend_items_read_failed" end
            if resolved ~= nil then item_interface = resolved end
        end
        if type(item_interface) ~= "table" then
            return false, "backend_items_missing"
        end

        local snapshots, seen, fields = {}, {}, {}
        snapshot_once(snapshots, seen, item_master_list)
        snapshot_once(snapshots, seen, inventory_packages)
        snapshot_once(snapshots, seen, item_names)
        snapshot_once(snapshots, seen, backend_mod_items)
        snapshot_once(snapshots, seen, new_masterlist_entries)
        for i = 1, #BRIDGE_REPLACE_FIELDS do
            snapshot_once(snapshots, seen, bridge[BRIDGE_REPLACE_FIELDS[i]])
        end
        for i = 1, #BRIDGE_MERGE_FIELDS do
            snapshot_once(snapshots, seen, bridge[BRIDGE_MERGE_FIELDS[i]])
        end

        -- MIL can project persistent rows into these mirrors. Snapshot the
        -- exact tables if its mirror has already been captured; nil/pre-ready
        -- mirror state remains a supported no-op.
        local backend_mirror = nil
        local general_data = persistent_table(mil_mod, "more_items_general_data")
        if type(general_data) == "table"
                and rawget(general_data, "backend_mirror_persisted") then
            local mirror_reason
            backend_mirror, mirror_reason = persistent_table(
                mil_mod, "backend_mirror_more_items")
            if not backend_mirror then return false, mirror_reason end
        end
        snapshot_table_field(snapshots, seen, fields,
            backend_mirror, "_inventory_items")
        snapshot_table_field(snapshots, seen, fields,
            backend_mirror, "_fake_inventory_items")
        snapshot_table_field(snapshots, seen, fields,
            backend_mirror, "_unlocked_cosmetics")
        snapshot_table_field(snapshots, seen, fields, item_interface, "_items")
        local dirty_before = nil
        if item_interface then dirty_before = rawget(item_interface, "_dirty") end

        local readiness_before = {
            la_registered = rawget(bridge, "la_registered"),
            registered = rawget(bridge, "registered"),
        }

        local function rollback()
            restore_snapshots(snapshots)
            restore_table_fields(fields)
            if item_interface then rawset(item_interface, "_dirty", dirty_before) end
            rawset(bridge, "la_registered", readiness_before.la_registered)
            rawset(bridge, "registered", readiness_before.registered)
        end

        local function fault(stage)
            if type(deps.fault) == "function" then deps.fault(stage) end
        end

        local commit_ok, commit_error = xpcall(function()
            mil_mod:add_mod_items_to_local_backend(plan.entries, "cosmetics_tweaker")
            local backend_ok, verify_reason = verify_backend_rows(
                backend_mod_items, plan.entries)
            if not backend_ok then error(verify_reason) end
            fault("after_mil")

            for i = 1, #plan.entries do
                local entry = plan.entries[i]
                rawset(item_master_list, entry.key or entry.name, entry)
            end
            fault("after_iml")

            replace_contents(inventory_packages, inventory_shadow)
            fault("after_inventory_packages")
            replace_contents(item_names, item_names_shadow)
            fault("after_item_names")

            for i = 1, #BRIDGE_MERGE_FIELDS do
                local field = BRIDGE_MERGE_FIELDS[i]
                merge_contents(bridge[field], plan[field])
            end
            for i = 1, #BRIDGE_REPLACE_FIELDS do
                local field = BRIDGE_REPLACE_FIELDS[i]
                replace_contents(bridge[field], plan[field])
            end
            fault("after_bridge")

            -- Readiness is deliberately the final publication write.
            bridge.registered = true
            fault("after_registered")
            bridge.la_registered = true
        end, function(err) return tostring(err) end)

        if not commit_ok then
            rollback()
            return false, "commit_failed:" .. tostring(commit_error)
        end

        return true, "registered", plan
    end

    return owner
end

return M
