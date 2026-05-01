local mod = get_mod("cosmetics_tweaker")
local U = mod:dofile("scripts/mods/cosmetics_tweaker/_cosmetic_unlocks")

local widgets = {
    {
        setting_id    = "dynamic_portraits",
        type          = "checkbox",
        default_value = true,
        tooltip       = mod:localize("dynamic_portraits_tooltip"),
    },
    {
        setting_id    = "unlock_all_illusions",
        type          = "checkbox",
        default_value = false,
        tooltip       = mod:localize("unlock_all_illusions_tooltip"),
    },
    {
        setting_id    = "unlock_all_frames",
        type          = "checkbox",
        default_value = false,
        tooltip       = mod:localize("unlock_all_frames_tooltip"),
    },
    {
        setting_id    = "la_bridge_enable",
        type          = "checkbox",
        default_value = false,
        tooltip       = mod:localize("la_bridge_enable_tooltip"),
    },
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

local data = {
    name = "Tweaker: Cosmetics",
    description = mod:localize("mod_description"),
    is_togglable = true,

    options = { widgets = widgets },

    custom_gui_textures = {
        textures = {
            "portrait_kruber_mercenary_hat_0004",
            "medium_portrait_kruber_mercenary_hat_0004",
            "small_portrait_kruber_mercenary_hat_0004",
            "portrait_kruber_mercenary_hat_0009",
            "medium_portrait_kruber_mercenary_hat_0009",
            "small_portrait_kruber_mercenary_hat_0009",
            "portrait_kruber_mercenary_hat_1001",
            "medium_portrait_kruber_mercenary_hat_1001",
            "small_portrait_kruber_mercenary_hat_1001",
            "portrait_kruber_mercenary_hat_1002",
            "medium_portrait_kruber_mercenary_hat_1002",
            "small_portrait_kruber_mercenary_hat_1002",
            "portrait_kruber_mercenary_hat_1003",
            "medium_portrait_kruber_mercenary_hat_1003",
            "small_portrait_kruber_mercenary_hat_1003",
            "portrait_kruber_mercenary_hat_0007",
            "medium_portrait_kruber_mercenary_hat_0007",
            "small_portrait_kruber_mercenary_hat_0007",
            "portrait_kruber_mercenary_hat_0006",
            "medium_portrait_kruber_mercenary_hat_0006",
            "small_portrait_kruber_mercenary_hat_0006",
        },
        ui_renderer_injections = {
            {
                "ingame_ui",
                "materials/ui/portrait_kruber_mercenary_hat_0004",
                "materials/ui/medium_portrait_kruber_mercenary_hat_0004",
                "materials/ui/small_portrait_kruber_mercenary_hat_0004",
                "materials/ui/portrait_kruber_mercenary_hat_0009",
                "materials/ui/medium_portrait_kruber_mercenary_hat_0009",
                "materials/ui/small_portrait_kruber_mercenary_hat_0009",
                "materials/ui/portrait_kruber_mercenary_hat_1001",
                "materials/ui/medium_portrait_kruber_mercenary_hat_1001",
                "materials/ui/small_portrait_kruber_mercenary_hat_1001",
                "materials/ui/portrait_kruber_mercenary_hat_1002",
                "materials/ui/medium_portrait_kruber_mercenary_hat_1002",
                "materials/ui/small_portrait_kruber_mercenary_hat_1002",
                "materials/ui/portrait_kruber_mercenary_hat_1003",
                "materials/ui/medium_portrait_kruber_mercenary_hat_1003",
                "materials/ui/small_portrait_kruber_mercenary_hat_1003",
                "materials/ui/portrait_kruber_mercenary_hat_0007",
                "materials/ui/medium_portrait_kruber_mercenary_hat_0007",
                "materials/ui/small_portrait_kruber_mercenary_hat_0007",
                "materials/ui/portrait_kruber_mercenary_hat_0006",
                "materials/ui/medium_portrait_kruber_mercenary_hat_0006",
                "materials/ui/small_portrait_kruber_mercenary_hat_0006",
            },
        },
    },
}

mod:info("[data] returning with custom_gui_textures=%s, textures=%d, injections=%d",
    tostring(data.custom_gui_textures ~= nil),
    data.custom_gui_textures and #data.custom_gui_textures.textures or 0,
    data.custom_gui_textures and #data.custom_gui_textures.ui_renderer_injections or 0)

return data
