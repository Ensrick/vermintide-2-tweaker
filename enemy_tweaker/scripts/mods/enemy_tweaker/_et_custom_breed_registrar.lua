-- Declarative, fail-closed custom-breed registration owner (#1413).
--
-- All fallible work is completed against off-table values before commit.  The
-- three NetworkLookup axes are planned through the canonical strict helper using
-- shadow tables, then committed together.  ConflictDirector's threat table is
-- a source-proven hidden upvalue, so its exact setter is the first commit
-- operation; Breeds[name] is the final raw write. If that opaque setter throws,
-- structural state remains untouched
-- but threat state is indeterminate and the breed is terminally retired for
-- this module load; production code does not pretend it can roll that upvalue
-- back through debug APIs.
--
-- Reload authority is schema-3 detached state persisted inside the published
-- breed marker: full breed/actions content, original identities, threat/elite,
-- all three numeric wire ids, dismemberment, and hit zones. Owner callbacks receive
-- detached views, so validation cannot mutate a live source or existing breed.

local M = {}

local MARKER_KEY = "_et_custom_breed_registration"
local SCHEMA = 3
local RACE_NAMES = { "beastmen", "chaos", "critter", "skaven", "undead" }
local TERMINAL = {}
local DECLARED, DECLARATION_ORDER = {}, {}
local MARKER_FIELDS = {
    schema = true, owner = true, fingerprint = true, source_breed = true,
    breed_snapshot = true,
    actions_ref = true, actions_snapshot = true,
    source_overlay_snapshot = true,
    threat_value = true, elite = true,
    breed_index = true, damage_source_index = true,
    statistics_path_index = true,
    dismemberment_ref = true, dismemberment_snapshot = true,
    hit_zones_ref = true,
}
local MARKER_FIELD_COUNT = 16

local function valid_string(value)
    return type(value) == "string" and value ~= ""
end

local function valid_index(value)
    return type(value) == "number" and value > 0 and value == value
        and value ~= math.huge and value % 1 == 0
end

local function valid_number(value)
    return type(value) == "number" and value >= 0 and value == value
        and value ~= math.huge and value ~= -math.huge
end

local function valid_count(value)
    return valid_number(value) and value % 1 == 0
end

local function dense_row_count(rows, label)
    if rows == nil then return 0 end
    if type(rows) ~= "table" then return nil, label .. "_invalid" end
    local count, maximum = 0, 0
    for key in next, rows do
        if not valid_index(key) then return nil, label .. "_invalid" end
        count = count + 1
        if key > maximum then maximum = key end
    end
    if count ~= maximum then return nil, label .. "_sparse" end
    return maximum
end

local function copy_raw(source)
    local out = {}
    for key, value in next, source do
        rawset(out, key, value)
    end
    setmetatable(out, getmetatable(source))
    return out
end

-- Detached validation authority is deliberately narrower than arbitrary Lua:
-- every table has a nil metatable and every key is primitive. Actual breed,
-- action, dismemberment, and presentation declarations satisfy that boundary.
-- Rejecting richer shapes prevents a table key or metatable from remaining a
-- mutable shared back door between live state and its canonical snapshot.
-- Values are copied recursively with a seen map so cycles and shared topology
-- remain exact while no nested mutable value is shared with live registration.
local function detached_copy(value, seen, root_omit)
    if type(value) ~= "table" then return value end
    if getmetatable(value) ~= nil then error("detached_metatable_invalid") end
    seen = seen or {}
    local prior = seen[value]
    if prior then return prior end
    local out = {}
    seen[value] = out
    for key, child in next, value do
        if root_omit == nil or key ~= root_omit then
            local key_type = type(key)
            if key_type ~= "string" and key_type ~= "number"
                and key_type ~= "boolean" then
                error("detached_key_invalid")
            end
            rawset(out, key, detached_copy(child, seen))
        end
    end
    return out
end

local function detached_copy_root_except(value, omitted_key)
    return detached_copy(value, {}, omitted_key)
end

local function deep_equal(left, right, left_seen, right_seen)
    if rawequal(left, right) then return true end
    if type(left) ~= "table" or type(right) ~= "table" then return false end
    if not rawequal(getmetatable(left), getmetatable(right)) then return false end
    left_seen, right_seen = left_seen or {}, right_seen or {}
    local mapped_right, mapped_left = left_seen[left], right_seen[right]
    if mapped_right ~= nil or mapped_left ~= nil then
        return rawequal(mapped_right, right) and rawequal(mapped_left, left)
    end
    left_seen[left], right_seen[right] = right, left
    for key, value in next, left do
        if not deep_equal(value, rawget(right, key), left_seen, right_seen) then
            return false
        end
    end
    for key in next, right do
        if rawget(left, key) == nil then return false end
    end
    return true
end

local function deep_equal_root_except(left, right, omitted_key)
    if type(left) ~= "table" or type(right) ~= "table"
        or not rawequal(getmetatable(left), getmetatable(right)) then
        return false
    end
    local left_seen, right_seen = { [left] = right }, { [right] = left }
    for key, value in next, left do
        if key ~= omitted_key
            and not deep_equal(value, rawget(right, key), left_seen, right_seen) then
            return false
        end
    end
    if rawget(right, omitted_key) ~= nil then return false end
    for key in next, right do
        if key == omitted_key or rawget(left, key) == nil then return false end
    end
    return true
end

local function collect_value_tables(value, seen, root_omit)
    if type(value) ~= "table" or seen[value] then return end
    seen[value] = true
    for key, child in next, value do
        if root_omit == nil or key ~= root_omit then
            collect_value_tables(child, seen)
        end
    end
end

local function table_graphs_disjoint(left, right, left_root_omit)
    local left_tables = {}
    collect_value_tables(left, left_tables, left_root_omit)
    local pending, right_seen = { right }, {}
    while #pending > 0 do
        local value = pending[#pending]
        pending[#pending] = nil
        if type(value) == "table" and not right_seen[value] then
            if left_tables[value] then return false end
            right_seen[value] = true
            for _, child in next, value do
                if type(child) == "table" then pending[#pending + 1] = child end
            end
        end
    end
    return true
end

local function append_path(path, key)
    local out = {}
    for i = 1, #path do out[i] = path[i] end
    out[#out + 1] = key
    return out
end

local function path_value(root, path)
    local value = root
    for i = 1, #path do
        if type(value) ~= "table" then return nil, false end
        value = rawget(value, path[i])
    end
    return value, true
end

local function set_path(root, path, value)
    local target = root
    for i = 1, #path - 1 do
        target = type(target) == "table" and rawget(target, path[i]) or nil
        if type(target) ~= "table" then return false end
    end
    rawset(target, path[#path], value)
    return true
end

-- Compare the immutable action projection while omitting only fields that the
-- engine's SET_BREED_DIFFICULTY function is source-proven to rewrite. The
-- left/right maps retain stable graph topology, including shared tables and
-- cycles, across every non-overlay edge.
local function deep_equal_projection(left, right, allowed, left_seen, right_seen)
    if rawequal(left, right) then return true end
    if type(left) ~= "table" or type(right) ~= "table" then return false end
    if not rawequal(getmetatable(left), getmetatable(right)) then return false end
    left_seen, right_seen = left_seen or {}, right_seen or {}
    local mapped_right, mapped_left = left_seen[left], right_seen[right]
    if mapped_right ~= nil or mapped_left ~= nil then
        return rawequal(mapped_right, right) and rawequal(mapped_left, left)
    end
    left_seen[left], right_seen[right] = right, left
    local permitted = allowed[right]
    for key, value in next, left do
        if not (permitted and permitted[key])
            and not deep_equal_projection(
                value, rawget(right, key), allowed, left_seen, right_seen) then
            return false
        end
    end
    for key in next, right do
        if not (permitted and permitted[key]) and rawget(left, key) == nil then
            return false
        end
    end
    return true
end

local function add_action_overlay(allowed, rows, target, target_path, key,
        declaration_path, duration_path)
    local fields = allowed[target]
    if not fields then fields = {}; allowed[target] = fields end
    if fields[key] then return end
    fields[key] = true
    rows[#rows + 1] = {
        path = append_path(target_path, key),
        declaration_path = declaration_path,
        duration_path = duration_path,
    }
end

local function collect_bot_threat_overlays(node, path, allowed, rows, seen)
    if type(node) ~= "table" or seen[node] then return true end
    seen[node] = true
    local declaration = rawget(node, "bot_threat_difficulty_data")
    if declaration then
        if type(declaration) ~= "table" then
            return nil, "existing_actions_overlay_declaration_invalid"
        end
        local declaration_path = append_path(path, "bot_threat_difficulty_data")
        local function add_target(target, target_path)
            if type(target) ~= "table" then
                return nil, "existing_actions_overlay_shape_invalid"
            end
            if rawget(target, "duration") then
                add_action_overlay(allowed, rows, target, target_path,
                    "max_start_delay", declaration_path,
                    append_path(target_path, "duration"))
            elseif rawget(target, "bot_threat_duration") then
                add_action_overlay(allowed, rows, target, target_path,
                    "bot_threat_max_start_delay", declaration_path,
                    append_path(target_path, "bot_threat_duration"))
            end
            return true
        end
        local bot_threats = rawget(node, "bot_threats")
        if bot_threats ~= nil then
            if type(bot_threats) ~= "table" then
                return nil, "existing_actions_overlay_shape_invalid"
            end
            local threats_path = append_path(path, "bot_threats")
            if rawget(bot_threats, 1) then
                for i = 1, #bot_threats do
                    local ok, reason = add_target(
                        rawget(bot_threats, i), append_path(threats_path, i))
                    if not ok then return nil, reason end
                end
            else
                for animation, animation_threats in next, bot_threats do
                    if type(animation_threats) ~= "table" then
                        return nil, "existing_actions_overlay_shape_invalid"
                    end
                    local animation_path = append_path(threats_path, animation)
                    for i = 1, #animation_threats do
                        local ok, reason = add_target(rawget(animation_threats, i),
                            append_path(animation_path, i))
                        if not ok then return nil, reason end
                    end
                end
            end
        elseif rawget(node, "bot_threat_duration") then
            local ok, reason = add_target(node, path)
            if not ok then return nil, reason end
        end
        return true
    end
    for key, child in next, node do
        if type(child) == "table" then
            local ok, reason = collect_bot_threat_overlays(
                child, append_path(path, key), allowed, rows, seen)
            if not ok then return nil, reason end
        end
    end
    return true
end

local function action_overlay_contract(canonical)
    local allowed, rows, bot_seen = {}, {}, {}
    for action_name, action in next, canonical do
        if type(action) == "table" then
            local action_path = { action_name }
            local mappings = {
                { "difficulty_damage", "damage" },
                { "blocked_difficulty_damage", "blocked_damage" },
                { "difficulty_diminishing_damage", "diminishing_damage" },
            }
            for i = 1, #mappings do
                local declaration_key, output_key = mappings[i][1], mappings[i][2]
                if rawget(action, declaration_key) then
                    add_action_overlay(allowed, rows, action, action_path,
                        output_key, append_path(action_path, declaration_key))
                end
            end
            local ok, reason = collect_bot_threat_overlays(
                action, action_path, allowed, rows, bot_seen)
            if not ok then return nil, nil, reason end
        end
    end
    return allowed, rows
end

-- The vanilla donor's declaration topology is independent from the custom
-- clone's topology: Foundation table.clone recursively clones each occurrence
-- without a seen map, so one shared Chaos Warrior difficulty declaration can
-- legitimately become several distinct custom declaration tables. Pin the
-- donor declarations/durations in their own detached graph instead of trying
-- to compare donor identity topology with the custom canonical snapshot.
local function build_source_overlay_snapshot(source, rows)
    local snapshot, copied = {}, {}
    for i = 1, #rows do
        local row = rows[i]
        local declaration, declaration_ok = path_value(
            source, row.declaration_path)
        if not declaration_ok then
            return nil, "existing_actions_overlay_source_mismatch"
        end
        local copy_ok, declaration_copy = pcall(
            detached_copy, declaration, copied)
        if not copy_ok then
            return nil, "existing_actions_overlay_source_mismatch"
        end
        local entry = { declaration = declaration_copy }
        if row.duration_path then
            local duration, duration_ok = path_value(source, row.duration_path)
            if not duration_ok then
                return nil, "existing_actions_overlay_source_mismatch"
            end
            local duration_copy_ok, duration_copy = pcall(
                detached_copy, duration, copied)
            if not duration_copy_ok then
                return nil, "existing_actions_overlay_source_mismatch"
            end
            entry.has_duration = true
            entry.duration = duration_copy
        end
        snapshot[i] = entry
    end
    if not table_graphs_disjoint(snapshot, source) then
        return nil, "existing_actions_overlay_source_mismatch"
    end
    return snapshot
end

-- DifficultyManager.set_difficulty invokes SET_BREED_DIFFICULTY after selecting
-- the active difficulty. That engine pass rewrites every BreedActions family,
-- including the vanilla source and ET clone, so the current source outputs are
-- the only runtime authority for these narrowly declared overlay paths. The
-- detached marker remains canonical for declarations, durations, and every
-- stable field; it is never refreshed from either live table.
local function validate_action_reload(live, canonical, source,
        canonical_source_overlay)
    if not table_graphs_disjoint(live, canonical) then
        return nil, "existing_actions_fingerprint_mismatch"
    end
    if not table_graphs_disjoint(source, canonical) then
        return nil, "existing_actions_overlay_source_mismatch"
    end
    if type(canonical_source_overlay) ~= "table"
        or not table_graphs_disjoint(canonical_source_overlay, source)
        or not table_graphs_disjoint(canonical_source_overlay, canonical)
        or not table_graphs_disjoint(canonical_source_overlay, live) then
        return nil, "existing_actions_overlay_source_mismatch"
    end
    local allowed, rows, contract_reason = action_overlay_contract(canonical)
    if not allowed then return nil, contract_reason end
    local current_source_overlay, source_overlay_reason =
        build_source_overlay_snapshot(source, rows)
    if not current_source_overlay
        or not deep_equal(current_source_overlay, canonical_source_overlay) then
        return nil, source_overlay_reason
            or "existing_actions_overlay_source_mismatch"
    end
    if not deep_equal_projection(live, canonical, allowed) then
        return nil, "existing_actions_fingerprint_mismatch"
    end
    local expected_ok, expected = pcall(detached_copy, canonical)
    if not expected_ok or type(expected) ~= "table"
        or not table_graphs_disjoint(expected, canonical) then
        return nil, "existing_actions_overlay_copy_failed"
    end
    local source_output_seen = {}
    for i = 1, #rows do
        local row = rows[i]
        local canonical_declaration, canonical_ok = path_value(
            canonical, row.declaration_path)
        local source_declaration, source_ok = path_value(
            source, row.declaration_path)
        if not canonical_ok or not source_ok
            or not deep_equal(source_declaration, canonical_declaration) then
            return nil, "existing_actions_overlay_source_mismatch"
        end
        if row.duration_path then
            local canonical_duration, canonical_duration_ok = path_value(
                canonical, row.duration_path)
            local source_duration, source_duration_ok = path_value(
                source, row.duration_path)
            if not canonical_duration_ok or not source_duration_ok
                or not deep_equal(source_duration, canonical_duration) then
                return nil, "existing_actions_overlay_source_mismatch"
            end
        end
        local source_value, source_value_ok = path_value(source, row.path)
        if not source_value_ok then
            return nil, "existing_actions_overlay_source_mismatch"
        end
        local copy_ok, copied_source_value = pcall(
            detached_copy, source_value, source_output_seen)
        if not copy_ok or not set_path(expected, row.path, copied_source_value) then
            return nil, "existing_actions_overlay_copy_failed"
        end
    end
    if not table_graphs_disjoint(expected, canonical)
        or not table_graphs_disjoint(expected, source) then
        return nil, "existing_actions_overlay_copy_failed"
    end
    if not table_graphs_disjoint(live, source)
        or not deep_equal(live, expected) then
        return nil, "existing_actions_overlay_mismatch"
    end
    return true
end

local function marker_shape_valid(marker)
    if type(marker) ~= "table" or getmetatable(marker) ~= nil then return false end
    local count = 0
    for key in next, marker do
        if not MARKER_FIELDS[key] then return false end
        count = count + 1
    end
    return count == MARKER_FIELD_COUNT
end

local function default_runtime()
    local managers = rawget(_G, "Managers")
    local state = type(managers) == "table" and rawget(managers, "state")
    local performance = type(state) == "table" and rawget(state, "performance")
    return {
        breeds = rawget(_G, "Breeds"),
        actions = rawget(_G, "BreedActions"),
        network_lookup = rawget(_G, "NetworkLookup"),
        network_constants = rawget(_G, "NetworkConstants"),
        network = rawget(_G, "Network"),
        clone = type(table) == "table" and rawget(table, "clone"),
        conflict_director = rawget(_G, "ConflictDirector"),
        statistics = rawget(_G, "StatisticsDefinitions"),
        difficulties = rawget(_G, "DifficultySettings"),
        package_settings = rawget(_G, "EnemyPackageLoaderSettings"),
        dismemberments = rawget(_G, "Dismemberments"),
        race_sets = {
            beastmen = rawget(_G, "BEASTMEN"), chaos = rawget(_G, "CHAOS"),
            critter = rawget(_G, "CRITTER"), skaven = rawget(_G, "SKAVEN"),
            undead = rawget(_G, "UNDEAD"),
        },
        elites = rawget(_G, "ELITES"),
        hit_zones = rawget(_G, "BreedHitZonesLookup"),
        performance = performance,
        raw_set = rawset,
    }
end

local function read_damage_source_cap(runtime)
    local constants = runtime.network_constants
    if type(constants) == "table" then
        local info = rawget(constants, "damage_source_id")
        local cap = type(info) == "table" and rawget(info, "max")
        if valid_index(cap) then return cap end
    end
    local network = runtime.network
    local type_info = type(network) == "table" and rawget(network, "type_info")
    if type(type_info) == "function" then
        local ok, info = pcall(type_info, "damage_source_id")
        local cap = ok and type(info) == "table" and rawget(info, "max")
        if valid_index(cap) then return cap end
    end
    return nil, "damage_source_cap_unavailable"
end

local function read_statistics_path_cap(runtime)
    -- network_constants.lua checks this exact generated-network capacity. The
    -- axis is needed by StatisticsDatabase's hot-join path encoder/decoder.
    local network = runtime.network
    local type_info = type(network) == "table" and rawget(network, "type_info")
    if type(type_info) == "function" then
        local ok, info = pcall(type_info, "statistics_path_lookup")
        local cap = ok and type(info) == "table" and rawget(info, "max")
        if valid_index(cap) then return cap end
    end
    return nil, "statistics_path_cap_unavailable"
end

local function stat_values(name, difficulties)
    local kills_difficulty, assists_difficulty = {}, {}
    for difficulty_name in next, difficulties do
        if not valid_string(difficulty_name) then
            return nil, "difficulty_name_invalid"
        end
        kills_difficulty[difficulty_name] = {
            value = 0, name = name .. "_" .. difficulty_name,
        }
        assists_difficulty[difficulty_name] = {
            value = 0, name = name .. "_" .. difficulty_name,
        }
    end
    return {
        kills_per_breed = { sync_on_hot_join = true, value = 0, name = name },
        kills_per_breed_persistent = {
            source = "player_data", value = 0, name = name,
            database_name = "kills_per_breed_persistent_" .. name,
        },
        kill_assists_per_breed = { value = 0, name = name },
        damage_dealt_per_breed = { value = 0, name = name },
        kills_per_breed_difficulty = kills_difficulty,
        kill_assists_per_breed_difficulty = assists_difficulty,
    }
end

local STAT_NAMES = {
    "kills_per_breed", "kills_per_breed_persistent",
    "kill_assists_per_breed", "damage_dealt_per_breed",
    "kills_per_breed_difficulty", "kill_assists_per_breed_difficulty",
}

local function add_write(plan, target, key, value, label)
    if type(target) ~= "table" then return nil, label .. "_missing" end
    local per_table = plan.seen[target]
    if not per_table then
        per_table = {}
        plan.seen[target] = per_table
    end
    if per_table[key] then return nil, "duplicate_write:" .. label end
    per_table[key] = true
    plan.writes[#plan.writes + 1] = {
        target = target, key = key, value = value, label = label,
    }
    return true
end

local function alias_counts(breed_to_aliases, name, expected_source)
    local total, expected = 0, 0
    for source, aliases in next, breed_to_aliases do
        if type(aliases) == "table" then
            for _, alias in next, aliases do
                if alias == name then
                    total = total + 1
                    if source == expected_source then expected = expected + 1 end
                end
            end
        end
    end
    return total, expected
end

local function validate_alias_array(aliases)
    if aliases == nil then return 0 end
    if type(aliases) ~= "table" then return nil, "source_aliases_malformed" end
    local count, maximum = 0, 0
    for key, value in next, aliases do
        if not valid_index(key) or not valid_string(value) then
            return nil, "source_aliases_malformed"
        end
        count = count + 1
        if key > maximum then maximum = key end
    end
    if count ~= maximum then return nil, "source_aliases_sparse" end
    return maximum
end

local function plan_lookup(runtime, axis, name)
    local real = rawget(runtime.network_lookup, axis)
    if type(real) ~= "table" then return nil, "lookup_" .. axis .. "_missing" end
    local copy_ok, shadow = pcall(copy_raw, real)
    if not copy_ok then return nil, "lookup_" .. axis .. "_copy_failed" end
    local outer = {}
    rawset(outer, axis, shadow)
    local ok, index, inserted, reason = pcall(
        runtime.lookup_lib.register_named, outer, axis, name)
    if not ok then return nil, "lookup_" .. axis .. "_threw" end
    if inserted then
        if reason ~= "registered" or not valid_index(index)
            or rawget(real, index) ~= nil or rawget(real, name) ~= nil
            or rawget(shadow, index) ~= name or rawget(shadow, name) ~= index then
            return nil, "lookup_" .. axis .. "_plan_invalid"
        end
    elseif reason ~= "already_registered" or not valid_index(index)
        or rawget(real, index) ~= name or rawget(real, name) ~= index then
        return nil, "lookup_" .. axis .. ":" .. tostring(reason)
    end
    return { real = real, index = index, inserted = inserted }
end

local function validate_spec(spec)
    if type(spec) ~= "table" then return nil, "spec_missing" end
    if not valid_string(spec.name) then return nil, "name_invalid" end
    if not valid_string(spec.owner) then return nil, "owner_invalid" end
    if not valid_string(spec.fingerprint) then return nil, "fingerprint_invalid" end
    if not valid_string(spec.source_breed) then return nil, "source_breed_invalid" end
    if not valid_string(spec.race) then return nil, "race_invalid" end
    local race_known = false
    for i = 1, #RACE_NAMES do
        if spec.race == RACE_NAMES[i] then race_known = true break end
    end
    if not race_known then return nil, "race_unsupported" end
    if spec.configure ~= nil and type(spec.configure) ~= "function" then
        return nil, "configure_invalid"
    end
    if spec.validate_breed ~= nil and type(spec.validate_breed) ~= "function" then
        return nil, "validate_breed_invalid"
    end
    return true
end

local function configure_candidate(spec, breed, source)
    if not spec.configure then return true end
    local view_ok, source_view = pcall(detached_copy, source)
    if not view_ok then return nil, "configure_source_view_failed" end
    local configure_ok, configure_error = pcall(spec.configure, breed, source_view)
    if not configure_ok then
        return nil, "configure_threw:" .. tostring(configure_error)
    end
    return true
end

local function validate_candidate(spec, breed, source, fallback_reason)
    if not spec.validate_breed then return true end
    local breed_ok, breed_view = pcall(
        detached_copy_root_except, breed, MARKER_KEY)
    if not breed_ok then return nil, "validate_breed_view_failed" end
    local source_ok, source_view = pcall(detached_copy, source)
    if not source_ok then return nil, "validate_source_view_failed" end
    local valid_ok, valid, valid_reason = pcall(
        spec.validate_breed, breed_view, source_view)
    if not valid_ok then return nil, "validate_breed_threw" end
    if not valid then
        return nil, valid_reason or fallback_reason or "configured_breed_invalid"
    end
    return true
end

local function mandatory_context(runtime, spec)
    local required = {
        { runtime.breeds, "breeds" }, { runtime.actions, "actions" },
        { runtime.network_lookup, "network_lookup" },
        { runtime.lookup_lib, "lookup_lib" },
        { runtime.statistics, "statistics" },
        { runtime.difficulties, "difficulties" },
        { runtime.package_settings, "package_settings" },
        { runtime.dismemberments, "dismemberments" },
        { runtime.race_sets, "race_sets" }, { runtime.elites, "elites" },
        { runtime.hit_zones, "hit_zones" },
    }
    for i = 1, #required do
        if type(required[i][1]) ~= "table" then return nil, required[i][2] .. "_missing" end
    end
    if type(runtime.clone) ~= "function" then return nil, "clone_missing" end
    if type(runtime.raw_set) ~= "function" then return nil, "raw_set_missing" end
    if type(rawget(runtime.lookup_lib, "register_named")) ~= "function" then
        return nil, "lookup_register_missing"
    end
    local cd = runtime.conflict_director
    if type(cd) ~= "table" or type(rawget(cd, "set_threat_value")) ~= "function" then
        return nil, "threat_setter_missing"
    end
    for i = 1, #RACE_NAMES do
        if type(rawget(runtime.race_sets, RACE_NAMES[i])) ~= "table" then
            return nil, "race_set_" .. RACE_NAMES[i] .. "_missing"
        end
    end
    if type(rawget(runtime.race_sets, spec.race)) ~= "table" then
        return nil, "race_set_selected_missing"
    end
    local player = rawget(runtime.statistics, "player")
    if type(player) ~= "table" then return nil, "statistics_player_missing" end
    for i = 1, #STAT_NAMES do
        if type(rawget(player, STAT_NAMES[i])) ~= "table" then
            return nil, "statistics_" .. STAT_NAMES[i] .. "_missing"
        end
    end
    local aliases = rawget(runtime.package_settings, "alias_to_breed")
    local reverse = rawget(runtime.package_settings, "breed_to_aliases")
    if type(aliases) ~= "table" then return nil, "alias_to_breed_missing" end
    if type(reverse) ~= "table" then return nil, "breed_to_aliases_missing" end
    if runtime.performance ~= nil
        and (type(runtime.performance) ~= "table"
            or type(rawget(runtime.performance, "_activated_per_breed")) ~= "table") then
        return nil, "performance_surface_malformed"
    end
    return true
end

local function validate_presentations(spec, existing, plan)
    local presentations = spec.presentations
    if presentations == nil then presentations = {} end
    local row_count, row_reason = dense_row_count(presentations, "presentations")
    if not row_count then return nil, row_reason end
    local declared_tables = {}
    for i = 1, row_count do
        local row = presentations[i]
        local value = type(row) == "table" and rawget(row, "value")
        if type(value) == "table" then
            declared_tables[#declared_tables + 1] = value
        end
    end
    local selected_tables = {}
    for i = 1, row_count do
        local row = presentations[i]
        if type(row) ~= "table" or rawget(row, "key") == nil
            or rawget(row, "value") == nil then
            return nil, "presentation_" .. i .. "_invalid"
        end
        local required = rawget(row, "required")
        if required ~= nil and type(required) ~= "boolean" then
            return nil, "presentation_" .. i .. "_invalid"
        end
        local target = rawget(row, "target")
        if type(target) ~= "table" then
            if required == false then
                -- Optional presentation surfaces may genuinely be absent.
            else
                return nil, "presentation_" .. i .. "_missing"
            end
        else
            local key, value = rawget(row, "key"), rawget(row, "value")
            local ephemeral = rawget(row, "ephemeral")
            if ephemeral ~= nil and type(ephemeral) ~= "boolean" then
                return nil, "presentation_" .. i .. "_invalid"
            end
            local planned_value = value
            if type(value) == "table" then
                local copy_ok, detached = pcall(detached_copy, value)
                if not copy_ok or type(detached) ~= "table"
                    or not table_graphs_disjoint(detached, declared_tables)
                    or not table_graphs_disjoint(detached, selected_tables) then
                    return nil, "presentation_" .. i .. "_copy_failed"
                end
                planned_value = detached
            end
            local current = rawget(target, key)
            local detached = type(value) ~= "table"
                or (type(current) == "table"
                    and table_graphs_disjoint(current, declared_tables)
                    and table_graphs_disjoint(current, selected_tables))
            local selected
            if ephemeral then
                if not detached or not deep_equal(current, value) then
                    local ok, reason = add_write(plan, target, key, planned_value,
                        "presentation_" .. i)
                    if not ok then return nil, reason end
                    selected = planned_value
                else
                    selected = current
                end
            elseif existing then
                if not detached or not deep_equal(current, value) then
                    return nil, "presentation_" .. i .. "_mismatch"
                end
                selected = current
            else
                if current ~= nil then return nil, "presentation_" .. i .. "_residue" end
                local ok, reason = add_write(plan, target, key, planned_value,
                    "presentation_" .. i)
                if not ok then return nil, reason end
                selected = planned_value
            end
            if type(selected) == "table" then
                if not table_graphs_disjoint(selected, declared_tables)
                    or not table_graphs_disjoint(selected, selected_tables) then
                    return nil, "presentation_" .. i .. "_mismatch"
                end
                selected_tables[#selected_tables + 1] = selected
            end
        end
    end
    return true
end

local function build_plan(spec, runtime)
    local ok, reason = validate_spec(spec)
    if not ok then return nil, reason end
    ok, reason = mandatory_context(runtime, spec)
    if not ok then return nil, reason end
    if TERMINAL[spec.name] then return nil, "terminal:" .. TERMINAL[spec.name] end

    local plan = { writes = {}, seen = {}, runtime = runtime, spec = spec }
    local name, source_name = spec.name, spec.source_breed
    local source = rawget(runtime.breeds, source_name)
    local source_actions = rawget(runtime.actions, source_name)
    local source_dismemberment = rawget(runtime.dismemberments, source_name)
    if type(source) ~= "table" then return nil, "source_breed_missing" end
    if type(source_actions) ~= "table" then return nil, "source_actions_missing" end
    if type(source_dismemberment) ~= "table" then return nil, "source_dismemberment_missing" end

    local existing = rawget(runtime.breeds, name)
    local existing_present = existing ~= nil
    if existing_present and type(existing) ~= "table" then
        return nil, "existing_breed_foreign"
    end

    local breed_wire, wire_reason = plan_lookup(runtime, "breeds", name)
    if not breed_wire then return nil, wire_reason end
    local damage_wire, damage_reason = plan_lookup(runtime, "damage_sources", name)
    if not damage_wire then return nil, damage_reason end
    local statistics_wire, statistics_reason = plan_lookup(
        runtime, "statistics_path_names", name)
    if not statistics_wire then return nil, statistics_reason end

    if existing_present then
        if breed_wire.inserted or damage_wire.inserted or statistics_wire.inserted then
            return nil, "existing_breed_wire_partial"
        end
    elseif not breed_wire.inserted or not damage_wire.inserted then
        return nil, "new_breed_wire_residue"
    end
    if damage_wire.inserted then
        local cap, cap_reason = read_damage_source_cap(runtime)
        if not cap then return nil, cap_reason end
        if damage_wire.index > cap then return nil, "damage_source_cap_exceeded" end
    end
    if statistics_wire.inserted then
        local cap, cap_reason = read_statistics_path_cap(runtime)
        if not cap then return nil, cap_reason end
        if statistics_wire.index > cap then
            return nil, "statistics_path_cap_exceeded"
        end
    end

    local stats_player = rawget(runtime.statistics, "player")
    local expected_stats, stats_reason = stat_values(name, runtime.difficulties)
    if not expected_stats then return nil, stats_reason end
    local alias_to = rawget(runtime.package_settings, "alias_to_breed")
    local breed_to_aliases = rawget(runtime.package_settings, "breed_to_aliases")
    local source_aliases = rawget(breed_to_aliases, source_name)
    local source_alias_count, source_alias_reason = validate_alias_array(source_aliases)
    if not source_alias_count then return nil, source_alias_reason end
    local alias_total, expected_aliases = alias_counts(breed_to_aliases, name, source_name)
    local performance = runtime.performance
        and rawget(runtime.performance, "_activated_per_breed") or nil
    local breed, actions, expected_elite, canonical_threat

    if existing_present then
        breed = existing
        local marker = rawget(breed, MARKER_KEY)
        if not marker_shape_valid(marker) or rawget(marker, "schema") ~= SCHEMA
            or rawget(marker, "owner") ~= spec.owner
            or rawget(marker, "fingerprint") ~= spec.fingerprint
            or rawget(marker, "source_breed") ~= source_name
            or type(rawget(marker, "breed_snapshot")) ~= "table"
            or type(rawget(marker, "actions_ref")) ~= "table"
            or type(rawget(marker, "actions_snapshot")) ~= "table"
            or type(rawget(marker, "source_overlay_snapshot")) ~= "table"
            or not valid_number(rawget(marker, "threat_value"))
            or type(rawget(marker, "elite")) ~= "boolean"
            or not valid_index(rawget(marker, "breed_index"))
            or not valid_index(rawget(marker, "damage_source_index"))
            or not valid_index(rawget(marker, "statistics_path_index"))
            or type(rawget(marker, "dismemberment_ref")) ~= "table"
            or type(rawget(marker, "dismemberment_snapshot")) ~= "table"
            or type(rawget(marker, "hit_zones_ref")) ~= "table" then
            return nil, "existing_breed_fingerprint_mismatch"
        end
        if breed_wire.index ~= rawget(marker, "breed_index")
            or damage_wire.index ~= rawget(marker, "damage_source_index")
            or statistics_wire.index ~= rawget(marker, "statistics_path_index") then
            return nil, "existing_wire_identity_mismatch"
        end
        canonical_threat = rawget(marker, "threat_value")
        expected_elite = rawget(marker, "elite") and true or nil
        actions = rawget(marker, "actions_ref")
        if type(actions) ~= "table"
            or not rawequal(rawget(runtime.actions, name), actions) then
            return nil, "existing_actions_mismatch"
        end
        local actions_ok, actions_reason = validate_action_reload(
            actions, rawget(marker, "actions_snapshot"), source_actions,
            rawget(marker, "source_overlay_snapshot"))
        if not actions_ok then return nil, actions_reason end
        if breed.name ~= name or breed.race ~= spec.race then
            return nil, "existing_breed_identity_mismatch"
        end
        if rawget(breed, "threat_value") ~= canonical_threat then
            return nil, "existing_threat_value_mismatch"
        end
        local current_elite = rawget(breed, "elite") and true or nil
        if current_elite ~= expected_elite then
            return nil, "existing_elite_fingerprint_mismatch"
        end
        local live_hit_zones = rawget(breed, "hit_zones_lookup")
        local snapshot_hit_zones = rawget(
            rawget(marker, "breed_snapshot"), "hit_zones_lookup")
        if type(live_hit_zones) ~= "table"
            or not rawequal(live_hit_zones, rawget(marker, "hit_zones_ref"))
            or not rawequal(rawget(runtime.hit_zones, name), live_hit_zones) then
            return nil, "hit_zones_mismatch"
        end
        if type(snapshot_hit_zones) ~= "table"
            or not deep_equal(live_hit_zones, snapshot_hit_zones) then
            return nil, "hit_zones_fingerprint_mismatch"
        end
        local breed_snapshot = rawget(marker, "breed_snapshot")
        if not table_graphs_disjoint(breed, breed_snapshot, MARKER_KEY)
            or not deep_equal_root_except(breed, breed_snapshot, MARKER_KEY) then
            return nil, "existing_breed_fingerprint_mismatch"
        end
        ok, reason = validate_candidate(
            spec, breed, source, "existing_breed_invalid")
        if not ok then return nil, reason end
        for i = 1, #STAT_NAMES do
            local stat_name = STAT_NAMES[i]
            if not deep_equal(rawget(rawget(stats_player, stat_name), name),
                    expected_stats[stat_name]) then
                return nil, "statistics_" .. stat_name .. "_mismatch"
            end
        end
        if rawget(alias_to, name) ~= source_name
            or alias_total ~= 1 or expected_aliases ~= 1 then
            return nil, "package_alias_mismatch"
        end
        local dismemberment_ref = rawget(marker, "dismemberment_ref")
        local dismemberment_snapshot = rawget(marker, "dismemberment_snapshot")
        if not rawequal(source_dismemberment, dismemberment_ref)
            or not rawequal(rawget(runtime.dismemberments, name), dismemberment_ref)
            or not table_graphs_disjoint(dismemberment_ref, dismemberment_snapshot)
            or not deep_equal(dismemberment_ref, dismemberment_snapshot) then
            return nil, "dismemberment_mismatch"
        end
        for i = 1, #RACE_NAMES do
            local race_name = RACE_NAMES[i]
            local expected = race_name == spec.race and true or nil
            if rawget(rawget(runtime.race_sets, race_name), name) ~= expected then
                return nil, "race_membership_mismatch"
            end
        end
        if rawget(runtime.elites, name) ~= expected_elite then
            return nil, "elite_membership_mismatch"
        end
        if performance and not valid_count(rawget(performance, name)) then
            return nil, "performance_mismatch"
        end
    else
        local clone_ok, clone_or_error = pcall(runtime.clone, source)
        if not clone_ok or type(clone_or_error) ~= "table"
            or rawequal(clone_or_error, source) then
            return nil, "breed_clone_failed"
        end
        breed = clone_or_error
        rawset(breed, "name", name)
        ok, reason = configure_candidate(spec, breed, source)
        if not ok then return nil, reason end
        if breed.name ~= name or breed.race ~= spec.race
            or type(rawget(breed, "hit_zones_lookup")) ~= "table" then
            return nil, "configured_breed_invalid"
        end
        expected_elite = rawget(breed, "elite") and true or nil
        local actions_ok, actions_or_error = pcall(runtime.clone, source_actions)
        if not actions_ok or type(actions_or_error) ~= "table"
            or not table_graphs_disjoint(actions_or_error, source_actions) then
            return nil, "actions_clone_failed"
        end
        actions = actions_or_error
        ok, reason = validate_candidate(
            spec, breed, source, "configured_breed_invalid")
        if not ok then return nil, reason end
        canonical_threat = rawget(breed, "threat_value")
        if not valid_number(canonical_threat) then return nil, "threat_value_invalid" end
        local breed_snapshot_ok, breed_snapshot = pcall(
            detached_copy_root_except, breed, MARKER_KEY)
        if not breed_snapshot_ok or type(breed_snapshot) ~= "table"
            or not table_graphs_disjoint(breed, breed_snapshot, MARKER_KEY) then
            return nil, "breed_snapshot_failed"
        end
        local actions_snapshot_ok, actions_snapshot = pcall(detached_copy, actions)
        if not actions_snapshot_ok or type(actions_snapshot) ~= "table"
            or not table_graphs_disjoint(actions, actions_snapshot) then
            return nil, "actions_snapshot_failed"
        end
        local _, source_overlay_rows, source_contract_reason =
            action_overlay_contract(actions_snapshot)
        if not source_overlay_rows then
            return nil, source_contract_reason or "actions_snapshot_failed"
        end
        local source_overlay_snapshot = build_source_overlay_snapshot(
            source_actions, source_overlay_rows)
        if not source_overlay_snapshot
            or not table_graphs_disjoint(
                source_overlay_snapshot, actions_snapshot)
            or not table_graphs_disjoint(source_overlay_snapshot, actions) then
            return nil, "actions_snapshot_failed"
        end
        local dismemberment_snapshot_ok, dismemberment_snapshot = pcall(
            detached_copy, source_dismemberment)
        if not dismemberment_snapshot_ok or type(dismemberment_snapshot) ~= "table"
            or not table_graphs_disjoint(
                source_dismemberment, dismemberment_snapshot) then
            return nil, "dismemberment_snapshot_failed"
        end
        rawset(breed, MARKER_KEY, {
            schema = SCHEMA, owner = spec.owner, fingerprint = spec.fingerprint,
            source_breed = source_name,
            breed_snapshot = breed_snapshot,
            actions_ref = actions, actions_snapshot = actions_snapshot,
            source_overlay_snapshot = source_overlay_snapshot,
            threat_value = canonical_threat, elite = expected_elite == true,
            breed_index = breed_wire.index,
            damage_source_index = damage_wire.index,
            statistics_path_index = statistics_wire.index,
            dismemberment_ref = source_dismemberment,
            dismemberment_snapshot = dismemberment_snapshot,
            hit_zones_ref = rawget(breed, "hit_zones_lookup"),
        })

        if rawget(runtime.actions, name) ~= nil then return nil, "actions_residue" end
        for i = 1, #STAT_NAMES do
            if rawget(rawget(stats_player, STAT_NAMES[i]), name) ~= nil then
                return nil, "statistics_" .. STAT_NAMES[i] .. "_residue"
            end
        end
        if rawget(alias_to, name) ~= nil or alias_total ~= 0 then
            return nil, "package_alias_residue"
        end
        if rawget(runtime.dismemberments, name) ~= nil then
            return nil, "dismemberment_residue"
        end
        for i = 1, #RACE_NAMES do
            if rawget(rawget(runtime.race_sets, RACE_NAMES[i]), name) ~= nil then
                return nil, "race_membership_residue"
            end
        end
        if rawget(runtime.elites, name) ~= nil then return nil, "elite_membership_residue" end
        if rawget(runtime.hit_zones, name) ~= nil then return nil, "hit_zones_residue" end
        if performance and rawget(performance, name) ~= nil then
            return nil, "performance_residue"
        end

        local write_ok, write_reason = add_write(
            plan, runtime.actions, name, actions, "actions")
        if not write_ok then return nil, write_reason end
        for i = 1, #STAT_NAMES do
            local stat_name = STAT_NAMES[i]
            write_ok, write_reason = add_write(
                plan, rawget(stats_player, stat_name), name,
                expected_stats[stat_name], "statistics_" .. stat_name)
            if not write_ok then return nil, write_reason end
        end
        if performance then
            write_ok, write_reason = add_write(plan, performance, name, 0, "performance")
            if not write_ok then return nil, write_reason end
        end
        write_ok, write_reason = add_write(
            plan, alias_to, name, source_name, "alias_forward")
        if not write_ok then return nil, write_reason end
        local alias_copy_ok, aliases_copy = pcall(
            copy_raw, source_aliases or {})
        if not alias_copy_ok then return nil, "source_aliases_copy_failed" end
        rawset(aliases_copy, source_alias_count + 1, name)
        write_ok, write_reason = add_write(
            plan, breed_to_aliases, source_name, aliases_copy, "alias_reverse")
        if not write_ok then return nil, write_reason end
        write_ok, write_reason = add_write(
            plan, runtime.dismemberments, name, source_dismemberment, "dismemberment")
        if not write_ok then return nil, write_reason end
        write_ok, write_reason = add_write(
            plan, rawget(runtime.race_sets, spec.race), name, true, "race")
        if not write_ok then return nil, write_reason end
        if expected_elite then
            write_ok, write_reason = add_write(
                plan, runtime.elites, name, true, "elite")
            if not write_ok then return nil, write_reason end
        end
        write_ok, write_reason = add_write(
            plan, runtime.hit_zones, name, breed.hit_zones_lookup, "hit_zones")
        if not write_ok then return nil, write_reason end
    end

    if breed_wire.inserted then
        local write_ok, write_reason = add_write(
            plan, breed_wire.real, breed_wire.index, name, "wire_breeds_forward")
        if not write_ok then return nil, write_reason end
        write_ok, write_reason = add_write(
            plan, breed_wire.real, name, breed_wire.index, "wire_breeds_reverse")
        if not write_ok then return nil, write_reason end
    end
    if damage_wire.inserted then
        local write_ok, write_reason = add_write(
            plan, damage_wire.real, damage_wire.index, name, "wire_damage_forward")
        if not write_ok then return nil, write_reason end
        write_ok, write_reason = add_write(
            plan, damage_wire.real, name, damage_wire.index, "wire_damage_reverse")
        if not write_ok then return nil, write_reason end
    end
    if statistics_wire.inserted then
        local write_ok, write_reason = add_write(plan, statistics_wire.real,
            statistics_wire.index, name, "wire_statistics_path_forward")
        if not write_ok then return nil, write_reason end
        write_ok, write_reason = add_write(plan, statistics_wire.real,
            name, statistics_wire.index, "wire_statistics_path_reverse")
        if not write_ok then return nil, write_reason end
    end

    ok, reason = validate_presentations(spec, existing_present, plan)
    if not ok then return nil, reason end

    local readiness = spec.readiness
    if readiness == nil then readiness = {} end
    local readiness_count, readiness_reason = dense_row_count(readiness, "readiness")
    if not readiness_count then return nil, readiness_reason end
    for i = 1, readiness_count do
        local row = readiness[i]
        if type(row) ~= "table" or type(rawget(row, "target")) ~= "table"
            or rawget(row, "key") == nil or rawget(row, "value") == nil then
            return nil, "readiness_" .. i .. "_invalid"
        end
        local target = rawget(row, "target")
        local key, value = rawget(row, "key"), rawget(row, "value")
        if existing_present and deep_equal(rawget(target, key), value) then
            -- Exact reload already owns this readiness row.
        else
            local write_ok, write_reason = add_write(plan, target, key, value,
                "readiness_" .. i)
            if not write_ok then return nil, write_reason end
        end
    end
    if not existing_present then
        local write_ok, write_reason = add_write(
            plan, runtime.breeds, name, breed, "breed_publish")
        if not write_ok then return nil, write_reason end
    end
    plan.breed = breed
    plan.existing = existing_present
    plan.threat_value = canonical_threat
    if not valid_number(plan.threat_value) then return nil, "threat_value_invalid" end
    return plan
end

local function rollback(writes, applied)
    for i = applied, 1, -1 do
        local write = writes[i]
        if write.had_value then rawset(write.target, write.key, write.old_value)
        else rawset(write.target, write.key, nil) end
    end
end

local function commit(plan)
    local spec, runtime = plan.spec, plan.runtime
    local setter = rawget(runtime.conflict_director, "set_threat_value")
    local threat_ok = pcall(setter, nil, spec.name, plan.threat_value)
    if not threat_ok then
        TERMINAL[spec.name] = "threat_state_indeterminate"
        return nil, "threat_state_indeterminate"
    end

    local applied = 0
    for i = 1, #plan.writes do
        local write = plan.writes[i]
        write.old_value = rawget(write.target, write.key)
        write.had_value = write.old_value ~= nil
        local write_ok = pcall(runtime.raw_set, write.target, write.key, write.value)
        if not write_ok
            or not rawequal(rawget(write.target, write.key), write.value) then
            -- The injected setter may have written before throwing, so include
            -- this position in the exact structural rollback.
            applied = i
            rollback(plan.writes, applied)
            TERMINAL[spec.name] = "commit_failed_after_threat"
            return nil, "commit_failed_after_threat:" .. write.label
        end
        applied = i
    end
    return true, plan.existing and "revalidated" or "registered", plan.breed
end

local function runtime_for(injected_runtime)
    local runtime = injected_runtime or default_runtime()
    if not injected_runtime then runtime.lookup_lib = M.lookup_lib end
    return runtime
end

local function remember_spec(spec)
    local name = rawget(spec, "name")
    local prior = DECLARED[name]
    if prior and prior ~= spec then return nil, "duplicate_declaration" end
    if not prior then
        DECLARED[name] = spec
        DECLARATION_ORDER[#DECLARATION_ORDER + 1] = name
    end
    return true
end

function M.register(spec, injected_runtime)
    local valid, valid_reason = validate_spec(spec)
    if not valid then return nil, valid_reason end
    local remembered, remember_reason = remember_spec(spec)
    if not remembered then return nil, remember_reason end
    local runtime = runtime_for(injected_runtime)
    if type(runtime) ~= "table" then return nil, "runtime_invalid" end
    local plan, reason = build_plan(spec, runtime)
    if not plan then return nil, reason end
    return commit(plan)
end

function M.validate_registered(spec, injected_runtime)
    local runtime = runtime_for(injected_runtime)
    if type(runtime) ~= "table" then return nil, "runtime_invalid" end
    if type(spec) ~= "table" or type(runtime.breeds) ~= "table"
        or rawget(runtime.breeds, spec.name) == nil then
        return nil, "breed_unpublished"
    end
    local plan, reason = build_plan(spec, runtime)
    if not plan then return nil, reason end
    if not plan.existing then return nil, "breed_unpublished" end
    if #plan.writes > 0 then
        return nil, "registered_state_incomplete:" .. plan.writes[1].label
    end
    return true
end

function M.validate_all_registered(injected_runtime)
    if #DECLARATION_ORDER == 0 then return nil, "no_declared_breeds" end
    for i = 1, #DECLARATION_ORDER do
        local name = DECLARATION_ORDER[i]
        local ok, reason = M.validate_registered(DECLARED[name], injected_runtime)
        if not ok then return nil, name .. ":" .. tostring(reason) end
    end
    return true
end

function M._reset_terminal_for_tests(name)
    TERMINAL[name] = nil
end

M.marker_key = MARKER_KEY
M.schema = SCHEMA

return M
