local M = {}

M.CONFIG_GETTERS = {
    "get_run_id",
    "get_run_seed",
    "get_run_difficulty",
    "get_journey_name",
    "get_dominant_god",
    "get_event_boons",
    "get_event_mutators",
}

M.PROGRESS_GETTERS = {
    "get_current_node_key",
    "get_completed_level_count",
    "get_traversed_nodes",
    "get_arena_belakor_node",
}

local function count_callable(object, names)
    local count = 0
    for _, name in ipairs(names) do
        if object and type(object[name]) == "function" then
            count = count + 1
        end
    end
    return count
end

local function count_readable(object, names)
    local count = 0
    for _, name in ipairs(names) do
        local fn = object and object[name]
        if type(fn) == "function" then
            local ok, value = pcall(fn, object)
            if ok and value ~= nil then count = count + 1 end
        end
    end
    return count
end

-- #141 audit repair (2026-08-03): the audit printf reported only COUNTS, but
-- the issue card asks WHICH getters are missing. These pure helpers name them;
-- the join is bounded so the log line cannot grow unbounded.
M.MISSING_NAME_CAP = 6

function M.missing(object, names)
    local out = {}
    for _, name in ipairs(names) do
        if not (object and type(object[name]) == "function") then
            out[#out + 1] = name
        end
    end
    return out
end

function M.joined_missing(object, names)
    local missing = M.missing(object, names)
    if #missing == 0 then return "none" end
    local shown = {}
    for i = 1, math.min(#missing, M.MISSING_NAME_CAP) do shown[i] = missing[i] end
    local joined = table.concat(shown, ",")
    if #missing > M.MISSING_NAME_CAP then
        joined = joined .. string.format("+%d more", #missing - M.MISSING_NAME_CAP)
    end
    return joined
end

function M.inspect(controller)
    local state = controller and controller._run_state
    local shared = state and state._shared_state
    return {
        controller = controller ~= nil,
        run_state = state ~= nil,
        server = state and type(state.is_server) == "function" and state:is_server() == true or false,
        config_methods = count_callable(controller, M.CONFIG_GETTERS),
        config_values = count_readable(controller, M.CONFIG_GETTERS),
        progress_methods = count_callable(state, M.PROGRESS_GETTERS),
        progress_values = count_readable(state, M.PROGRESS_GETTERS),
        shared_state = shared ~= nil,
        full_sync = shared and type(shared.full_sync) == "function" or false,
        player_power_ups = state and type(state.get_player_power_ups) == "function" or false,
        player_currency = state and type(state.get_player_soft_currency) == "function" or false,
        player_loadout = state and type(state.get_player_loadout) == "function" or false,
        set_power_ups = state and type(state.set_player_power_ups) == "function" or false,
        set_currency = state and type(state.set_player_soft_currency) == "function" or false,
        set_loadout = state and type(state.set_player_loadout) == "function" or false,
    }
end

return M
