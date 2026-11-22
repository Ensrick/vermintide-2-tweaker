-- qa/runtime/gt/guards_counters.lua
-- WP-GT-05 rig case 1 (audit finding A6-F03): the first measurement of which
-- always-on engine guards are load-bearing. After a minute of a normal mission
-- with bots, every guard's firing count is written as evidence
-- (mod._gt_guard_counts, _gt_engine_guards.lua). A count of 0 is a valid
-- result; the counts are notes, not assertions.

local MOD_ID = "gt_dev"
local GUARDS = {
    "world_spawn_unit", "unit_get_data", "unit_create_actor", "request_breed_limits",
    "update_aggro", "bt_health_nil", "fog_volume", "whereabouts_no_pos",
    "round_start_no_pos", "commander_no_pos", "utility_inputs",
}

return {
    id = "gt-guards-counters",
    issue = 0,
    class = "R",
    covers = "WP-GT-05 RIG 1: engine guard counters exist; first per-guard counts",
    arena = "mission:military",
    bots = true,
    mods = { MOD_ID },
    timeout = 120,

    run = function(T)
        T.step("preconditions")
        local gt = get_mod(MOD_ID)
        T.require(gt ~= nil, "gt_dev loaded")
        T.local_hero()

        T.step("play for a minute")
        T.wait(60)

        T.step("record the counters")
        local counts = get_mod("gt_dev")._gt_guard_counts
        T.expect(type(counts) == "table", "counters exist")
        T.note("guards_on", tostring(gt._gt_guards_on and gt._gt_guards_on()))
        for _, name in ipairs(GUARDS) do
            T.note("guard." .. name, tostring(type(counts) == "table" and counts[name] or 0))
        end
    end,
}
