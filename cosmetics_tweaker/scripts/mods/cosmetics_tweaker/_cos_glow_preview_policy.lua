-- Pure ownership policy for the glow editor's LootItemUnitPreviewer target.
-- The editor may repaint only the preview belonging to its exact backend item
-- and selected illusion; stale/asynchronous previewers fail closed.

local Policy = {}

local function _skin_of(item)
    if type(item) ~= "table" then return nil end
    local skin = item.skin
    if type(skin) == "string" and skin ~= "" then return skin end
    local data = item.data
    if type(data) == "table" and data.item_type == "weapon_skin" then
        return data.name or item.key
    end
    return nil
end

function Policy.resolve(host, backend_id, slot_data, is_unit)
    if host == nil or backend_id == nil then return nil, "missing_identity" end
    if host._item_backend_id ~= backend_id then return nil, "backend_mismatch" end

    local previewer = host._previewer
    local item = previewer and previewer._item
    local requested_skin = type(slot_data) == "table" and slot_data.skin or nil
    local preview_skin = _skin_of(item)
    if type(requested_skin) == "string" and requested_skin ~= ""
            and preview_skin ~= requested_skin then
        return nil, "skin_mismatch"
    end

    local spawned = previewer and previewer._spawned_units
    if type(spawned) ~= "table" then return nil, "not_spawned" end
    local units = {}
    for i = 1, #spawned do
        local unit = spawned[i]
        if type(is_unit) ~= "function" or is_unit(unit) then
            units[#units + 1] = unit
        end
    end
    if #units == 0 then return nil, "no_live_units" end

    local data = type(item) == "table" and item.data or nil
    return {
        units = units,
        skin = preview_skin or requested_skin or "",
        item_name = type(data) == "table" and (data.name or data.matching_item_key) or nil,
        item_template = type(data) == "table" and data.template or nil,
    }, "ready"
end

return Policy
