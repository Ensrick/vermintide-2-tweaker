return {
    mod_name = {
        en = "Crafting in Modded",
    },
    mod_description = {
        en = "Craft any career-eligible weapon with custom properties and traits. Open the Athanor (B hotkey by default) to access the modded crafting UI.",
    },
    forge_group = {
        en = "Athanor (Mod Weapon Crafting)",
    },
    forge_hotkey = {
        en = "Open Athanor Crafting Menu (Keep only)",
    },
    forge_hotkey_description = {
        en = "Opens the Athanor (Winds-of-Magic forge) repurposed as a modded weapon crafting menu. Keep and Chaos Wastes hub only -- the Athanor does not open inside missions (its mid-mission render path still crashes). For in-mission crafting use the Standard Crafting Bench below.",
    },
    standard_crafting_hotkey = {
        en = "Open Standard Crafting Bench",
    },
    standard_crafting_hotkey_description = {
        en = "Opens the standard crafting bench (salvage / craft / re-roll properties + traits / upgrade rarity / apply illusion / convert dust) -- the Keep Smithy, NOT the Athanor. Unlike the Athanor hotkey above, this surface renders cleanly in missions (flat atlas widgets, no preview world). In the Keep it always opens; in a mission it follows the 'Allow in mission' toggle below. Chaos Wastes excluded (loadout-locked). Also available as /cim_craft_standard.",
    },
    allow_in_mission = {
        en = "Allow standard crafting bench in mission",
    },
    allow_in_mission_description = {
        en = "When OFF (default), the standard crafting bench opens only in the Keep and Chaos Wastes hub. When ON, the standard bench (Standard Crafting hotkey / /cim_craft_standard) also opens inside Adventure missions -- it renders cleanly mid-run. The Athanor (weave forge) is always Keep-only and is NOT governed by this toggle (its in-mission render path still crashes).",
    },
    base_power_level = {
        en = "[untested] Base power level for new crafts",
    },
    base_power_level_description = {
        en = "Power level assigned to every weapon / jewelry item crafted from the Athanor or the standard forge. Vanilla weapons cap at 300; Chaos Wastes pickups can boost above. Range 0-950 in steps of 50; default 300.",
    },
    prefill_random_properties = {
        en = "[untested] Pre-fill new crafts with random properties + trait",
    },
    prefill_random_properties_description = {
        en = "OFF (default): freshly-crafted items start bare — no properties, no trait — ready to roll. ON: every craft starts with 2 random max-value properties + 1 random trait (the pre-v0.7.24 behavior).",
    },
    movespeed_2pct_mode = {
        en = "[untested] Movespeed: 5 bubbles at +2%% each (max +10%%)",
    },
    movespeed_2pct_mode_description = {
        en = "OFF (default, matches vanilla): movement speed is 1 bubble = +5%%, capped at +5%%. ON: uncap movement speed to 5 bubbles, each granting +2%% — max +10%%. Costs 5/10 trinket layer slots for the full +10%%, vs 1/10 for the default +5%%.",
    },
    inventory_group = {
        en = "Modded Inventory",
    },
    show_only_modded_weapons = {
        en = "[untested] Show only modded weapons in inventory",
    },
    show_only_modded_weapons_description = {
        en = "Hide vanilla weapons from the inventory and equip screens. Crafting materials and cosmetics are unaffected.",
    },
    persist_modded_loadouts = {
        en = "[untested] Persist modded-crafted weapons across loadouts/sessions",
    },
    persist_modded_loadouts_description = {
        en = "When OFF (default), cim does NOT touch your loadouts — your vanilla player and bot loadouts behave exactly as the base game. Turn ON only if you want cim-CRAFTED weapons to survive relogs (they won't while this is off; re-equip them as needed).",
    },
    persist_modded_loadouts_tooltip = {
        en = "When OFF (default), cim does NOT touch your loadouts — your vanilla player and bot loadouts behave exactly as the base game. Turn ON only if you want cim-CRAFTED weapons to survive relogs (they won't while this is off; re-equip them as needed).",
    },
    restore_modded_loadout = {
        en = "[untested] Restore modded loadout each session",
    },
    restore_modded_loadout_description = {
        en = "Only matters when 'Persist modded-crafted weapons' above is ON. When you start the game in modded realm, automatically re-equip the last modded weapon you had on each (career, slot).",
    },
    import_group = {
        en = "Import",
    },
    saveweapon_import_hotkey = {
        en = "[untested] Import from SaveWeapon",
    },
    saveweapon_import_hotkey_description = {
        en = "Press the assigned key (or run /cim_import_saved_weapons) to pull every weapon you saved with the SaveWeapon mod into your cim modded inventory. Idempotent — re-running skips items that already match. Items locked behind unowned DLC are skipped automatically.",
    },
}
