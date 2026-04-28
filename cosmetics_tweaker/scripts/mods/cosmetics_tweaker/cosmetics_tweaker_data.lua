local mod = get_mod("cosmetics_tweaker")
local U = mod:dofile("scripts/mods/cosmetics_tweaker/_cosmetic_unlocks")

local widgets = {
    {
        setting_id  = "appearance_group",
        type        = "group",
        sub_widgets = {
            {
                setting_id  = "weapon_model_group",
                type        = "group",
                sub_widgets = {
                    {
                        setting_id    = "es_bastard_sword_thiccc",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = mod:localize("es_bastard_sword_thiccc_tooltip"),
                    },
                },
            },
            {
                setting_id  = "experimental_tints_group",
                type        = "group",
                sub_widgets = {
                    {
                        setting_id    = "tint_pureheart_white",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = mod:localize("tint_pureheart_white_tooltip"),
                    },
                },
            },
        },
    },
}

-- Append the auto-generated cosmetic-unlock widget tree (Character → Career →
-- Hats/Skins → individual checkboxes). See _cosmetic_unlocks.lua and the python
-- generator that produces it.
for _, w in ipairs(U.widgets) do
    widgets[#widgets + 1] = w
end

return {
    name = "Tweaker: Cosmetics",
    description = mod:localize("mod_description"),
    is_togglable = true,

    options = { widgets = widgets },
}
