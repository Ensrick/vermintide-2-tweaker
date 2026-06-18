-- Fixture: a bare `unpack(` appears only inside a STRING LITERAL (an error /
-- marker message), not as a real call. The check must blank string interiors
-- before matching, so this is NOT flagged.
-- Expected verdict from qa/check_unpack_safety.ps1: PASS (no warning).

local function describe()
    return "MARKER not defined — hooks may have reverted to bare unpack(args), truncating at nil holes"
end

return describe
