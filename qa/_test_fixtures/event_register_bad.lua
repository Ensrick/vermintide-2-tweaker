-- Fixture: Stingray event:register with a function VALUE as 3rd arg.
-- Expected verdict from qa/check_event_register_signature.ps1: ERROR.
-- This file is excluded from the normal scan (lives under _test_fixtures/).

local mod = get_mod("fixture")

local function _on_event(_peer)
    return true
end

-- WRONG: 3rd arg is a function value, not a string method name.
-- Engine logs: "No function found with name '[function]'" and the handler
-- never fires.
local function _register_bad()
    local em = Managers.state and Managers.state.event
    if not em then return end
    em:register(mod, "on_player_joined_party", _on_event)
end

return _register_bad
