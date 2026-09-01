-- Generate the bounded Patch 6.11.0 Longbow and shared Hammer/Mace history
-- catalog (#1436).
--
-- Usage:
--   lua5.1 generate_patch_6_11_0_history.lua <source-repo> <evidence-dir> <output.lua>
--
-- Both Longbow templates own the same adjacent aim_zoom_delay leaf. The two
-- Hammer/Mace source files expose the same block-angle and dodge-count leaves
-- across three templates. Each family is emitted atomically over independently
-- rehydrated current guards; later changes elsewhere remain current.

local source_repo = assert(arg[1], "source repository path required")
local evidence_dir = assert(arg[2], "evidence directory required")
local output_path = assert(arg[3], "output path required")

assert(os.setlocale("C", "numeric"), "C numeric locale unavailable")

local function load_data(path)
    local chunk, load_error = loadfile(path)
    assert(chunk, load_error)
    local ok, value = pcall(chunk)
    assert(ok, value)
    assert(type(value) == "table", "evidence module must return a table")
    return value
end

local normalized_script = tostring(arg[0] or ""):gsub("\\", "/")
local script_dir = normalized_script:match("^(.*)/[^/]+$") or "."
local current_anchor = load_data(script_dir .. "/current_source_anchor.lua")
assert(current_anchor.schema == 1, "unsupported current source anchor")

local function shell_quote(value)
    return '"' .. tostring(value):gsub('"', '\\"') .. '"'
end

local function command_output(command)
    local pipe = assert(io.popen(command, "r"))
    local output = pipe:read("*a")
    pipe:close()
    return (output or ""):gsub("%s+$", "")
end

local function git_blob(revision, path)
    local value = command_output("git -C " .. shell_quote(source_repo)
        .. " rev-parse " .. shell_quote(revision .. ":" .. path) .. " 2>nul")
    assert(value:match("^[0-9a-f][0-9a-f]+$") and #value == 40,
        "source blob unavailable for " .. revision .. ":" .. path)
    return value
end

local function count_keys(value)
    local count = 0
    for _ in pairs(value or {}) do count = count + 1 end
    return count
end

local function array_length(value)
    assert(type(value) == "table", "array required")
    local count, maximum = 0, 0
    for key in pairs(value) do
        assert(type(key) == "number" and key >= 1 and key % 1 == 0,
            "array has a non-index key")
        count = count + 1
        if key > maximum then maximum = key end
    end
    assert(count == maximum, "array is sparse")
    return count
end

local function exact_keys(value, expected, label)
    assert(type(value) == "table", label .. " must be a table")
    local allowed = {}
    for _, key in ipairs(expected) do allowed[key] = true end
    for key in pairs(value) do
        assert(allowed[key], label .. " has unexpected key " .. tostring(key))
    end
    for _, key in ipairs(expected) do
        assert(value[key] ~= nil, label .. " is missing key " .. key)
    end
end

local expected_path = {
    "actions", "action_two", "default", "aim_zoom_delay",
}

local function validate_longbow_snapshot(snapshot, rehydrated, catalog)
    exact_keys(snapshot, { "new_revision", "old_revision", "records" },
        rehydrated and "rehydrated snapshot" or "adjacent snapshot")
    assert(snapshot.old_revision == catalog.boundary.historical_revision,
        "historical revision drift")
    assert(snapshot.new_revision == catalog.boundary.post_revision,
        "boundary revision drift")
    assert(array_length(snapshot.records) == 2, "snapshot record budget drift")
    local operations = {}
    for index, expected_template in ipairs(catalog.family.templates) do
        local record = snapshot.records[index]
        exact_keys(record, { "ops", "source_path", "template", "unsupported" },
            "snapshot record " .. index)
        assert(record.source_path == catalog.source_path, "source path drift")
        assert(record.template == expected_template,
            "template order or identity drift at record " .. index)
        assert(count_keys(record.unsupported) == 0,
            "unsupported source delta present at record " .. index)
        assert(array_length(record.ops) == 1,
            "operation budget drift at record " .. index)
        local operation = record.ops[1]
        local operation_keys = rehydrated
            and { "expected_current", "expected_current_unset", "path", "unset", "value" }
            or { "path", "unset", "value" }
        exact_keys(operation, operation_keys, "snapshot operation " .. index)
        assert(array_length(operation.path) == #expected_path,
            "operation path length drift at record " .. index)
        for path_index, key in ipairs(expected_path) do
            assert(operation.path[path_index] == key,
                "operation path drift at record " .. index .. "/" .. path_index)
        end
        assert(operation.unset == false and operation.value == 2,
            "historical aim zoom delay drift at record " .. index)
        if rehydrated then
            assert(operation.expected_current_unset == false
                    and operation.expected_current == 0.22,
                "current aim zoom delay guard drift at record " .. index)
        end
        operations[index] = operation
    end
    return operations
end

local hammer_paths = {
    { "block_angle" },
    { "dodge_count" },
}
local hammer_historical_values = { 90, 3 }
local hammer_current_values = { 120, 4 }

local function validate_hammer_snapshot(snapshot, rehydrated, catalog, source)
    exact_keys(snapshot, { "new_revision", "old_revision", "records" },
        rehydrated and "rehydrated Hammer/Mace snapshot"
            or "adjacent Hammer/Mace snapshot")
    assert(snapshot.old_revision == catalog.boundary.historical_revision,
        "Hammer/Mace historical revision drift")
    assert(snapshot.new_revision == catalog.boundary.post_revision,
        "Hammer/Mace boundary revision drift")
    assert(array_length(snapshot.records) == #source.templates,
        "Hammer/Mace snapshot record budget drift")
    local operations = {}
    for index, expected_template in ipairs(source.templates) do
        local record = snapshot.records[index]
        exact_keys(record, { "ops", "source_path", "template", "unsupported" },
            "Hammer/Mace snapshot record " .. index)
        assert(record.source_path == source.path,
            "Hammer/Mace source path drift")
        assert(record.template == expected_template,
            "Hammer/Mace template order or identity drift at record " .. index)
        assert(count_keys(record.unsupported) == 0,
            "unsupported Hammer/Mace source delta at record " .. index)
        assert(array_length(record.ops) == 2,
            "Hammer/Mace operation budget drift at record " .. index)
        operations[index] = {}
        for operation_index = 1, 2 do
            local operation = record.ops[operation_index]
            local operation_keys = rehydrated
                and { "expected_current", "expected_current_unset", "path", "unset", "value" }
                or { "path", "unset", "value" }
            exact_keys(operation, operation_keys,
                "Hammer/Mace snapshot operation " .. index .. "/"
                    .. operation_index)
            assert(array_length(operation.path) == 1
                    and operation.path[1] == hammer_paths[operation_index][1],
                "Hammer/Mace operation path drift at " .. index .. "/"
                    .. operation_index)
            assert(operation.unset == false
                    and operation.value == hammer_historical_values[operation_index],
                "historical Hammer/Mace value drift at " .. index .. "/"
                    .. operation_index)
            if rehydrated then
                assert(operation.expected_current_unset == false
                        and operation.expected_current
                            == hammer_current_values[operation_index],
                    "current Hammer/Mace guard drift at " .. index .. "/"
                        .. operation_index)
            end
            operations[index][operation_index] = operation
        end
    end
    return operations
end

local source_catalog = load_data(evidence_dir
    .. "/_wt_history_6_11_0_source_catalog.lua")
assert(source_catalog.schema == 2, "unsupported Patch 6.11.0 source catalog")
assert(source_catalog.current.revision == current_anchor.content_revision,
    "unexpected current revision")
assert(array_length(source_catalog.family.templates) == 2,
    "Longbow family template budget drift")
assert(git_blob(source_catalog.boundary.historical_revision,
        source_catalog.source_path) == source_catalog.boundary.historical_blob,
    "historical source blob drift")
assert(git_blob(source_catalog.boundary.post_revision,
        source_catalog.source_path) == source_catalog.boundary.post_blob,
    "post-boundary source blob drift")
assert(git_blob(source_catalog.current.revision,
        source_catalog.source_path) == source_catalog.current.blob,
    "current source blob drift")

local adjacent = load_data(evidence_dir
    .. "/_wt_history_snapshot_6_10_0_to_6_11_0_generated.lua")
local rehydrated = load_data(evidence_dir
    .. "/_wt_history_snapshot_6_10_0_rehydrated_generated.lua")
validate_longbow_snapshot(adjacent, false, source_catalog)
local source_operations = validate_longbow_snapshot(
    rehydrated, true, source_catalog)

assert(array_length(source_catalog.hammer_sources) == 2,
    "Hammer/Mace source-file budget drift")
assert(array_length(source_catalog.hammer_family.templates) == 3,
    "Hammer/Mace family template budget drift")
local hammer_operations = {}
local hammer_template_index = 0
for _, source in ipairs(source_catalog.hammer_sources) do
    assert(git_blob(source_catalog.boundary.historical_revision, source.path)
            == source.historical_blob,
        "Hammer/Mace historical source blob drift")
    assert(git_blob(source_catalog.boundary.post_revision, source.path)
            == source.post_blob,
        "Hammer/Mace post-boundary source blob drift")
    assert(git_blob(source_catalog.current.revision, source.path)
            == source.current_blob,
        "Hammer/Mace current source blob drift")
    local hammer_adjacent = load_data(evidence_dir
        .. "/_wt_history_snapshot_6_10_0_" .. source.evidence_stem
        .. "_to_6_11_0_generated.lua")
    local hammer_rehydrated = load_data(evidence_dir
        .. "/_wt_history_snapshot_6_10_0_" .. source.evidence_stem
        .. "_rehydrated_generated.lua")
    validate_hammer_snapshot(hammer_adjacent, false, source_catalog, source)
    local evaluated = validate_hammer_snapshot(
        hammer_rehydrated, true, source_catalog, source)
    for template_index, template in ipairs(source.templates) do
        hammer_template_index = hammer_template_index + 1
        assert(source_catalog.hammer_family.templates[hammer_template_index]
                == template,
            "Hammer/Mace family/source template order drift")
        for operation_index = 1, 2 do
            local operation = evaluated[template_index][operation_index]
            hammer_operations[#hammer_operations + 1] = {
                change_class = "official_weapon_balance",
                current_source_blob = source.current_blob,
                expected_current = operation.expected_current,
                expected_present = true,
                family_id = source_catalog.hammer_family.id,
                official_change_id = source_catalog.hammer_official_change_id,
                official_summary = source_catalog.hammer_official_summary,
                path = operation.path,
                result = operation.value,
                result_present = true,
                root = "Weapons",
                source_blob = source.historical_blob,
                source_path = source.path,
                source_revision = source_catalog.boundary.historical_revision,
                state_id = source_catalog.state.id,
                template = template,
            }
        end
    end
end
assert(hammer_template_index == 3 and #hammer_operations == 6,
    "Hammer/Mace emitted operation budget drift")

local family = source_catalog.family
local state = source_catalog.state
local operations = {}
for index, template in ipairs(family.templates) do
    local operation = source_operations[index]
    operations[index] = {
        change_class = "official_weapon_balance",
        current_source_blob = source_catalog.current.blob,
        expected_current = operation.expected_current,
        expected_present = true,
        family_id = family.id,
        official_change_id = source_catalog.official_change_id,
        official_summary = source_catalog.official_summary,
        path = operation.path,
        result = operation.value,
        result_present = true,
        root = "Weapons",
        source_blob = source_catalog.boundary.historical_blob,
        source_path = source_catalog.source_path,
        source_revision = source_catalog.boundary.historical_revision,
        state_id = state.id,
        template = template,
    }
end

local hammer_family = source_catalog.hammer_family
local catalog = {
    catalog_id = "wt_history_patch_6_11_0_v2",
    current_id = "current",
    current_source = {
        display_name = "Current (Game Version " .. current_anchor.game_version .. ")",
        label = current_anchor.game_version .. " source anchor",
        revision = source_catalog.current.revision,
    },
    derived_profiles = {},
    families = {
        {
            display_name = family.display_name,
            id = family.id,
            label_key = family.label_key,
            setting_id = family.setting_id,
            state_order = { state.id },
            states = {
                [state.id] = {
                    direct_profile_names = {},
                    operations = operations,
                    profile_names = {},
                },
            },
            templates = family.templates,
        },
        {
            display_name = hammer_family.display_name,
            id = hammer_family.id,
            label_key = hammer_family.label_key,
            setting_id = hammer_family.setting_id,
            state_order = { state.id },
            states = {
                [state.id] = {
                    direct_profile_names = {},
                    operations = hammer_operations,
                    profile_names = {},
                },
            },
            templates = hammer_family.templates,
        },
    },
    generation = {
        adjacent_operation_count = 8,
        global_operations = 0,
        profile_route_count = 0,
        unsupported_count = 0,
    },
    profile_specs = {},
    schema = 2,
    states = {
        [state.id] = {
            change_class = "official_weapon_balance",
            display_name = state.display_name,
            label_key = state.label_key,
            official_patch_notes = source_catalog.official_patch_notes,
            source_revision = source_catalog.boundary.historical_revision,
        },
    },
}

local function sorted_keys(value)
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(left, right)
        if type(left) == type(right) then return left < right end
        return type(left) < type(right)
    end)
    return keys
end

local function serialize(value, indent, active)
    indent = indent or 0
    local kind = type(value)
    if value == nil then return "nil" end
    if kind == "boolean" then return tostring(value) end
    if kind == "number" then
        assert(value == value, "cannot serialize NaN")
        if value == math.huge then return "math.huge" end
        if value == -math.huge then return "-math.huge" end
        return string.format("%.17g", value)
    end
    if kind == "string" then return string.format("%q", value) end
    assert(kind == "table", "cannot serialize " .. kind)
    active = active or {}
    assert(not active[value], "cycle in generated catalog")
    active[value] = true
    local keys = sorted_keys(value)
    if #keys == 0 then active[value] = nil; return "{}" end
    local pad = string.rep(" ", indent)
    local child_pad = string.rep(" ", indent + 4)
    local parts = { "{" }
    for _, key in ipairs(keys) do
        local rendered_key
        if type(key) == "string" and key:match("^[%a_][%w_]*$") then
            rendered_key = key
        else
            rendered_key = "[" .. serialize(key, indent + 4, active) .. "]"
        end
        parts[#parts + 1] = "\n" .. child_pad .. rendered_key .. " = "
            .. serialize(value[key], indent + 4, active) .. ","
    end
    parts[#parts + 1] = "\n" .. pad .. "}"
    active[value] = nil
    return table.concat(parts)
end

local file = assert(io.open(output_path, "wb"))
file:write("-- AUTO-GENERATED by tools/weapon-history/generate_patch_6_11_0_history.lua; DO NOT HAND-EDIT.\n")
file:write("return ", serialize(catalog), "\n")
file:close()

print("generated " .. output_path .. " families=2 operations=8 profiles=0 globals=0")
