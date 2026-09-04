-- Generate the bounded Patch 3.1 weapon-history catalog (#1436).
--
-- Usage:
--   lua5.1 generate_patch_3_1_history.lua <source-repo> <evidence-dir> <output.lua>
--
-- This is an adjacent-delta projection, not a complete Game 3.0 baseline.

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

local expected_by_family = {
    kruber_blunderbuss = {
        adjacent = "_wt_history_snapshot_pre_3_1_to_3_1_generated.lua",
        current = 16,
        historical = 12,
        path = { "ammo_data", "max_ammo" },
        rehydrated = "_wt_history_snapshot_pre_3_1_rehydrated_generated.lua",
    },
    tuskgor_spear = {
        adjacent =
            "_wt_history_snapshot_pre_3_1_tuskgor_to_3_1_generated.lua",
        current = 0.5,
        historical = 0.25,
        path = { "block_fatigue_point_multiplier" },
        rehydrated =
            "_wt_history_snapshot_pre_3_1_tuskgor_rehydrated_generated.lua",
    },
}

local function validate_snapshot(snapshot, rehydrated, catalog, change, expected)
    local family_id = change.family.id
    exact_keys(snapshot, { "new_revision", "old_revision", "records" },
        family_id .. (rehydrated and " rehydrated snapshot" or " adjacent snapshot"))
    assert(snapshot.old_revision == catalog.boundary.historical_revision,
        family_id .. " historical revision drift")
    assert(snapshot.new_revision == catalog.boundary.post_revision,
        family_id .. " boundary revision drift")
    assert(array_length(snapshot.records) == 1,
        family_id .. " snapshot record budget drift")
    local record = snapshot.records[1]
    exact_keys(record, { "ops", "source_path", "template", "unsupported" },
        family_id .. " snapshot record")
    assert(record.source_path == change.source_path,
        family_id .. " source path drift")
    assert(record.template == change.family.template,
        family_id .. " template drift")
    assert(count_keys(record.unsupported) == 0,
        family_id .. " unsupported source delta present")
    assert(array_length(record.ops) == 1,
        family_id .. " operation budget drift")
    local operation = record.ops[1]
    exact_keys(operation, rehydrated
        and { "expected_current", "expected_current_unset", "path", "unset", "value" }
        or { "path", "unset", "value" }, family_id .. " snapshot operation")
    assert(array_length(operation.path) == #expected.path,
        family_id .. " operation path length drift")
    for index, key in ipairs(expected.path) do
        assert(operation.path[index] == key,
            family_id .. " operation path drift at " .. index)
    end
    assert(operation.unset == false and operation.value == expected.historical,
        family_id .. " historical value drift")
    if rehydrated then
        assert(operation.expected_current_unset == false
                and operation.expected_current == expected.current,
            family_id .. " current guard drift")
    end
    return record, operation
end

local source_catalog = load_data(evidence_dir .. "/_wt_history_3_1_source_catalog.lua")
assert(source_catalog.schema == 2, "unsupported Patch 3.1 source catalog")
exact_keys(source_catalog, {
    "artifacts", "boundary", "changes", "current", "exclusions",
    "official_patch_notes", "schema", "state",
}, "Patch 3.1 source catalog")
exact_keys(source_catalog.boundary,
    { "historical_revision", "post_revision" }, "Patch 3.1 boundary")
exact_keys(source_catalog.current, { "revision" }, "Patch 3.1 current source")
exact_keys(source_catalog.state,
    { "display_name", "id", "label_key" }, "Patch 3.1 state")
assert(source_catalog.current.revision == current_anchor.content_revision,
    "unexpected current revision")
assert(source_catalog.boundary.historical_revision
        == "c96aa3858011ecd557d55d80b66fe3bb8342eeb2"
        and source_catalog.boundary.post_revision
            == "3f0e3ba442d8dcafb8b5f829ff6c2a95ae24ae63",
    "Patch 3.1 boundary identity drift")
assert(source_catalog.state.id == "pre_3_1_delta",
    "Patch 3.1 state identity drift")
assert(source_catalog.official_patch_notes
        == "https://www.vermintide.com/news/patch-31",
    "Patch 3.1 official source drift")
assert(array_length(source_catalog.exclusions) == 1
        and source_catalog.exclusions[1].template == "blunderbuss_template_1_vs",
    "current-only Versus exclusion drift")
exact_keys(source_catalog.exclusions[1], { "id", "reason", "template" },
    "Patch 3.1 exclusion")

local change_count = array_length(source_catalog.changes)
assert(change_count == 2, "Patch 3.1 change budget drift")
local generated_families = {}
local seen_families, seen_settings, seen_sources, seen_templates = {}, {}, {}, {}
for index, change in ipairs(source_catalog.changes) do
    exact_keys(change, {
        "current_blob", "family", "historical_blob", "official_change_id",
        "official_summary", "post_blob", "source_path",
    }, "Patch 3.1 change " .. index)
    exact_keys(change.family, {
        "display_name", "id", "label_key", "setting_id", "template",
    }, "Patch 3.1 family " .. index)
    local family = change.family
    local expected = expected_by_family[family.id]
    assert(expected and not seen_families[family.id],
        "duplicate or unknown Patch 3.1 family " .. tostring(family.id))
    assert(not seen_settings[family.setting_id],
        "duplicate Patch 3.1 setting " .. tostring(family.setting_id))
    assert(not seen_sources[change.source_path],
        "duplicate Patch 3.1 source " .. tostring(change.source_path))
    assert(not seen_templates[family.template],
        "duplicate Patch 3.1 template " .. tostring(family.template))
    assert(type(change.official_change_id) == "string"
            and change.official_change_id ~= ""
            and type(change.official_summary) == "string"
            and change.official_summary ~= "",
        "Patch 3.1 official identity is incomplete for " .. family.id)
    assert(git_blob(source_catalog.boundary.historical_revision,
            change.source_path) == change.historical_blob,
        family.id .. " historical source blob drift")
    assert(git_blob(source_catalog.boundary.post_revision,
            change.source_path) == change.post_blob,
        family.id .. " post-boundary source blob drift")
    assert(git_blob(source_catalog.current.revision,
            change.source_path) == change.current_blob,
        family.id .. " current source blob drift")

    local adjacent = load_data(evidence_dir .. "/" .. expected.adjacent)
    local rehydrated = load_data(evidence_dir .. "/" .. expected.rehydrated)
    validate_snapshot(adjacent, false, source_catalog, change, expected)
    local _, operation = validate_snapshot(
        rehydrated, true, source_catalog, change, expected)
    local state = source_catalog.state
    generated_families[#generated_families + 1] = {
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
                        current_source_blob = change.current_blob,
                        expected_current = operation.expected_current,
                        expected_present = not operation.expected_current_unset,
                        family_id = family.id,
                        official_change_id = change.official_change_id,
                        official_summary = change.official_summary,
                        path = operation.path,
                        result = operation.value,
                        result_present = not operation.unset,
                        root = "Weapons",
                        source_blob = change.historical_blob,
                        source_path = change.source_path,
                        source_revision = source_catalog.boundary.historical_revision,
                        state_id = state.id,
                        template = family.template,
                    },
                },
                profile_names = {},
            },
        },
        templates = { family.template },
    }
    seen_families[family.id] = true
    seen_settings[family.setting_id] = true
    seen_sources[change.source_path] = true
    seen_templates[family.template] = true
end
assert(count_keys(seen_families) == count_keys(expected_by_family),
    "Patch 3.1 expected-family census drift")

local state = source_catalog.state
local catalog = {
    catalog_id = "wt_history_patch_3_1_v1",
    current_id = "current",
    current_source = {
        display_name = "Current (Game Version " .. current_anchor.game_version .. ")",
        label = current_anchor.game_version .. " source anchor",
        revision = source_catalog.current.revision,
    },
    derived_profiles = {},
    families = generated_families,
    generation = {
        adjacent_operation_count = change_count,
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
    local pad, child_pad = string.rep(" ", indent), string.rep(" ", indent + 4)
    local parts = { "{" }
    for _, key in ipairs(keys) do
        local rendered_key = type(key) == "string"
                and key:match("^[%a_][%w_]*$") and key
            or "[" .. serialize(key, indent + 4, active) .. "]"
        parts[#parts + 1] = "\n" .. child_pad .. rendered_key .. " = "
            .. serialize(value[key], indent + 4, active) .. ","
    end
    parts[#parts + 1] = "\n" .. pad .. "}"
    active[value] = nil
    return table.concat(parts)
end

local file = assert(io.open(output_path, "wb"))
file:write("-- AUTO-GENERATED by tools/weapon-history/generate_patch_3_1_history.lua; DO NOT HAND-EDIT.\n")
file:write("return ", serialize(catalog), "\n")
file:close()

print("generated " .. output_path .. " families=" .. change_count
    .. " operations=" .. change_count .. " profiles=0 globals=0")
