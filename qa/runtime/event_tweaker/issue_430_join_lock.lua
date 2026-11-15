-- qa/runtime/event_tweaker/issue_430_join_lock.lua
-- WP-CW-01 (#430, #413): while a managed curse is active, the live game-mode
-- instance refuses hot joins. Host half only; a late join by a player without
-- the mod stays class C.
--
-- Engine reads:
--   GameModeManager.game_mode   Vermintide-2-Source-Code/scripts/managers/game_mode/game_mode_manager.lua:911
--   GameModeManager._mutator_handler   game_mode_manager.lua:99
--   MutatorHandler._active_mutators    scripts/managers/game_mode/mutator_handler.lua:42, :221
--   game_mode:is_joinable() caller     scripts/network/peer_states.lua:116
return {
    id      = "event_tweaker-430-join-lock",
    issue   = 430,
    class   = "R",
    covers  = "WP-CW-01: curse join lock reaches the live Adventure game mode (host half)",
    not_covered = "a real late join by a peer without the mod (class C)",
    arena   = "mission:military",
    mods    = { "event_tweaker" },
    -- Plan option: must be in the profile before the mission loads.
    options = { event_tweaker = { mut_curse_blood_storm = true } },
    timeout = 120,

    host_expect_log = {
        "%[et:430%] peer%-required session hot%-join contract LOCKED",
    },

    run = function(T)
        local function curse_active()
            local gm = Managers.state and Managers.state.game_mode
            local handler = gm and gm._mutator_handler
            local active = handler and handler._active_mutators
            return type(active) == "table" and active["curse_blood_storm"] ~= nil
        end

        T.step("wait for the managed curse to activate")
        for _ = 1, 30 do
            if curse_active() then break end
            T.wait(1)
        end
        -- INCONCLUSIVE without the morris DLC (curse_blood_storm is a Chaos Wastes curse).
        T.require(curse_active(), "managed curse active")

        T.step("read the live game mode's joinability")
        local game_mode = Managers.state.game_mode:game_mode()
        T.expect_eq(game_mode:is_joinable(), false, "session locked")

        T.expect_rt("event_tweaker", "issue430_join_lock_reaches_instances")
    end,
}
