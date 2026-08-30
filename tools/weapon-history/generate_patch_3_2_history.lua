-- Generate the bounded Patch 3.2 history catalog for Tweaker: Weapons (#1436).
--
-- Usage:
--   lua5.1 generate_patch_3_2_history.lua <source-repo> <evidence-dir> <output.lua>
--
-- The operation set comes from the adjacent 3.1.0 -> 3.2 source diff. The
-- exact selected path is separately rehydrated against the current anchor.
-- This prevents later changes in the same weapon template from being mistaken
-- for Patch 3.2 changes.

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
    "actions", "action_one", "light_attack_bopp",
    "additional_critical_strike_chance",
}

local function validate_snapshot(snapshot, rehydrated, catalog)
    exact_keys(snapshot, { "new_revision", "old_revision", "records" },
        rehydrated and "rehydrated snapshot" or "adjacent snapshot")
    assert(snapshot.old_revision == catalog.boundary.historical_revision,
        "historical revision drift")
    assert(snapshot.new_revision == catalog.boundary.post_revision,
        "boundary revision drift")
    assert(array_length(snapshot.records) == 1, "snapshot record budget drift")
    local record = snapshot.records[1]
    exact_keys(record, { "ops", "source_path", "template", "unsupported" },
        "snapshot record")
    assert(record.source_path == catalog.source_path, "source path drift")
    assert(record.template == catalog.family.template, "template drift")
    assert(count_keys(record.unsupported) == 0, "unsupported source delta present")
    assert(array_length(record.ops) == 1, "operation budget drift")
    local operation = record.ops[1]
    local operation_keys = rehydrated
        and { "expected_current_unset", "path", "unset", "value" }
        or { "path", "unset", "value" }
    exact_keys(operation, operation_keys, "snapshot operation")
    assert(array_length(operation.path) == #expected_path, "operation path length drift")
    for index, key in ipairs(expected_path) do
        assert(operation.path[index] == key, "operation path drift at " .. index)
    end
    assert(operation.unset == false and operation.value == 0.1,
        "historical critical chance drift")
    if rehydrated then
        assert(operation.expected_current_unset == true
                and rawget(operation, "expected_current") == nil,
            "current absence guard drift")
    end
    return operation
end

local source_catalog = load_data(evidence_dir .. "/_wt_history_3_2_source_catalog.lua")
assert(source_catalog.schema == 1, "unsupported Patch 3.2 source catalog")
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

local adjacent = load_data(evidence_dir
    .. "/_wt_history_snapshot_3_1_0_to_3_2_0_generated.lua")
local rehydrated = load_data(evidence_dir
    .. "/_wt_history_snapshot_3_1_0_rehydrated_generated.lua")
validate_snapshot(adjacent, false, source_catalog)
local operation = validate_snapshot(rehydrated, true, source_catalog)

local family = source_catalog.family
local state = source_catalog.state
local catalog = {
    catalog_id = "wt_history_patch_3_2_v1",
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
                    operations = {
                        {
                            change_class = "official_weapon_balance",
                            current_source_blob = source_catalog.current.blob,
                            expected_present = false,
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
                            template = family.template,
                        },
                    },
                    profile_names = {},
                },
            },
            templates = { family.template },
        },
    },
    generation = {
        adjacent_operation_count = 1,
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
file:write("-- AUTO-GENERATED by tools/weapon-history/generate_patch_3_2_history.lua; DO NOT HAND-EDIT.\n")
file:write("return ", serialize(catalog), "\n")
file:close()

print("generated " .. output_path .. " families=1 operations=1 profiles=0 globals=0")
