-- Pure conditional-ownership policy shared by WT availability and backend
-- cache validation. Engine-free for host Lua 5.1 regression coverage (#593).
local M = {}

M.REPLACEMENTS = {
    dr_shield_axe = { "cwv_es_axe_shield", "cwv_es_axe_shield_veteran" },
    dr_2h_axe = { "cwv_es_greataxe" },
}

function M.cwv_is_active(cwv)
    if type(cwv) ~= "table" then return false end
    if type(cwv.is_enabled) == "function" then
        local ok, enabled = pcall(cwv.is_enabled, cwv)
        return ok and enabled == true
    end
    -- Older VMF/mod doubles do not expose is_enabled; presence means loaded.
    return true
end

function M.replacement_ready(item_master_list, weapon_key)
    local required = M.REPLACEMENTS[weapon_key]
    if type(item_master_list) ~= "table" or type(required) ~= "table" then return false end
    for _, key in ipairs(required) do
        local item = rawget(item_master_list, key)
        if not item or item.cwv_variant ~= true then return false end
    end
    return true
end

function M.should_yield_native(career_name, weapon_key, cwv_active, managed, replacement_ready)
    local career = managed and managed[career_name]
    return cwv_active == true and replacement_ready == true
        and career and career[weapon_key] == true or false
end

return M
