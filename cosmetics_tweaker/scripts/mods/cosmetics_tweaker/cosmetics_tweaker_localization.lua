local mod = get_mod("cosmetics_tweaker")
local U = mod:dofile("scripts/mods/cosmetics_tweaker/_cosmetic_unlocks")

local loc = {
    mod_description = {
        en = "Cosmetic tweaks: per-career hat/skin unlocks within each character, plus per-weapon scale and grip-offset overrides.",
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
        en = "Reduces the Bretonian Longsword's X-axis width to 65% of vanilla so it looks like a proper longsword instead of a slab. Also applies to the sword in Bretonian Sword and Shield (shield unaffected). Affects all wielders.",
    },
}

-- Merge auto-generated cosmetic-unlock localization (group titles + per-item
-- humanized labels for ~1272 toggles). See _cosmetic_unlocks.lua.
for k, v in pairs(U.localization) do
    loc[k] = v
end

return loc
