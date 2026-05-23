-- ============================================================
-- MoreItemsLibrary — embedded into cosmetics_tweaker (v0.9.3.6+)
-- ============================================================
-- Upstream: https://github.com/Aussiemon/VT2-More-Items-Library
-- License: MIT — Copyright (c) 2022 Aussiemon
-- (full MIT terms preserved at the bottom of this file)
--
-- Ported byte-for-byte (with adapter changes documented below) from MIL's
-- MoreItemsLibrary.lua + MoreItemsLibrary_templates.lua. Same public API:
--   * mod:add_mod_items_to_masterlist(items)
--   * mod:add_mod_items_to_local_backend(items, mod_name)
--   * mod:remove_mod_items_from_local_backend(items, mod_name)
--   * mod.cosmetic_item_types (table)
--   * mod.every_career (list)
-- ...exposed on cosmetics_tweaker's mod handle when this embed is the
-- active MIL copy. Consumers reach them via `get_mod("MoreItemsLibrary")`
-- — the la_prefix_embedded.lua alias redirects that lookup to the owner
-- of the embed (cosmetics_tweaker) when the standalone MIL isn't enabled.
--
-- Conflict guards (no load-order requirement):
--   1. Standalone MoreItemsLibrary (Workshop 1422758813) enabled → embed
--      bails dormant; standalone wins. Persistent-state ownership stays
--      with standalone in this case.
--   2. _G._cos_mil_embed_owner already set → a sibling tweaker mod (this
--      same file copy-pasted into character_weapon_variants etc.) already
--      claimed the embed. First mod to load wins. Lets us drop the same
--      file into any tweaker mod without coordination logic.
--
-- Persistent-state ownership transfer: when this embed activates, the
-- VMF persistent tables (`more_items_general_data`, `backend_mod_items`,
-- `new_masterlist_entries`, `backend_mirror_more_items`) live in
-- cosmetics_tweaker's persistent namespace. If the user later uninstalls
-- cosmetics_tweaker, those tables orphan and other consumers (CWV etc.)
-- would need standalone MIL again. Documented; not destructive.

local mod = get_mod("cosmetics_tweaker")
if not mod then return end

-- Sibling sentinel — first-loaded tweaker mod with this embed wins.
if _G._cos_mil_embed_owner then
    mod:info("[mil_embed] sibling embed (%s) already active; this copy stays dormant",
        tostring(_G._cos_mil_embed_owner))
    return
end

-- Standalone-running guard.
do
    local standalone = get_mod("MoreItemsLibrary")
    if standalone then
        local enabled = true
        if type(standalone.is_enabled) == "function" then
            enabled = standalone:is_enabled()
        end
        if enabled then
            mod:info("[mil_embed] standalone MoreItemsLibrary is enabled; embed dormant")
            return
        end
    end
end

mod:info("[mil_embed] activating (no conflict detected)")
_G._cos_mil_embed_owner = "cosmetics_tweaker"

-- ============================================================
-- Templates (ported from MoreItemsLibrary_templates.lua, MIT © Aussiemon 2022)
-- ============================================================
local mod_item_rarity = "default"
local default_catalog_version = "1"
local default_purchase_date = "2018-03-08T00:00:00.132Z"
local default_remaining_uses = 1
local default_unit_price = 0

local backend_templates = {
    -- Cosmetic --
    skin = {
        CustomData = {},
    },
    hat = {
        CustomData = {},
    },
    frame = {
        CustomData = {},
    },
    weapon_skin = {
        CustomData = {
            skin = nil,
        },
        skin = "",
    },
    -- Equipment --
    melee = {
        CustomData = {
            power_level = nil,
            properties  = nil,
            skin        = nil,
            traits      = nil,
        },
        power_level = "",
        properties  = {},
        skin        = "",
        traits      = {},
    },
    ranged = {
        CustomData = {
            power_level = nil,
            properties  = nil,
            skin        = nil,
            traits      = nil,
        },
        power_level = "",
        properties  = {},
        skin        = "",
        traits      = {},
    },
    necklace = {
        CustomData = {
            power_level = nil,
            properties  = nil,
            traits      = nil,
        },
        power_level = "",
        properties  = {},
        traits      = {},
    },
    ring = {
        CustomData = {
            power_level = nil,
            properties  = nil,
            traits      = nil,
        },
        power_level = "",
        properties  = {},
        traits      = {},
    },
    trinket = {
        CustomData = {
            power_level = nil,
            properties  = nil,
            traits      = nil,
        },
        power_level = "",
        properties  = {},
        traits      = {},
    },
}

-- ============================================================
-- Public mod-handle attributes (also from MIL_data.lua, MIT © Aussiemon)
-- ============================================================
mod.cosmetic_item_types = mod.cosmetic_item_types or {
    skin        = true,
    hat         = true,
    frame       = true,
    weapon_skin = true,
}

mod.every_career = mod.every_career or {
    -- Bright Wizard
    "bw_adept", "bw_scholar", "bw_unchained",
    -- Wood Elf
    "we_waywatcher", "we_maidenguard", "we_shade",
    -- Dwarf Ranger
    "dr_ranger", "dr_ironbreaker", "dr_slayer",
    -- Witch Hunter
    "wh_captain", "wh_bountyhunter", "wh_zealot",
    -- Empire Soldier
    "es_mercenary", "es_huntsman", "es_knight",
}

-- ============================================================
-- Persistent state (in cosmetics_tweaker's namespace per VMF API)
-- ============================================================
local general_data           = mod:persistent_table("more_items_general_data")
local backend_mod_items      = mod:persistent_table("backend_mod_items")
local new_masterlist_entries = mod:persistent_table("new_masterlist_entries")

local backend_mirror_hooked = false
local echo_header = "[More Items Library (embedded)]: "

-- Optimization locals (from upstream)
local ItemMasterList = ItemMasterList
local Managers       = Managers
local NetworkLookup  = NetworkLookup
local pairs          = pairs
local rawget         = rawget
local table          = table
local tostring       = tostring

-- ============================================================
-- Internal helpers
-- ============================================================
local function add_modded_item(item_id, item)
    backend_mod_items[item_id] = item
end

local function remove_modded_item(item_id)
    local backend = Managers.backend
    local backend_item_interface = backend:get_interface("items")
    local career_names = backend_item_interface:equipped_by(item_id)
    if #career_names > 0 then
        return false
    end
    backend_mod_items[item_id] = false
    return true
end

local function get_modded_item_list()
    local backend_ids = {}
    local index = 1
    for key, _ in pairs(backend_mod_items) do
        backend_ids[index] = key
        index = index + 1
    end
    return backend_ids
end

local function refresh_modded_items()
    local backend = Managers.backend
    local backend_item_interface = backend:get_interface("items")
    if backend_item_interface then
        backend_item_interface:make_dirty()
    end
end

-- Hooks the backend_mirror.get_all_inventory_items once we've captured the
-- mirror instance (during BackendInterfaceItemPlayfab.init below).
local function hook_backend_mirror()
    if backend_mirror_hooked then return end
    if not general_data["backend_mirror_persisted"] then return end

    local backend_mirror = mod:persistent_table("backend_mirror_more_items")
    if not (backend_mirror and backend_mirror.get_all_inventory_items) then return end

    mod:hook(backend_mirror, "get_all_inventory_items", function (func, ...)
        local backend_items = func(...)
        for mod_backend_id, mod_backend_item in pairs(backend_mod_items) do
            if not mod_backend_item then
                backend_mod_items[mod_backend_id] = nil
                backend_items[mod_backend_id] = nil
            else
                backend_items[mod_backend_id] = mod_backend_item
                local item_data = mod_backend_item.data
                local item_type = item_data and item_data.item_type
                -- Cosmetic items must be in the backend mirror's
                -- _unlocked_cosmetics member or vanilla won't render
                -- them in cosmetic browsers.
                if item_data and item_type and mod.cosmetic_item_types[item_type] then
                    backend_mirror._unlocked_cosmetics[mod_backend_item.data.name] = mod_backend_id
                end
            end
        end
        return backend_items
    end)
    backend_mirror_hooked = true
    mod:info("[mil_embed] backend_mirror.get_all_inventory_items hooked")
end

-- ============================================================
-- Public API on cosmetics_tweaker's mod handle
-- ============================================================
mod.add_mod_items_to_masterlist = function(self, items)
    for item_num = 1, #items do
        repeat
            local item = items[item_num]
            if not item or not item.name then break end
            local item_name = item.name
            if rawget(ItemMasterList, item_name) then break end

            ItemMasterList[item_name] = item
            new_masterlist_entries[item_name] = true

            local item_name_index = #NetworkLookup.item_names + 1
            NetworkLookup.item_names[item_name_index] = item_name
            NetworkLookup.item_names[item_name] = item_name_index

            local slot_type = item.slot_type
            if slot_type == "melee" or slot_type == "ranged" then
                local damage_source_index = #NetworkLookup.damage_sources + 1
                NetworkLookup.damage_sources[damage_source_index] = item_name
                NetworkLookup.damage_sources[item_name] = damage_source_index
            end
        until true
    end
    refresh_modded_items()
end

mod.add_mod_items_to_local_backend = function(self, items, mod_name)
    if not mod_name then
        mod:echo(echo_header .. "Unknown mod attempted to add items.")
        return
    end

    for item_num = 1, #items do
        repeat
            local item = items[item_num]
            if not item then
                mod:echo(echo_header .. mod_name .. " tried to add a nil item.")
                break
            end

            local slot_type = item.slot_type
            if not slot_type or not backend_templates[slot_type] then
                mod:echo(echo_header .. mod_name
                    .. " tried to add unknown item type " .. tostring(slot_type))
                break
            end

            local default_item_name = item.name
            if not default_item_name then
                mod:echo(echo_header .. mod_name .. " tried to add an item with no name.")
                break
            end

            local backend_item = table.clone(backend_templates[slot_type])
            local mod_data = item.mod_data or {}
            for key, _ in pairs(backend_item) do
                if mod_data[key] then
                    backend_item[key] = mod_data[key]
                end
            end

            local default_backend_id = mod_name .. "_" .. default_item_name
            backend_item.IsModItem      = true
            backend_item.CreatedBy      = mod_name
            backend_item.backend_id     = mod_data.backend_id or default_backend_id
            backend_item.ItemInstanceId = mod_data.ItemInstanceId or default_backend_id
            backend_item.CatalogVersion = mod_data.CatalogVersion or default_catalog_version
            backend_item.PurchaseDate   = mod_data.PurchaseDate or default_purchase_date
            backend_item.RemainingUses  = mod_data.RemainingUses or default_remaining_uses
            backend_item.UnitPrice      = mod_data.UnitPrice or default_unit_price
            backend_item.ItemId         = mod_data.ItemId or item.key or default_item_name
            backend_item.key            = mod_data.key or item.key or default_item_name
            backend_item.data           = item
            backend_item.CustomData.rarity = mod_item_rarity
            backend_item.rarity         = mod_item_rarity
            backend_item.bypass_skin_ownership_check = true
            backend_item.skin           = mod_data.skin

            add_modded_item(backend_item.backend_id, backend_item)
        until true
    end
    refresh_modded_items()
end

mod.remove_mod_items_from_local_backend = function(self, items, mod_name)
    if not mod_name then
        mod:echo(echo_header .. "Unknown mod attempted to remove items.")
        return
    end
    for item_num = 1, #items do
        repeat
            local backend_id = items[item_num]
            if not backend_id then
                mod:echo(echo_header .. mod_name .. " tried to remove a nil item.")
                break
            end
            remove_modded_item(backend_id)
        until true
    end
    refresh_modded_items()
end

-- Diagnostic command — mirrors upstream's GetAllModItems.
mod:command("GetAllModItems", "Print list of MIL-registered items (embedded copy)", function()
    local items = get_modded_item_list()
    if #items == 0 then mod:echo("[mil_embed] no items registered"); return end
    for i = 1, #items do
        if items[i] then mod:echo(items[i]) end
    end
end)

-- ============================================================
-- The load-bearing hook: capture backend_mirror on BackendInterfaceItemPlayfab.init
-- ============================================================
-- VMF idempotency: re-registering this hook on the same Class+method via
-- the same mod handle is wrapped LIFO. Re-runs are harmless since the
-- captured pointer is the same instance.
mod:hook(BackendInterfaceItemPlayfab, "init", function(func, self, backend_mirror)
    mod:persistent_table("backend_mirror_more_items", backend_mirror)
    general_data["backend_mirror_persisted"] = true
    hook_backend_mirror()
    return func(self, backend_mirror)
end)

-- ============================================================
-- Lifecycle callbacks — fold into cosmetics_tweaker's existing handlers
-- ============================================================
-- cosmetics_tweaker already defines mod.on_game_state_changed and
-- mod.on_all_mods_loaded. Wrap rather than overwrite so the existing
-- behaviors keep firing.
do
    local _prev_on_game_state_changed = mod.on_game_state_changed
    mod.on_game_state_changed = function(...)
        hook_backend_mirror()
        if _prev_on_game_state_changed then
            local ok, err = pcall(_prev_on_game_state_changed, ...)
            if not ok then mod:warning("[mil_embed] prior on_game_state_changed errored: %s", tostring(err)) end
        end
    end

    local _prev_on_all_mods_loaded = mod.on_all_mods_loaded
    mod.on_all_mods_loaded = function(...)
        hook_backend_mirror()
        if _prev_on_all_mods_loaded then
            local ok, err = pcall(_prev_on_all_mods_loaded, ...)
            if not ok then mod:warning("[mil_embed] prior on_all_mods_loaded errored: %s", tostring(err)) end
        end
    end
end

mod:info("[mil_embed] API installed — add_mod_items_to_masterlist / add_mod_items_to_local_backend / remove_mod_items_from_local_backend available")

-- ============================================================
-- MIT LICENSE (preserved per upstream copyright requirement)
-- ============================================================
-- Copyright (c) 2022 Aussiemon
--
-- Permission is hereby granted, free of charge, to any person obtaining a
-- copy of this software and associated documentation files (the
-- "Software"), to deal in the Software without restriction, including
-- without limitation the rights to use, copy, modify, merge, publish,
-- distribute, sublicense, and/or sell copies of the Software, and to
-- permit persons to whom the Software is furnished to do so, subject to
-- the following conditions:
--
-- The above copyright notice and this permission notice shall be included
-- in all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
-- OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
-- MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
-- IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
-- CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
-- TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
-- SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
