-- Pure capacity census for native-loadout expansion (#231).
local Policy = { TARGET = 30, VANILLA_VISIBLE = 6 }

local function custom_rows(loadouts)
    local rows, seen = {}, {}
    local duplicate = 0
    for _, row in ipairs(loadouts or {}) do
        if row and row.loadout_type == "custom" then
            local index = tonumber(row.loadout_index)
            rows[#rows + 1] = row
            if index and seen[index] then duplicate = duplicate + 1 end
            if index then seen[index] = true end
        end
    end
    return rows, duplicate
end

local function compress(indices)
    if #indices == 0 then return "none" end
    table.sort(indices)
    local out, first, last = {}, indices[1], indices[1]
    for i = 2, #indices + 1 do
        local value = indices[i]
        if value == last + 1 then
            last = value
        else
            out[#out + 1] = first == last and tostring(first)
                or string.format("%d-%d", first, last)
            first, last = value, value
        end
    end
    return table.concat(out, ",")
end

function Policy.inspect(loadouts, declared_cap, widget_count, icon_exists, title_exists, store_max)
    local rows, duplicates = custom_rows(loadouts)
    local result = {
        target = Policy.TARGET,
        custom_count = #rows,
        declared_cap = tonumber(declared_cap) or 0,
        widget_count = tonumber(widget_count) or 0,
        store_max = tonumber(store_max) or 0,
        duplicate_count = duplicates,
        missing_icons = {},
        missing_titles = {},
    }
    for index = 1, Policy.TARGET do
        if type(icon_exists) == "function" and not icon_exists(index) then
            result.missing_icons[#result.missing_icons + 1] = index
        end
        if type(title_exists) == "function" and not title_exists(index) then
            result.missing_titles[#result.missing_titles + 1] = index
        end
    end
    result.missing_icon_ranges = compress(result.missing_icons)
    result.missing_title_ranges = compress(result.missing_titles)
    result.needs_paging = result.target > Policy.VANILLA_VISIBLE
    result.data_ready = result.custom_count >= result.target
        and result.declared_cap >= result.target and result.duplicate_count == 0
    result.assets_ready = #result.missing_icons == 0 and #result.missing_titles == 0
    result.direct_ui_ready = result.widget_count >= result.target
    result.cutover_ready = result.data_ready and result.assets_ready
        and result.direct_ui_ready
    return result
end

return Policy
