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
local RECORD_CAP = 160
local SAMPLE_CAP_PER_SET = 4
local records = 0
local seen = {}

local function emit(key, fmt, ...)
    if records >= RECORD_CAP or seen[key] then return false end
    seen[key] = true
    records = records + 1
    local ok, line = pcall(string.format, fmt, ...)
    if not ok then line = "format-error:" .. tostring(fmt) end
    if printf then
        printf("[ct:skull52] %s", line)
    else
        mod:info("[ct:skull52] %s", line)
    end
    return true
end

local function current_level_key()
    local lth = Managers and Managers.level_transition_handler
    local key = lth and lth.get_current_level_keys and lth:get_current_level_keys()
    return type(key) == "string" and key or "unknown"
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
    if type(object_sets) ~= "table" or type(spawned_object_sets) ~= "table" then return end
    local key = current_level_key()
    local base = injected_base_from_key and injected_base_from_key(key) or nil
    local tower = key == TARGET_LEVEL or base == TARGET_LEVEL
    if not tower then return end
    if not rawget(_G, "_ct_skull52_flow_wrapped") then M.install() end

    local spawned_lookup = {}
    for _, s in ipairs(spawned_object_sets) do spawned_lookup[s] = true end

    local names = {}
    for set_name in pairs(object_sets) do names[#names + 1] = set_name end
    table.sort(names)

    emit("header|" .. tostring(key) .. "|" .. tostring(level_name) .. "|" .. tostring(game_mode_key),
        "mode=%s key=%s base=%s level_name=%s object_sets=%d spawned=%d cap=%d source=GameModeHelper.get_object_sets evidence=flow_callback_on_tower_skull_found",
        tostring(game_mode_key), tostring(key), tostring(base), tostring(level_name),
        #names, #spawned_object_sets, RECORD_CAP)

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
end

function M.install()
    local original = rawget(_G, "flow_callback_on_tower_skull_found")
    if type(original) == "function" and not rawget(_G, "_ct_skull52_flow_wrapped") then
        rawset(_G, "_ct_skull52_flow_wrapped", true)
        rawset(_G, "flow_callback_on_tower_skull_found", function(params)
            emit("flow|" .. tostring(current_level_key()),
                "flow_callback_on_tower_skull_found fired key=%s params=%s",
                tostring(current_level_key()), compact_unit_data(params, 2, { n = 12 }, {}))
            return original(params)
        end)
    else
        emit("flow-wrap|" .. tostring(type(original)),
            "flow_callback_on_tower_skull_found wrap=%s type=%s",
            tostring(type(original) == "function"), tostring(type(original)))
    end
end

function M.regression()
    if RECORD_CAP ~= 160 then return "#52 diagnostic record cap drifted" end
    if SAMPLE_CAP_PER_SET ~= 4 then return "#52 unit sample cap drifted" end
    if TARGET_LEVEL ~= "dlc_wizards_tower" then return "#52 target level drifted" end
    if type(M.census) ~= "function" or type(M.install) ~= "function" then
        return "#52 diagnostic lifecycle missing"
    end
end

return M
