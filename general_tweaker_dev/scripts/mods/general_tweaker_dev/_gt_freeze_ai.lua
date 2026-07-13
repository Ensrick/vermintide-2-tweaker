local mod = get_mod("gt_dev")

-- _gt_freeze_ai.lua — Freeze AI (#303)
--
-- Dev-only testing tool. Halts every enemy AI in place so a tester can inspect
-- positioning, hitboxes, or set up a scenario, and pauses new spawns while held.
-- Exposed BOTH as the /freezeai chat command and as the "Freeze AI" keybind in
-- the dev-only Dev Tools group (keybind_type=function_call -> mod.gt_freeze_ai_toggle).
--
-- HOST-ONLY. AI brains run only on the server, so the toggle refuses on a client
-- (one echo). mod._gt_freeze_ai_active is the single piece of state; it is never
-- set on a client or in the stable stream, so every reader of it (the merged
-- AISystem.update_brains gate in _gt_creature_spawner.lua, the ConflictDirector
-- spawn hook + _apply_script_data_no_enemies in the main file) is inert there.
--
-- Mechanism (two vanilla-respected switches, both cited):
--   1. Halt existing + future AI: the brain gate merged into gt's existing
--      mod:hook(AISystem, "update_brains") short-circuits `bt:root():evaluate`
--      (ai_system.lua:882) for every alive AI unit while frozen. No enemy picks
--      a new action, attack, target, or nav destination; a mid-motion enemy
--      coasts to its last nav step and stands; a mid-swing attack stalls without
--      landing (its action's run() never advances). Newly-spawned enemies are
--      frozen the instant their brain would first tick.
--   2. Pause new spawns: mod._gt_apply_spawn_block() (main file) sets the same
--      script_data.ai_*_disabled flag set the vanilla dedicated-server
--      `disable_ai_and_bots` command (dedicated_server_commands.lua:824-845) and
--      the Testify `disable_ai` snippet (testify_snippets.lua:52-73) flip. Those
--      flags gate the conflict-director pipelines: ai_pacing_disabled
--      (conflict_director.lua:930/1475/1536), ai_horde_spawning_disabled
--      (753/1321/1550), ai_specials_spawning_disabled (1544; specials_pacing.lua:807/892),
--      ai_roaming_spawning_disabled (1601), ai_mini_patrol_disabled (1558),
--      ai_boss_spawning_disabled (enemy_recycler.lua:429), ai_critter_spawning_disabled
--      (enemy_recycler.lua:387). Composed (OR) with the /no_enemies toggle so
--      neither clobbers the other.
--
-- State persists until toggled off (or a mod reload clears it); a tester who
-- froze AI knows they did, and the echo confirms each transition.

local IS_DEV_STREAM = (mod == get_mod("gt" .. "_dev"))

if IS_DEV_STREAM then
    -- Called by /freezeai AND the Dev Tools keybind (function_call). Host-gated.
    mod.gt_freeze_ai_toggle = function()
        if not (Managers.player and Managers.player.is_server) then
            mod:echo("Only the host can freeze AI.")
            return
        end

        mod._gt_freeze_ai_active = not mod._gt_freeze_ai_active

        -- Re-apply the combined spawn block (freeze OR /no_enemies). Resolved at
        -- call time from the main file.
        if mod._gt_apply_spawn_block then
            mod._gt_apply_spawn_block()
        end

        mod:echo(mod._gt_freeze_ai_active and "AI frozen" or "AI unfrozen")
        printf("[gt:303] freeze_ai -> %s", tostring(mod._gt_freeze_ai_active and true or false))
    end

    mod:command("freezeai", "Toggle freezing all enemy AI in place (host-only, dev)", function()
        mod.gt_freeze_ai_toggle()
    end)
end

printf("[gt:303] freeze-ai loaded (dev_stream=%s)", tostring(IS_DEV_STREAM))
