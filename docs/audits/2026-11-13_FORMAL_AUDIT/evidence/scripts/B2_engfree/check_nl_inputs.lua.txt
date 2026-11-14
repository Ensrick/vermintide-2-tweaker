-- Which DLC-declared NetworkLookup source tables are still nil at this point?
local missing = {}
for dlc_name, dlc in pairs(DLCSettings) do
    local lookups = dlc.network_lookups
    if lookups then
        for name, table_data in pairs(lookups) do
            if type(table_data) == "table" then
                if rawget(_G, table_data.table_name) == nil then
                    missing[#missing + 1] = dlc_name .. ":" .. name .. "<-" .. tostring(table_data.table_name)
                end
            else
                local root = tostring(table_data):match("^[^%.]+")
                if rawget(_G, root) == nil then missing[#missing + 1] = dlc_name .. ":" .. name .. "<-" .. tostring(table_data) end
            end
        end
    end
end
table.sort(missing)
io.write("NL_INPUTS_MISSING " .. #missing .. ": " .. table.concat(missing, " | ") .. "\n")
