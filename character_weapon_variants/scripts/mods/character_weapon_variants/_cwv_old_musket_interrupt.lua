-- Issue #412: make the Old Musket stance action reachable from every running
-- weapon sub-action. This pure template mutator is shared by runtime and tests.

local M = {}

local function _is_toggle(entry, action_name)
    return type(entry) == "table"
        and entry.action == action_name
        and entry.input == action_name
        and entry.sub_action == "default"
end

local function _canonicalize(entry)
    entry.start_time = 0
    entry.clear_buffer = true
    entry.end_time = nil
    entry.clear_input = nil -- not an engine-consumed chain field
end

function M.install(template, action_name)
    action_name = action_name or "action_three"
    local actions = template and template.actions
    if type(actions) ~= "table" then return 0 end

    local installed = 0
    for current_action, sub_actions in pairs(actions) do
        if current_action ~= action_name and type(sub_actions) == "table" then
            for _, sub_action in pairs(sub_actions) do
                if type(sub_action) == "table" and type(sub_action.kind) == "string" then
                    local chains = sub_action.allowed_chain_actions
                    if type(chains) ~= "table" then
                        chains = {}
                        sub_action.allowed_chain_actions = chains
                    end

                    local found = nil
                    for index = #chains, 1, -1 do
                        if _is_toggle(chains[index], action_name) then
                            if found then
                                table.remove(chains, index)
                            else
                                found = chains[index]
                            end
                        end
                    end
                    if not found then
                        found = {
                            action = action_name,
                            input = action_name,
                            sub_action = "default",
                        }
                        chains[#chains + 1] = found
                    end
                    _canonicalize(found)
                    installed = installed + 1
                end
            end
        end
    end
    return installed
end

function M.audit(template, action_name)
    action_name = action_name or "action_three"
    local actions = template and template.actions
    if type(actions) ~= "table" then return false, "actions missing" end

    local covered = 0
    for current_action, sub_actions in pairs(actions) do
        if current_action ~= action_name and type(sub_actions) == "table" then
            for sub_name, sub_action in pairs(sub_actions) do
                if type(sub_action) == "table" and type(sub_action.kind) == "string" then
                    local matches = 0
                    for _, entry in ipairs(sub_action.allowed_chain_actions or {}) do
                        if _is_toggle(entry, action_name) then
                            matches = matches + 1
                            if entry.start_time ~= 0 or entry.clear_buffer ~= true then
                                return false, current_action .. "." .. tostring(sub_name) .. " is not immediate"
                            end
                        end
                    end
                    if matches ~= 1 then
                        return false, current_action .. "." .. tostring(sub_name) .. " toggle count=" .. matches
                    end
                    covered = covered + 1
                end
            end
        end
    end
    if covered == 0 then return false, "no weapon sub-actions" end
    return true, covered
end

return M
