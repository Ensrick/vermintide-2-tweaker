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
        en = "Open Crafting Menu",
    },
    forge_hotkey_description = {
        en = "Opens the Athanor (Winds-of-Magic forge) repurposed as a modded weapon crafting menu. Disabled outside the Keep and Chaos Wastes hub unless 'Allow in mission' below is enabled.",
    },
    allow_in_mission = {
        en = "Allow forge hotkey in mission (may crash)",
    },
    allow_in_mission_description = {
        en = "When OFF (default), the forge hotkey only opens in the Keep and Chaos Wastes hub. When ON, the hotkey also works inside missions — useful for testing builds mid-run, but known to crash on some setups. If you turn this on, please share any crash logs.",
    },
    base_power_level = {
        en = "Base power level for new crafts",
    },
    base_power_level_description = {
        en = "Power level assigned to every weapon / jewelry item crafted from the Athanor or the standard forge. Vanilla weapons cap at 300; Chaos Wastes pickups can boost above. Range 0-950 in steps of 50; default 300.",
    },
    prefill_random_properties = {
        en = "Pre-fill new crafts with random properties + trait",
    },
    prefill_random_properties_description = {
        en = "OFF (default): freshly-crafted items start bare — no properties, no trait — ready to roll. ON: every craft starts with 2 random max-value properties + 1 random trait (the pre-v0.7.24 behavior).",
    },
    movespeed_2pct_mode = {
        en = "Movespeed: 5 bubbles at +2%% each (max +10%%)",
    },
    movespeed_2pct_mode_description = {
        en = "OFF (default, matches vanilla): movement speed is 1 bubble = +5%%, capped at +5%%. ON: uncap movement speed to 5 bubbles, each granting +2%% — max +10%%. Costs 5/10 trinket layer slots for the full +10%%, vs 1/10 for the default +5%%.",
    },
    inventory_group = {
        en = "Modded Inventory",
    },
    show_only_modded_weapons = {
        en = "Show only modded weapons in inventory",
    },
    show_only_modded_weapons_description = {
        en = "Hide vanilla weapons from the inventory and equip screens. Crafting materials and cosmetics are unaffected.",
    },
    restore_modded_loadout = {
        en = "Restore modded loadout each session",
    },
    restore_modded_loadout_description = {
        en = "When you start the game in modded realm, automatically re-equip the last modded weapon you had on each (career, slot). Without this, switching to vanilla and back can wipe your modded loadout.",
    },
    import_group = {
        en = "Import",
    },
    saveweapon_import_hotkey = {
        en = "Import from SaveWeapon",
    },
    saveweapon_import_hotkey_description = {
        en = "Press the assigned key (or run /cim_import_saved_weapons) to pull every weapon you saved with the SaveWeapon mod into your cim modded inventory. Idempotent — re-running skips items that already match. Items locked behind unowned DLC are skipped automatically.",
    },
    -- Universal Debug Logging toggle (PROJECT_STANDARDS.md § 3.6).
    -- v0.7.37-alpha: renamed from `debug_mode` (was nested in `debug_group`)
    -- to the universal `enable_debug_logging` key.
    enable_debug_logging = {
        en = "Debug Logging",
    },
    enable_debug_logging_tooltip = {
        en = "Emit detailed diagnostic logs to %%APPDATA%%\\Fatshark\\Vermintide 2\\console_logs\\. Increases log volume; enable when investigating a bug, then disable.",
    },
}
