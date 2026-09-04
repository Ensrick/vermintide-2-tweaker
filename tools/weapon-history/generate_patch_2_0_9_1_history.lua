-- Generate the bounded Patch 2.0.9.1 Halberd history catalog (#1436).
-- Usage:
--   lua5.1 generate_patch_2_0_9_1_history.lua <source-repo> <evidence-dir> <output.lua>

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
assert(current_anchor.schema == 1 or current_anchor.schema == 2,
    "unsupported current source anchor")

local function shell_quote(value)
    return '"' .. tostring(value):gsub('"', '\\"') .. '"'
end

local function command_output(command)
    local pipe = assert(io.popen(command, "r"))
    local output = pipe:read("*a")
    local ok = pipe:close()
    assert(ok, "command failed: " .. command)
    return (output or ""):gsub("%s+$", "")
end

local function git_blob(revision, path)
    local value = command_output("git -C " .. shell_quote(source_repo)
        .. " rev-parse " .. shell_quote(revision .. ":" .. path) .. " 2>nul")
    assert(value:match("^[0-9a-f]+$") and #value == 40,
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
        assert(rawget(value, key) ~= nil, label .. " is missing key " .. key)
    end
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

local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, child in pairs(value) do result[copy(key, seen)] = copy(child, seen) end
    return result
end

local source_catalog = load_data(evidence_dir
    .. "/_wt_history_2_0_9_1_source_catalog.lua")
assert(source_catalog.schema == 1, "unsupported Patch 2.0.9.1 source catalog")
assert(source_catalog.boundary.historical_revision
        == "6d41bab482ac64ebebc5c8bba2c3a47954952af9",
    "unexpected historical revision")
assert(source_catalog.boundary.post_revision
        == "90c7c21adb7aa2b7de5fcdca5094727895fbeb1a",
    "unexpected post-boundary revision")
assert(source_catalog.current.revision == current_anchor.content_revision,
    "unexpected current revision")
assert(git_blob(source_catalog.boundary.historical_revision,
        source_catalog.source_path) == source_catalog.boundary.historical_blob,
    "historical source blob drift")
assert(git_blob(source_catalog.boundary.post_revision,
        source_catalog.source_path) == source_catalog.boundary.post_blob,
    "post-boundary source blob drift")
assert(git_blob(source_catalog.current.revision,
        source_catalog.source_path) == source_catalog.current.blob,
    "current source blob drift")

local expected_operations = {
    { index = 1, key = "end_time", unset = true, current = 0.6 },
    { index = 1, key = "start_time", value = 0.6, current = 0.5 },
    { index = 1, key = "sub_action", value = "default_right", current = "default_last" },
    { index = 2, key = "end_time", unset = true, current = 0.6 },
    { index = 2, key = "start_time", value = 0.6, current = 0.5 },
    { index = 3, key = "action", value = "action_two", current = "action_one" },
    { index = 3, key = "end_time", unset = true, current = 1.8 },
    { index = 3, key = "input", value = "action_two_hold", current = "action_one" },
    { index = 3, key = "release_required", unset = true, current = "action_two_hold" },
    { index = 3, key = "start_time", value = 0.45, current = 0.6 },
    { index = 3, key = "sub_action", value = "default", current = "default_right" },
    { index = 4, key = "action", value = "action_wield", current = "action_one" },
    { index = 4, key = "end_time", unset = true, current = 1.8 },
    { index = 4, key = "input", value = "action_wield", current = "action_one_hold" },
    { index = 4, key = "release_required", unset = true, current = "action_two_hold" },
    { index = 4, key = "start_time", value = 0.45, current = 0.6 },
    { index = 4, key = "sub_action", value = "default", current = "default_right" },
    {
        index = 5,
        unset = true,
        current = {
            action = "action_one",
            input = "action_one",
            start_time = 1.8,
            sub_action = "default",
        },
    },
    {
        index = 6,
        unset = true,
        current = {
            action = "action_two",
            input = "action_two_hold",
            start_time = 0.45,
            sub_action = "default",
        },
    },
    {
        index = 7,
        unset = true,
        current = {
            action = "action_wield",
            input = "action_wield",
            start_time = 0.45,
            sub_action = "default",
        },
    },
}

local path_prefix = {
    "actions", "action_one", "light_attack_down", "allowed_chain_actions",
}

local function validate_snapshot(snapshot, rehydrated)
    exact_keys(snapshot, { "new_revision", "old_revision", "records" },
        rehydrated and "rehydrated snapshot" or "adjacent snapshot")
    assert(snapshot.old_revision == source_catalog.boundary.historical_revision,
        "historical revision drift")
    assert(snapshot.new_revision == source_catalog.boundary.post_revision,
        "boundary revision drift")
    assert(array_length(snapshot.records) == 1, "snapshot record budget drift")
    local record = snapshot.records[1]
    exact_keys(record, { "ops", "source_path", "template", "unsupported" },
        "snapshot record")
    assert(record.source_path == source_catalog.source_path, "source path drift")
    assert(record.template == source_catalog.family.template, "template drift")
    assert(count_keys(record.unsupported) == 0, "unsupported source delta present")
    assert(array_length(record.ops) == #expected_operations,
        "operation budget drift")

    for operation_index, expected in ipairs(expected_operations) do
        local operation = record.ops[operation_index]
        local operation_keys = { "path", "unset" }
        if not expected.unset then operation_keys[#operation_keys + 1] = "value" end
        if rehydrated then
            operation_keys[#operation_keys + 1] = "expected_current"
            operation_keys[#operation_keys + 1] = "expected_current_unset"
        end
        exact_keys(operation, operation_keys,
            "snapshot operation " .. operation_index)
        local expected_path_length = expected.key and 6 or 5
        assert(array_length(operation.path) == expected_path_length,
            "operation path length drift " .. operation_index)
        for index, key in ipairs(path_prefix) do
            assert(operation.path[index] == key,
                "operation path prefix drift " .. operation_index .. "/" .. index)
        end
        assert(operation.path[5] == expected.index,
            "operation chain index drift " .. operation_index)
        if expected.key then
            assert(operation.path[6] == expected.key,
                "operation leaf drift " .. operation_index)
        end
        assert(operation.unset == (expected.unset == true),
            "historical presence drift " .. operation_index)
        if expected.unset then
            assert(rawget(operation, "value") == nil,
                "unexpected historical value " .. operation_index)
        else
            assert(deep_equal(operation.value, expected.value),
                "historical value drift " .. operation_index)
        end
        if rehydrated then
            assert(operation.expected_current_unset == false,
                "current presence drift " .. operation_index)
            assert(deep_equal(operation.expected_current, expected.current),
                "current guard drift " .. operation_index)
        end
    end
    return record.ops
end

local adjacent = load_data(evidence_dir
    .. "/_wt_history_snapshot_2_0_9_to_2_0_9_1_generated.lua")
local rehydrated = load_data(evidence_dir
    .. "/_wt_history_snapshot_2_0_9_rehydrated_generated.lua")
validate_snapshot(adjacent, false)
local source_operations = validate_snapshot(rehydrated, true)

local family = source_catalog.family
local state = source_catalog.state
local operations = {}
for _, source_operation in ipairs(source_operations) do
    local operation = {
        change_class = "official_weapon_balance",
        current_source_blob = source_catalog.current.blob,
        expected_present = not source_operation.expected_current_unset,
        family_id = family.id,
        official_change_id = source_catalog.official_change_id,
        official_summary = source_catalog.official_summary,
        path = copy(source_operation.path),
        result_present = not source_operation.unset,
        root = "Weapons",
        source_blob = source_catalog.boundary.historical_blob,
        source_path = source_catalog.source_path,
        source_revision = source_catalog.boundary.historical_revision,
        state_id = state.id,
        template = family.template,
    }
    if operation.expected_present then
        operation.expected_current = copy(source_operation.expected_current)
    end
    if operation.result_present then
        operation.result = copy(source_operation.value)
    end
    operations[#operations + 1] = operation
end

local catalog = {
    catalog_id = "wt_history_patch_2_0_9_1_halberd_v1",
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
                    atomic_group = source_catalog.official_change_id,
                    direct_profile_names = {},
                    operations = operations,
                    profile_names = {},
                },
            },
            templates = { family.template },
        },
    },
    generation = {
        adjacent_operation_count = #operations,
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
file:write("-- AUTO-GENERATED by tools/weapon-history/generate_patch_2_0_9_1_history.lua; DO NOT HAND-EDIT.\n")
file:write("return ", serialize(catalog), "\n")
file:close()

print("generated " .. output_path
    .. " families=1 operations=20 profiles=0 globals=0")
