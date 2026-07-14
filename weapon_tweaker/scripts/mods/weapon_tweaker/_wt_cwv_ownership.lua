-- Pure conditional-ownership policy shared by WT availability and backend
-- cache validation. Engine-free for host Lua 5.1 regression coverage (#593).
local M = {}

function M.cwv_is_active(cwv)
    if type(cwv) ~= "table" then return false end
    if type(cwv.is_enabled) == "function" then
        local ok, enabled = pcall(cwv.is_enabled, cwv)
        return ok and enabled == true
    end
    -- Older VMF/mod doubles do not expose is_enabled; presence means loaded.
    return true
end

function M.should_yield_native(career_name, weapon_key, cwv_active, managed)
    local career = managed and managed[career_name]
    return cwv_active == true and career and career[weapon_key] == true or false
end

return M
