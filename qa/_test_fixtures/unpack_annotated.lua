-- Fixture: bare unpack(t) but the maintainer has audited the call site and
-- annotated it with the recognised `single-return` marker. The wrapped fn
-- returns at most one value so nil-hole truncation cannot occur.
-- Expected verdict from qa/check_unpack_safety.ps1: PASS (no warning).

local function vanilla_one_return()
    return 42
end

local function passthrough()
    local results = { vanilla_one_return() }
    return unpack(results) -- single-return: ok
end

return passthrough
