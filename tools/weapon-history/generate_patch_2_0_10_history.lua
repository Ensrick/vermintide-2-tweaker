-- Generate the bounded Patch 2.0.10 Sword-and-Dagger history catalog (#1436).
-- Usage: lua5.1 generate_patch_2_0_10_history.lua <source-repo> <evidence-dir> <output.lua>

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

local source_catalog = load_data(evidence_dir
    .. "/_wt_history_2_0_10_source_catalog.lua")
assert(source_catalog.schema == 1, "unsupported Patch 2.0.10 source catalog")
assert(source_catalog.boundary.historical_revision
        == "90c7c21adb7aa2b7de5fcdca5094727895fbeb1a",
    "unexpected historical revision")
assert(source_catalog.boundary.post_revision
        == "67d593c4f98653e1d511105b6adeebb5d6619c58",
    "unexpected post-boundary revision")
assert(source_catalog.current.revision == current_anchor.content_revision,
    "unexpected current revision")

local source_by_path = {}
assert(array_length(source_catalog.source_files) == 3,
    "Patch 2.0.10 three-revision source-file budget drift")
for _, source in ipairs(source_catalog.source_files) do
    assert(type(source.path) == "string" and not source_by_path[source.path],
        "duplicate or invalid Patch 2.0.10 source path")
    assert(git_blob(source_catalog.boundary.historical_revision, source.path)
            == source.historical_blob, "historical source blob drift " .. source.path)
    assert(git_blob(source_catalog.boundary.post_revision, source.path)
            == source.post_blob, "post-boundary source blob drift " .. source.path)
    assert(git_blob(source_catalog.current.revision, source.path)
            == source.current_blob, "current source blob drift " .. source.path)
    source_by_path[source.path] = source
end
assert(array_length(source_catalog.current_only_profile_files) == 3,
    "Patch 2.0.10 current-only profile-file budget drift")
for _, source in ipairs(source_catalog.current_only_profile_files) do
    assert(type(source.path) == "string" and not source_by_path[source.path],
        "duplicate or invalid current-only profile path")
    assert(git_blob(source_catalog.current.revision, source.path)
            == source.current_blob, "current-only source blob drift " .. source.path)
    source_by_path[source.path] = source
end

local DAMAGE_PATH = "scripts/settings/equipment/damage_profile_templates.lua"
local TEMPLATE_PATH =
    "scripts/settings/equipment/weapon_templates/dual_wield_sword_dagger.lua"
local TEMPLATE = "dual_wield_sword_dagger_template_1"
local PROFILE_NAMES = {
    "light_slashing_linesman_dual_medium",
    "light_slashing_smiter_stab_dual",
}
local state_id = source_catalog.state.id

local adjacent = load_data(evidence_dir
    .. "/_wt_history_profiles_2_0_9_1_to_2_0_10_generated.lua")
local post = load_data(evidence_dir
    .. "/_wt_history_profiles_post_2_0_10_generated.lua")
local current = load_data(evidence_dir
    .. "/_wt_history_profiles_current_6_12_1_generated.lua")
assert(adjacent.old_revision == source_catalog.boundary.historical_revision
        and adjacent.new_revision == source_catalog.boundary.post_revision,
    "adjacent profile boundary drift")
assert(post.old_revision == source_catalog.boundary.post_revision
        and post.new_revision == source_catalog.boundary.historical_revision,
    "post profile evidence boundary drift")
assert(current.old_revision == source_catalog.boundary.historical_revision
        and current.new_revision == source_catalog.boundary.post_revision,
    "current profile evidence boundary drift")
for _, snapshot in ipairs({ adjacent, post, current }) do
    assert(count_keys(snapshot.profiles) == 2,
        "Patch 2.0.10 profile evidence budget drift")
    for _, name in ipairs(PROFILE_NAMES) do
        assert(type(snapshot.profiles[name]) == "table",
            "Patch 2.0.10 profile missing " .. name)
    end
end

local expected_differences = {
    "/light_slashing_linesman_dual_medium/melee_boost_override",
    "/light_slashing_smiter_stab_dual/melee_boost_override",
}
local differences = collect_differences(adjacent.profiles, post.profiles, "")
table.sort(differences)
assert(#differences == 2, "adjacent Sword-and-Dagger delta escaped two-leaf budget")
for index, expected in ipairs(expected_differences) do
    assert(differences[index] == expected,
        "unexpected adjacent difference " .. tostring(differences[index]))
end
assert(adjacent.profiles.light_slashing_linesman_dual_medium
        .melee_boost_override == 4,
    "historical first-heavy melee boost drift")
assert(adjacent.profiles.light_slashing_smiter_stab_dual
        .melee_boost_override == 3.5,
    "historical second-heavy melee boost drift")
assert(post.profiles.light_slashing_linesman_dual_medium
        .melee_boost_override == 3.5,
    "post-boundary first-heavy melee boost drift")
assert(post.profiles.light_slashing_smiter_stab_dual
        .melee_boost_override == 4,
    "post-boundary second-heavy melee boost drift")
for _, name in ipairs(PROFILE_NAMES) do
    assert(current.profiles[name].melee_boost_override
            == post.profiles[name].melee_boost_override,
        "current profile no longer matches post-boundary value " .. name)
end

local private_profiles = copy(current.profiles)
for _, name in ipairs(PROFILE_NAMES) do
    private_profiles[name].melee_boost_override =
        adjacent.profiles[name].melee_boost_override
end
local private_differences = collect_differences(
    private_profiles, current.profiles, "")
table.sort(private_differences)
assert(#private_differences == 2, "private current-schema profile drift")
for index, expected in ipairs(expected_differences) do
    assert(private_differences[index] == expected,
        "unexpected private profile difference " .. tostring(private_differences[index]))
end

local routes = load_data(evidence_dir .. "/_wt_history_2_0_10_routes_oracle.lua")
assert(routes.schema == 1
        and routes.oracle_id
            == "wt_patch_2_0_10_sword_and_dagger_source_oracle_v1"
        and routes.current_revision == source_catalog.current.revision,
    "route oracle identity drift")
local route_rows = assert(routes.routes.sword_and_dagger[state_id],
    "Sword-and-Dagger route oracle state missing")
assert(array_length(route_rows) == 4,
    "Sword-and-Dagger profile-route budget drift")
local expected_routes = {
    ["heavy_attack\31damage_profile_left"] =
        "light_slashing_linesman_dual_medium",
    ["heavy_attack\31damage_profile_right"] =
        "light_slashing_linesman_dual_medium",
    ["heavy_attack_2\31damage_profile_left"] =
        "light_slashing_smiter_stab_dual",
    ["heavy_attack_2\31damage_profile_right"] =
        "light_slashing_smiter_stab_dual",
}
local seen_routes = {}
for _, route in ipairs(route_rows) do
    assert(route.template == TEMPLATE and array_length(route.path) == 4
            and route.path[1] == "actions" and route.path[2] == "action_one",
        "unexpected Sword-and-Dagger route identity")
    local key = route.path[3] .. "\31" .. route.path[4]
    assert(expected_routes[key] == route.native_name and not seen_routes[key],
        "unexpected or duplicate Sword-and-Dagger route " .. key)
    seen_routes[key] = true
end
assert(count_keys(seen_routes) == 4, "Sword-and-Dagger route census drift")

local family = source_catalog.family
local route_operations = {}
for _, route in ipairs(route_rows) do
    route_operations[#route_operations + 1] = {
        change_class = "official_weapon_balance",
        current_source_blob = source_by_path[TEMPLATE_PATH].current_blob,
        expected_current = route.native_name,
        expected_present = true,
        family_id = family.id,
        official_change_id = family.official_change_id,
        official_summary = family.official_summary,
        path = copy(route.path),
        result = route.native_name,
        result_present = true,
        root = "Weapons",
        source_blob = source_by_path[TEMPLATE_PATH].historical_blob,
        source_path = TEMPLATE_PATH,
        source_revision = source_catalog.boundary.historical_revision,
        state_id = state_id,
        synthetic_profile_route = true,
        template = TEMPLATE,
    }
end
assert(#route_operations == 4, "explicit profile-route operation budget drift")

local profile_specs = {}
for _, name in ipairs(PROFILE_NAMES) do
    profile_specs[name] = {
        change_class = "official_weapon_balance",
        current_source_blob = source_by_path[DAMAGE_PATH].current_blob,
        historical_profile = private_profiles[name],
        native_name = name,
        official_change_id = family.official_change_id,
        official_summary = family.official_summary,
        private_name = "wt_hist_2_0_9_1_" .. name,
        source_blob = source_by_path[DAMAGE_PATH].historical_blob,
        source_path = DAMAGE_PATH,
        source_revision = source_catalog.boundary.historical_revision,
        state_id = state_id,
    }
end

local catalog = {
    catalog_id = "wt_history_patch_2_0_10_sword_and_dagger_v1",
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
                    direct_profile_names = {},
                    operations = route_operations,
                    profile_names = copy(PROFILE_NAMES),
                },
            },
            templates = { family.template },
        },
    },
    generation = {
        adjacent_operation_count = 2,
        excluded_operation_count = 0,
        global_operations = 0,
        profile_route_count = 4,
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
    if kind == "number" then
        assert(value == value, "cannot serialize NaN")
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
file:write("-- AUTO-GENERATED by tools/weapon-history/generate_patch_2_0_10_history.lua; DO NOT HAND-EDIT.\n")
file:write("return ", serialize(catalog), "\n")
file:close()

print("generated " .. output_path
    .. " families=1 operations=4 profiles=2 routes=4 exclusions=0")
