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

-- =========================================================================
-- Issue #96 epilogue (2026-07-02, user direction): the "Allow standard crafting
-- bench in mission" WIDGET no longer lives in cim at all. The option moved to
-- gut's "In-Mission Menus" group (shown there only when cim is installed - the
-- same conditional-build pattern this file used to carry); gut writes through to
-- cim's `allow_in_mission` SETTING, which the main-lua readers still honor
-- unchanged (crafting_in_modded_dev.lua ~:1920). The former `_gut_present()`
-- helper + prune machinery are gone with the widget.

local options_data = {
    name        = mod:localize("mod_name"),
    description = mod:localize("mod_description"),
    is_togglable = true,
    options = {
        -- Top-level groups sorted A->Z by display label: Athanor (forge_group),
        -- Import (import_group), Modded Inventory (inventory_group).
        widgets = {
            {
                setting_id = "forge_group",
                type = "group",
                -- forge_group children use a deliberate functional order (NOT
                -- A->Z): the two crafting-menu hotkeys first, then the
                -- in-mission permission they honor, then the craft-output
                -- tuning toggles.
                sub_widgets = {
                    {
                        setting_id = "forge_hotkey",
                        type = "keybind",
                        default_value = {"b"},
                        keybind_trigger = "pressed",
                        keybind_type = "function_call",
                        function_name = "open_forge",
                    },
                    -- Standard crafting bench (Keep Smithy) hotkey. Opens the
                    -- VANILLA salvage / craft / re-roll / upgrade / apply-illusion
                    -- bench. Unlike the Athanor (forge_hotkey above), this surface
                    -- is material-clean in adventure missions — it draws flat atlas
                    -- widgets with no preview world or inn-only shading. Default
                    -- unbound (the /cim_craft_standard chat command is the primary
                    -- trigger). In the Keep it always opens; in a mission it honors
                    -- the same 'Allow in mission' toggle below.
                    {
                        setting_id = "standard_crafting_hotkey",
                        type = "keybind",
                        default_value = {},
                        keybind_trigger = "pressed",
                        keybind_type = "function_call",
                        function_name = "open_standard_crafting",
                    },
                    -- (The "Allow standard crafting bench in mission" checkbox
                    -- lived here until 2026-07-02; the option now lives in gut's
                    -- In-Mission Menus group, which writes through to cim's
                    -- `allow_in_mission` setting - see the #96 epilogue above.)
                    -- Default-on quality-of-life: equip the exact weapon a
                    -- successful craft just created into the primary/secondary
                    -- slot selected by that craft surface. Jewelry is excluded.
                    {
                        setting_id = "auto_equip_new_weapons",
                        type = "checkbox",
                        default_value = true,
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
                    -- Feature toggles for what the forge lets you put on a craft.
                    -- Both default OFF so the forge behaves exactly as before
                    -- unless the user opts in.
                    --
                    -- allow_cw_traits: normally the standard bench mirrors the
                    -- official forge and drops the Chaos Wastes / deus "boon"
                    -- traits (crafting_disabled=true, e.g. deus_extra_shot,
                    -- shield_splinters). ON surfaces those boon traits so you can
                    -- roll / pick them on crafted weapons. Traits only; does not
                    -- touch properties.
                    {
                        setting_id = "allow_cw_traits",
                        type = "checkbox",
                        default_value = false,
                    },
                    -- allow_any_trait_property: normally a weapon can only receive
                    -- traits/properties from its own slot pool (a melee weapon gets
                    -- melee traits, etc.). ON pools EVERY trait and EVERY property
                    -- across all slot types onto any craftable item. Supersedes
                    -- allow_cw_traits (its union already includes the boon traits).
                    {
                        setting_id = "allow_any_trait_property",
                        type = "checkbox",
                        default_value = false,
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
            {
                setting_id = "inventory_group",
                type = "group",
                -- Children A->Z by display label: "Ignore items from inactive
                -- mods" before "Show only modded weapons".
                sub_widgets = {
                    -- Loadout persistence toggles (persist_modded_loadouts /
                    -- restore_modded_loadout) REMOVED 2026-06-30: the feature
                    -- never worked reliably and a proper loadout system is being
                    -- built in Tweaker: GUI (gut). cim no longer surfaces these
                    -- and force-disables the machinery at load (see the master
                    -- gate in crafting_in_modded_dev.lua).
                    -- When ON, saved crafts whose source mod isn't currently
                    -- active are skipped SILENTLY (logged via mod:info, not
                    -- echoed to chat). The deferred-injection retry still runs,
                    -- so a craft auto-recovers if the user re-enables its mod;
                    -- only the chat announcement is suppressed. DEFAULT OFF to
                    -- preserve the existing "N saved crafts deferred" feedback.
                    {
                        setting_id = "ignore_unloadable_items",
                        type = "checkbox",
                        default_value = false,
                        tooltip = "ignore_unloadable_items_description",
                    },
                    {
                        setting_id = "show_only_modded_weapons",
                        type = "checkbox",
                        default_value = false,
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

return options_data
