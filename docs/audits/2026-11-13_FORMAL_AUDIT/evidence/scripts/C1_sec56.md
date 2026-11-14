### 5.6 Worked example: issue #1143 "Dev heal command" (General Tweaker, `verify-fix`, `coop-required`)

Newest card (`issues/open/1143.md`, comment 2026-11-06, official stream): banner `[gt:LOAD] v0.2.180`; enable official Tweaker: General only. Steps: (1) host a private Adventure game; (2) damage the host and wound them by downing and reviving, then the host runs `/heal`; (3) confirm full permanent health and cleared wounded state; (4-5) the same on the client; (6) both run `/gt_regression_test`. Expected: both heroes reach full permanent health with wounds cleared, the result rows name their route and report `wounded_after=false`, the developer-heal regression passes, no custom network event or direct health-state error.

Split: steps 1-3 and the host half of step 6 are class R. Steps 4-5 need a second peer (class C). The script below closes the host half and leaves the client half in the co-op queue.

Source facts used (repo): `/heal` is registered at `general_tweaker/scripts/mods/general_tweaker/_gt_dev_heal.lua:235` (mod id `gt`, `MOD_VERSION = "0.2.180"` at `general_tweaker.lua:3`); its receipt line `[gt:1143] heal result=... route=... wounded_after=...` is built at `:87-103`; the regression check `issue1143_dev_heal_command` is at `:240-262`. The dev stream has the same file at the same lines (`general_tweaker_dev/.../_gt_dev_heal.lua:235, 240`), so the earlier dev card (2026-08-13, `v0.2.279-dev`) uses the same script with `mods = { "gt_dev" }`. The stable tree has no `/down` command (only the dev tree does, `general_tweaker_dev/.../_gt_level_control.lua:587`), so the script downs the hero with the engine call instead.

Engine facts used: `StatusUtils.set_knocked_down_network` and `set_revived_network` (`scripts/helpers/status_utils.lua:21-34, 36-56`, host only); `GenericStatusExtension.is_knocked_down`, `is_disabled`, `is_wounded` (`scripts/unit_extensions/generic/generic_status_extension.lua:2091, 2158, 2222`); `PlayerUnitHealthExtension.current_permanent_health`, `get_max_health` (`scripts/unit_extensions/default_player_unit/player_unit_health_extension.lua:1073, 1107`).

```lua
-- qa/runtime/gt/issue_1143_dev_heal_host.lua
return {
    id      = "gt-1143-host",
    issue   = 1143,
    covers  = "card steps 1-3 and the host half of step 6; the client route stays coop-required",
    arena   = "mission",
    level   = "military",
    bots    = true,
    mods    = { "gt" },                                   -- VMF ids that must be loaded (card: official General only)
    banner  = { marker = "[gt:LOAD]", exact = "0.2.180" }, -- from the card's Build/banner line
    timeout = 90,

    -- Checked by the orchestrator in the console log after the run.
    host_expect_log = {
        { pattern = "%[gt:1143%] heal result=ok route=host .*wounded_after=false", count = 1 },
    },
    host_forbid_log = {
        "%[gt:1143%] heal result=error",
        "%[gt:1143%] heal result=timeout",
    },

    run = function(T)
        local unit   = T.local_hero()
        local health = T.ext(unit, "health_system")
        local status = T.ext(unit, "status_system")

        T.step("down the host (card step 2)")
        StatusUtils.set_knocked_down_network(unit, true)
        T.wait_until(function() return status:is_knocked_down() end, 10, "host is knocked down")

        T.step("revive the host (card step 2)")
        StatusUtils.set_revived_network(unit, true, T.first_bot_unit())
        T.wait_until(function()
            return not status:is_knocked_down() and not status:is_disabled()
        end, 20, "host is living and controllable")

        -- States the card assumes. If they do not hold, the case is INCONCLUSIVE, not FAIL.
        T.require(status:is_wounded(), "host is wounded before /heal")
        T.require(health:current_permanent_health() < health:get_max_health(),
                  "host is below full permanent health before /heal")

        T.step("run /heal (card step 2)")
        T.cmd("heal")

        -- Card step 3. Oracle = engine state, not the mod's own receipt line.
        T.wait_until(function()
            return health:current_permanent_health() >= health:get_max_health() - 0.01
               and not status:is_wounded()
        end, 10, "full permanent health and wound cleared")
        T.expect_near(health:current_permanent_health(), health:get_max_health(), 0.01,
                      "full permanent health")
        T.expect(not status:is_wounded(), "wound cleared")

        -- Card step 6, host half.
        T.expect_rt("gt", "issue1143_dev_heal_command")
    end,
}
```

What the run produces for the issue: verdict PASS or FAIL for the host route, the `ASSERT` lines, the one matching `[gt:1143]` receipt line, the `[gt:LOAD]` version, the run id and the log path. The card's "ordinary healing conditions" clause is met by loading only VMF, General and the driver, with no heal-blocking mutator. The script has not been run; the down-and-revive steps are the part most likely to need adjustment at E7, and `T.require` reports that as INCONCLUSIVE instead of a false FAIL. The client route remains for a two-machine run (section 5.8) or a live pair.

Side observation for the lead: the stable tree lacking `/down` while the dev tree has it is dev-to-stable drift in the test-verb set. Scripts for official-stream cards should use engine calls, not dev-only commands.
