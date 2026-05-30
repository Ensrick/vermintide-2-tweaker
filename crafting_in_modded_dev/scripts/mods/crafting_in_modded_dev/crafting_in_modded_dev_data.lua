local mod = get_mod("cim_dev")

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
                    -- Default OFF. Vanilla `HeroViewStateWeaveForge` was never
                    -- expected to run mid-mission and several code paths fault
                    -- (gamepad cursor renderer, shading_environment loads). The
                    -- v0.7.13/.14 hooks catch the known crashes but new ones
                    -- keep surfacing. While off, the keybind silently no-ops
                    -- outside the Keep; opt-in if you want to test in-mission
                    -- and report crash logs.
                    {
                        setting_id = "allow_in_mission",
                        type = "checkbox",
                        default_value = false,
                    },
                    -- Base power level applied to every freshly-crafted item.
                    -- Vanilla weapons cap at 300; CW boosts apply on top. 0-950
                    -- in steps of 50 covers the range the user might want.
                    --
                    -- `unit_text` intentionally omitted — VMF treats an empty
                    -- string as a loc key and renders the unresolved-key
                    -- placeholder "< >" next to the value. No unit needed for
                    -- a bare power-level number.
                    {
                        setting_id = "base_power_level",
                        type = "numeric",
                        default_value = 300,
                        range = {0, 950},
                        decimals_number = 0,
                    },
                    -- When OFF (default), new crafts start with NO properties
                    -- and NO trait — bare 300-power template ready for the user
                    -- to roll. When ON, restore the pre-v0.7.24 behavior of
                    -- pre-seeding 2 max-value properties + 1 random trait.
                    {
                        setting_id = "prefill_random_properties",
                        type = "checkbox",
                        default_value = false,
                    },
                    -- Movespeed trade-off mode. OFF (default, vanilla):
                    --   1 bubble = +5% movement speed, capped at 1 bubble.
                    -- ON: movespeed uncaps to 5 bubbles, each +2% movespeed.
                    --   Max = +10% at a cost of 5/10 of the trinket's bubble
                    --   layer (vs. 1/10 for +5% in default mode). For players
                    --   who'd trade other trinket properties for raw speed.
                    {
                        setting_id = "movespeed_2pct_mode",
                        type = "checkbox",
                        default_value = false,
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
            {
                setting_id = "import_group",
                type = "group",
                sub_widgets = {
                    -- Bindable hotkey for the SaveWeapon importer. Default
                    -- unbound; the chat command `/cim_import_saved_weapons`
                    -- is the primary trigger. Set a key if you want a one-
                    -- press shortcut from the keep.
                    {
                        setting_id = "saveweapon_import_hotkey",
                        type = "keybind",
                        default_value = {},
                        keybind_trigger = "pressed",
                        keybind_type = "function_call",
                        function_name = "_cim_saveweapon_import",
                    },
                },
            },
            -- Universal Debug Logging toggle (PROJECT_STANDARDS.md § 3.6).
            -- v0.7.37-alpha: renamed from `debug_mode` (was nested in
            -- `debug_group`) to the universal `enable_debug_logging` key,
            -- un-nested to top-level at the BOTTOM of the widget tree.
            -- Equivalent behavior: gates the curated set of diagnostic auto-
            -- dumps (forge open, Athanor open, customization menu open,
            -- salvage page open, restore-pass completion) at `mod:info` level.
            {
                setting_id    = "enable_debug_logging",
                type          = "checkbox",
                default_value = false,
                tooltip       = mod:localize("enable_debug_logging_tooltip"),
            },
        },
    },

    custom_gui_textures = {
        textures = _texture_names,
        ui_renderer_injections = _build_injections(),
    },
}
