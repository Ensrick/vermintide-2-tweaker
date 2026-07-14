-- Engine-free capability classifier for career-themed HUD inventory holders
-- (#442). Runtime feeds this UISettings.hud_inventory_panel_data; tests exercise
-- malformed entries and fallback semantics without loading UI resources.
local M = {}

local function _valid(entry)
    return type(entry) == "table"
        and type(entry.texture_id) == "string"
        and entry.texture_id ~= ""
        and type(entry.texture_size) == "table"
        and type(entry.texture_size[1]) == "number"
        and entry.texture_size[1] > 0
        and type(entry.texture_size[2]) == "number"
        and entry.texture_size[2] > 0
end

function M.inspect(careers, panel_data)
    local result = {
        career_count = 0,
        dedicated_count = 0,
        fallback_count = 0,
        malformed_count = 0,
        dedicated = {},
        fallback = {},
        texture_ids = {},
        missing_default = false,
    }
    if type(careers) ~= "table" or type(panel_data) ~= "table" then
        result.malformed_count = 1
        result.missing_default = true
        return result
    end
    result.missing_default = not _valid(panel_data.default)
    local seen_textures = {}
    for _, career_name in ipairs(careers) do
        result.career_count = result.career_count + 1
        local explicit = panel_data[career_name]
        if explicit ~= nil then
            if _valid(explicit) then
                result.dedicated_count = result.dedicated_count + 1
                result.dedicated[#result.dedicated + 1] = career_name
                if not seen_textures[explicit.texture_id] then
                    seen_textures[explicit.texture_id] = true
                    result.texture_ids[#result.texture_ids + 1] = explicit.texture_id
                end
            else
                result.malformed_count = result.malformed_count + 1
            end
        else
            result.fallback_count = result.fallback_count + 1
            result.fallback[#result.fallback + 1] = career_name
        end
    end
    table.sort(result.dedicated)
    table.sort(result.fallback)
    table.sort(result.texture_ids)
    return result
end

return M
