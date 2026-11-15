-- qa/runtime/event_tweaker/issue_430_join_lock_open.lua
-- WP-CW-01 (#430, #413) control: with no managed curse selected the live
-- game mode stays joinable, so the lock does not close ordinary sessions.
--
-- Engine reads:
--   GameModeManager.game_mode   Vermintide-2-Source-Code/scripts/managers/game_mode/game_mode_manager.lua:911
--   GameModeBase.is_joinable    scripts/managers/game_mode/game_modes/game_mode_base.lua:570-572 (vanilla true)
return {
    id      = "event_tweaker-430-join-lock-open",
    issue   = 430,
    class   = "R",
    covers  = "WP-CW-01 control: no managed curse, the live game mode stays joinable",
    arena   = "mission:military",
    mods    = { "event_tweaker" },
    options = { event_tweaker = { mut_curse_blood_storm = false } },
    timeout = 90,

    run = function(T)
        T.step("let the mission settle")
        T.wait(5)

        T.step("read the live game mode's joinability")
        local game_mode = Managers.state.game_mode:game_mode()
        T.expect_eq(game_mode:is_joinable(), true, "session open")

        T.expect_rt("event_tweaker", "issue430_join_lock_reaches_instances")
    end,
}
