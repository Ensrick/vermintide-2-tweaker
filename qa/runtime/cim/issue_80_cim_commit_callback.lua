-- qa/runtime/cim/issue_80_cim_commit_callback.lua
-- WP-CIM-02 rig case: a backend commit that carries a completion callback
-- reaches vanilla and fires while the standard-forge flag is set, and a
-- game-state change clears the flag. Advances #80 (class R); no issue closes.
--
-- Engine reads (Vermintide-2-Source-Code):
--   * BackendManagerPlayFab.commit returns the mirror's commit id:
--     scripts/managers/backend_playfab/backend_manager_playfab.lua:933-937
--   * the callback fires from _check_current_commit:
--     scripts/managers/backend_playfab/playfab_mirror_base.lua:1847-1868
--
-- If case A also times out with the flag false, commits are blocked in the rig
-- itself: report INCONCLUSIVE, not a product failure (card stop condition).

local MOD_ID = "cim_dev"

local function clear_flag()
    local cim = get_mod(MOD_ID)
    if cim then
        cim._cim_standard_forge_active = false
    end
end

return {
    id = "cim-80-commit-callback",
    issue = 80,
    class = "R",
    covers = "WP-CIM-02 RIG acceptance: case A callback fires with the forge flag set; case B flag reset on state change",
    arena = "keep",
    mods = { MOD_ID },
    timeout = 150,

    run = function(T)
        local cim = get_mod(MOD_ID)
        T.require(cim ~= nil, "cim_dev loaded")
        T.require(type(cim.on_game_state_changed) == "function", "state callback exposed")

        T.step("case A: commit with a callback while the forge flag is set")
        local fired = false
        cim._cim_standard_forge_active = true
        local id = Managers.backend:commit(true, function() fired = true end)
        T.expect(id ~= nil, "commit returned an id")
        T.wait_until(function() return fired end, 90, "callback fired while the forge flag is set")
        T.note("commit_id", tostring(id))
        clear_flag()

        T.step("case B: a game-state change clears the forge flag")
        cim._cim_standard_forge_active = true
        cim.on_game_state_changed("enter", "StateIngame")
        T.expect_eq(cim._cim_standard_forge_active, false, "flag reset on state change")
        clear_flag()

        T.expect_rt(MOD_ID, "issue_cim_commit_callback_preserved")
    end,

    cleanup = function()
        clear_flag()
    end,
}
