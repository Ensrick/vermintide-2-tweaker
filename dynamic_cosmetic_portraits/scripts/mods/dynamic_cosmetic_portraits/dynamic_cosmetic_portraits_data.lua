local mod = get_mod("dynamic_cosmetic_portraits")

-- =========================================================================
-- Standalone texture/material list. HUD and small portraits are sprites in
-- the private dcp_portrait_atlas; only medium portraits remain standalone.
-- Keep this list in sync with _PORTRAIT_STANDALONE_MATERIALS in
-- dynamic_cosmetic_portraits.lua and with the .package file.
-- DO NOT hand-add entries without first running tools/add_portrait.ps1
-- to generate the .png / .texture / .material files. Free-handing the
-- assets is the source of every portrait bug to date.
-- See DEVELOPMENT.md "Adding a new portrait" before editing.
-- =========================================================================
local _texture_names = {
    "medium_portrait_kruber_mercenary_hat_0004",
    "medium_portrait_kruber_mercenary_hat_0009",
    "medium_portrait_kruber_mercenary_hat_1001",
    "medium_portrait_kruber_mercenary_hat_1002",
    "medium_portrait_kruber_mercenary_hat_1003",
    "medium_portrait_kruber_mercenary_hat_0007",
    "medium_portrait_kruber_mercenary_hat_0006",
    "medium_portrait_kruber_skin_es_mercenary_1003",
    "medium_portrait_kruber_skin_es_default",
    "medium_portrait_kruber_mercenary_hat_0001",
    "medium_portrait_kruber_mercenary_hat_0003",
    "medium_portrait_kruber_mercenary_hat_0005",
}

local _atlas_material_path = "materials/dynamic_cosmetic_portraits/dcp_portrait_atlas"

-- =========================================================================
-- Renderer creators we inject into. The "creator" string must match the
-- BASENAME of the lua file that calls UIRenderer.create — VMF reads it
-- from the callstack (see VMF custom_textures.lua line 191).
--
-- IMPORTANT: Lua 5.1 tail-call elimination means the file VMF sees is
-- often the OUTER caller, not the inner factory. e.g. when
-- hero_view_state_loot.lua:271 calls
--   self.ingame_ui:create_ui_renderer(world)
-- which `return`s into IngameUI:create_ui_renderer which `return`s into
-- view_settings.ui_renderer_function which `return`s UIRenderer.create —
-- the tail-called intermediate frames are elided, and VMF lands on
-- `hero_view_state_loot.lua` as the creator. So every entry-point file
-- for a portrait-bearing UI must be enumerated below; registering only
-- the inner factory (`ingame_ui_settings`) is NOT enough.
--
-- Known crash paths fixed by entries below:
--   pause-menu buttons      → ingame_ui_settings + hero_view*
--   Spoils of War           → hero_view_state_loot
--   Lohner's Emporium       → hero_view_state_store
--   Athanor / Weave Forge   → hero_view_state_weave_forge
--   end-of-mission screens  → level_end_view_base / _versus
--   store popups            → store_item_purchase_popup, store_welcome_popup
--   start-game overview     → start_game_state_settings_overview
--   Chaos Wastes map        → game_mode_map_deus
-- =========================================================================
local _renderer_creators = {
    -- main HUD (unit frames, tab overlay)
    "ingame_ui",
    -- inner factory used by IngameUI:create_ui_renderer (covers ALL
    -- create_ui_renderer call sites that are NOT tail-called)
    "ingame_ui_settings",
    -- HeroView entry points
    "hero_view",
    "hero_view_state_loot",          -- Spoils of War
    "hero_view_state_store",         -- Lohner's Emporium / Cosmetics shop
    "hero_view_state_weave_forge",   -- Athanor / Weave forge
    -- StartGame entry points
    "start_game_state_settings_overview",
    "store_item_purchase_popup",
    "store_welcome_popup",
    -- end-of-mission
    "level_end_view_base",
    "level_end_view_versus",
    -- Chaos Wastes overworld map (uses portraits)
    "game_mode_map_deus",
    -- Managers.ui:create_ui_renderer chain
    "ui_manager",
}

local function _build_material_paths()
    local out = { _atlas_material_path }
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

-- This mod deliberately exposes NO VMF settings page and no enable/disable
-- toggle: it "simply does what it does" (user directive 2026-06-22). The
-- `options.widgets` tree was removed entirely and `is_togglable` set to false.
-- Portrait swapping is always on; debug logging is always on (see the main
-- lua's _dbg / _dbg_alert helpers). The `custom_gui_textures` block below is
-- NOT options — it is the load-bearing texture/material registration that VMF
-- injects into the UI renderers, and must stay.
local data = {
    name = "Dynamic Cosmetic Portraits",
    description = mod:localize("mod_description"),
    is_togglable = false,

    custom_gui_textures = {
        textures = _texture_names,
        atlases = {
            {
                _atlas_material_path,
                "dcp_portrait_atlas",
                "dcp_portrait_atlas_masked",
                nil,
                nil,
                "dcp_portrait_atlas",
            },
        },
        ui_renderer_injections = _build_injections(),
    },
}

mod:info("[data] returning with custom_gui_textures=%s, textures=%d, atlases=%d, injections=%d",
    tostring(data.custom_gui_textures ~= nil),
    data.custom_gui_textures and #data.custom_gui_textures.textures or 0,
    data.custom_gui_textures and #data.custom_gui_textures.atlases or 0,
    data.custom_gui_textures and #data.custom_gui_textures.ui_renderer_injections or 0)

return data
