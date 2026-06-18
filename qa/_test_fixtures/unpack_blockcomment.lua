-- Fixture: a bare unpack(t) that appears ONLY inside a --[[ ... ]] block
-- comment (documentation describing the historical nil-hole bug, as in
-- weapon_tweaker/_safe_hook.lua). The check must NOT flag prose inside a
-- block comment.
-- Expected verdict from qa/check_unpack_safety.ps1: PASS (no warning).

--[[
    Historical note: an earlier version did `return unpack(results)` here,
    which truncated at nil holes. The bare `unpack(args)` form is the WRONG
    fix and must not be reintroduced.
]]

local function passthrough(...)
    local results = { ... }
    local n = select("#", ...)
    return unpack(results, 1, n)
end

return passthrough
