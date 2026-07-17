-- Pure fail-closed policy for General Tweaker's bot utility seams.
--
-- Vanilla seeds ally_distance to math.huge in AISystem.set_default_blackboard_values
-- and PlayerBotBase._select_ally_by_utility returns math.huge when it has no ally.
-- Keep that sentinel contract at GT's producer boundary, and validate every
-- non-condition consideration before Utility.get_action_utility performs numeric
-- arithmetic. This module stays engine-free so the crash boundary is testable
-- without launching Vermintide 2.
local Policy = {}

function Policy.normalize_ally_distance(distance)
    if type(distance) == "number" then
        return distance
    end

    return math.huge
end

local function consideration_value(action_data, blackboard, input)
    -- Match vanilla Utility.get_action_utility exactly: an action-local truthy
    -- value wins; otherwise the root blackboard value is used.
    return action_data[input] or blackboard[input]
end

function Policy.prepare_utility_inputs(breed_action, action_name, blackboard, player_follow_considerations)
    if type(breed_action) ~= "table" then
        return false, "breed_action"
    end
    if type(blackboard) ~= "table" then
        return false, "blackboard"
    end

    local utility_actions = blackboard.utility_actions
    local action_data = type(utility_actions) == "table" and utility_actions[action_name]
    if type(action_data) ~= "table" then
        return false, "utility_actions." .. tostring(action_name)
    end

    local considerations = breed_action.considerations
    if type(considerations) ~= "table" then
        return false, "considerations"
    end

    local repaired_ally_distance = false
    for name, consideration in pairs(considerations) do
        if type(consideration) ~= "table" then
            return false, "consideration." .. tostring(name)
        end

        local input = consideration.blackboard_input
        if type(input) ~= "string" then
            return false, "blackboard_input." .. tostring(name)
        end

        if not consideration.is_condition then
            local value = consideration_value(action_data, blackboard, input)

            -- Exact source-backed repair: this is the sentinel vanilla installs
            -- for player_bot_default_follow before any bot tick. Do not invent a
            -- generic infinity fallback for other utility inputs.
            if type(value) ~= "number"
                    and input == "ally_distance"
                    and considerations == player_follow_considerations then
                blackboard.ally_distance = math.huge
                value = math.huge
                repaired_ally_distance = true
            end

            if type(value) ~= "number" then
                return false, "numeric_input." .. input
            end
            if type(consideration.max_value) ~= "number" then
                return false, "max_value." .. tostring(name)
            end
            if consideration.min_value ~= nil and type(consideration.min_value) ~= "number" then
                return false, "min_value." .. tostring(name)
            end
            if type(consideration.spline) ~= "table" then
                return false, "spline." .. tostring(name)
            end
        end
    end

    if type(breed_action.action_weight) ~= "number" then
        return false, "action_weight"
    end

    return true, repaired_ally_distance and "ally_distance" or nil
end

return Policy
