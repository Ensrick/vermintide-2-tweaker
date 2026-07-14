-- Pure authored-pose catalog policy for issue #485. Engine-free for QA.
local Policy = {}

function Policy.build_catalog(item_master_list)
    local by_parent = {}
    if type(item_master_list) ~= "table" then return by_parent end

    for item_name, data in pairs(item_master_list) do
        if type(data) == "table"
            and data.item_type == "weapon_pose"
            and type(data.parent) == "string"
            and type(data.pose_index) == "number"
            and type(data.data) == "table"
            and type(data.data.anim_event) == "string" then
            local rows = by_parent[data.parent]
            if not rows then
                rows = {}
                by_parent[data.parent] = rows
            end
            rows[#rows + 1] = {
                ItemId = item_name,
                backend_id = "cos_pose:" .. item_name,
                data = data,
                rarity = data.rarity or "default",
            }
        end
    end

    for _, rows in pairs(by_parent) do
        table.sort(rows, function(a, b)
            if a.data.pose_index == b.data.pose_index then
                return a.ItemId < b.ItemId
            end
            return a.data.pose_index < b.data.pose_index
        end)
    end

    return by_parent
end

function Policy.for_parent(catalog, parent_item)
    if type(catalog) ~= "table" or type(parent_item) ~= "string" then return nil end
    local rows = catalog[parent_item]
    if type(rows) ~= "table" or #rows == 0 then return nil end
    return rows
end

return Policy
