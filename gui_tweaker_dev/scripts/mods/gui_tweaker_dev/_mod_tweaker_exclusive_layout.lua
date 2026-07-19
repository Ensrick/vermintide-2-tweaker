-- Pure layout planner for Mod Tweaker mutually-exclusive controls (#446).
--
-- VMF only understands the underlying checkbox settings.  This module leaves that
-- persistence surface untouched and replaces a complete, same-parent checkbox cluster
-- with one synthetic collapsible plus radio rows in Mod Tweaker's render plan.
-- Cross-mod, incomplete, or structurally scattered groups fail closed to the ordinary
-- checkbox presentation; exclusivity enforcement still works for those groups.

local M = {}

local function _parent_index(depths, index)
    local depth = depths[index] or 0
    if depth <= 0 then return 0 end
    for i = index - 1, 1, -1 do
        local candidate = depths[i] or 0
        if candidate < depth then
            return candidate == depth - 1 and i or 0
        end
    end
    return 0
end

local function _copy_display_fields(source, target, field)
    for _, key in ipairs({ "title", "text", "tooltip", "disabled" }) do
        local value = field(source, key)
        if value ~= nil then target[key] = value end
    end
end

-- Returns planned_nodes, planned_depths, synthesized_group_count.
-- `api` requires:
--   mod_id, field(node,key), get_group_id(mod_id,setting_id),
--   get_members(group_id), get_presentation(group_id).
function M.plan(nodes, depths, api)
    if type(nodes) ~= "table" or type(depths) ~= "table" or type(api) ~= "table" then
        return nodes or {}, depths or {}, 0
    end
    local field = api.field
    if type(field) ~= "function" then return nodes, depths, 0 end

    local candidates = {}
    for i = 1, #nodes do
        local setting_id = field(nodes[i], "setting_id")
        if type(setting_id) == "string" and type(api.get_group_id) == "function" then
            local group_id = api.get_group_id(api.mod_id, setting_id)
            if group_id then
                local c = candidates[group_id]
                if not c then c = { indices = {}, by_setting = {} }; candidates[group_id] = c end
                c.indices[#c.indices + 1] = i
                c.by_setting[setting_id] = i
            end
        end
    end

    local replacements, skipped = {}, {}
    local synthesized = 0
    for group_id, candidate in pairs(candidates) do
        local presentation = type(api.get_presentation) == "function"
            and api.get_presentation(group_id) or nil
        local members = type(api.get_members) == "function" and api.get_members(group_id) or nil
        local valid = type(presentation) == "table" and presentation.control == "radio"
            and type(presentation.label) == "string" and presentation.label ~= ""
            and type(members) == "table" and #members >= 2

        local member_indices, first_index, common_depth, common_parent = {}, nil, nil, nil
        if valid then
            for i = 1, #members do
                local member = members[i]
                local index = member.mod_id == api.mod_id and candidate.by_setting[member.setting_id] or nil
                local depth = index and (depths[index] or 0) or nil
                local parent = index and _parent_index(depths, index) or nil
                if not index or (common_depth ~= nil and depth ~= common_depth)
                    or (common_parent ~= nil and parent ~= common_parent) then
                    valid = false
                    break
                end
                common_depth = common_depth or depth
                common_parent = common_parent or parent
                first_index = (not first_index or index < first_index) and index or first_index
                member_indices[i] = index
            end
        end

        if valid then
            local planned = {
                {
                    type = "group",
                    setting_id = "__mt_radio_group::" .. group_id,
                    title = presentation.label,
                    _mt_exclusive_group = group_id,
                },
                {
                    type = "radio",
                    setting_id = "__mt_radio_none::" .. group_id,
                    title = presentation.none_label or "None [Default]",
                    _mt_exclusive_group = group_id,
                    _mt_exclusive_none = true,
                },
            }
            for i = 1, #members do
                local member = members[i]
                local source = nodes[member_indices[i]]
                local radio = {
                    type = "radio",
                    setting_id = member.setting_id,
                    _mt_exclusive_group = group_id,
                    _mt_exclusive_member_mod = member.mod_id,
                }
                _copy_display_fields(source, radio, field)
                planned[#planned + 1] = radio
                skipped[member_indices[i]] = true
            end
            replacements[first_index] = { nodes = planned, depth = common_depth }
            synthesized = synthesized + 1
        end
    end

    if synthesized == 0 then return nodes, depths, 0 end
    local out_nodes, out_depths = {}, {}
    for i = 1, #nodes do
        local replacement = replacements[i]
        if replacement then
            for j = 1, #replacement.nodes do
                out_nodes[#out_nodes + 1] = replacement.nodes[j]
                out_depths[#out_depths + 1] = replacement.depth + (j == 1 and 0 or 1)
            end
        end
        if not skipped[i] then
            out_nodes[#out_nodes + 1] = nodes[i]
            out_depths[#out_depths + 1] = depths[i]
        end
    end
    return out_nodes, out_depths, synthesized
end

return M
