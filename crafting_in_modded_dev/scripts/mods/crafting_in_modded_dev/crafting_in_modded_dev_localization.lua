return {
    mod_name = {
        en = "Crafting in Modded",
    },
    mod_description = {
        en = "Craft any weapon your career can use, with the properties and traits you choose. Open the Athanor (B key by default) to reach the modded crafting menu.",
    },
    forge_group = {
        en = "Athanor (Mod Weapon Crafting)",
    },
    forge_hotkey = {
        en = "Open Athanor Crafting Menu (Keep only)",
    },
    forge_hotkey_description = {
        en = "Opens the Athanor (the Winds of Magic forge) as a modded weapon crafting menu. Works in the Keep and the Chaos Wastes hub only, not inside missions; for in-mission crafting use the Standard Crafting Bench below.",
    },
    standard_crafting_hotkey = {
        en = "Open Standard Crafting Bench",
    },
    standard_crafting_hotkey_description = {
        en = "Opens the standard Keep Smithy bench: salvage, craft, re-roll properties and traits, upgrade rarity, apply illusions, convert dust (not the Athanor). Works in the Keep and the Chaos Wastes, and follows the 'Allow in mission' toggle below inside missions; you can also run /cim_craft_standard.",
    },
    allow_in_mission = {
        en = "Allow standard crafting bench in mission",
    },
    allow_in_mission_description = {
        en = "OFF (default): the standard crafting bench does not open during missions. ON: it also opens inside Adventure missions; the Athanor stays Keep-only either way.",
    },
    base_power_level = {
        en = "[untested] Base power level for new crafts",
    },
    base_power_level_description = {
        en = "Power level given to every weapon and jewelry item you craft at the Athanor or the standard bench (0 to 950 in steps of 50, default 300). Normal weapons cap at 300, though Chaos Wastes pickups can push higher.",
    },
    prefill_random_properties = {
        en = "[untested] Pre-fill new crafts with random properties + trait",
    },
    prefill_random_properties_description = {
        en = "OFF (default): freshly crafted items start bare, with no properties or trait, ready for you to roll. ON: every craft starts with 2 random top-value properties and 1 random trait.",
    },
    movespeed_2pct_mode = {
        en = "[untested] Movespeed: 5 bubbles at +2%% each (max +10%%)",
    },
    movespeed_2pct_mode_description = {
        en = "OFF (default): the movement speed property gives +5%% and fills 1 bubble. ON: it can reach 5 bubbles at +2%% each for up to +10%%, but the full +10%% uses 5 of the trinket's 10 property slots instead of 1.",
    },
    inventory_group = {
        en = "Modded Inventory",
    },
    show_only_modded_weapons = {
        en = "[untested] Show only modded weapons in inventory",
    },
    show_only_modded_weapons_description = {
        en = "Hides normal weapons from your inventory and equip screens, leaving only modded ones. Crafting materials and cosmetics are unaffected.",
    },
    -- persist_modded_loadouts / restore_modded_loadout loc entries REMOVED
    -- 2026-06-30 with the toggles (loadout persistence moved to Tweaker: GUI).
    ignore_unloadable_items = {
        en = "[untested] Ignore items from inactive mods (no chat spam)",
    },
    ignore_unloadable_items_description = {
        en = "When ON, saved crafts that need an item from a mod you no longer have active are skipped quietly, without the usual chat messages. They return automatically if you re-enable that mod.",
    },
    import_group = {
        en = "Import",
    },
    saveweapon_import_hotkey = {
        en = "[untested] Import from SaveWeapon",
    },
    saveweapon_import_hotkey_description = {
        en = "Press the assigned key (or run /cim_import_saved_weapons) to bring every weapon saved with the SaveWeapon mod into your modded inventory. Running it again skips anything already imported, and items from DLC you do not own are left out.",
    },
}
