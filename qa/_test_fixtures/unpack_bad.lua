-- Fixture: bare unpack(t) WITHOUT annotation or explicit j arg.
-- Expected verdict from qa/check_unpack_safety.ps1: WARN.
-- This file is excluded from the normal scan (lives under _test_fixtures/).

local function passthrough(...)
    local results = { ... }
    return unpack(results)
end

return passthrough
