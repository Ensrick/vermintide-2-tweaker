-- Pure policy for Mod Tweaker integrations whose VMF mod is installed but disabled.
-- Keeps presence/layout decisions and subtree removal engine-free for Lua 5.1 tests.
local M = {
    REASON = "Disabled in VMF",
}

-- Keep authored-mod discovery and Equipment stream aliases in one pure policy table.
-- The Mod Tweaker has two presentation paths (_state and _view); duplicating these
-- tables in both let the wt_dev namespace drift out of the UI in issue #636.
M.AUTHOR_MOD_IDS = {
    gut = true, gut_dev = true, wt = true, wt_dev = true,
    ct = true, ct_dev = true, gt = true, gt_dev = true,
    cim = true, cim_dev = true, crt = true, cosmetics_tweaker = true,
    dynamic_cosmetic_portraits = true, enemy_tweaker = true,
    character_weapon_variants = true, event_tweaker = true, mp = true, bt = true,
}

M.EQUIPMENT_ROLES = {
    cosmetics_tweaker = "cosmetics",
    cim = "crafting", cim_dev = "crafting",
    wt = "weapons", wt_dev = "weapons",
    character_weapon_variants = "cwv",
}

function M.is_author_mod(mod_id)
    return M.AUTHOR_MOD_IDS[mod_id] == true
end

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

function M.select_equipment_members(categories)
    return M.select_members(categories, M.EQUIPMENT_ROLES)
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
