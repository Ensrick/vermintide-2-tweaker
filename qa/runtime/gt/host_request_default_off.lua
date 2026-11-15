-- qa/runtime/gt/host_request_default_off.lua
-- WP-GT-01 rig case (audit finding A6-F01): on a profile that never saw the
-- setting, "Allow Client Requests" starts off, so a host refuses a peer's
-- win / fail / restart, respawn, godmode and spawn requests by default.
-- VMF writes a new widget's default_value into the settings on first load
-- (Vermintide-Mod-Framework vmf/scripts/mods/vmf/modules/core/options.lua:603-604).
-- The end-to-end refusal needs a second client and stays class C.

local MOD_ID = "gt_dev"

return {
    id = "gt-host-request-default-off",
    issue = 0,
    class = "R",
    covers = "WP-GT-01 RIG acceptance (A6-F01): gt_host_allow_client_requests defaults to false",
    arena = "keep",
    mods = { MOD_ID },
    timeout = 30,

    run = function(T)
        T.step("preconditions")
        local gt = get_mod(MOD_ID)
        T.require(gt ~= nil, "gt_dev loaded")
        T.require(type(gt._gt_host_request_policy) == "table", "host request policy installed")
        T.note("policy_schema", tostring(gt._gt_host_request_policy.SCHEMA))

        T.step("read the opt-in")
        T.expect_eq(get_mod("gt_dev"):get("gt_host_allow_client_requests"), false,
            "opt-in is off on a fresh profile")
    end,
}
