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
-- Issue #96: the "Allow standard crafting bench in mission" option only does
-- something useful when GUI Tweaker (gut) is present (gut supplies the
-- in-mission menu access cim's standard bench rides on), so the widget is
-- HIDDEN when gut isn't installed.
--
-- VMF has NO native conditional-visibility / mod-dependency widget field
-- (verified against upstream vmf/.../core/options.lua: the validated checkbox
-- fields are setting_id/type/title/tooltip/default_value/localize/is_collapsed;
-- the only conditional feature is dropdown `show_widgets`, which keys off a
-- dropdown VALUE, not mod presence). So we gate by conditionally BUILDING the
-- widget tree — the `allow_in_mission` entry is pruned below before the data
-- table is returned when gut is absent.
--
-- Load-order safety (the footgun): `get_mod("gut")` is just `_mods["gut"]` and
-- returns nil if gut hasn't run its `new_mod` yet — VMF unfolds this data table
-- IMMEDIATELY at cim's registration (not lazily), so if cim loads before gut,
-- a bare get_mod check would wrongly hide the widget. The load-order-INDEPENDENT
-- signal is the engine ModManager's mod table (`Managers.mod._mods`), which is
-- built once from the user's full enabled-mod list at scan time BEFORE any mod's
-- Lua runs (mod_manager.lua:278-343; each entry carries `name` = Workshop title
-- + `enabled`). We check both: the fast get_mod path (gut already loaded) OR an
-- enabled ModManager entry whose Workshop title is gut's ("Tweaker: GUI",
-- covering gut and gut_dev) — so presence is detected regardless of load order.
local function _gut_present()
    -- Fast path: gut (or its dev clone) already registered with VMF.
    if get_mod("gut") or get_mod("gut_dev") then
        return true
    end
    -- Load-order-safe path: scan the engine's enabled-mod manifest by name.
    local mod_mgr = rawget(_G, "Managers") and Managers.mod
    local mods = mod_mgr and mod_mgr._mods
    if type(mods) == "table" then
        for i = 1, (mod_mgr._num_mods or #mods) do
            local entry = mods[i]
            if entry and entry.enabled and type(entry.name) == "string"
               and entry.name:find("Tweaker: GUI", 1, true) then
                return true
            end
        end
    end
    return false
end

local options_data = {
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
        },
    },

    custom_gui_textures = {
        textures = _texture_names,
        ui_renderer_injections = _build_injections(),
    },
}

-- Issue #96 prune: drop the `allow_in_mission` checkbox from the forge group's
-- sub_widgets when gut is absent, so VMF never builds it. The forge_group is the
-- first widget in the options tree; locate it by setting_id rather than a fixed
-- index so a future reorder doesn't silently target the wrong group.
if not _gut_present() then
    local widgets = options_data.options and options_data.options.widgets
    for _, group in ipairs(widgets or {}) do
        if group.setting_id == "forge_group" and type(group.sub_widgets) == "table" then
            for i = #group.sub_widgets, 1, -1 do
                if group.sub_widgets[i].setting_id == "allow_in_mission" then
                    table.remove(group.sub_widgets, i)
                end
            end
            break
        end
    end
end

return options_data
