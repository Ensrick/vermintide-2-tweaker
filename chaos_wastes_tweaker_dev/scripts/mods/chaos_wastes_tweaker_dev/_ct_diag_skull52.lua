-- #52 Tower of Treachery gargoyle-skull object-set census.
--
-- Observation-only.  Tower skulls are not the Drachenfels/portals
-- `gargoyle_head` pickup path; the source-backed Tower evidence is the level
-- flow callback `flow_callback_on_tower_skull_found` and achievement event
-- `on_tower_skull_found`.  The units live in the level binary, so the safe
-- next step is a bounded Adventure-vs-Deus object-set diff, not a guessed
-- respawn.
local mod = get_mod("ct_dev")
local M = {}

local TARGET_LEVEL = "dlc_wizards_tower"
local CENSUS_RECORD_CAP_TOTAL = 320
local CENSUS_RECORD_CAP_PER_SESSION = 160
local LIFECYCLE_RECORD_CAP_TOTAL = 256
local LIFECYCLE_RECORD_CAP_PER_SESSION = 128
local SAMPLE_CAP_PER_SET = 4
local IDENTITY_CAP_PER_PHASE = 32
local FLOW_SET_CAP_PER_SESSION = 32
local FLOW_CALLBACK_CAP_PER_SESSION = 12
local records = 0
local seen = {}
local lifecycle_records = 0
local lifecycle_seen = {}
local active
local hooks_installed = false

local function emit(key, fmt, ...)
    local state = active
    if records >= CENSUS_RECORD_CAP_TOTAL
        or (state and state.census_records >= CENSUS_RECORD_CAP_PER_SESSION)
        or seen[key]
    then
        return false
    end
    seen[key] = true
    records = records + 1
    if state then state.census_records = state.census_records + 1 end
    local ok, line = pcall(string.format, fmt, ...)
    if not ok then line = "format-error:" .. tostring(fmt) end
    local engine_printf = rawget(_G, "printf")
    if type(engine_printf) == "function" then
        pcall(engine_printf, "[ct:skull52] %s", line)
    end
    return true
end

local function emit_lifecycle(key, fmt, ...)
    local state = active
    if lifecycle_records >= LIFECYCLE_RECORD_CAP_TOTAL
        or (state and state.lifecycle_records >= LIFECYCLE_RECORD_CAP_PER_SESSION)
        or lifecycle_seen[key]
    then
        return false
    end
    lifecycle_seen[key] = true
    lifecycle_records = lifecycle_records + 1
    if state then state.lifecycle_records = state.lifecycle_records + 1 end
    local ok, line = pcall(string.format, fmt, ...)
    if not ok then line = "format-error:" .. tostring(fmt) end
    local engine_printf = rawget(_G, "printf")
    if type(engine_printf) == "function" then
        pcall(engine_printf, "[ct:skull52] %s", line)
    end
    return true
end

local function current_level_key()
    local lth = Managers and Managers.level_transition_handler
    local key = lth and lth.get_current_level_keys and lth:get_current_level_keys()
    if type(key) ~= "string" and lth and lth.get_current_level_key then
        key = lth:get_current_level_key()
    end
    return type(key) == "string" and key or "unknown"
end

local function safe_call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    return ok and value or nil
end

local function compact_unit_data(v, depth, budget, visited)
    if type(v) ~= "table" then return tostring(v) end
    if depth <= 0 then return "<table>" end
    if visited[v] then return "<cycle>" end
    visited[v] = true
    local keys = {}
    for k in pairs(v) do
        local kt = type(k)
        if kt == "string" or kt == "number" then keys[#keys + 1] = k end
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local out = {}
    for _, k in ipairs(keys) do
        if budget.n <= 0 then out[#out + 1] = "..." break end
        budget.n = budget.n - 1
        out[#out + 1] = tostring(k) .. "=" .. compact_unit_data(v[k], depth - 1, budget, visited)
    end
    visited[v] = nil
    return "{" .. table.concat(out, ",") .. "}"
end

local function units_count(entry)
    local units = type(entry) == "table" and entry.units
    return type(units) == "table" and #units or 0
end

local function suspicion(set_name, entry)
    local s = tostring(set_name):lower()
    local score = 0
    for _, needle in ipairs({
        "tower", "skull", "gargoyle", "illusion", "objective", "interact", "pickup",
        "flow", "challenge", "event",
    }) do
        if s:find(needle, 1, true) then score = score + 1 end
    end
    if type(entry) == "table" and entry.type == "flow" then score = score + 1 end
    return score
end

local function unit_sets_text(state, info)
    local names = {}
    for set_name in pairs(info.sets) do
        local set = state.sets[set_name] or {}
        names[#names + 1] = string.format("%s(raw=%s,final=%s,flow=%s)", set_name,
            tostring(set.requested), tostring(set.expected), tostring(set.flow_set_enabled))
    end
    table.sort(names)
    return table.concat(names, ",")
end

local function remember_lifecycle(key, base, level_name, game_mode_key, object_sets, spawned_lookup)
    local session = table.concat({ tostring(key), tostring(level_name), tostring(game_mode_key) }, "|")
    local state = {
        base = base,
        game_mode_key = game_mode_key,
        key = key,
        level_name = level_name,
        session = session,
        sets = {},
        units = {},
        census_records = 0,
        flow_callbacks = 0,
        flow_set_records = 0,
        lifecycle_records = 0,
    }

    for set_name, entry in pairs(object_sets) do
        local requested = spawned_lookup[set_name] == true
        state.sets[set_name] = {
            expected = requested,
            kind = type(entry) == "table" and entry.type or "",
            requested = requested,
        }
        local indices = type(entry) == "table" and entry.units
        if type(indices) == "table" then
            for _, index in ipairs(indices) do
                local info = state.units[index]
                if not info then
                    info = { expected = false, sets = {} }
                    state.units[index] = info
                end
                info.sets[set_name] = true
                info.expected = info.expected or requested
            end
        end
    end

    active = state
    return state
end

local function runtime_identity(unit)
    if not unit then return false, "", "", "", "" end
    local alive = safe_call(Unit and Unit.alive, unit) == true
    if not alive then return false, "", "", "", "" end
    local debug_name = safe_call(Unit and Unit.debug_name, unit) or ""
    local interaction_type = safe_call(Unit and Unit.get_data, unit, "interaction_data", "interaction_type") or ""
    local hud_description = safe_call(Unit and Unit.get_data, unit, "interaction_data", "hud_description") or ""
    local hud_action = safe_call(Unit and Unit.get_data, unit, "interaction_data", "hud_interaction_action") or ""
    local interactable = safe_call(ScriptUnit and ScriptUnit.has_extension, unit, "interactable_system") ~= nil
    return true, tostring(debug_name), tostring(interaction_type), tostring(hud_description),
        tostring(hud_action), interactable
end

local function target_context(level_name, injected_base_from_key)
    local key = current_level_key()
    local base = injected_base_from_key and injected_base_from_key(key) or nil
    local tower = key == TARGET_LEVEL or base == TARGET_LEVEL
    if not tower then return nil, base end

    -- get_object_sets is also called for hero sublevels while the Tower key is
    -- current. When the live LevelSettings row is available, accept only the
    -- main level resource so a sublevel cannot replace the lifecycle snapshot.
    local settings = rawget(_G, "LevelSettings")
    local entry = settings and rawget(settings, key)
    if entry and type(entry.level_name) == "string" and entry.level_name ~= level_name then
        return nil, base
    end
    return key, base
end

-- Runtime half of the probe. GameModeHelper only says which object sets were
-- requested. This snapshot runs after StateIngame has activated the world and
-- registered its units, then immediately before level teardown. The pair
-- separates selection from realization and from later loss without changing
-- any unit, extension, object-set reference, or flow state.
function M.level_snapshot(state_ingame, phase)
    local state = active
    if not state then return false end

    local runtime_key = current_level_key()
    if runtime_key ~= state.key and runtime_key ~= state.base then
        emit_lifecycle("transition|" .. state.session .. "|" .. tostring(phase) .. "|" .. tostring(runtime_key),
            "lifecycle phase=%s transition_mismatch selected_key=%s base=%s runtime_key=%s",
            tostring(phase), tostring(state.key), tostring(state.base), tostring(runtime_key))
        active = nil
        return false
    end

    local level = state_ingame and state_ingame.level
    if not level then
        emit_lifecycle("no-level|" .. state.session .. "|" .. tostring(phase),
            "lifecycle phase=%s key=%s level_missing=true", tostring(phase), tostring(state.key))
        return false
    end

    local expected_total, live_total, missing_total, disappeared_total = 0, 0, 0, 0
    local interactable_total = 0
    local candidates = {}
    for index, info in pairs(state.units) do
        if info.expected then
            expected_total = expected_total + 1
            local unit = safe_call(Level and Level.unit_by_index, level, index)
            local alive, debug_name, interaction_type, hud_description, hud_action, interactable = runtime_identity(unit)
            if alive then
                live_total = live_total + 1
            else
                missing_total = missing_total + 1
            end
            if phase == "post_create" then
                info.post_create_alive = alive
                if alive then
                    info.post_create_identity = {
                        debug_name = debug_name,
                        hud_action = hud_action,
                        hud_description = hud_description,
                        interactable = interactable,
                        interaction_type = interaction_type,
                    }
                end
            elseif info.post_create_alive and not alive then
                disappeared_total = disappeared_total + 1
            end

            if interactable then interactable_total = interactable_total + 1 end
            local text = table.concat({ debug_name, interaction_type, hud_description, hud_action }, " "):lower()
            local strong = text:find("skull", 1, true) or text:find("tower", 1, true)
            local identity = info.post_create_identity
            if not alive and identity then
                debug_name = identity.debug_name
                interaction_type = identity.interaction_type
                hud_description = identity.hud_description
                hud_action = identity.hud_action
                interactable = identity.interactable
                text = table.concat({ debug_name, interaction_type, hud_description, hud_action }, " "):lower()
                strong = text:find("skull", 1, true) or text:find("tower", 1, true)
            end
            if strong or interactable then
                candidates[#candidates + 1] = {
                    debug_name = debug_name,
                    hud_action = hud_action,
                    hud_description = hud_description,
                    index = index,
                    interactable = interactable,
                    interaction_type = interaction_type,
                    live = alive,
                    source = alive and "live" or "post_create",
                    strong = strong and true or false,
                    sets = unit_sets_text(state, info),
                }
            end
        end
    end

    table.sort(candidates, function(a, b)
        if a.strong ~= b.strong then return a.strong end
        local an, bn = tonumber(a.index), tonumber(b.index)
        if an and bn and an ~= bn then return an < bn end
        return tostring(a.index) < tostring(b.index)
    end)
    local identities = math.min(#candidates, IDENTITY_CAP_PER_PHASE)
    for i = 1, identities do
        local candidate = candidates[i]
        emit_lifecycle("identity|" .. state.session .. "|" .. tostring(phase) .. "|" .. tostring(candidate.index),
            "lifecycle phase=%s index=%s live=%s identity_source=%s strong=%s sets=%s debug=%s interactable=%s interaction_type=%s hud=%s action=%s",
            tostring(phase), tostring(candidate.index), tostring(candidate.live), tostring(candidate.source),
            tostring(candidate.strong), candidate.sets, tostring(candidate.debug_name),
            tostring(candidate.interactable), tostring(candidate.interaction_type),
            tostring(candidate.hud_description), tostring(candidate.hud_action))
    end

    emit_lifecycle("summary|" .. state.session .. "|" .. tostring(phase),
        "lifecycle phase=%s key=%s mode=%s expected=%d live=%d missing=%d disappeared_since_create=%d interactables=%d identity_candidates=%d identities_emitted=%d identity_cap=%d flow_callbacks=%d",
        tostring(phase), tostring(state.key), tostring(state.game_mode_key), expected_total, live_total,
        missing_total, disappeared_total, interactable_total, #candidates, identities,
        IDENTITY_CAP_PER_PHASE, state.flow_callbacks)
    return true
end

function M.flow_set_changed(set_name, enable, set)
    local state = active
    if not state or not state.sets[set_name] then return false end
    local final = type(set) == "table" and set.flow_set_enabled or nil
    state.sets[set_name].flow_set_enabled = final
    if state.flow_set_records >= FLOW_SET_CAP_PER_SESSION then return false end
    local emitted = emit_lifecycle("flow-set|" .. state.session .. "|" .. tostring(set_name) .. "|" .. tostring(enable),
        "lifecycle phase=flow_set key=%s mode=%s set=%s requested=%s final=%s units=%d",
        tostring(state.key), tostring(state.game_mode_key), tostring(set_name), tostring(enable),
        tostring(final),
        type(set) == "table" and type(set.units) == "table" and #set.units or 0)
    if emitted then state.flow_set_records = state.flow_set_records + 1 end
    return emitted
end

local function sample_units(level_name, set_name, entry)
    if not (LevelResource and type(entry) == "table" and type(entry.units) == "table") then
        return
    end
    for i = 1, math.min(#entry.units, SAMPLE_CAP_PER_SET) do
        local index = entry.units[i]
        local ok, data = pcall(LevelResource.unit_data, level_name, index)
        local text = ok and compact_unit_data(data, 2, { n = 18 }, {}) or "<unit_data_failed>"
        emit("unit|" .. tostring(level_name) .. "|" .. tostring(set_name) .. "|" .. tostring(index),
            "unit_sample level_name=%s set=%s index=%s data=%s",
            tostring(level_name), tostring(set_name), tostring(index), text)
    end
end

function M.census(level_name, game_mode_key, object_sets, spawned_object_sets, injected_base_from_key)
    if type(object_sets) ~= "table" or type(spawned_object_sets) ~= "table" then return false end
    local key, base = target_context(level_name, injected_base_from_key)
    if not key then
        local runtime_key = current_level_key()
        if active and runtime_key ~= active.key then
            emit_lifecycle("transition-away|" .. active.session .. "|" .. tostring(runtime_key),
                "lifecycle phase=selection_transition from_key=%s from_mode=%s to_key=%s",
                tostring(active.key), tostring(active.game_mode_key), tostring(runtime_key))
            active = nil
        end
        return false
    end
    if not rawget(_G, "_ct_skull52_flow_wrapped") then M.install() end

    local spawned_lookup = {}
    for _, s in ipairs(spawned_object_sets) do spawned_lookup[s] = true end
    remember_lifecycle(key, base, level_name, game_mode_key, object_sets, spawned_lookup)

    local names = {}
    for set_name in pairs(object_sets) do names[#names + 1] = set_name end
    table.sort(names)

    emit("header|" .. tostring(key) .. "|" .. tostring(level_name) .. "|" .. tostring(game_mode_key),
        "mode=%s key=%s base=%s level_name=%s object_sets=%d spawned=%d cap=%d source=GameModeHelper.get_object_sets evidence=flow_callback_on_tower_skull_found",
        tostring(game_mode_key), tostring(key), tostring(base), tostring(level_name),
        #names, #spawned_object_sets, CENSUS_RECORD_CAP_PER_SESSION)

    for _, set_name in ipairs(names) do
        local entry = object_sets[set_name]
        local score = suspicion(set_name, entry)
        local n = units_count(entry)
        emit("set|" .. tostring(key) .. "|" .. tostring(level_name) .. "|" .. tostring(game_mode_key) .. "|" .. tostring(set_name),
            "mode=%s set=%s spawned=%s units=%d kind=%s suspect=%d",
            tostring(game_mode_key), tostring(set_name), tostring(spawned_lookup[set_name] == true),
            n, tostring(type(entry) == "table" and entry.type or ""), score)
        if score > 0 or (n > 0 and spawned_lookup[set_name] ~= true) then
            sample_units(level_name, set_name, entry)
        end
    end
    return true
end

-- This is the entry-hook surface: both normal Adventure and injected Deus call
-- it, while the target_context gate keeps every unrelated level inert.
function M.observe_object_sets(level_name, game_mode_key, object_sets, spawned_object_sets, injected_base_from_key)
    return M.census(level_name, game_mode_key, object_sets, spawned_object_sets, injected_base_from_key)
end

-- The entry hook calls this after the existing #156 mutation. The census keeps
-- the raw game-mode decision, while lifecycle snapshots follow the array that
-- AsyncLevelSpawner actually receives.
function M.finalize_selection(spawned_object_sets)
    local state = active
    if not state or type(spawned_object_sets) ~= "table" then return false end
    local final = {}
    for _, set_name in ipairs(spawned_object_sets) do final[set_name] = true end

    local raw_total, final_total, changed = 0, 0, 0
    for set_name, set in pairs(state.sets) do
        if set.requested then raw_total = raw_total + 1 end
        set.expected = final[set_name] == true
        if set.expected then final_total = final_total + 1 end
        if set.expected ~= set.requested then changed = changed + 1 end
    end
    for _, info in pairs(state.units) do
        info.expected = false
        for set_name in pairs(info.sets) do
            local set = state.sets[set_name]
            info.expected = info.expected or (set and set.expected == true)
        end
    end

    emit_lifecycle("selection-final|" .. state.session,
        "lifecycle phase=selection_final key=%s mode=%s raw_selected=%d final_selected=%d changed=%d",
        tostring(state.key), tostring(state.game_mode_key), raw_total, final_total, changed)
    return true
end

local function record_flow_callback(params)
    local state = active
    if not state or state.flow_callbacks >= FLOW_CALLBACK_CAP_PER_SESSION then return false end
    state.flow_callbacks = state.flow_callbacks + 1
    return emit_lifecycle("flow|" .. state.session .. "|" .. tostring(state.flow_callbacks),
        "flow_callback_on_tower_skull_found fired key=%s mode=%s ordinal=%d cap=%d params=%s",
        tostring(current_level_key()), tostring(state.game_mode_key), state.flow_callbacks,
        FLOW_CALLBACK_CAP_PER_SESSION, compact_unit_data(params, 2, { n = 12 }, {}))
end

function M.install()
    local original = rawget(_G, "flow_callback_on_tower_skull_found")
    if type(original) == "function" and not rawget(_G, "_ct_skull52_flow_wrapped") then
        rawset(_G, "_ct_skull52_flow_wrapped", true)
        rawset(_G, "flow_callback_on_tower_skull_found", function(params, ...)
            -- A malformed diagnostic payload must not suppress the vanilla
            -- achievement callback or alter its arguments/returns.
            pcall(record_flow_callback, params)
            return original(params, ...)
        end)
    else
        emit_lifecycle("flow-wrap|" .. tostring(type(original)),
            "flow_callback_on_tower_skull_found wrap=%s type=%s",
            tostring(type(original) == "function"), tostring(type(original)))
    end

    if not hooks_installed and mod and mod.hook_safe and mod.hook then
        hooks_installed = true
        mod:hook_safe("StateIngame", "_create_level", function(self)
            M.level_snapshot(self, "post_create")
        end)
        mod:hook("StateIngame", "_teardown_level", function(func, self, ...)
            -- Observation must never block the vanilla destroy boundary. Clear
            -- state even when the diagnostic itself raises, then delegate once.
            local ok, err = pcall(M.level_snapshot, self, "pre_teardown")
            if not ok then
                pcall(emit_lifecycle, "teardown-error",
                    "lifecycle phase=pre_teardown diagnostic_error=%s", tostring(err))
            end
            active = nil
            return func(self, ...)
        end)
        mod:hook_safe("GameModeManager", "_set_flow_object_set_enabled", function(self, set, enable, set_name)
            M.flow_set_changed(set_name, enable, set)
        end)
    end
end

function M.regression()
    if CENSUS_RECORD_CAP_TOTAL ~= 320 or CENSUS_RECORD_CAP_PER_SESSION ~= 160 then
        return "#52 diagnostic record caps drifted"
    end
    if LIFECYCLE_RECORD_CAP_TOTAL ~= 256 or LIFECYCLE_RECORD_CAP_PER_SESSION ~= 128 then
        return "#52 lifecycle record caps drifted"
    end
    if SAMPLE_CAP_PER_SET ~= 4 then return "#52 unit sample cap drifted" end
    if IDENTITY_CAP_PER_PHASE ~= 32 then return "#52 identity cap drifted" end
    if FLOW_SET_CAP_PER_SESSION ~= 32 then return "#52 flow-set cap drifted" end
    if FLOW_CALLBACK_CAP_PER_SESSION ~= 12 then return "#52 flow callback cap drifted" end
    if TARGET_LEVEL ~= "dlc_wizards_tower" then return "#52 target level drifted" end
    if type(M.census) ~= "function" or type(M.observe_object_sets) ~= "function"
        or type(M.finalize_selection) ~= "function"
        or type(M.install) ~= "function"
    then
        return "#52 diagnostic lifecycle missing"
    end
end

return M
