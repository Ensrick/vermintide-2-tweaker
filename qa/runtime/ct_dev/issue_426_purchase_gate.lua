-- qa/runtime/ct_dev/issue_426_purchase_gate.lua
-- WP-CW-03 (#426, #1191): a shrine purchase of a custom boon is refused while
-- peer parity is not confirmed. Forces the parity read false for the call and
-- restores it.
--
-- Engine reads:
--   DeusMechanism.get_deus_run_controller        Vermintide-2-Source-Code/scripts/managers/game_mode/mechanisms/deus_mechanism.lua:523
--   DeusRunController._try_buy_power_up          scripts/managers/game_mode/mechanisms/deus_run_controller.lua:1725
--   DeusRunController.get_own_peer_id            deus_run_controller.lua:816
--   DeusRunController.get_player_power_ups       deus_run_controller.lua:1080
--   DeusPowerUpUtils.generate_specific_power_up  scripts/helpers/deus_power_up_utils.lua:387
return {
    id      = "ct_dev-426-purchase-gate",
    issue   = 426,
    class   = "R",
    covers  = "WP-CW-03: _try_buy_power_up refuses ct_meta_health while parity is unconfirmed",
    not_covered = "a client-sent purchase from a peer without the catalog (class C)",
    arena   = "deus",
    mods    = { "ct_dev" },
    timeout = 180,

    host_expect_log = {
        "%[ct:426%] BLOCKED modded boon at purchase: ct_meta_health",
    },

    run = function(T)
        local m = get_mod("ct_dev")
        T.require(m ~= nil, "ct_dev loaded")
        local mechanism = Managers.mechanism and Managers.mechanism:game_mechanism()
        local rc = mechanism and mechanism.get_deus_run_controller and mechanism:get_deus_run_controller()
        T.require(rc ~= nil, "Chaos Wastes run controller present")

        local peer_id = rc:get_own_peer_id()
        local pu = DeusPowerUpUtils.generate_specific_power_up("ct_meta_health", "exotic")

        T.step("force parity unconfirmed and try the purchase")
        local saved = m._ct_wire_safe
        m._ct_wire_safe = function() return false end
        local ok, bought = pcall(rc._try_buy_power_up, rc, peer_id, pu, 0)
        m._ct_wire_safe = saved

        T.expect(ok, "purchase call did not raise: " .. tostring(bought))
        T.expect_eq(bought, false, "purchase refused")

        local owned = rc:get_player_power_ups(peer_id, 1) or {}
        local has = false
        for _, entry in ipairs(owned) do
            if entry and entry.name == "ct_meta_health" then has = true end
        end
        T.expect(not has, "no ct_meta_health in the buyer's power-ups")
    end,
}
