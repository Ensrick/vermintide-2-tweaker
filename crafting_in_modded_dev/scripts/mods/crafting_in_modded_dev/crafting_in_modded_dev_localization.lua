return {
    mod_name = {
        en = "Crafting in Modded",
    },
    mod_description = {
        en = "Craft any weapon your career can use, with the properties and traits you choose. Open the Athanor (B key by default) to reach the modded crafting menu.",
    },
    ranalds_opener = { en = "COMMUNITY BUILDS" },
    ranalds_title = { en = "RANALD'S GIFT COMMUNITY BUILDS" },
    ranalds_career_prev = { en = "< CAREER" },
    ranalds_career_next = { en = "CAREER >" },
    ranalds_sort_likes = { en = "SORT: LIKES" },
    ranalds_sort_recent = { en = "SORT: RECENT" },
    ranalds_page_prev = { en = "< PAGE" },
    ranalds_page_next = { en = "PAGE >" },
    ranalds_page_label = { en = "PAGE %d / %d" },
    ranalds_import = { en = "IMPORT SELECTED BUILD" },
    ranalds_loading = { en = "Loading community builds..." },
    ranalds_load_failed = { en = "Could not load builds: %s" },
    ranalds_request_failed = { en = "Could not start request: %s" },
    ranalds_loaded = { en = "Loaded %d community build(s)" },
    ranalds_ignored = { en = "; ignored %d malformed" },
    ranalds_bounded = { en = "; showing the bounded first 800" },
    ranalds_row = { en = "%s\nby %s  |  Likes %d  |  %s" },
    ranalds_unknown_date = { en = "Unknown date" },
    ranalds_importing = { en = "Importing %s..." },
    ranalds_import_failed = { en = "Import failed safely: %s" },
    ranalds_import_rejected = { en = "Import rejected: %s" },
    ranalds_imported = { en = "Imported and equipped: %s" },
    forge_group = {
        en = "Athanor (Mod Weapon Crafting)",
    },
    forge_hotkey = {
        en = "Open Athanor Crafting Menu",
    },
    forge_hotkey_description = {
        en = "Opens the Athanor (the Winds of Magic forge) as a modded weapon crafting menu. Always works in the Keep and the Chaos Wastes hub. Inside missions it follows the 'Allow crafting bench in mission' option in Tweaker: GUI's In-Mission Menus, the same toggle the Standard Crafting Bench uses.",
    },
    standard_crafting_hotkey = {
        en = "Open Standard Crafting Bench",
    },
    standard_crafting_hotkey_description = {
        en = "Opens the standard Keep Smithy bench: salvage, craft, re-roll properties and traits, upgrade rarity, apply illusions, convert dust (not the Athanor). Works in the Keep and the Chaos Wastes; inside missions it follows the 'Allow crafting bench in mission' option in Tweaker: GUI's In-Mission Menus. You can also run /cim_craft_standard.",
    },
    auto_equip_new_weapons = {
        en = "Automatically equip newly crafted weapons",
    },
    auto_equip_new_weapons_description = {
        en = "ON (default): after a weapon is crafted successfully, equip that exact new item in the primary or secondary slot used to craft it. OFF: leave new weapons in the inventory without changing your equipped loadout. Accessories are unaffected.",
    },
    -- (allow_in_mission / allow_in_mission_description removed 2026-07-02: the
    -- widget moved to gut's In-Mission Menus group; gut writes through to cim's
    -- setting, so the main-lua readers are unchanged.)
    base_power_level = {
        en = "Base power level for new crafts",
    },
    base_power_level_description = {
        en = "Power level given to every weapon and jewelry item you craft at the Athanor or the standard bench (0 to 950 in steps of 50, default 300). Normal weapons cap at 300, though Chaos Wastes pickups can push higher.",
    },
    prefill_random_properties = {
        en = "Pre-fill new crafts with random properties + trait",
    },
    prefill_random_properties_description = {
        en = "OFF (default): freshly crafted items start bare, with no properties or trait, ready for you to roll. ON: every craft starts with 2 random top-value properties and 1 random trait.",
    },
    movespeed_2pct_mode = {
        en = "Movespeed: 5 bubbles at +2%% each (max +10%%)",
    },
    movespeed_2pct_mode_description = {
        en = "OFF (default): the movement speed property gives +5%% and fills 1 bubble. ON: it can reach 5 bubbles at +2%% each for up to +10%%, but the full +10%% uses 5 of the trinket's 10 property slots instead of 1.",
    },
    allow_cw_traits = {
        en = "Allow Chaos Wastes traits on crafted weapons",
    },
    allow_cw_traits_description = {
        en = "OFF (default): the forge hides the Chaos Wastes boon traits (like the extra-shot, shield-splinters and chain-lightning traits) that the normal crafting bench never offers. ON: slot-eligible boon traits become available to weapons you craft; melee-only and ranged-only traits stay in their vanilla weapon family. Affects traits only, not properties.",
    },
    allow_any_trait_property = {
        en = "Allow any trait and property on any weapon",
    },
    allow_any_trait_property_description = {
        en = "OFF (default): a crafted item can only take traits and properties from its own type (a melee weapon gets melee traits, a necklace gets necklace traits, and so on). ON: every trait and every property becomes available on any weapon or accessory you craft. Includes the Chaos Wastes traits, so this covers the option above.",
    },
    inventory_group = {
        en = "Modded Inventory",
    },
    show_only_modded_weapons = {
        en = "Show only modded weapons in inventory",
    },
    show_only_modded_weapons_description = {
        en = "Hides normal weapons from your inventory and equip screens, leaving only modded ones. Crafting materials and cosmetics are unaffected.",
    },
    -- persist_modded_loadouts / restore_modded_loadout loc entries REMOVED
    -- 2026-06-30 with the toggles (loadout persistence moved to Tweaker: GUI).
    ignore_unloadable_items = {
        en = "Ignore items from inactive mods (no chat spam)",
    },
    ignore_unloadable_items_description = {
        en = "When ON, saved crafts that need an item from a mod you no longer have active are skipped quietly, without the usual chat messages. They return automatically if you re-enable that mod.",
    },
    import_group = {
        en = "Import",
    },
    saveweapon_import_hotkey = {
        en = "Import from SaveWeapon",
    },
    saveweapon_import_hotkey_description = {
        en = "Press the assigned key (or run /cim_import_saved_weapons) to bring every weapon saved with the SaveWeapon mod into your modded inventory. Running it again skips anything already imported, and items from DLC you do not own are left out.",
    },
}
