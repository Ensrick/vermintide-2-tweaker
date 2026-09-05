-- Generate the bounded Patch 5.2 history catalog for Tweaker: Weapons (#1436).
--
-- Usage:
--   lua5.1 generate_patch_5_2_history.lua <source-repo> <evidence-dir> <output.lua>
--
-- The evidence directory contains the immutable semantic snapshots preserved
-- from the source-archeology lane.  They are deliberately not shipped with the
-- mod.  This generator filters them through literal ownership/deny lists,
-- attaches full Git provenance, removes vacuous selector states, and emits the
-- compact schema consumed at runtime.

local source_repo = assert(arg and arg[1], "missing source repository")
local evidence_dir = assert(arg[2], "missing evidence directory")
local output_path = assert(arg[3], "missing output path")

-- Lua 5.1's tostring(number) emits too few significant digits to round-trip
-- every IEEE-754 double.  The generated catalog is also a runtime guard oracle,
-- so losing even one low bit makes a source-exact expected_current value reject
-- the live game value.  Pin the numeric locale before any formatting; otherwise
-- %.17g can emit a locale decimal comma that is not valid Lua source.
assert(os.setlocale("C", "numeric"), "C numeric locale unavailable")

local function slash(value)
    return tostring(value):gsub("\\", "/"):gsub("/+$", "")
end

source_repo = slash(source_repo)
evidence_dir = slash(evidence_dir)
output_path = slash(output_path)

local function shell_quote(value)
    return '"' .. tostring(value):gsub('"', '\\"') .. '"'
end

local function command_output(command)
    local pipe = assert(io.popen(command, "r"))
    local output = pipe:read("*a")
    local ok = pipe:close()
    assert(ok, "command failed: " .. command)
    return (output:gsub("[%s]+$", ""))
end

local function load_module(path)
    local chunk, load_error = loadfile(path)
    assert(chunk, load_error)
    local ok, value = pcall(chunk)
    assert(ok, value)
    assert(type(value) == "table", path .. " did not return a table")
    return value
end

local script_dir = slash(tostring(arg[0] or "")):match("^(.*)/[^/]+$") or "."
local current_anchor = load_module(script_dir .. "/current_source_anchor.lua")
assert(current_anchor.schema == 1 or current_anchor.schema == 2,
    "unsupported current source anchor")

local source_catalog = load_module(evidence_dir
    .. "/_wt_history_5_2_source_catalog.lua")

local snapshot_files = {
    ["5_1_1"] = {
        "_wt_history_snapshot_5_1_1_part_1_generated.lua",
        "_wt_history_snapshot_5_1_1_part_2_generated.lua",
    },
    ["5_2_0"] = {
        "_wt_history_snapshot_5_2_0_part_1_generated.lua",
        "_wt_history_snapshot_5_2_0_part_2_generated.lua",
    },
    ["5_2_3"] = {
        "_wt_history_snapshot_5_2_3_generated.lua",
    },
}

local profile_files = {
    ["5_1_1"] = {
        "_wt_history_profiles_5_1_1_generated.lua",
        "_wt_history_profiles_5_1_1_dlc_generated.lua",
    },
    ["5_2_0"] = {
        "_wt_history_profiles_5_2_0_generated.lua",
        "_wt_history_profiles_5_2_0_dlc_generated.lua",
    },
    ["5_2_3"] = {},
}

local full_revision = {
    ["5_1_1"] = "8224b4436e20905a6ba463cb28fa2d7771bb2330",
    ["5_2_0"] = "4f496970e2e7514bef7d612ab91331aa065d5e52",
    ["5_2_3"] = "cdc0a86e24e017119e6d6998870bf76f6e76e868",
}

local current_revision = source_catalog.current_revision
assert(current_revision == current_anchor.content_revision,
    "unexpected current source anchor")

local function path_text(path)
    local parts = {}
    for index = 1, #path do parts[index] = tostring(path[index]) end
    return table.concat(parts, ".")
end

local generation_state_order = { "5_1_1", "5_2_0", "5_2_3" }

local function sorted_keys(value)
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(left, right)
        if type(left) == type(right) then return left < right end
        return type(left) < type(right)
    end)
    return keys
end

local rejected = {
    ["javelin_template|actions.action_one.heavy_stab.allowed_chain_actions"] = true,
    ["javelin_template|actions.action_one.throw_charged.anim_event_infinite_ammo_3p"] = true,
    ["javelin_template|actions.action_one.throw_charged.anim_event_last_ammo_3p"] = true,
    ["javelin_template|destroy_indexed_projectiles"] = true,
    ["heavy_steam_pistol_template_1|actions.action_one.default.allowed_chain_actions"] = true,
    ["one_hand_falchion_template_1|actions.action_one.light_attack_bopp.allowed_chain_actions"] = true,
    ["one_handed_swords_template_1|actions.action_one.light_attack_bopp.allowed_chain_actions"] = true,
    ["one_handed_sword_shield_template_1|actions.action_two.default.anim_event_3p"] = true,
}

local expected_filtered_snapshot_ops = {
    ["5_1_1"] = 91,
    ["5_2_0"] = 74,
    ["5_2_3"] = 9,
}

local family_by_id, family_by_template = {}, {}
for _, family in ipairs(source_catalog.families) do
    family_by_id[family.id] = family
    for _, template in ipairs(family.templates) do
        assert(not family_by_template[template], "duplicate template owner " .. template)
        family_by_template[template] = family
    end
end

local family_allows_state = {}
for _, family in ipairs(source_catalog.families) do
    family_allows_state[family.id] = {}
    for _, state in ipairs(family.states) do
        family_allows_state[family.id][state] = true
    end
end
-- Patch 5.2.3 remains source-distinct from Current for these two families due
-- later gameplay-only drift.  The raw catalog omitted the state because its
-- original purpose was only to describe the adjacent hotfix boundary.
family_allows_state.falchion["5_2_3"] = true
family_allows_state.crowbill["5_2_3"] = true

local blob_cache = {}
local function source_blob(revision, path)
    local key = revision .. ":" .. path
    if blob_cache[key] then return blob_cache[key] end
    local blob = command_output("git -C " .. shell_quote(source_repo)
        .. " rev-parse " .. shell_quote(key) .. " 2>nul")
    assert(blob:match("^[0-9a-f]+$") and #blob == 40,
        "missing source blob " .. key)
    blob_cache[key] = blob
    return blob
end

local function classification(state, family_id, path)
    local text = path_text(path)
    local official
    if state == "5_1_1" then
        if family_id == "coruscation_staff" then official = "P520-COR"
        elseif family_id == "dual_daggers" then official = "P520-DD-MONSTER"
        elseif family_id == "two_handed_sword_shared" then official = "P520-2HS"
        elseif family_id == "javelin" then official = "P520-JAV"
        elseif family_id == "elf_one_handed_axe" then official = "P520-ELF1HA-MOVESET"
        elseif family_id == "one_handed_sword_shared"
                and (text:find("damage_profile", 1, true)
                    or text:find("actions.action_one.push", 1, true)) then
            official = "P520-1HS"
        elseif family_id == "one_handed_axe_shared"
                and text:match("actions%.action_one%.push%.fatigue_cost$") then
            official = "P520-1HA-PUSH"
        elseif family_id == "one_handed_hammer_shared"
                and text:match("actions%.action_one%.push%.fatigue_cost$") then
            official = "P520-1HH-PUSH"
        elseif family_id == "kruber_sword_and_shield"
                and text == "actions.action_one.heavy_attack_right.damage_profile" then
            official = "P520-SS-H3"
        end
    elseif state == "5_2_0" then
        if family_id == "dual_daggers" then official = "P523-DD-REVERT-CRIT"
        elseif family_id == "sword_and_dagger" then official = "P523-SD-H2CRIT"
        elseif family_id == "falchion" then official = "P523-FAL-PUSH"
        elseif family_id == "crowbill" then official = "P523-CROW-PUSH"
        elseif family_id == "one_handed_flail" then official = "P523-FLAIL-PUSH"
        elseif family_id == "masterwork_pistol" then official = "P523-MWP-MONSTER"
        end
    end
    if official then
        return "official_weapon_balance", official,
            "Source-exact gameplay state owned by " .. official .. "."
    end
    return "source_anchor_drift", "source_anchor_drift:" .. family_id,
        "Source-exact gameplay drift between this historical state and the current anchor."
end

local operations_by_state_family = {}
local filtered_counts = {}
for _, state in ipairs(generation_state_order) do
    local files = assert(snapshot_files[state])
    operations_by_state_family[state] = {}
    filtered_counts[state] = 0
    for _, file_name in ipairs(files) do
        local snapshot = load_module(evidence_dir .. "/" .. file_name)
        assert(snapshot.old_revision == full_revision[state]:sub(1, 8),
            file_name .. " old revision mismatch")
        assert(snapshot.new_revision == current_revision:sub(1, 8),
            file_name .. " current revision mismatch")
        for _, record in ipairs(snapshot.records or {}) do
            local family = family_by_template[record.template]
            assert(family, "unowned snapshot template " .. tostring(record.template))
            for _, operation in ipairs(record.ops or {}) do
                local key = record.template .. "|" .. path_text(operation.path)
                if not rejected[key] then
                    filtered_counts[state] = filtered_counts[state] + 1
                    if family_allows_state[family.id][state] then
                        local change_class, change_id, summary = classification(
                            state, family.id, operation.path)
                        local output = {
                            change_class = change_class,
                            current_source_blob = source_blob(current_revision,
                                record.source_path),
                            expected_present = operation.expected_current_unset ~= true,
                            family_id = family.id,
                            official_change_id = change_id,
                            official_summary = summary,
                            path = operation.path,
                            result_present = operation.unset ~= true,
                            root = "Weapons",
                            source_blob = source_blob(full_revision[state],
                                record.source_path),
                            source_path = record.source_path,
                            source_revision = full_revision[state],
                            state_id = state,
                            template = record.template,
                        }
                        if output.expected_present then
                            output.expected_current = operation.expected_current
                        end
                        if output.result_present then output.result = operation.value end
                        local by_family = operations_by_state_family[state]
                        by_family[family.id] = by_family[family.id] or {}
                        by_family[family.id][#by_family[family.id] + 1] = output
                    end
                end
            end
        end
    end
    assert(filtered_counts[state] == expected_filtered_snapshot_ops[state],
        string.format("%s filtered operation budget drift: expected %d got %d",
            state, expected_filtered_snapshot_ops[state], filtered_counts[state]))
end

-- Exact non-template Coruscation gameplay leaves.
local global_count = 0
for _, state in ipairs(generation_state_order) do
    local records = source_catalog.global_records[state] or {}
    for _, record in ipairs(records) do
        local family = assert(family_by_id[record.family_id])
        assert(family_allows_state[family.id][state], "global state not owned")
        local change_class, change_id, summary = classification(
            state, family.id, record.path)
        local operation = {
            change_class = change_class,
            current_source_blob = source_blob(current_revision, record.source_path),
            expected_current = record.expected_current,
            expected_present = true,
            family_id = family.id,
            official_change_id = change_id,
            official_summary = summary,
            path = record.path,
            result = record.value,
            result_present = true,
            root = record.root,
            source_blob = source_blob(full_revision[state], record.source_path),
            source_path = record.source_path,
            source_revision = full_revision[state],
            state_id = state,
        }
        local by_family = operations_by_state_family[state]
        by_family[family.id] = by_family[family.id] or {}
        by_family[family.id][#by_family[family.id] + 1] = operation
        global_count = global_count + 1
    end
end
assert(global_count == 8, "Patch 5.2 global operation budget drift")

local raw_profiles = {}
for _, state in ipairs(generation_state_order) do
    local files = assert(profile_files[state])
    raw_profiles[state] = {}
    for _, file_name in ipairs(files) do
        local module = load_module(evidence_dir .. "/" .. file_name)
        assert(module.old_revision == full_revision[state]:sub(1, 8),
            file_name .. " old revision mismatch")
        assert(module.new_revision == current_revision:sub(1, 8),
            file_name .. " current revision mismatch")
        for name, profile in pairs(module.profiles or {}) do
            assert(not raw_profiles[state][name], "duplicate profile " .. state .. "/" .. name)
            raw_profiles[state][name] = profile
        end
    end
end

local profile_source_path = {
    staff_magma = "scripts/settings/dlcs/morris/damage_profile_templates_dlc_morris.lua",
    geiser_magma = "scripts/settings/dlcs/morris/damage_profile_templates_dlc_morris.lua",
    geiser_magma_no_damage = "scripts/settings/dlcs/morris/damage_profile_templates_dlc_morris.lua",
    medium_javelin_smiter_stab = "scripts/settings/equipment/damage_profile_templates_dlc_woods.lua",
    medium_javelin_smiter_stab_bleed = "scripts/settings/equipment/damage_profile_templates_dlc_woods.lua",
    heavy_javelin_smiter_stab_bleed = "scripts/settings/equipment/damage_profile_templates_dlc_woods.lua",
    thrown_javelin = "scripts/settings/equipment/damage_profile_templates_dlc_woods.lua",
    shot_sniper_pistol = "scripts/settings/equipment/damage_profile_templates_dlc_cog.lua",
}

local function profile_path(name)
    return profile_source_path[name]
        or "scripts/settings/equipment/damage_profile_templates.lua"
end

local profile_specs, profile_names_by_state_family = {}, {}
local profile_route_count, unique_profile_count = {}, {}
local explicit_profile_provenance = {
    ["5_1_1"] = {
        -- Patch 5.2.0's named Elf Axe moveset owns the shared profile's
        -- historical semantic change. The Bardin/Saltzpyre axe family also
        -- consumes that native name, but has no competing named profile delta.
        medium_slashing_smiter_1h_axe = {
            family_id = "elf_one_handed_axe",
            owners = { "elf_one_handed_axe", "one_handed_axe_shared" },
        },
    },
}
for _, state in ipairs(generation_state_order) do
    local routes = source_catalog.profile_routes[state] or {}
    profile_specs[state] = {}
    profile_names_by_state_family[state] = {}
    profile_route_count[state], unique_profile_count[state] = 0, 0
    local owners_by_name = {}
    for _, family_id in ipairs(sorted_keys(routes)) do
        local names = routes[family_id]
        if family_allows_state[family_id] and family_allows_state[family_id][state] then
            local owned = {}
            profile_names_by_state_family[state][family_id] = owned
            for _, name in ipairs(names) do
                profile_route_count[state] = profile_route_count[state] + 1
                owned[#owned + 1] = name
                owners_by_name[name] = owners_by_name[name] or {}
                owners_by_name[name][family_id] = true
            end
            table.sort(owned)
        end
    end
    for _, name in ipairs(sorted_keys(owners_by_name)) do
        local owner_ids = sorted_keys(owners_by_name[name])
        local explicit = explicit_profile_provenance[state]
            and explicit_profile_provenance[state][name]
        local provenance_family
        if explicit then
            assert(#owner_ids == #explicit.owners,
                "profile provenance owner budget drift " .. state .. "/" .. name)
            for index, owner_id in ipairs(owner_ids) do
                assert(owner_id == explicit.owners[index],
                    "profile provenance owner drift " .. state .. "/" .. name)
            end
            assert(owners_by_name[name][explicit.family_id],
                "profile provenance family is not an owner " .. state .. "/" .. name)
            provenance_family = explicit.family_id
        else
            provenance_family = owner_ids[1]
            local expected_class, expected_id, expected_summary = classification(
                state, provenance_family, { "profile", name })
            for index = 2, #owner_ids do
                local change_class, change_id, summary = classification(
                    state, owner_ids[index], { "profile", name })
                assert(change_class == expected_class and change_id == expected_id
                        and summary == expected_summary,
                    "ambiguous shared profile provenance " .. state .. "/" .. name)
            end
        end
        local profile = assert(raw_profiles[state][name],
            "missing routed profile " .. state .. "/" .. name)
        local path = profile_path(name)
        local change_class, change_id, summary = classification(
            state, provenance_family, { "profile", name })
        profile_specs[state][name] = {
            change_class = change_class,
            current_source_blob = source_blob(current_revision, path),
            historical_profile = profile,
            native_name = name,
            official_change_id = change_id,
            official_summary = summary,
            private_name = "wt_hist_" .. state .. "_" .. name,
            source_blob = source_blob(full_revision[state], path),
            source_path = path,
            source_revision = full_revision[state],
            state_id = state,
        }
        unique_profile_count[state] = unique_profile_count[state] + 1
    end
end
assert(profile_route_count["5_1_1"] == 11 and unique_profile_count["5_1_1"] == 10,
    "5.1.1 profile route/unique budget drift")
assert(profile_route_count["5_2_0"] == 3 and unique_profile_count["5_2_0"] == 3,
    "5.2.0 profile budget drift")

local derived_profiles = {
    ["5_1_1"] = {
        geiser_magma_no_damage = {
            derivation = "native_no_damage_clone",
            family_id = "coruscation_staff",
            native_name = "geiser_magma_no_damage",
            private_name = "wt_hist_5_1_1_geiser_magma_no_damage",
            source_profile = "geiser_magma",
            state_id = "5_1_1",
        },
    },
}
profile_names_by_state_family["5_1_1"].coruscation_staff[#profile_names_by_state_family["5_1_1"].coruscation_staff + 1]
    = "geiser_magma_no_damage"
table.sort(profile_names_by_state_family["5_1_1"].coruscation_staff)

local direct_profile_names_by_state_family = {}
local direct_profile_route_count = {}
for _, state in ipairs(generation_state_order) do
    direct_profile_names_by_state_family[state] = {}
    direct_profile_route_count[state] = 0
    local routes = source_catalog.direct_profile_routes
        and source_catalog.direct_profile_routes[state] or {}
    for _, family_id in ipairs(sorted_keys(routes)) do
        assert(family_allows_state[family_id] and family_allows_state[family_id][state],
            "direct profile route state not owned " .. state .. "/" .. family_id)
        local all_names = profile_names_by_state_family[state][family_id] or {}
        local allowed = {}
        for _, name in ipairs(all_names) do allowed[name] = true end
        local direct, seen = {}, {}
        for _, name in ipairs(routes[family_id]) do
            assert(allowed[name], "direct profile is not registered "
                .. state .. "/" .. family_id .. "/" .. name)
            assert(not seen[name], "duplicate direct profile "
                .. state .. "/" .. family_id .. "/" .. name)
            seen[name] = true
            direct[#direct + 1] = name
            direct_profile_route_count[state] = direct_profile_route_count[state] + 1
        end
        table.sort(direct)
        direct_profile_names_by_state_family[state][family_id] = direct
    end
end
assert(direct_profile_route_count["5_1_1"] == 9
        and direct_profile_route_count["5_2_0"] == 2
        and direct_profile_route_count["5_2_3"] == 0,
    "direct profile route budget drift")

local state_metadata = {
    ["5_1_1"] = {
        change_class = "official_weapon_balance",
        display_name = "Game Version 5.1.1",
        label_key = "wt_history_state_5_1_1",
        official_patch_notes = source_catalog.provenance.official_notes["5_2_0"],
        source_revision = full_revision["5_1_1"],
    },
    ["5_2_0"] = {
        change_class = "official_weapon_balance",
        display_name = "Game Version 5.2.0",
        label_key = "wt_history_state_5_2_0",
        official_patch_notes = source_catalog.provenance.official_notes["5_2_3"],
        source_revision = full_revision["5_2_0"],
    },
    ["5_2_3"] = {
        change_class = "source_anchor_drift",
        display_name = "Game Version 5.2.3",
        label_key = "wt_history_state_5_2_3",
        official_patch_notes = source_catalog.provenance.official_notes["5_2_3"],
        source_revision = full_revision["5_2_3"],
    },
}

local families = {}
for _, source_family in ipairs(source_catalog.families) do
    local family = {
        display_name = source_family.label,
        id = source_family.id,
        label_key = "wt_history_family_" .. source_family.id,
        setting_id = source_family.setting_id,
        state_order = {},
        states = {},
        templates = source_family.templates,
    }
    for _, state in ipairs(generation_state_order) do
        if family_allows_state[family.id][state] then
            local operations = operations_by_state_family[state][family.id] or {}
            local profile_names = profile_names_by_state_family[state]
                and profile_names_by_state_family[state][family.id] or {}
            local direct_profile_names = direct_profile_names_by_state_family[state]
                and direct_profile_names_by_state_family[state][family.id] or {}
            if #operations > 0 or #profile_names > 0 then
                family.state_order[#family.state_order + 1] = state
                family.states[state] = {
                    operations = operations,
                    profile_names = profile_names,
                    direct_profile_names = direct_profile_names,
                    atomic_group = family.id == "elf_one_handed_axe"
                        and state == "5_1_1" and "P520-ELF1HA-MOVESET" or nil,
                }
            end
        end
    end
    assert(#family.state_order > 0, "vacuous family " .. family.id)
    families[#families + 1] = family
end

local output = {
    catalog_id = "wt_history_patch_5_2_v1",
    current_id = "current",
    current_source = {
        display_name = "Current (Game Version " .. current_anchor.game_version .. ")",
        label = current_anchor.game_version .. " source anchor",
        revision = current_revision,
    },
    derived_profiles = derived_profiles,
    families = families,
    generation = {
        excluded_paths = rejected,
        filtered_snapshot_operations = filtered_counts,
        global_operations = global_count,
        direct_profile_route_count = direct_profile_route_count,
        profile_route_count = profile_route_count,
        unique_profile_count = unique_profile_count,
    },
    profile_specs = profile_specs,
    schema = 2,
    states = state_metadata,
}

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
file:write("-- AUTO-GENERATED by tools/weapon-history/generate_patch_5_2_history.lua; DO NOT HAND-EDIT.\n")
file:write("return ", serialize(output), "\n")
file:close()

print(string.format(
    "generated %s families=%d snapshot_ops=%d/%d/%d globals=%d profile_routes=%d/%d",
    output_path, #families, filtered_counts["5_1_1"],
    filtered_counts["5_2_0"], filtered_counts["5_2_3"], global_count,
    profile_route_count["5_1_1"], profile_route_count["5_2_0"]))
