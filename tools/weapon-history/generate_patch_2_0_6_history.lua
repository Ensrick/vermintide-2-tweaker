-- Generate the bounded Patch 2.0.6 Handgun history catalog (#1436).
--
-- Usage:
--   lua5.1 generate_patch_2_0_6_history.lua <source-repo> <evidence-dir> <output.lua>
--
-- The adjacent source has one shared Handgun template. Current source makes
-- two gameplay-identical clones for Kruber and Bardin; this generator proves
-- that clone boundary before emitting the three historical leaves for each.

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

local function git_source(revision, path)
    return command_output("git -C " .. shell_quote(source_repo)
        .. " show " .. shell_quote(revision .. ":" .. path) .. " 2>nul")
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
        assert(rawget(value, key) ~= nil, label .. " is missing key " .. key)
    end
end

local expected_operations = {
    ["actions\31action_one\31default\31ignore_shield_hit"] = {
        current = true,
        current_present = true,
        historical_present = false,
    },
    ["actions\31action_one\31zoomed_shot\31ignore_armour_hit"] = {
        current_present = false,
        historical = true,
        historical_present = true,
    },
    ["actions\31action_one\31zoomed_shot\31ignore_shield_hit"] = {
        current = true,
        current_present = true,
        historical_present = false,
    },
}

local function validate_snapshot(snapshot, rehydrated, source_catalog)
    exact_keys(snapshot, { "new_revision", "old_revision", "records" },
        rehydrated and "rehydrated snapshot" or "adjacent snapshot")
    assert(snapshot.old_revision == source_catalog.boundary.historical_revision,
        "historical revision drift")
    assert(snapshot.new_revision == source_catalog.boundary.post_revision,
        "post-boundary revision drift")
    assert(array_length(snapshot.records) == 1, "snapshot record budget drift")
    local record = snapshot.records[1]
    exact_keys(record, { "ops", "source_path", "template", "unsupported" },
        "snapshot record")
    assert(record.source_path == source_catalog.source_path,
        "snapshot source path drift")
    assert(record.template == source_catalog.family.source_template,
        "snapshot source template drift")
    assert(count_keys(record.unsupported) == 0,
        "unsupported adjacent Handgun delta present")
    assert(array_length(record.ops) == 3, "snapshot operation budget drift")

    local selected, seen = {}, {}
    for index, operation in ipairs(record.ops) do
        local path_key = table.concat(operation.path or {}, "\31")
        local expected = assert(expected_operations[path_key],
            "unexpected Handgun operation " .. path_key)
        assert(not seen[path_key], "duplicate Handgun operation " .. path_key)
        seen[path_key] = true

        local keys = { "path", "unset" }
        if expected.historical_present then keys[#keys + 1] = "value" end
        if rehydrated then
            keys[#keys + 1] = "expected_current_unset"
            if expected.current_present then keys[#keys + 1] = "expected_current" end
        end
        exact_keys(operation, keys, "snapshot operation " .. index)
        assert(operation.unset == not expected.historical_present,
            "historical presence drift " .. path_key)
        if expected.historical_present then
            assert(operation.value == expected.historical,
                "historical value drift " .. path_key)
        end
        if rehydrated then
            assert(operation.expected_current_unset == not expected.current_present,
                "current presence drift " .. path_key)
            if expected.current_present then
                assert(operation.expected_current == expected.current,
                    "current value drift " .. path_key)
            end
            selected[#selected + 1] = operation
        end
    end
    assert(count_keys(seen) == count_keys(expected_operations),
        "Handgun operation census drift")
    return selected
end

local function validate_current_clone_projection(source)
    local es_clone = "local handgun_es = table.clone(weapon_template)"
    local dr_clone = "local handgun_dr = table.clone(weapon_template)"
    local return_marker = "return {"
    local clone_start = assert(source:find(es_clone, 1, true),
        "current Kruber Handgun clone declaration missing")
    assert(source:find(dr_clone, clone_start, true),
        "current Bardin Handgun clone declaration missing")
    local return_start = assert(source:find(return_marker, clone_start, true),
        "current Handgun return table missing")
    local clone_block = source:sub(clone_start, return_start - 1)
    assert(not clone_block:find("handgun_es.actions", 1, true)
            and not clone_block:find("handgun_dr.actions", 1, true),
        "current Handgun clone gameplay actions diverged")
    assert(source:find(
            "handgun_template_1 = table.clone(handgun_es)", return_start, true),
        "current Kruber Handgun return route missing")
    assert(source:find(
            "handgun_template_2 = table.clone(handgun_dr)", return_start, true),
        "current Bardin Handgun return route missing")
end

local source_catalog = load_data(evidence_dir
    .. "/_wt_history_2_0_6_source_catalog.lua")
assert(source_catalog.schema == 1, "unsupported Patch 2.0.6 source catalog")
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
assert(array_length(source_catalog.family.templates) == 2
        and source_catalog.family.templates[1] == "handgun_template_1"
        and source_catalog.family.templates[2] == "handgun_template_2",
    "current Handgun target-template contract drift")
validate_current_clone_projection(git_source(
    source_catalog.current.revision, source_catalog.source_path))

local adjacent = load_data(evidence_dir
    .. "/_wt_history_snapshot_2_0_5_to_2_0_6_generated.lua")
local rehydrated = load_data(evidence_dir
    .. "/_wt_history_snapshot_2_0_5_rehydrated_generated.lua")
validate_snapshot(adjacent, false, source_catalog)
local selected = validate_snapshot(rehydrated, true, source_catalog)

local family, state = source_catalog.family, source_catalog.state
local operations = {}
for _, template in ipairs(family.templates) do
    for _, evidence in ipairs(selected) do
        local operation = {
            change_class = "official_weapon_balance",
            current_source_blob = source_catalog.current.blob,
            expected_present = not evidence.expected_current_unset,
            family_id = family.id,
            official_change_id = source_catalog.official_change_id,
            official_summary = source_catalog.official_summary,
            path = evidence.path,
            result_present = not evidence.unset,
            root = "Weapons",
            source_blob = source_catalog.boundary.historical_blob,
            source_path = source_catalog.source_path,
            source_revision = source_catalog.boundary.historical_revision,
            state_id = state.id,
            template = template,
        }
        if not evidence.expected_current_unset then
            operation.expected_current = evidence.expected_current
        end
        if not evidence.unset then operation.result = evidence.value end
        operations[#operations + 1] = operation
    end
end
assert(#operations == 6, "projected Handgun operation budget drift")

local catalog = {
    catalog_id = "wt_history_patch_2_0_6_v1",
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
            templates = family.templates,
        },
    },
    generation = {
        adjacent_operation_count = 6,
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
file:write("-- AUTO-GENERATED by tools/weapon-history/generate_patch_2_0_6_history.lua; DO NOT HAND-EDIT.\n")
file:write("return ", serialize(catalog), "\n")
file:close()

print("generated " .. output_path .. " families=1 operations=6 profiles=0 globals=0")
