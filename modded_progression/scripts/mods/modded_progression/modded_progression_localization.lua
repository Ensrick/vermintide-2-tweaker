local function en(s) return { en = s } end

return {
    mod_description = en("Re-enables vanilla VT2 progression systems in the modded realm. XP, shillings, loot chests, Okri's Challenges, Lohner's Emporium, crafting bench — all working, all persisted locally, real PlayFab account never touched."),

    -- ============================================================
    -- Starting state
    -- ============================================================
    starting_state             = en("Starting State"),
    starting_state_description = en("Chosen at first launch; takes effect ONCE per local store. Re-applies only after a manual /mp_reset."),
    starting_state_tooltip     = en("How your modded progression begins on first launch. Only applied ONCE — the chosen seed is locked in, and changing this later only takes effect after a manual reset.\n\n• Fresh (level 1): Brand-new player feel — 0 XP, default starter weapons, 0 currency.\n• Level 35, default inventory: Career-capped, default weapons, 0 currency. Grind cosmetics from scratch.\n• Level 35, everything unlocked: Sandbox — career-capped, all cosmetic unlocks, one of every craftable item, sane starting currency."),
    start_fresh            = en("Fresh (level 1)"),
    start_level_35         = en("Level 35, default inventory"),
    start_level_35_unlocked = en("Level 35, everything unlocked"),

    -- ============================================================
    -- Reset
    -- ============================================================
    reset_progression         = en("Reset Modded Progression"),
    reset_progression_tooltip = en("Wipe all locally-stored modded progression: XP, currency, items, unlocks, claimed challenges. Next game launch will re-apply the chosen starting state. Does not affect your real PlayFab account."),
}
