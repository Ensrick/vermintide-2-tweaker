-- _mod_tweaker_external_group.lua
--
-- Pure planner for folding a third-party mod's LIVE VMF widget tree into one
-- authored Mod Tweaker group. It operates on flat node/depth lists and never
-- mutates VMF-owned nodes. Both the keep and mission presentations consume this
-- module so an external-mod update cannot drift between twins (#312/#339).

local M = {}

local function _field(node, key)
    if type(node) ~= "table" then return nil end
    local value = node[key]
    if value == nil and type(node.content) == "table" then
        value = node.content[key]
    end
    return value
end

local function _copy(source)
    local out = {}
    if type(source) == "table" then
        for key, value in pairs(source) do out[key] = value end
    end
    return out
end

local function _append_unique(out, seen, value)
    if value ~= nil and not seen[value] then
        seen[value] = true
        out[#out + 1] = value
    end
end

function M.find_mod_list(widget_data, mod_id, field)
    field = field or _field
    if type(widget_data) ~= "table" or type(mod_id) ~= "string" then return nil end
    for i = 1, #widget_data do
        local list = widget_data[i]
        local header = type(list) == "table" and list[1]
        if field(header, "mod_name") == mod_id then return list end
    end
    return nil
end

-- Replace every old mirrored child under `group_id` with the external mod's
-- current VMF nodes. `preserve_group_ids` identifies authored sub-groups that
-- remain after the live tree (GUT's sync/vanilla controls for #312).
function M.replace_group_children(args)
    args = args or {}
    local widgets = args.widgets
    local live_list = args.live_list
    local field = args.field or _field
    if type(widgets) ~= "table" then
        return { changed = false, reason = "widgets_missing", widgets = widgets }
    end
    if type(live_list) ~= "table" then
        return { changed = false, reason = "live_list_missing", widgets = widgets }
    end

    local group_index, group_depth
    for i = 1, #widgets do
        if field(widgets[i], "setting_id") == args.group_id then
            group_index = i
            group_depth = tonumber(field(widgets[i], "depth")) or 0
            break
        end
    end
    if not group_index then
        return { changed = false, reason = "target_group_missing", widgets = widgets }
    end

    local group_end = #widgets + 1
    for i = group_index + 1, #widgets do
        local depth = tonumber(field(widgets[i], "depth")) or 0
        if depth <= group_depth then group_end = i; break end
    end

    local preserved = {}
    local preserve_ids = args.preserve_group_ids or {}
    local i = group_index + 1
    while i < group_end do
        local node = widgets[i]
        local sid = field(node, "setting_id")
        if preserve_ids[sid] then
            local root_depth = tonumber(field(node, "depth")) or (group_depth + 1)
            local j = i + 1
            while j < group_end do
                local depth = tonumber(field(widgets[j], "depth")) or 0
                if depth <= root_depth then break end
                j = j + 1
            end
            for k = i, j - 1 do preserved[#preserved + 1] = widgets[k] end
            i = j
        else
            i = i + 1
        end
    end

    local live_min
    for n = 2, #live_list do
        local node = live_list[n]
        if type(node) == "table" and field(node, "type") ~= "header" then
            local depth = tonumber(field(node, "depth")) or 0
            live_min = live_min and math.min(live_min, depth) or depth
        end
    end
    if live_min == nil then
        return { changed = false, reason = "live_tree_empty", widgets = widgets }
    end

    local live_nodes = {}
    local owners = _copy(args.owners)
    local injected = 0
    for n = 2, #live_list do
        local source = live_list[n]
        if type(source) == "table" and field(source, "type") ~= "header" then
            local node = _copy(source)
            local depth = tonumber(field(source, "depth")) or live_min
            node.depth = group_depth + 1 + (depth - live_min)
            live_nodes[#live_nodes + 1] = node
            local sid = field(source, "setting_id")
            if type(sid) == "string" then
                owners[sid] = { mod_id = args.owner_id, mod_obj = args.owner_obj }
            end
            injected = injected + 1
        end
    end
    if injected == 0 then
        return { changed = false, reason = "live_tree_empty", widgets = widgets }
    end

    local result = {}
    for n = 1, group_index do result[#result + 1] = widgets[n] end
    for n = 1, #live_nodes do result[#result + 1] = live_nodes[n] end
    for n = 1, #preserved do result[#result + 1] = preserved[n] end
    for n = group_end, #widgets do result[#result + 1] = widgets[n] end

    local owner_ids, seen = {}, {}
    for _, id in ipairs(args.owner_mod_ids or {}) do _append_unique(owner_ids, seen, id) end
    _append_unique(owner_ids, seen, args.base_owner_id)
    _append_unique(owner_ids, seen, args.owner_id)

    local excluded = _copy(args.profile_excluded_owners)
    if args.exclude_owner_from_profiles and args.owner_id then
        excluded[args.owner_id] = true
    end

    return {
        changed = true,
        reason = "live_tree_spliced",
        widgets = result,
        owners = owners,
        owner_mod_ids = owner_ids,
        profile_excluded_owners = excluded,
        injected = injected,
    }
end

-- Compatibility path for a temporarily unavailable/changed VMF widget registry.
-- It preserves the pre-#312 behavior by routing authored fallback rows whose ids
-- still exist in the external mod's setting-name table. The normal path above is
-- dynamic and does not depend on this catalogue.
function M.bridge_known_fallback(args)
    args = args or {}
    local field = args.field or _field
    local widgets = args.widgets
    local names = args.setting_names
    if type(widgets) ~= "table" or type(names) ~= "table" then
        return { changed = false, reason = "fallback_catalogue_missing" }
    end

    local valid = {}
    for _, sid in pairs(names) do
        if type(sid) == "string" then valid[sid] = true end
    end
    local owners = _copy(args.owners)
    local bridged = 0
    for i = 1, #widgets do
        local node = widgets[i]
        local sid = field(node, "setting_id")
        local kind = field(node, "type")
        if type(sid) == "string" and valid[sid]
                and kind ~= "group" and kind ~= "header" and owners[sid] == nil then
            owners[sid] = { mod_id = args.owner_id, mod_obj = args.owner_obj }
            bridged = bridged + 1
        end
    end
    if bridged == 0 then
        return { changed = false, reason = "fallback_no_matches" }
    end

    local owner_ids, seen = {}, {}
    for _, id in ipairs(args.owner_mod_ids or {}) do _append_unique(owner_ids, seen, id) end
    _append_unique(owner_ids, seen, args.base_owner_id)
    _append_unique(owner_ids, seen, args.owner_id)
    local excluded = _copy(args.profile_excluded_owners)
    if args.exclude_owner_from_profiles and args.owner_id then excluded[args.owner_id] = true end

    return {
        changed = true,
        reason = "known_fallback_bridged",
        owners = owners,
        owner_mod_ids = owner_ids,
        profile_excluded_owners = excluded,
        bridged = bridged,
    }
end

return M
