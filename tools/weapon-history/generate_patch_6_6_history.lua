-- Generate the bounded Patch 6.6 Deepwood Staff catalog for issue #1436.
--
-- Usage:
--   lua5.1 generate_patch_6_6_history.lua <source-repo> <evidence-dir> <output.lua>
--
-- The adjacent 6.5.4 -> 6.6.0 comparison selects exactly the three official
-- Chaos Warrior with Shield leaves. Rehydration supplies their current guards.

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

local function count_keys(value)
    local count = 0
    for _ in pairs(value or {}) do count = count + 1 end
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

local STAFF_PATH =
    "scripts/settings/equipment/weapon_templates/staff_life.lua"
local VORTEX_PATH =
    "scripts/settings/dlcs/woods/woods_equipment_settings.lua"
local STAFF_LEAF = {
    "actions", "action_two", "default", "prioritized_breeds", "chaos_bulwark",
}
local VORTEX_LEAF = { "reduce_duration_per_breed", "chaos_bulwark" }

local source_catalog = load_data(evidence_dir
    .. "/_wt_history_6_6_source_catalog.lua")
assert(source_catalog.schema == 1, "unsupported Patch 6.6 source catalog")
assert(source_catalog.boundary.historical_revision
        == "5a74a378502353b075cbe0c3abe37da07f1d9bc9",
    "unexpected historical revision")
assert(source_catalog.boundary.post_revision
        == "877aa9b2720d297e0594f7039773eca610324f5b",
    "unexpected post-boundary revision")
assert(source_catalog.current.revision
        == current_anchor.content_revision,
    "unexpected current revision")

local source_by_path = {}
assert(array_length(source_catalog.source_files) == 2,
    "Patch 6.6 source-file budget drift")
for _, source in ipairs(source_catalog.source_files) do
    exact_keys(source, {
        "current_blob", "historical_blob", "path", "post_blob",
    }, "source file")
    assert(source.path == STAFF_PATH or source.path == VORTEX_PATH,
        "unexpected Patch 6.6 source path")
    assert(not source_by_path[source.path], "duplicate Patch 6.6 source path")
    assert(git_blob(source_catalog.boundary.historical_revision, source.path)
            == source.historical_blob,
        "historical source blob drift " .. source.path)
    assert(git_blob(source_catalog.boundary.post_revision, source.path)
            == source.post_blob,
        "post-boundary source blob drift " .. source.path)
    assert(git_blob(source_catalog.current.revision, source.path)
            == source.current_blob,
        "current source blob drift " .. source.path)
    source_by_path[source.path] = source
end

local expected_records = {
    [VORTEX_PATH .. "|spirit_storm"] = {
        current = 0.5,
        path = VORTEX_LEAF,
        root = "VortexTemplates",
    },
    [STAFF_PATH .. "|staff_life"] = {
        current = 1,
        path = STAFF_LEAF,
        root = "Weapons",
        template = "staff_life",
    },
    [STAFF_PATH .. "|staff_life_vs"] = {
        current = 1,
        path = STAFF_LEAF,
        root = "Weapons",
        template = "staff_life_vs",
    },
}

local function validate_snapshot(snapshot, rehydrated)
    exact_keys(snapshot, { "new_revision", "old_revision", "records" },
        rehydrated and "rehydrated snapshot" or "adjacent snapshot")
    assert(snapshot.old_revision == source_catalog.boundary.historical_revision,
        "historical revision drift")
    assert(snapshot.new_revision == source_catalog.boundary.post_revision,
        "boundary revision drift")
    assert(array_length(snapshot.records) == 3, "snapshot record budget drift")
    local selected, seen = {}, {}
    for _, record in ipairs(snapshot.records) do
        exact_keys(record, { "ops", "source_path", "template", "unsupported" },
            "snapshot record")
        local key = record.source_path .. "|" .. record.template
        local expected = assert(expected_records[key], "unexpected snapshot record " .. key)
        assert(not seen[key], "duplicate snapshot record " .. key)
        seen[key] = true
        assert(count_keys(record.unsupported) == 0,
            "unsupported source delta present " .. key)
        assert(array_length(record.ops) == 1, "operation budget drift " .. key)
        local operation = record.ops[1]
        exact_keys(operation, rehydrated
            and { "expected_current", "expected_current_unset", "path", "unset" }
            or { "path", "unset" }, "snapshot operation")
        assert(operation.unset == true, "historical leaf must be absent " .. key)
        assert(array_length(operation.path) == #expected.path,
            "operation path length drift " .. key)
        for index, path_key in ipairs(expected.path) do
            assert(operation.path[index] == path_key,
                "operation path drift " .. key .. " at " .. index)
        end
        if rehydrated then
            assert(operation.expected_current_unset == false
                    and operation.expected_current == expected.current,
                "current guard drift " .. key)
        end
        selected[#selected + 1] = {
            evidence = operation,
            expected = expected,
            record = record,
        }
    end
    for key in pairs(expected_records) do
        assert(seen[key], "missing snapshot record " .. key)
    end
    return selected
end

local adjacent = load_data(evidence_dir
    .. "/_wt_history_snapshot_6_5_4_to_6_6_0_generated.lua")
local rehydrated = load_data(evidence_dir
    .. "/_wt_history_snapshot_6_5_4_rehydrated_generated.lua")
validate_snapshot(adjacent, false)
local selected = validate_snapshot(rehydrated, true)

local family, state = source_catalog.family, source_catalog.state
local operations = {}
for _, row in ipairs(selected) do
    local record, expected, evidence = row.record, row.expected, row.evidence
    local source = assert(source_by_path[record.source_path])
    local path = {}
    if expected.root == "VortexTemplates" then path[#path + 1] = record.template end
    for _, key in ipairs(evidence.path) do path[#path + 1] = key end
    operations[#operations + 1] = {
        change_class = "official_weapon_balance",
        current_source_blob = source.current_blob,
        expected_current = evidence.expected_current,
        expected_present = true,
        family_id = family.id,
        official_change_id = source_catalog.official_change_id,
        official_summary = source_catalog.official_summary,
        path = path,
        result_present = false,
        root = expected.root,
        source_blob = source.historical_blob,
        source_path = record.source_path,
        source_revision = source_catalog.boundary.historical_revision,
        state_id = state.id,
        template = expected.template,
    }
end

local catalog = {
    catalog_id = "wt_history_patch_6_6_v1",
    current_id = "current",
    current_source = {
        display_name = "Current (Game Version " .. current_anchor.game_version .. ")",
        label = current_anchor.game_version .. " source anchor",
        revision = source_catalog.current.revision,
    },
    derived_profiles = {},
    families = {
        {
            authority = family.authority,
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
            templates = family.templates,
        },
    },
    generation = {
        adjacent_operation_count = 3,
        global_operations = 1,
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
file:write("-- AUTO-GENERATED by tools/weapon-history/generate_patch_6_6_history.lua; DO NOT HAND-EDIT.\n")
file:write("return ", serialize(catalog), "\n")
file:close()

print("generated " .. output_path .. " families=1 operations=3 profiles=0 globals=1")
