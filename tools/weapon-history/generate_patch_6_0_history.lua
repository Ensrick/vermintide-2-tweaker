-- Generate the bounded Patch 6.0 launch history catalog for issue #1436.
-- Usage: lua5.1 generate_patch_6_0_history.lua <source-repo> <evidence-dir> <output.lua>

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

local source_catalog = load_data(evidence_dir
    .. "/_wt_history_6_0_source_catalog.lua")
assert(source_catalog.schema == 1, "unsupported Patch 6.0 source catalog")
assert(source_catalog.boundary.historical_revision
        == "f64ecd2495bd26b1b0a4d296970bef0a0d7a06a9",
    "unexpected historical revision")
assert(source_catalog.boundary.post_revision
        == "da0bbdaf6af1ca7e8c96e7892a3416a4aa8a7f87",
    "unexpected post-boundary revision")
assert(source_catalog.current.revision == current_anchor.content_revision,
    "unexpected current revision")

local source_by_path = {}
assert(array_length(source_catalog.source_files) == 8,
    "Patch 6.0 source-file budget drift")
for _, source in ipairs(source_catalog.source_files) do
    assert(type(source.path) == "string" and not source_by_path[source.path],
        "duplicate or invalid Patch 6.0 source path")
    assert(git_blob(source_catalog.boundary.historical_revision, source.path)
            == source.historical_blob, "historical source blob drift " .. source.path)
    assert(git_blob(source_catalog.boundary.post_revision, source.path)
            == source.post_blob, "post-boundary source blob drift " .. source.path)
    assert(git_blob(source_catalog.current.revision, source.path)
            == source.current_blob, "current source blob drift " .. source.path)
    source_by_path[source.path] = source
end

local SHIELD_PATH = "scripts/settings/equipment/weapon_templates/1h_swords_shield.lua"
local BRETON_PATH =
    "scripts/settings/equipment/weapon_templates/1h_swords_shield_breton.lua"
local DAMAGE_PATH = "scripts/settings/equipment/damage_profile_templates.lua"
local FIREBALL_TEMPLATE_PATH =
    "scripts/settings/equipment/weapon_templates/staff_fireball_fireball.lua"
local FIREBALL_TEMPLATE = "staff_fireball_fireball_template_1"
local POSTPUSH = { "actions", "action_one", "light_attack_stab_postpush" }
assert(source_by_path[FIREBALL_TEMPLATE_PATH], "Fireball template source is unpinned")
assert(source_catalog.families.fireball_staff.template == FIREBALL_TEMPLATE,
    "Fireball weapon-template identity drift")
for _, revision in ipairs({
    source_catalog.boundary.historical_revision,
    source_catalog.boundary.post_revision,
    source_catalog.current.revision,
}) do
    local source = command_output("git -C " .. shell_quote(source_repo)
        .. " show " .. shell_quote(revision .. ":" .. FIREBALL_TEMPLATE_PATH)
        .. " 2>nul")
    local _, count = source:gsub(
        FIREBALL_TEMPLATE .. "%s*=%s*table%.clone%(weapon_template%)", "")
    assert(count == 1, "Fireball weapon-template declaration drift at " .. revision)
end
local expected = {
    [SHIELD_PATH] = {
        template = "one_handed_sword_shield_template_1",
        values = {
            damage_window_end = { current = 0.32, historical = 0.28, present = true },
            damage_window_start = { current = 0.22, historical = 0.18, present = true },
            dedicated_target_range = { current = 2.8, historical = 2.5, present = true },
            range_mod = { current = 1.3, historical = 1.2, present = true },
            range_mod_add = { current = 0.2, present = false },
        },
    },
    [BRETON_PATH] = {
        template = "one_handed_sword_shield_template_2",
        values = {
            damage_window_end = { current = 0.32, historical = 0.28, present = true },
            damage_window_start = { current = 0.22, historical = 0.18, present = true },
            dedicated_target_range = { current = 2.8, historical = 2.5, present = true },
            range_mod = { current = 1.5, historical = 1.2, present = true },
            range_mod_add = { current = 0.25, present = false },
            sweep_z_offset = { current = -0.035, present = false },
        },
    },
}

local function validate_template_pair(adjacent_name, rehydrated_name, source_path)
    local adjacent = load_data(evidence_dir .. "/" .. adjacent_name)
    local rehydrated = load_data(evidence_dir .. "/" .. rehydrated_name)
    local spec = assert(expected[source_path], "unknown template evidence path")
    local expected_count = count_keys(spec.values)
    local function validate(snapshot, is_rehydrated)
        assert(snapshot.old_revision == source_catalog.boundary.historical_revision
                and snapshot.new_revision == source_catalog.boundary.post_revision,
            "template evidence boundary drift")
        assert(array_length(snapshot.records) == 1, "template record budget drift")
        local record = snapshot.records[1]
        assert(record.source_path == source_path and record.template == spec.template,
            "template evidence identity drift")
        assert(count_keys(record.unsupported) == 0, "unsupported template delta present")
        assert(array_length(record.ops) == expected_count, "template operation budget drift")
        local selected = {}
        for _, operation in ipairs(record.ops) do
            assert(array_length(operation.path) == 4
                    and operation.path[1] == POSTPUSH[1]
                    and operation.path[2] == POSTPUSH[2]
                    and operation.path[3] == POSTPUSH[3],
                "template operation path drift")
            local leaf = operation.path[4]
            local wanted = assert(spec.values[leaf], "unexpected template leaf " .. tostring(leaf))
            assert(not selected[leaf], "duplicate template leaf " .. leaf)
            selected[leaf] = true
            assert(operation.unset == not wanted.present,
                "historical presence drift " .. leaf)
            if wanted.present then
                assert(operation.value == wanted.historical,
                    "historical value drift " .. leaf)
            else
                assert(operation.value == nil, "absent historical value supplied " .. leaf)
            end
            if is_rehydrated then
                assert(operation.expected_current_unset == false
                        and operation.expected_current == wanted.current,
                    "current guard drift " .. leaf)
            end
        end
        for leaf in pairs(spec.values) do assert(selected[leaf], "missing leaf " .. leaf) end
        return record
    end
    validate(adjacent, false)
    return validate(rehydrated, true)
end

local shield_record = validate_template_pair(
    "_wt_history_snapshot_5_6_1_sword_shield_to_6_0_generated.lua",
    "_wt_history_snapshot_5_6_1_sword_shield_rehydrated_generated.lua",
    SHIELD_PATH)
local breton_record = validate_template_pair(
    "_wt_history_snapshot_5_6_1_breton_to_6_0_generated.lua",
    "_wt_history_snapshot_5_6_1_breton_rehydrated_generated.lua",
    BRETON_PATH)

local adjacent_profiles = load_data(evidence_dir
    .. "/_wt_history_profiles_5_6_1_to_6_0_generated.lua")
local historical_profiles = load_data(evidence_dir
    .. "/_wt_history_profiles_5_6_1_rehydrated_generated.lua")
local current_profiles = load_data(evidence_dir
    .. "/_wt_history_profiles_current_6_12_0_generated.lua")
for _, snapshot in ipairs({ adjacent_profiles, historical_profiles, current_profiles }) do
    assert(snapshot.old_revision == source_catalog.boundary.historical_revision
            and snapshot.new_revision == source_catalog.boundary.post_revision,
        "profile evidence boundary drift")
    assert(count_keys(snapshot.profiles) == 1
            and type(snapshot.profiles.staff_fireball_charged) == "table",
        "profile evidence budget drift")
end

local historical_profile = historical_profiles.profiles.staff_fireball_charged
local current_profile = current_profiles.profiles.staff_fireball_charged
assert(adjacent_profiles.profiles.staff_fireball_charged.armor_modifier.attack[5] == 0.1
        and historical_profile.armor_modifier.attack[5] == 0.1
        and current_profile.armor_modifier.attack[5] == 1,
    "Fireball berserker leaf drift")

local differences = {}
local function collect_differences(left, right, path)
    if type(left) ~= type(right) then
        differences[#differences + 1] = path
        return
    end
    if type(left) ~= "table" then
        if left ~= right then differences[#differences + 1] = path end
        return
    end
    local keys = {}
    for key in pairs(left) do keys[key] = true end
    for key in pairs(right) do keys[key] = true end
    for key in pairs(keys) do
        collect_differences(left[key], right[key], path .. "/" .. tostring(key))
    end
end
collect_differences(historical_profile, current_profile, "staff_fireball_charged")
assert(#differences == 1
        and differences[1] == "staff_fireball_charged/armor_modifier/attack/5",
    "Fireball profile delta escaped the one-leaf budget")

local state_id = source_catalog.state.id
local function operations(record, family)
    local source = assert(source_by_path[record.source_path])
    local result = {}
    for _, evidence in ipairs(record.ops) do
        result[#result + 1] = {
            change_class = "official_weapon_balance",
            current_source_blob = source.current_blob,
            expected_current = evidence.expected_current,
            expected_present = not evidence.expected_current_unset,
            family_id = family.id,
            official_change_id = family.official_change_id,
            official_summary = family.official_summary,
            path = evidence.path,
            result = evidence.value,
            result_present = not evidence.unset,
            root = "Weapons",
            source_blob = source.historical_blob,
            source_path = record.source_path,
            source_revision = source_catalog.boundary.historical_revision,
            state_id = state_id,
            template = record.template,
        }
    end
    return result
end

local families = source_catalog.families
local fireball_private = copy(current_profile)
fireball_private.armor_modifier.attack[5] = 0.1
local catalog = {
    catalog_id = "wt_history_patch_6_0_v1",
    current_id = "current",
    current_source = {
        display_name = "Current (Game Version " .. current_anchor.game_version .. ")",
        label = current_anchor.game_version .. " source anchor",
        revision = source_catalog.current.revision,
    },
    derived_profiles = {},
    families = {
        {
            display_name = families.kruber_sword_and_shield.display_name,
            id = families.kruber_sword_and_shield.id,
            label_key = families.kruber_sword_and_shield.label_key,
            setting_id = families.kruber_sword_and_shield.setting_id,
            state_order = { state_id },
            states = { [state_id] = {
                atomic_group = families.kruber_sword_and_shield.official_change_id,
                direct_profile_names = {},
                operations = operations(shield_record, families.kruber_sword_and_shield),
                profile_names = {},
            } },
            templates = { families.kruber_sword_and_shield.template },
        },
        {
            display_name = families.bretonnian_sword_and_shield.display_name,
            id = families.bretonnian_sword_and_shield.id,
            label_key = families.bretonnian_sword_and_shield.label_key,
            setting_id = families.bretonnian_sword_and_shield.setting_id,
            state_order = { state_id },
            states = { [state_id] = {
                atomic_group = families.bretonnian_sword_and_shield.official_change_id,
                direct_profile_names = {},
                operations = operations(breton_record,
                    families.bretonnian_sword_and_shield),
                profile_names = {},
            } },
            templates = { families.bretonnian_sword_and_shield.template },
        },
        {
            display_name = families.fireball_staff.display_name,
            id = families.fireball_staff.id,
            label_key = families.fireball_staff.label_key,
            setting_id = families.fireball_staff.setting_id,
            state_order = { state_id },
            states = { [state_id] = {
                direct_profile_names = { "staff_fireball_charged" },
                operations = {},
                profile_names = { "staff_fireball_charged" },
            } },
            templates = { families.fireball_staff.template },
        },
    },
    generation = {
        adjacent_operation_count = 11,
        global_operations = 0,
        profile_route_count = 1,
        unsupported_count = 0,
    },
    profile_specs = {
        [state_id] = {
            staff_fireball_charged = {
                change_class = "official_weapon_balance",
                current_source_blob = source_by_path[DAMAGE_PATH].current_blob,
                historical_profile = fireball_private,
                native_name = "staff_fireball_charged",
                official_change_id = families.fireball_staff.official_change_id,
                official_summary = families.fireball_staff.official_summary,
                private_name = "wt_hist_5_6_1_staff_fireball_charged",
                source_blob = source_by_path[DAMAGE_PATH].historical_blob,
                source_path = DAMAGE_PATH,
                source_revision = source_catalog.boundary.historical_revision,
                state_id = state_id,
            },
        },
    },
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
file:write("-- AUTO-GENERATED by tools/weapon-history/generate_patch_6_0_history.lua; DO NOT HAND-EDIT.\n")
file:write("return ", serialize(catalog), "\n")
file:close()

print("generated " .. output_path .. " families=3 operations=11 profiles=1 globals=0")
