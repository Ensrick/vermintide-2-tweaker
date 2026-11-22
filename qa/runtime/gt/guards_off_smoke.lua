-- qa/runtime/gt/guards_off_smoke.lua
-- WP-GT-05 rig case 2 (audit finding A6-F03): the run-time switch turns every
-- gt_dev engine guard off so other mods can be tested without them, and the
-- game survives ordinary spawning with the guards off. A crash here is a
-- finding about the code a guard was hiding, not a failure of WP-GT-05: record
-- it and keep the switch. The guards are switched back on before the case ends.
-- T.spawn and host_forbid_log are CONVENTIONS API; the driver adds them in WP-H-06.

local MOD_ID = "gt_dev"
local state = {}

local function guards_on()
    local gt = get_mod(MOD_ID)
    if gt and gt.gt_set_engine_guards and not state.restored then
        state.restored = true
        pcall(gt.gt_set_engine_guards, true)
    end
end

return {
    id = "gt-guards-off-smoke",
    issue = 0,
    class = "R",
    covers = "WP-GT-05 RIG 2: guards off, five clan rats, thirty seconds, no update-consumer error",
    arena = "mission:military",
    bots = true,
    mods = { MOD_ID },
    timeout = 120,
    host_forbid_log = { "%[gt:update%] consumer '.-' raised" },

    run = function(T)
        for k in pairs(state) do state[k] = nil end
        T.step("preconditions")
        local gt = get_mod(MOD_ID)
        T.require(gt ~= nil and type(gt.gt_set_engine_guards) == "function", "gt_dev guard switch available")
        T.local_hero()

        T.step("switch the guards off")
        gt.gt_set_engine_guards(false)
        T.expect(gt._gt_guards_on() == false, "guards are off")

        T.step("spawn five clan rats")
        for i = 1, 5 do
            T.spawn("skaven_clan_rat", { 4 + i, 0, 0 })
        end
        T.wait(30)

        T.step("switch the guards back on")
        guards_on()
        T.expect(gt._gt_guards_on() == true, "guards are back on")
    end,

    cleanup = function()
        guards_on()
    end,
}
