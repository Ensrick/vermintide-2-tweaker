-- Fixture: correct pattern -- capture arity via select("#", ...) and pass
-- explicit `j` to unpack so nil holes round-trip.
-- Expected verdict from qa/check_unpack_safety.ps1: PASS (no warning).

local function passthrough(...)
    local n = select("#", ...)
    local results = { ... }
    return unpack(results, 1, n)
end

return passthrough
