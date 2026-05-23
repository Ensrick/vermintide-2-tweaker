return {
    mod_name = {
        en = "Tweaker: Buffs (WIP)",
    },
    mod_description = {
        en = "Shared registry that pre-registers buffs / damage profiles / explosion templates needed by other Tweaker mods. Currently hosts Core's Big Rebalance integration's 328 names.",
    },

    bt_big_rebalance_group = {
        en = "Big Rebalance Registrations",
    },
    bt_master_enable_br_registrations = {
        en = "Enable Big Rebalance Registrations (master)",
    },
    bt_master_enable_br_registrations_tooltip = {
        en = "When ON, this mod injects the canonical 328-entry registration list for Core's Big Rebalance integration (272 buffs + 37 damage profiles + 16 explosion templates + 3 stat-buff application methods) into vanilla tables on every peer in deterministic alphabetical order. The companion Tweaker mods (Tweaker: Weapons, Tweaker: Careers, Tweaker: Enemies) check this flag before their Big Rebalance sub-toggles do any work — leave this OFF if you don't want BR behavior anywhere. All peers in a lobby must match (either everyone has this on, or no one does) to avoid NetworkLookup divergence on buff RPCs. Default OFF (opt-in).",
    },
}
