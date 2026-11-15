-- qa/runtime/gt/issue_1034_lag_comp_default_off.lua
-- WP-GT-02 rig case (audit finding A6-F02): host melee latency compensation is
-- off after load, for a new profile and, through the one-time migration in
-- _gt_host_lag_comp.lua, for a profile that saved the old `true` default
-- (VMF writes defaults on first load: Vermintide-Mod-Framework
-- vmf/scripts/mods/vmf/modules/core/options.lua:603-604).
-- Advances #1034 only: the issue is class C and stays open until a
-- two-machine run shows the delay logic is safe.

local MOD_ID = "gt_dev"

return {
    id = "gt-1034-lag-comp-default-off",
    issue = 1034,
    class = "R",
    covers = "WP-GT-02 RIG acceptance: gt_host_lag_comp is false after load (migration flag recorded)",
    arena = "keep",
    mods = { MOD_ID },
    timeout = 30,

    run = function(T)
        T.step("preconditions")
        local gt = get_mod(MOD_ID)
        T.require(gt ~= nil, "gt_dev loaded")

        T.step("read the setting")
        T.expect_eq(get_mod("gt_dev"):get("gt_host_lag_comp"), false, "lag compensation is off")
        T.note("migration_flag", tostring(gt:get("gt_host_lag_comp_default_off_v1")))
    end,
}
