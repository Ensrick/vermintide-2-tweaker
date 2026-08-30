-- Generate the bounded Patch 4.6 Hagbane history catalog for issue #1436.
-- Usage: lua5.1 generate_patch_4_6_history.lua <source-repo> <evidence-dir> <output.lua>

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

local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, child in pairs(value) do result[copy(key, seen)] = copy(child, seen) end
    return result
end

local function collect_differences(left, right, path, differences)
    differences = differences or {}
    if type(left) ~= type(right) then
        differences[#differences + 1] = path
        return differences
    end
    if type(left) ~= "table" then
        if left ~= right then differences[#differences + 1] = path end
        return differences
    end
    local keys = {}
    for key in pairs(left) do keys[key] = true end
    for key in pairs(right) do keys[key] = true end
    for key in pairs(keys) do
        collect_differences(rawget(left, key), rawget(right, key),
            path .. "/" .. tostring(key), differences)
    end
    return differences
end

local source_catalog = load_data(evidence_dir .. "/_wt_history_4_6_source_catalog.lua")
assert(source_catalog.schema == 1, "unsupported Patch 4.6 source catalog")
assert(source_catalog.boundary.historical_revision
        == "0cec9547152a395c4f35f75288f29d8b18b8294f",
    "unexpected historical revision")
assert(source_catalog.boundary.post_revision
        == "b38754a3bd61983118215359845d5b4fe5005014",
    "unexpected post-boundary revision")
assert(source_catalog.current.revision == current_anchor.content_revision,
    "unexpected current revision")

local source_by_path = {}
assert(array_length(source_catalog.source_files) == 6,
    "Patch 4.6 source-file budget drift")
for _, source in ipairs(source_catalog.source_files) do
    assert(type(source.path) == "string" and not source_by_path[source.path],
        "duplicate or invalid Patch 4.6 source path")
    assert(git_blob(source_catalog.boundary.historical_revision, source.path)
            == source.historical_blob, "historical source blob drift " .. source.path)
    assert(git_blob(source_catalog.boundary.post_revision, source.path)
            == source.post_blob, "post-boundary source blob drift " .. source.path)
    assert(git_blob(source_catalog.current.revision, source.path)
            == source.current_blob, "current source blob drift " .. source.path)
    source_by_path[source.path] = source
end

assert(array_length(source_catalog.source_root_exclusions) == 1,
    "Patch 4.6 source-root exclusion census drift")
local presentation_exclusion = source_catalog.source_root_exclusions[1]
assert(presentation_exclusion.path
        == "scripts/settings/equipment/weapon_templates/shortbows_hagbane.lua"
        and presentation_exclusion.root == "weapon_diagram"
        and presentation_exclusion.reason == "presentation_only",
    "Patch 4.6 weapon-diagram exclusion drift")

local DAMAGE_PATH = "scripts/settings/equipment/damage_profile_templates.lua"
local TEMPLATE_PATH =
    "scripts/settings/equipment/weapon_templates/shortbows_hagbane.lua"
local PROFILE_NAMES = { "shortbow_hagbane", "shortbow_hagbane_charged" }
local state_id = source_catalog.state.id

local adjacent = load_data(evidence_dir
    .. "/_wt_history_profiles_4_5_1_to_4_6_generated.lua")
local historical = load_data(evidence_dir
    .. "/_wt_history_profiles_4_5_1_rehydrated_generated.lua")
local post = load_data(evidence_dir
    .. "/_wt_history_profiles_post_4_6_generated.lua")
local current = load_data(evidence_dir
    .. "/_wt_history_profiles_current_6_12_0_generated.lua")
for _, snapshot in ipairs({ adjacent, historical, post, current }) do
    assert(snapshot.old_revision == source_catalog.boundary.historical_revision
            and snapshot.new_revision == source_catalog.boundary.post_revision,
        "profile evidence boundary drift")
    assert(count_keys(snapshot.profiles) == 2,
        "Patch 4.6 profile evidence budget drift")
    for _, name in ipairs(PROFILE_NAMES) do
        assert(type(snapshot.profiles[name]) == "table",
            "Patch 4.6 profile missing " .. name)
    end
end

local expected_differences = {
    "shortbow_hagbane/allow_dot_finesse_hit",
    "shortbow_hagbane_charged/allow_dot_finesse_hit",
}
assert(#collect_differences(adjacent.profiles, historical.profiles, "") == 0,
    "adjacent and historical Hagbane payloads differ")
local function assert_two_finesse_differences(left, right, label)
    local differences = collect_differences(left, right, "")
    table.sort(differences)
    assert(#differences == 2, label .. " escaped the two-leaf budget")
    for index, expected in ipairs(expected_differences) do
        assert(differences[index] == "/" .. expected,
            label .. " unexpected difference " .. tostring(differences[index]))
    end
end
assert_two_finesse_differences(historical.profiles, post.profiles,
    "adjacent Hagbane profile delta")
for _, name in ipairs(PROFILE_NAMES) do
    assert(rawget(historical.profiles[name], "allow_dot_finesse_hit") == nil,
        "historical finesse flag must be absent " .. name)
    assert(rawget(post.profiles[name], "allow_dot_finesse_hit") == true,
        "post-boundary finesse flag drift " .. name)
    assert(rawget(current.profiles[name], "allow_dot_finesse_hit") == true,
        "current finesse flag drift " .. name)
end

local private_profiles = copy(current.profiles)
for _, name in ipairs(PROFILE_NAMES) do
    rawset(private_profiles[name], "allow_dot_finesse_hit", nil)
end
assert_two_finesse_differences(private_profiles, current.profiles,
    "current-rehydrated Hagbane profile")

local adjacent_template = load_data(evidence_dir
    .. "/_wt_history_snapshot_4_5_1_to_4_6_generated.lua")
local current_template = load_data(evidence_dir
    .. "/_wt_history_snapshot_4_5_1_rehydrated_generated.lua")
for _, snapshot in ipairs({ adjacent_template, current_template }) do
    assert(snapshot.old_revision == source_catalog.boundary.historical_revision
            and snapshot.new_revision == source_catalog.boundary.post_revision,
        "template evidence boundary drift")
    assert(array_length(snapshot.records) == 1,
        "template record budget drift")
    local record = snapshot.records[1]
    assert(record.source_path == TEMPLATE_PATH
            and record.template == source_catalog.family.template,
        "template evidence identity drift")
    assert(count_keys(record.unsupported) == 0
            and array_length(record.ops) == 2,
        "template exclusion budget drift")
end
local excluded = current_template.records[1].ops
assert(array_length(excluded[1].path) == 1 and excluded[1].path[1] == "__symbol"
        and excluded[1].value == "weapon_template"
        and excluded[1].expected_current_unset == true,
    "refactor-only symbol exclusion drift")
local talent = excluded[2]
local talent_path = { "actions", "action_one", "shoot_charged", "impact_data",
    "aoe_on_bounce" }
assert(array_length(talent.path) == #talent_path, "talent path length drift")
for index, key in ipairs(talent_path) do
    assert(talent.path[index] == key, "talent path drift at " .. index)
end
assert(talent.unset == true and talent.expected_current_unset == false
        and talent.expected_current == true,
    "Ricochet talent exclusion drift")

local routes = load_data(evidence_dir .. "/_wt_history_4_6_routes_oracle.lua")
assert(routes.schema == 1
        and routes.oracle_id == "wt_patch_4_6_hagbane_source_oracle_v1"
        and routes.current_revision == source_catalog.current.revision,
    "route oracle identity drift")
local route_rows = assert(routes.routes.hagbane_shortbow[state_id],
    "Hagbane route oracle state missing")
assert(array_length(route_rows) == 2, "Hagbane profile-route budget drift")
local expected_routes = {
    shortbow_hagbane = "default",
    shortbow_hagbane_charged = "shoot_charged",
}
for _, route in ipairs(route_rows) do
    assert(route.template == source_catalog.family.template
            and expected_routes[route.native_name], "unexpected Hagbane profile route")
    assert(array_length(route.path) == 5
            and route.path[1] == "actions" and route.path[2] == "action_one"
            and route.path[3] == expected_routes[route.native_name]
            and route.path[4] == "impact_data"
            and route.path[5] == "damage_profile",
        "Hagbane profile route path drift " .. route.native_name)
end

local family = source_catalog.family
local profile_specs = {}
for _, name in ipairs(PROFILE_NAMES) do
    profile_specs[name] = {
        change_class = "official_weapon_balance",
        current_source_blob = source_by_path[DAMAGE_PATH].current_blob,
        historical_profile = private_profiles[name],
        native_name = name,
        official_change_id = family.official_change_id,
        official_summary = family.official_summary,
        private_name = "wt_hist_4_5_1_" .. name,
        source_blob = source_by_path[DAMAGE_PATH].historical_blob,
        source_path = DAMAGE_PATH,
        source_revision = source_catalog.boundary.historical_revision,
        state_id = state_id,
    }
end

local catalog = {
    catalog_id = "wt_history_patch_4_6_hagbane_v1",
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
            state_order = { state_id },
            states = {
                [state_id] = {
                    direct_profile_names = copy(PROFILE_NAMES),
                    operations = {},
                    profile_names = copy(PROFILE_NAMES),
                },
            },
            templates = { family.template },
        },
    },
    generation = {
        adjacent_operation_count = 2,
        excluded_operation_count = 2,
        global_operations = 0,
        profile_route_count = 2,
        unsupported_count = 0,
    },
    profile_specs = { [state_id] = profile_specs },
    schema = 2,
    states = {
        [state_id] = {
            change_class = "official_weapon_balance",
            display_name = source_catalog.state.display_name,
            label_key = source_catalog.state.label_key,
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
    if kind == "number" then return string.format("%.17g", value) end
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
        local rendered_key = type(key) == "string" and key:match("^[%a_][%w_]*$")
            and key or "[" .. serialize(key, indent + 4, active) .. "]"
        parts[#parts + 1] = "\n" .. child_pad .. rendered_key .. " = "
            .. serialize(value[key], indent + 4, active) .. ","
    end
    parts[#parts + 1] = "\n" .. pad .. "}"
    active[value] = nil
    return table.concat(parts)
end

local file = assert(io.open(output_path, "wb"))
file:write("-- AUTO-GENERATED by tools/weapon-history/generate_patch_4_6_history.lua; DO NOT HAND-EDIT.\n")
file:write("return ", serialize(catalog), "\n")
file:close()

print("generated " .. output_path .. " families=1 operations=0 profiles=2 routes=2 exclusions=2")
