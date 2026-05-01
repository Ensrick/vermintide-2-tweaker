local mod = get_mod("cosmetics_tweaker")
local U = mod:dofile("scripts/mods/cosmetics_tweaker/_cosmetic_unlocks")

local loc = {
    mod_description = {
        en = "Cosmetic tweaks: per-career hat/skin unlocks within each character, plus per-weapon scale and grip-offset overrides.",
    },

    dynamic_portraits = {
        en = "New Dynamic Character Portraits for Hats",
    },
    unlock_all_illusions = {
        en = "Unlock All Weapon Illusions (Modded Only)",
    },
    unlock_all_illusions_tooltip = {
        en = "Makes every weapon illusion selectable in the illusion browser. Only works in modded realm — illusion swaps are applied locally for the session.",
    },
    unlock_all_frames = {
        en = "Unlock All Portrait Frames (Modded Only)",
    },
    unlock_all_frames_tooltip = {
        en = "Makes every portrait frame equippable in the cosmetics loadout. Only works in modded realm. Frames from unowned DLC remain locked. Restart after toggling.",
    },
    la_bridge_enable = {
        en = "Loremaster's Armoury: Cosmetics as Separate Items",
    },
    la_bridge_enable_tooltip = {
        en = "Adds every Loremaster's Armoury hat/skin recolor as its OWN inventory item (e.g. Pureheart Helm shows up four times — yellow, white, red, black — instead of LA silently overwriting the vanilla one). Requires Loremaster's Armoury and More Items Library subscribed and enabled. Restart after toggling.",
    },
    dynamic_portraits_tooltip = {
        en = "Swaps character HUD portraits to match equipped headgear. Currently supported: Kruber Mercenary with Marshal Ludenwald's Favourite Hat.",
    },

    appearance_group = {
        en = "Weapon & Item Appearance",
    },
    weapon_model_group = {
        en = "Weapon Model Tweaks",
    },
    experimental_tints_group = {
        en = "Experimental Tints",
    },
    tint_pureheart_white = {
        en = "Pureheart Helm: White Tint (matches GK Purified outfit)",
    },
    tint_pureheart_white_tooltip = {
        en = "Tints Grail Knight's Pureheart Helm white at spawn time. Experimental — depends on which material parameters the hat's shader exposes; if it doesn't visibly change, run `cos probe_hat` and report the material names so the tint param can be adjusted.",
    },

    es_bastard_sword_thiccc = {
        en = "Authentic Bretonian Longsword Thiccccness",
    },
    es_bastard_sword_thiccc_tooltip = {
        en = "Reduces the Bretonian Longsword's X-axis width to 65%% of vanilla so it looks like a proper longsword instead of a slab. Also applies to the sword in Bretonian Sword and Shield (shield unaffected). Affects all wielders.",
    },

    ct_es_mace_gk_shield_01_name = {
        en = "Mace & Bretonnian Shield",
    },
    ct_es_mace_gk_shield_01_description = {
        en = "An Empire mace paired with a Bretonnian shield.",
    },

    ct_we_spear_shield_es_01_name = {
        en = "Empire Spear & Shield",
    },
    ct_we_spear_shield_es_01_description = {
        en = "Kruber's standard Empire spear and shield on Kerillian's Handmaiden.",
    },
    ct_we_spear_shield_es_02_name = {
        en = "Empire Spear & Shield (Ornate)",
    },
    ct_we_spear_shield_es_02_description = {
        en = "Kruber's ornate Empire spear and shield on Kerillian's Handmaiden.",
    },
    ct_we_spear_shield_es_03_name = {
        en = "Empire Spear & Shield (Plumed)",
    },
    ct_we_spear_shield_es_03_description = {
        en = "Kruber's plumed Empire spear and shield on Kerillian's Handmaiden.",
    },

    ct_es_deus_we_01_name = {
        en = "Elven Spear & Shield",
    },
    ct_es_deus_we_01_description = {
        en = "Kerillian's standard elven spear and shield on Kruber.",
    },
    ct_es_deus_we_02_name = {
        en = "Elven Spear & Shield (Exotic)",
    },
    ct_es_deus_we_02_description = {
        en = "Kerillian's exotic elven spear and shield on Kruber.",
    },
}

-- Merge auto-generated cosmetic-unlock localization (group titles + per-item
-- humanized labels for ~1272 toggles). See _cosmetic_unlocks.lua.
for k, v in pairs(U.localization) do
    loc[k] = v
end

return loc
