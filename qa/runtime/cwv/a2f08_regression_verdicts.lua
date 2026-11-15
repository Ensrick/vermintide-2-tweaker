-- qa/runtime/cwv/a2f08_regression_verdicts.lua
-- WP-CWV-06 rig case (audit finding A2-F08): every /cwv_regression_test and
-- /woc_regression_test check prints exactly one verdict, the two WOC
-- source-text checks report SKIP (not PASS) in the shipped game, and the
-- cwv suite leaves no fake peer "rt474-peer" behind.
--
-- The runners also write each verdict with engine printf ("[regression] <VERDICT> <name>");
-- the offline suite pins that (qa/lua/tests/test_regression_runner_verdicts.lua).
-- Here the per-check verdict is read from the lines T.cmd captures (VMF echo),
-- and host_expect_log carries the two SKIP printf lines. host_expect_log is a
-- CONVENTIONS field; the driver gains it with the rest of the T API (WP-H-06).

local CWV_CHECKS = {
    "cwv_variant_flag_present",
    "issue914_peer_ready_identity_lifecycle",
    "issue474_old_musket_hot_join_identity_and_remote_fire",
    "issue645_mace_on_kruber_sword_family",
    "issue1320_outrider_projectile_unit_and_wire",
}
local WOC_CHECKS = {
    "issue422_wire_safety_unconditional_singleton",
    "no_unit_path_package_force_load",
    "wire_non_woc_item_passthrough_identity",
    "issue934_shared_relic_lease_contract",
    "issue637_unique_immutable_relic_inventory",
}
local WOC_SOURCE_TEXT_CHECKS = {
    issue422_wire_safety_unconditional_singleton = true,
    no_unit_path_package_force_load = true,
}

local function verdicts_for(lines, name)
    local found = {}
    for _, line in ipairs(lines or {}) do
        local verdict, rest = tostring(line):match("^%s*(%u[%u%-]*): (.*)$")
        if verdict and (rest == name or rest:sub(1, #name + 1) == name .. " ") then
            found[#found + 1] = verdict
        end
    end
    return found
end

return {
    id = "cwv-a2f08-regression-verdicts",
    issue = 0,
    class = "R",
    covers = "WP-CWV-06 RIG acceptance (A2-F08): one verdict per check, source-text checks SKIP, no rt474-peer left",
    arena = "keep",
    mods = { "character_weapon_variants", "WOC" },
    timeout = 180,
    host_expect_log = {
        "[regression] SKIP issue422_wire_safety_unconditional_singleton",
        "[regression] SKIP no_unit_path_package_force_load",
    },

    run = function(T)
        T.step("preconditions")
        local cwv = get_mod("character_weapon_variants")
        T.require(cwv ~= nil, "character_weapon_variants loaded")
        T.require(get_mod("WOC") ~= nil, "WOC loaded")
        T.require(type(cwv._cwv_peer_appearance) == "table"
            and type(cwv._cwv_peer_appearance.resolve_peer) == "function", "cwv peer appearance resolver")

        T.step("run the cwv suite")
        local cwv_lines = T.cmd("cwv_regression_test")
        for _, name in ipairs(CWV_CHECKS) do
            local found = verdicts_for(cwv_lines, name)
            T.expect_eq(#found, 1, "cwv " .. name .. " printed exactly one verdict")
            T.note("cwv_" .. name, table.concat(found, ","))
        end

        T.step("run the WOC suite")
        local woc_lines = T.cmd("woc_regression_test")
        for _, name in ipairs(WOC_CHECKS) do
            local found = verdicts_for(woc_lines, name)
            T.expect_eq(#found, 1, "WOC " .. name .. " printed exactly one verdict")
            if WOC_SOURCE_TEXT_CHECKS[name] then
                T.expect_eq(found[1], "SKIP", "WOC " .. name .. " is SKIP, not PASS, in the shipped game")
            end
            T.note("woc_" .. name, table.concat(found, ","))
        end

        T.step("no fake peer left behind")
        T.expect(select(1, cwv._cwv_peer_appearance.resolve_peer("rt474-peer", "slot_melee", "es_handgun")) == nil,
            "the cwv identity table holds no rt474-peer after the suite")
    end,
}
