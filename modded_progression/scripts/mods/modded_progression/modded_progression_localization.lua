local function en(s) return { en = s } end

return {
    mod_description = en("Re-enables the normal Vermintide 2 progression systems while you play in the modded realm, so XP, shillings, loot chests, Okri's Challenges, Lohner's Emporium, and the crafting bench all work again. Your progress is saved locally on your PC and your real account is never changed."),

    -- Local Silver Shilling UI (#578). The claimed string deliberately stores
    -- %%d: VMF consumes the first percent during mod:localize, leaving %d for
    -- vanilla's outer string.format in the reward popup.
    mp_local_wallet_prefix = en("[Local]"),
    mp_local_purchase_button = en("Buy with Local Shillings"),
    mp_local_shillings_name = en("Local Silver Shillings"),
    mp_local_shillings_description = en("Silver Shillings stored only by Modded Progression on this PC."),
    mp_local_shillings_obtain = en("Earned and spent only in Modded Progression."),
    mp_local_shillings_claimed = en("%%d Local Silver Shillings added to your modded balance."),

    -- ============================================================
    -- Starting state
    -- ============================================================
    starting_state             = en("[untested] Starting State"),
    starting_state_description = en("How your modded progression begins the first time you play. It is applied only once; to change it later, wipe your local progress with the /mp_reset chat command first."),
    starting_state_tooltip     = en("Choose how your modded progression begins the first time you play. It takes effect only once, so changing it later does nothing unless you first wipe your local progress with the /mp_reset chat command."),
    start_fresh            = en("Fresh (level 1)"),
    start_level_35         = en("Level 35, default inventory"),
    start_level_35_unlocked = en("Level 35, everything unlocked"),

    -- Reset is exposed via the /mp_reset chat command (modded_progression.lua),
    -- which echoes a plain string; there is no settings-UI widget for it, so the
    -- former `reset_progression` / `reset_progression_tooltip` loc keys had no
    -- consumer. Removed as dead leftover (audit 2026-06-07, v0.2.9-dev). If a
    -- reset widget is ever added to the data tree, reintroduce a tooltip key then.

}
