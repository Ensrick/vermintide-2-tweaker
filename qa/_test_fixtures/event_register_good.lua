-- Fixture: Stingray event:register with a STRING method name as 3rd arg.
-- Expected verdict from qa/check_event_register_signature.ps1: PASS.
-- This file is excluded from the normal scan (lives under _test_fixtures/).

local mod = get_mod("fixture")

local function _on_event(_self, _peer)
    return true
end

-- RIGHT: assign the function to mod under a method name, register with
-- the string. Stingray resolves `mod["on_player_joined_party"]` at fire
-- time and invokes it correctly.
mod.on_player_joined_party = _on_event

local function _register_good()
    local em = Managers.state and Managers.state.event
    if not em then return end
    em:register(mod, "on_player_joined_party", "on_player_joined_party")
end

return _register_good
