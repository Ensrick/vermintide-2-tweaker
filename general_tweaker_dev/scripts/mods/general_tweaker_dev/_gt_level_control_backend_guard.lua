-- _gt_level_control_backend_guard.lua -- issue #1509 end-screen realm guard.
--
-- Engine-free policy. StateInGameRunning caches the raw EAC flag at on_enter;
-- a synchronous UI bracket can temporarily clear that raw field. The launch
-- parameter is immutable authority, so a modded run must restore the cached
-- bit before any end-of-level reward request is allowed to reach PlayFab.

local M = {}

function M.reconcile(realm_authority, state, script_state, development)
    if type(realm_authority) ~= "table"
       or type(realm_authority.is_modded) ~= "function"
       or type(state) ~= "table" then
        return false, false
    end

    local ok, modded = pcall(
        realm_authority.is_modded, script_state, 0, development)
    if not ok or modded ~= true then
        return false, false
    end

    local corrected = rawget(state, "_booted_eac_untrusted") ~= true
    rawset(state, "_booted_eac_untrusted", true)
    return true, corrected
end

return M
