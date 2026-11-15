-- qa/runtime/cwv/a2f02_not_togglable.lua
-- WP-CWV-02 rig case (audit finding A2-F02): Character Weapon Variants and
-- Weapons of Chaos are non-togglable and still start fully active. VMF never
-- fires on_enabled at start-up for a non-togglable mod
-- (Vermintide-Mod-Framework vmf/scripts/mods/vmf/modules/vmf_mod_manager.lua:127-129),
-- so each mod now runs its start-up body itself; a new mod's state is enabled
-- (vmf_mod_data.lua:30), read through VMFMod:is_enabled (vmf_mod_data.lua:78).
-- [unverified] that the two named checks fail when the start-up call is
-- missing; they are the closest existing probes of what on_enabled activates.
-- T.expect_rt is part of the CONVENTIONS API; the driver adds it in WP-H-06.

return {
    id = "cwv-a2f02-not-togglable",
    issue = 0,
    class = "R",
    covers = "WP-CWV-02 RIG acceptance (A2-F02): cwv and WOC are enabled and their start-up runtimes are live",
    arena = "keep",
    mods = { "character_weapon_variants", "WOC" },
    timeout = 60,
    host_forbid_log = { "[regression] FAIL" },

    run = function(T)
        T.step("preconditions")
        local cwv = get_mod("character_weapon_variants")
        local woc = get_mod("WOC")
        T.require(cwv ~= nil, "character_weapon_variants loaded")
        T.require(woc ~= nil, "WOC loaded")

        T.step("both mods are enabled")
        T.expect(cwv:is_enabled() == true, "character_weapon_variants is enabled")
        T.expect(woc:is_enabled() == true, "WOC is enabled")

        T.step("start-up runtimes are live")
        T.expect_rt("character_weapon_variants", "issue645_mace_on_kruber_sword_family")
        T.expect_rt("WOC", "issue934_shared_relic_lease_contract")
    end,
}
