-- qa/runtime/ct_dev/issue_426_roll_gate.lua
-- WP-CW-03 (#426, #1191): a custom boon is offered by a roll only when its
-- enable toggle is on (dev: and peer parity confirmed). The roll hook strips
-- inside a remove-then-restore window, so the arrays are unchanged afterwards.
-- The plan runs this file twice: mods { "ct_dev" } (all card steps) and
-- mods { "ct" } (public step 7 only). The case detects which tree is loaded.
--
-- Engine reads:
--   DeusPowerUpUtils.generate_random_power_ups   Vermintide-2-Source-Code/scripts/helpers/deus_power_up_utils.lua:391 (returns seed, list)
--   roll source arrays DeusPowerUpsArray / DeusPowerUpsArrayByRarity   deus_power_up_utils.lua:138-146
--   DeusPowerUpAvailabilityTypes.shrine          scripts/settings/dlcs/morris/deus_power_up_settings.lua:5500
return {
    id      = "ct-426-roll-gate",
    issue   = 426,
    class   = "R",
    covers  = "WP-CW-03: rolls offer a ct_boon_* only when its toggle is on; roll arrays restored",
    not_covered = "a mixed lobby where a peer lacks the catalog (class C)",
    arena   = "keep",
    mods    = { "ct_dev" },
    timeout = 300,

    run = function(T)
        local mod_id = get_mod("ct_dev") and "ct_dev" or "ct"
        T.note("tree", mod_id)
        T.require(rawget(_G, "DeusPowerUpUtils") and rawget(_G, "DeusPowerUpsArray")
            and rawget(_G, "DeusPowerUpAvailabilityTypes"), "Chaos Wastes roll tables loaded (morris)")

        local toggles = {
            "enable_boon_vauls_anvil", "enable_boon_manann_tempest",
            "enable_boon_taal_twinned_arrow", "enable_boon_asuryan_wrath",
        }
        if mod_id == "ct_dev" then
            toggles[#toggles + 1] = "enable_boon_anath_raema_swiftness"
        end

        local function roll(seeds)
            local seen = {}
            for seed = 1, seeds do
                local _, list = DeusPowerUpUtils.generate_random_power_ups(seed, 4, {}, "hardest", 0.5,
                    DeusPowerUpAvailabilityTypes.shrine, "es_mercenary", "unique")
                for _, pu in ipairs(list or {}) do
                    if pu and pu.name then seen[pu.name] = (seen[pu.name] or 0) + 1 end
                end
            end
            return seen
        end

        T.step("umbrella on, every custom boon toggle off")
        T.set(mod_id, "enable_boon_reworks", true)
        for _, setting in ipairs(toggles) do
            T.set(mod_id, setting, false)
        end
        T.wait(3)

        local recorded = #DeusPowerUpsArray
        T.step("500 shrine rolls: no custom boon")
        local seen = roll(500)
        local leaked = {}
        for name in pairs(seen) do
            if name:find("^ct_boon_") then leaked[#leaked + 1] = name end
        end
        table.sort(leaked)
        T.expect(#leaked == 0, "no ct_boon_* rolled with toggles off: " .. table.concat(leaked, ","))
        T.expect_eq(#DeusPowerUpsArray, recorded, "arrays restored")

        T.step("enable Vaul's Anvil, 2000 rolls: it appears")
        T.set(mod_id, "enable_boon_vauls_anvil", true)
        T.wait(3)
        seen = roll(2000)
        T.note("vauls_anvil_hits", seen.ct_boon_vauls_anvil or 0)
        T.expect((seen.ct_boon_vauls_anvil or 0) >= 1, "ct_boon_vauls_anvil rolled at least once")
        T.expect_eq(#DeusPowerUpsArray, recorded, "arrays restored after the positive rolls")
    end,
}
