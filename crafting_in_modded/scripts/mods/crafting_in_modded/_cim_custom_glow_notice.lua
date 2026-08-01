-- Issue #48: once-per-session, log-only notice for opaque Cosmetics glow data.
-- CIM does not interpret or render the blob; it only reports that the optional
-- provider is absent and vanilla material defaults will therefore remain.

local M = {}

function M.new()
    local state = { emitted = false }

    function state:observe(records, get_mod_fn)
        local count = 0
        for _, record in pairs(type(records) == "table" and records or {}) do
            if type(record) == "table" and record.custom_glow ~= nil then
                count = count + 1
            end
        end
        if count == 0 or self.emitted then return count, false end
        if type(get_mod_fn) ~= "function" then return count, false end
        local ok, cosmetics = pcall(get_mod_fn, "cosmetics_tweaker")
        if not ok or cosmetics ~= nil then return count, false end
        self.emitted = true
        return count, true
    end

    return state
end

return M
