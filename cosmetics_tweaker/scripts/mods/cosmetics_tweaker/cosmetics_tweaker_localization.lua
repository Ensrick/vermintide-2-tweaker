local mod = get_mod("cosmetics_tweaker")
local U = mod:dofile("scripts/mods/cosmetics_tweaker/_cosmetic_unlocks")

local loc = {
    mod_description = {
        en = "Cosmetic tweaks: per-career hat/skin unlocks within each character, plus per-weapon scale and grip-offset overrides.",
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

    appearance_group = {
        en = "Weapon & Item Appearance",
    },
    cosmetic_availability_group = {
        en = "Cosmetic Availability",
    },
    weapon_model_group = {
        en = "Weapon Model Tweaks",
    },
es_bastard_sword_thiccc = {
        en = "Authentic Bretonian Longsword Thiccccness",
    },
    es_bastard_sword_thiccc_tooltip = {
        en = "Reduces the Bretonian Longsword's X-axis width to 65%% of vanilla so it looks like a proper longsword instead of a slab. Also applies to the sword in Bretonian Sword and Shield (shield unaffected). Affects all wielders.",
    },

    glow_override_group = {
        en = "Weapon Glow Override",
    },
    glow_override_enable = {
        en = "Override Weapon Glow Color",
    },
    glow_override_enable_tooltip = {
        en = "Repaints emissive runes/edges/animated glow on weapons. Covers rune-glow Veteran weapons (themed AND loot-chest white-glow), Weavebound (Winds of Magic), and Shyish-Infused (Versus rewards) — all routed through the same color picker. Takes effect on the next weapon spawn — re-apply a cosmetic / re-equip in the loadout to see a new color on a currently-equipped weapon.",
    },
    glow_override_preset = {
        en = "Glow Color",
    },
    glow_override_preset_tooltip = {
        en = "Color applied to glow-capable weapons when the override above is enabled.",
    },
    glow_preset_default = { en = "Default (no override)" },
    glow_preset_white   = { en = "White"  },
    glow_preset_purple  = { en = "Purple" },
    glow_preset_gold    = { en = "Gold"   },
    glow_preset_red     = { en = "Red"    },
    glow_preset_green   = { en = "Green"  },
    glow_preset_blue    = { en = "Blue"   },

    glow_advanced_group = {
        en = "Advanced: Per-Channel (Magic family)",
    },
    glow_mult_master = {
        en = "Master Brightness ×",
    },
    glow_mult_master_tooltip = {
        en = "Multiplier applied to ALL channels' brightness (1.0 = no change). Set above 1 to brighten everything, below 1 to dim. Useful for taming over-bright bloom on multi-channel weapons.",
    },
    glow_per_channel_color_enable = {
        en = "Use Per-Channel Colors (Magic family)",
    },
    glow_per_channel_color_enable_tooltip = {
        en = "When OFF (default), magic-family weapons (Weavebound + Shyish-Infused) use the main Glow Color above for all channels. When ON, the three pickers below drive each visual element separately: Lower Gradient (color_glow_high+low), Upper Gradient (color_smoke_high+low), and Dots (color_dots). Standard rune-family glowy weapons always use the main Glow Color regardless of this toggle — they only have one channel.",
    },
    glow_color_lower_gradient = {
        en = "Lower Gradient Color",
    },
    glow_color_lower_gradient_tooltip = {
        en = "Color for the LOWER part of the visible gradient on Weavebound (`_magic_01`) and Shyish-Infused (`_magic_02`) weapons (drives color_glow_high + color_glow_low). Only takes effect when 'Use Per-Channel Colors' is enabled.",
    },
    glow_color_upper_gradient = {
        en = "Upper Gradient Color",
    },
    glow_color_upper_gradient_tooltip = {
        en = "Color for the UPPER part of the visible gradient on `_magic_*` weapons (drives color_smoke_high + color_smoke_low). Only takes effect when 'Use Per-Channel Colors' is enabled.",
    },
    glow_color_dots = {
        en = "Dots Color",
    },
    glow_color_dots_tooltip = {
        en = "Color for the dots/particle layer on `_magic_*` weapons (drives color_dots). Only takes effect when 'Use Per-Channel Colors' is enabled AND Dots Brightness × is above 0.",
    },
    glow_mult_rune = {
        en = "Rune Emissive (themed + Stylish) ×",
    },
    glow_mult_rune_tooltip = {
        en = "Brightness multiplier for `rune_emissive_color`. Drives the glow on themed Veteran weapons (`_runed_02..06`) AND Stylish loot-chest white-glow weapons (`_runed_01`). Set to 0 to skip — leaves whatever vanilla wrote (or the mesh's baked default for Stylish).",
    },
    glow_mult_glow_high = {
        en = "Glow High (Magic — lower gradient) ×",
    },
    glow_mult_glow_high_tooltip = {
        en = "Brightness multiplier for `color_glow_high`. Drives the LOWER part of the visible gradient on Weavebound (`_magic_01`) and Shyish-Infused (`_magic_02`) weapons (per probe v0.8.22). Set to 0 to skip.",
    },
    glow_mult_glow_low = {
        en = "Glow Low (Magic — lower gradient) ×",
    },
    glow_mult_glow_low_tooltip = {
        en = "Brightness multiplier for `color_glow_low`. Pairs with Glow High to drive the lower gradient on `_magic_*` weapons. Set to 0 to skip.",
    },
    glow_mult_smoke_high = {
        en = "Smoke High (Magic — upper gradient) ×",
    },
    glow_mult_smoke_high_tooltip = {
        en = "Brightness multiplier for `color_smoke_high`. Drives the UPPER part of the visible gradient on `_magic_*` weapons (per probe v0.8.22). Set to 0 to skip.",
    },
    glow_mult_smoke_low = {
        en = "Smoke Low (Magic — upper gradient) ×",
    },
    glow_mult_smoke_low_tooltip = {
        en = "Brightness multiplier for `color_smoke_low`. Pairs with Smoke High to drive the upper gradient on `_magic_*` weapons. Set to 0 to skip.",
    },
    glow_mult_dots = {
        en = "Dots Particles (Magic — experimental) ×",
    },
    glow_mult_dots_tooltip = {
        en = "Brightness multiplier for `color_dots`. Probe (v0.8.22) showed this channel DARKENS Weavebound when set high and has unclear effect on Shyish-Infused. Default 0 (skip — preserves vanilla's value on Shyish, no effect on Weavebound). Set above 0 to experiment.",
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
