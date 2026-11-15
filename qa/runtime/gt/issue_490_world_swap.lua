-- qa/runtime/gt/issue_490_world_swap.lua
-- WP-GT-03 rig case (audit finding A6-F08, advances #490): every gt draw path
-- is active while the level world is destroyed and recreated by a restart,
-- and the process survives. The draw paths now read the level world through
-- mod._gt_world (has_world probe plus handle identity); WorldManager.world
-- asserts on a missing world (Vermintide-2-Source-Code/foundation/scripts/
-- managers/world/world_manager.lua:107-115) and a stale cached handle is a
-- native fault pcall cannot catch.
-- Run once with mods { "gt_dev" } and once with { "gt" } (the public build):
-- the "gt" PASS is the R evidence for #490, which is about the public build.
-- T.set and T.expect_rt are CONVENTIONS API; the driver adds them in WP-H-06.

local MOD_ID = "gt_dev"
local OPTIONS = {
    "gt_solo_draw_boss_spheres",
    "gt_devtools_leash_lines",
    "gt_devtools_bot_hud",
    "gt_debug_highlights",
    "gt_melee_warning",
}

return {
    id = "gt-490-world-swap",
    issue = 490,
    class = "R",
    covers = "WP-GT-03 RIG acceptance: world swap with every gt draw path on",
    arena = "mission:military",
    bots = true,
    mods = { MOD_ID },
    timeout = 240,
    host_forbid_log = { "%[gt:update%] consumer '.-' raised", "Access violation" },

    run = function(T)
        T.step("preconditions")
        T.require(get_mod(MOD_ID) ~= nil, "gt_dev loaded")
        T.local_hero()

        T.step("turn every draw path on")
        for _, setting in ipairs(OPTIONS) do
            T.set(MOD_ID, setting, true)
        end
        T.wait(10)

        T.step("restart: destroys and recreates the level world")
        T.cmd("restart")
        local hero = T.wait_until(function()
            local player = Managers.player and Managers.player:local_player()
            local unit = player and player.player_unit
            return unit and Unit.alive(unit) and unit or nil
        end, 120, "local hero alive after the restart")
        T.require(hero ~= nil, "local hero alive after the restart")
        T.wait(10)

        T.step("the process survived with the draw paths active")
        T.expect_rt(MOD_ID, "gt_459_lineobject_cleanup_liveness_gated")
    end,
}
