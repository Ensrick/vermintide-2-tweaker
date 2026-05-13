local mod = get_mod("cim")

-- =========================================================================
-- Custom UI textures shipped with cim. Currently just `icon_bg_modded` —
-- the rarity-background tile drawn behind every modded-rarity item in the
-- inventory grid (registered as UISettings.item_rarity_textures.modded by
-- modded_rarities.lua).
--
-- Renderer creators we inject into: every UI surface that renders inventory
-- icons, so the material is loaded into that renderer's atlas before the
-- icon widget tries to draw with it. Matches the broad list dynamic_cosmetic
-- _portraits uses, since rarity backgrounds appear in identical surfaces.
-- =========================================================================
local _texture_names = {
    "icon_bg_modded",
}

local _renderer_creators = {
    "ingame_ui",                       -- main HUD (in-mission popups)
    "ingame_ui_settings",              -- inner factory for create_ui_renderer
    "hero_view",                       -- keep inventory grid
    "hero_view_state_loot",            -- Spoils of War
    "hero_view_state_store",           -- Lohner's Emporium
    "hero_view_state_weave_forge",     -- Athanor / cim's modded forge
    "start_game_state_settings_overview",
    "level_end_view_base",             -- end-of-mission rewards
    "level_end_view_versus",
    "ui_manager",
}

local function _build_material_paths()
    local out = {}
    for _, name in ipairs(_texture_names) do
        out[#out + 1] = "materials/ui/" .. name
    end
    return out
end

local function _build_injections()
    local material_paths = _build_material_paths()
    local injections = {}
    for _, creator in ipairs(_renderer_creators) do
        local entry = { creator }
        for _, path in ipairs(material_paths) do
            entry[#entry + 1] = path
        end
        injections[#injections + 1] = entry
    end
    return injections
end

return {
    name        = mod:localize("mod_name"),
    description = mod:localize("mod_description"),
    is_togglable = true,
    options = {
        widgets = {
            {
                setting_id = "forge_group",
                type = "group",
                sub_widgets = {
                    {
                        setting_id = "forge_hotkey",
                        type = "keybind",
                        default_value = {"b"},
                        keybind_trigger = "pressed",
                        keybind_type = "function_call",
                        function_name = "open_forge",
                    },
                },
            },
            {
                setting_id = "inventory_group",
                type = "group",
                sub_widgets = {
                    {
                        setting_id = "show_only_modded_weapons",
                        type = "checkbox",
                        default_value = false,
                    },
                    {
                        setting_id = "restore_modded_loadout",
                        type = "checkbox",
                        default_value = true,
                    },
                },
            },
        },
    },

    custom_gui_textures = {
        textures = _texture_names,
        ui_renderer_injections = _build_injections(),
    },
}
