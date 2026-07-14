-- Pure policy for Mod Tweaker integrations whose VMF mod is installed but disabled.
-- Keeps presence/layout decisions and subtree removal engine-free for Lua 5.1 tests.
local M = {
    REASON = "Disabled in VMF",
}

local function field(node, key)
    if type(node) ~= "table" then return nil end
    local value = node[key]
    if value == nil and type(node.content) == "table" then value = node.content[key] end
    return value
end

function M.select_members(categories, roles)
    local members = {}
    for _, category in ipairs(categories or {}) do
        local role = roles and roles[category.mod_id]
        local current = role and members[role]
        -- Presence, not enablement, determines layout. For aliases such as cim/cim_dev,
        -- prefer an enabled instance over an already-selected disabled one.
        if role and (not current or (current.enabled == false and category.enabled ~= false)) then
            members[role] = category
        end
    end
    local count = 0
    for _ in pairs(members) do count = count + 1 end
    return members, count
end

function M.disabled_header(setting_id, title, depth, reason)
    return {
        setting_id = setting_id,
        type = "group",
        title = title,
        depth = depth,
        disabled = true,
        tooltip = reason or M.REASON,
    }
end

function M.disable_group_subtree(widgets, setting_id, reason)
    if type(widgets) ~= "table" then return widgets, false end
    local out, found, skip_depth = {}, false, nil
    for _, node in ipairs(widgets) do
        local depth = field(node, "depth") or 0
        if skip_depth ~= nil and depth <= skip_depth then skip_depth = nil end
        if skip_depth == nil then
            if field(node, "setting_id") == setting_id then
                local copy = {}
                for key, value in pairs(node) do copy[key] = value end
                copy.disabled = true
                copy.tooltip = reason or M.REASON
                out[#out + 1] = copy
                found = true
                skip_depth = depth
            else
                out[#out + 1] = node
            end
        end
    end
    return out, found
end

return M
