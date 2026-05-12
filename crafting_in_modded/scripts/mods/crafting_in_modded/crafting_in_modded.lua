--[[
crafting_in_modded — modded crafting menus for Vermintide 2.

Currently surfaces the Athanor (Winds of Magic forge) UI as a custom weapon-
crafting menu. Future versions may add additional surfaces (e.g. the Keep's
standard forge / Smithy). Split out of weapon_tweaker on 2026-05-05.

Major sections (search by name to jump):
  * NetworkLookup.rarities patch                — adds "promo" rarity for crafted items
  * Forge core (`_forge_*`)                     — persistence, item creation, MIL injection
  * Athanor section                             — UI hooks, _custom_forge_active flag, B hotkey opener
  * BackendInterfaceWeavesPlayFab hooks         — redirect weave loadout queries to real items
  * HeroWindowWeaveForgeWeapons hooks           — replace weapon list, equip → craft, etc.
  * Diagnostic commands (`cim forge_dump`, etc.)
  * Manual console crafting (`cim forge`, `cim forge_confirm`)
]]

local mod = get_mod("cim")

local MOD_VERSION = "0.7.0-dev"
mod:info("Crafting in Modded v%s loaded", MOD_VERSION)
mod:echo("Crafting in Modded v" .. MOD_VERSION)

-- Register the "modded" rarity (and any future custom rarities) BEFORE
-- anything else loads — sibling modules will create items with this rarity.
local _ok_rr, _err_rr = pcall(mod.dofile, mod, "scripts/mods/crafting_in_modded/modded_rarities")
if not _ok_rr then mod:error("Failed to load modded_rarities: %s", tostring(_err_rr)) end

-- Standard Keep crafting — same Athanor pattern: mutations are session-only because
-- we block PlayFab commits while the forge is open. v0.2.0 crashed because we left
-- the commit alive and PlayFab's anti-tamper rejected the modified inventory state.
local _ok_sf, _err_sf = pcall(mod.dofile, mod, "scripts/mods/crafting_in_modded/standard_forge")
if not _ok_sf then mod:error("Failed to load standard_forge: %s", tostring(_err_sf)) end

-- Backward-compat: pre-v0.7.0 cim used `rarity = "promo"` for crafts. Keep
-- "promo" registered in NetworkLookup.rarities too so legacy saved items can
-- still round-trip through inventory sync until they get re-crafted/migrated.
local NL = rawget(_G, "NetworkLookup")
if NL and NL.rarities and not rawget(NL.rarities, "promo") then
    local t = NL.rarities
    local idx = #t + 1
    t[idx] = "promo"
    rawset(t, "promo", idx)
end

-- ============================================================
-- Forge core (persistence + item creation)
-- ============================================================
local _more_items_lib = nil
local _forge_pending = nil
local _forged_weapons = {}

local function _forge_detect_mil()
    if _more_items_lib then return true end
    local ok, lib = pcall(get_mod, "MoreItemsLibrary")
    if ok and lib then
        _more_items_lib = lib
        return true
    end
    return false
end

local function _forge_save()
    local save_data = {}
    for bid, w in pairs(_forged_weapons) do
        save_data[bid] = {
            item_key = w.item_key,
            properties = w.properties,
            trait = w.trait,
            traits = w.traits,
            skin = w.skin,
            power_level = w.power_level or 300,
            rarity = w.rarity,
            via_mirror = w.via_mirror,
            rerolled_props_indices = w.rerolled_props_indices,
            rerolled_trait_indices = w.rerolled_trait_indices,
        }
    end
    mod:set("forged_weapons", save_data)
end

local function _forge_load()
    local save_data = mod:get("forged_weapons")
    if not save_data or type(save_data) ~= "table" then return end
    _forged_weapons = {}
    for bid, w in pairs(save_data) do
        -- Backward-compat: legacy entries without `via_mirror` were saved by the
        -- Athanor (rarity=promo, mirror path) or the legacy `cim forge_confirm`
        -- (rarity=exotic, MIL path). Default via_mirror to true for promo/modded so
        -- the mirror restore path picks it up.
        local via_mirror = w.via_mirror
        if via_mirror == nil then via_mirror = (w.rarity == "promo" or w.rarity == "modded") end
        -- v0.7.0 migration: rewrite legacy `promo` saves to `modded` so they get
        -- the new rarity's behaviors (cog enabled, full customization window) on
        -- next session.
        local rarity = w.rarity
        if rarity == "promo" then rarity = "modded" end
        _forged_weapons[bid] = {
            item_key = w.item_key,
            properties = w.properties or {},
            trait = w.trait,
            traits = w.traits,
            skin = w.skin,
            power_level = w.power_level or 300,
            rarity = rarity,
            via_mirror = via_mirror,
            rerolled_props_indices = w.rerolled_props_indices,
            rerolled_trait_indices = w.rerolled_trait_indices,
        }
    end
    _forge_save() -- persist any rarity migrations
end

-- Public helper for sibling modules (standard_forge.lua) to register a newly
-- crafted item into the persistent save layer. `via_mirror = true` means the
-- item is added via `backend_mirror:add_item` on session restore (not MIL).
mod._cim_register_craft = function(backend_id, weapon_data)
    local entry = {
        item_key = weapon_data.item_key,
        properties = weapon_data.properties or {},
        trait = weapon_data.trait,
        traits = weapon_data.traits,
        skin = weapon_data.skin,
        power_level = weapon_data.power_level or 300,
        rarity = weapon_data.rarity,
        via_mirror = weapon_data.via_mirror ~= false,
    }
    _forged_weapons[backend_id] = entry
    _forge_save()
end

mod._cim_unregister_craft = function(backend_id)
    if _forged_weapons[backend_id] then
        _forged_weapons[backend_id] = nil
        _forge_save()
    end
end

mod._cim_get_craft = function(backend_id)
    return _forged_weapons[backend_id]
end

mod._cim_persist_crafts = function()
    _forge_save()
end

mod._cim_is_modded_backend_id = function(backend_id)
    if not backend_id or type(backend_id) ~= "string" then return false end
    -- Our crafts (registered via_mirror)
    if _forged_weapons[backend_id] then return true end
    -- character_weapon_variants items
    if backend_id:sub(1, 4) == "cwv_" then return true end
    -- Application.guid() output: 8-4-4-4-12 hex with dashes (UUID format).
    -- Vanilla PlayFab IDs are continuous hex, no dashes.
    if backend_id:find("^%x+%-%x+%-%x+%-%x+%-%x+$") then return true end
    return false
end

-- Item-level "is this a modded craft?" check. Same as the backend_id check,
-- plus a rarity-based fallback: any item with our custom rarity ("modded", or
-- the legacy "promo" we used pre-v0.7.0) is treated as modded regardless of
-- bid format. The rarity is the load-bearing visual cue we apply to crafts, so
-- it's a more reliable signal than guessing at bid heuristics — covers crafts
-- saved by older mod versions whose bid format doesn't match our current
-- regex, items the player crafted on another machine that synced down, etc.
mod._cim_is_modded_item = function(item)
    if not item then return false end
    if item.rarity == "modded" or item.rarity == "promo" then return true end
    return mod._cim_is_modded_backend_id(item.backend_id)
end

local function _forge_create_item(weapon_data, backend_id)
    if not ItemMasterList then return nil end
    local item_key = weapon_data.item_key
    local master = rawget(ItemMasterList, item_key)
    if not master then
        mod:echo("Forge: unknown weapon key '" .. tostring(item_key) .. "'")
        return nil
    end

    local props = weapon_data.properties or {}
    local trait = weapon_data.trait
    local traits_array = weapon_data.traits
    local skin = weapon_data.skin
    local power_level = weapon_data.power_level or 300

    local custom_props = "{"
    for k, v in pairs(props) do
        custom_props = custom_props .. '"' .. k .. '":' .. tostring(v) .. ','
    end
    custom_props = custom_props .. "}"

    local traits_table = {}
    if traits_array then
        for i, t in ipairs(traits_array) do traits_table[i] = t end
    elseif trait then
        traits_table[1] = trait
    end

    local custom_traits = "["
    for i, t in ipairs(traits_table) do
        if i > 1 then custom_traits = custom_traits .. "," end
        custom_traits = custom_traits .. '"' .. t .. '"'
    end
    custom_traits = custom_traits .. "]"

    local rarity = weapon_data.rarity or "exotic"

    local entry = table.clone(master, true)
    entry.mod_data = {
        backend_id = backend_id,
        ItemInstanceId = backend_id,
        CustomData = {
            traits = custom_traits,
            power_level = tostring(power_level),
            properties = custom_props,
            rarity = rarity,
        },
        rarity = rarity,
        traits = traits_table,
        power_level = power_level,
        properties = table.clone(props, true),
    }
    if skin then
        entry.mod_data.CustomData.skin = skin
        entry.mod_data.skin = skin
        if WeaponSkins and WeaponSkins.skins and WeaponSkins.skins[skin] then
            entry.mod_data.inventory_icon = WeaponSkins.skins[skin].inventory_icon
        end
    end
    entry.rarity = rarity

    return entry
end

local function _forge_inject_item(weapon_data, backend_id)
    if not _forge_detect_mil() then
        mod:echo("Forge: MoreItemsLibrary not found — install it from the Workshop")
        return false
    end

    local entry = _forge_create_item(weapon_data, backend_id)
    if not entry then return false end

    _more_items_lib:add_mod_items_to_local_backend({entry}, "crafting_in_modded")
    if Managers.backend then
        local items = Managers.backend:get_interface("items")
        if items then items:_refresh() end
    end
    if ItemHelper and ItemHelper.mark_backend_id_as_new then
        pcall(ItemHelper.mark_backend_id_as_new, backend_id)
    end
    return true
end

local function _forge_inject_all()
    if not _forge_detect_mil() then return end
    for bid, w in pairs(_forged_weapons) do
        -- Mirror-path crafts (Athanor + standard forge) go through
        -- `_athanor_inject_all`. MIL is reserved for legacy `cim forge_confirm`
        -- console crafts that explicitly opted into the MIL path.
        if not w.via_mirror then
            local entry = _forge_create_item(w, bid)
            if entry then
                _more_items_lib:add_mod_items_to_local_backend({entry}, "crafting_in_modded")
            end
        end
    end
    if Managers.backend then
        local items = Managers.backend:get_interface("items")
        if items then items:_refresh() end
    end
end

_forge_load()

local _athanor_inject_all -- forward declaration; defined in the Athanor section below
local _restore_modded_loadout -- forward declaration; defined in the inventory section below

mod:hook_safe("BackendManagerPlayFab", "_create_interfaces", function()
    _forge_load()
    _forge_inject_all()
    if _athanor_inject_all then _athanor_inject_all() end
    if _restore_modded_loadout then _restore_modded_loadout() end
    local count = 0
    for _ in pairs(_forged_weapons) do count = count + 1 end
    mod:info("Forge: restored %d forged weapons", count)
end)

-- ============================================================
-- Modded inventory filter + loadout restore
-- ============================================================
-- The mod-realm view: hide vanilla weapons from the inventory grid (toggleable),
-- and remember the last modded item the player equipped on each (career, slot)
-- so that switching to vanilla and back doesn't wipe their modded loadout.

local _WEAPON_SLOT_TYPES = { melee = true, ranged = true, trinket = true, ring = true, necklace = true }
local _modded_loadout = {}

local function _modded_loadout_save()
    mod:set("modded_loadout", _modded_loadout)
end

local function _modded_loadout_load()
    local data = mod:get("modded_loadout")
    if type(data) == "table" then
        _modded_loadout = data
    else
        _modded_loadout = {}
    end
end

_modded_loadout_load()

-- Public helper for sibling modules (standard_forge.lua salvage synth) to drop
-- a salvaged backend_id out of the saved loadout — otherwise loadout-restore
-- on next session would try to re-equip a non-existent item.
mod._cim_clear_modded_loadout_for_bid = function(backend_id)
    if not backend_id then return end
    local dirty = false
    for career_name, slots in pairs(_modded_loadout) do
        for slot_name, bid in pairs(slots) do
            if bid == backend_id then
                slots[slot_name] = nil
                dirty = true
            end
        end
    end
    if dirty then _modded_loadout_save() end
end

-- Assigned to the forward-declared local at the top of the Forge core section,
-- so the `_create_interfaces` hook can call it.
_restore_modded_loadout = function()
    if not mod:get("restore_modded_loadout") then return end
    _modded_loadout_load()
    local items = Managers.backend and Managers.backend:get_interface("items")
    if not items then return end
    local restored = 0
    for career_name, slots in pairs(_modded_loadout) do
        for slot_name, backend_id in pairs(slots) do
            -- Only restore if the saved item still exists in the mirror
            -- (it should, after _athanor_inject_all + _forge_inject_all ran).
            local item = items:get_item_from_id(backend_id)
            if item then
                local ok = pcall(items.set_loadout_item, items, backend_id, career_name, slot_name)
                if ok then restored = restored + 1 end
            end
        end
    end
    if restored > 0 then mod:info("Restored %d modded loadout entries", restored) end
end

-- Capture each set_loadout_item call for modded items so we can restore later.
mod:hook_safe("BackendInterfaceItemPlayfab", "set_loadout_item", function(self, item_id, career_name, slot_name, optional_loadout_index)
    if not item_id or not career_name or not slot_name then return end
    if mod._cim_is_modded_backend_id and mod._cim_is_modded_backend_id(item_id) then
        _modded_loadout[career_name] = _modded_loadout[career_name] or {}
        _modded_loadout[career_name][slot_name] = item_id
        _modded_loadout_save()
    end
end)

-- Inventory filter: drops vanilla weapons / jewellery from get_filtered_items
-- results when EITHER (a) the "show only modded" setting is on, OR (b) the
-- standard crafting UI is open. (b) is unconditional because vanilla items in
-- modded realm can't actually be salvaged/upgraded/rerolled (the commit-block
-- prevents PlayFab from learning about the change, so PlayFab restores them
-- on next session). Showing them in crafting menus would be misleading.
-- Crafting materials and cosmetics (hat/skin) are unaffected because their
-- slot_type isn't in `_WEAPON_SLOT_TYPES`.
mod:hook("BackendInterfaceItemPlayfab", "get_filtered_items", function(func, self, filter, params)
    local items = func(self, filter, params)
    local should_filter = mod:get("show_only_modded_weapons") or mod._cim_standard_forge_active
    if not should_filter then return items end
    if type(items) ~= "table" then return items end

    local filtered = {}
    for i, item in ipairs(items) do
        local slot_type = item and item.data and item.data.slot_type
        local bid = item and item.backend_id
        local rarity = item and item.rarity
        local is_weapon_like = slot_type and _WEAPON_SLOT_TYPES[slot_type]
        local is_modded = mod._cim_is_modded_backend_id and mod._cim_is_modded_backend_id(bid)
        -- Default-rarity items are blacksmith's templates / placeholders, used
        -- by the "Craft Item" recipe (can_craft_with) to pick what to craft.
        -- Always allow them through so the crafting flow stays usable.
        local is_default_template = rarity == "default"
        if not is_weapon_like or is_modded or is_default_template then
            filtered[#filtered + 1] = item
        end
    end
    return filtered
end)

-- ============================================================
-- Salvage filter override: surface modded items in the salvage grid
-- ============================================================
-- Vanilla `can_salvage` (backend_interface_common.lua:412) excludes
-- `rarity == "promo"` AND equipped items AND items in any loadout. Modded
-- items skip the rarity exclusion (rarity = "modded", not "promo") but auto-
-- equip on craft, so they'd still be hidden. Post-hook the filter to add our
-- crafts back regardless of equip/loadout state when the filter is the
-- salvage recipe's (`can_salvage and not is_equipped and not
-- is_equipped_by_any_loadout`). Also catches legacy promo-rarity crafts.
local _SALVAGE_SLOT_TYPES = { melee = true, ranged = true, ring = true, necklace = true, trinket = true }

local function _is_salvage_filter(filter_infix)
    if type(filter_infix) ~= "string" then return false end
    return filter_infix:find("can_salvage", 1, true) ~= nil
end

mod:hook("BackendInterfaceCommon", "filter_items", function(func, self, items, filter_infix, params)
    local result = func(self, items, filter_infix, params)
    if not _is_salvage_filter(filter_infix) then return result end
    if type(result) ~= "table" or type(items) ~= "table" then return result end

    local seen = {}
    for _, r in ipairs(result) do
        if r and r.backend_id then seen[r.backend_id] = true end
    end

    local backend_items = Managers.backend and Managers.backend:get_interface("items")
    if not backend_items then return result end

    -- Surface modded items in salvage REGARDLESS of equip / loadout / favorite
    -- state. Vanilla excludes equipped items so players don't accidentally
    -- destroy their gear, but modded crafts are throwaway by design — the user
    -- crafted them and wants the option to delete them. Auto-equipping after
    -- a craft (which we do via `set_loadout_item`) would otherwise immediately
    -- hide every craft from the scrap list.
    --
    -- Use the item-level check (rarity OR bid heuristic) so promo items from
    -- earlier sessions / other machines / older mod versions still surface
    -- even if their bid format doesn't match our current regex.
    for _, item in ipairs(items) do
        local bid = item and item.backend_id
        if bid and not seen[bid]
           and mod._cim_is_modded_item and mod._cim_is_modded_item(item) then
            local slot_type = item.data and item.data.slot_type
            if _SALVAGE_SLOT_TYPES[slot_type] then
                result[#result + 1] = item
                seen[bid] = true
            end
        end
    end
    return result
end)

-- ============================================================
-- Athanor (Winds of Magic forge) — UI hooks
-- ============================================================
local _custom_forge_active = false
local _forge_loadout = {}
local _forge_item_props = {}
local _forge_panel_styled = false
local _forge_bg_colored = false

-- Per-amulet-slot dirty tracking. Declared here (above the on_exit hook that
-- resets it) so the hook closure captures this local rather than reading a
-- nil global. The actual assignment lives further down with the amulet helpers.
local _amulet_dirty = { false, false, false }

mod.open_forge = function()
    if not Managers.ui then
        mod:echo("Forge: UI not available")
        return
    end
    local ingame_ui = Managers.ui._ingame_ui
    if not ingame_ui then
        mod:echo("Forge: not in game")
        return
    end
    if ingame_ui:pending_transition() then return end
    _custom_forge_active = true
    _forge_loadout = {}
    _forge_item_props = {}
    ingame_ui:transition_with_fade("hero_view_force", {
        menu_state_name = "weave_forge",
    })
end

mod:hook_safe("HeroViewStateWeaveForge", "on_exit", function(self)
    _custom_forge_active = false
    _forge_loadout = {}
    _forge_item_props = {}
    _forge_panel_styled = false
    _forge_bg_colored = false
    _amulet_dirty[1], _amulet_dirty[2], _amulet_dirty[3] = false, false, false
end)

-- --- Forge UI polish (runs each frame while forge is open) ---

local function _forge_get_widget(window, widget_name)
    local wbn = window and window._widgets_by_name
    return wbn and wbn[widget_name]
end

local function _forge_hide_widget(window, widget_name)
    local w = _forge_get_widget(window, widget_name)
    if w and w.content then w.content.visible = false end
end

local function _forge_set_text(window, widget_name, text)
    local w = _forge_get_widget(window, widget_name)
    if w and w.content then w.content.text = text end
end

local function _forge_set_style_color(window, widget_name, style_key, color)
    local w = _forge_get_widget(window, widget_name)
    if w and w.style and w.style[style_key] then
        w.style[style_key].color = color
    end
end

local function _forge_is_hovered(widget)
    if not widget or not widget.content then return false end
    local hs = widget.content.button_hotspot or widget.content.hotspot
    return hs and hs.is_hover
end

-- The Athanor's hover preview now uses VT2's standard `item_tooltip` pass —
-- the same box that pops up on hover in the regular inventory and crafting
-- menus. The widget is created lazily inside `_forge_apply_ui_polish` and
-- stored on `overview._cim_tooltip_widget`.
local function _forge_populate_item_panels(overview, item)
    local tt = overview._cim_tooltip_widget
    if not tt then return end
    tt.content.item = item or nil
end

local function _forge_hide_item_panels(overview)
    local tt = overview._cim_tooltip_widget
    if not tt then return end
    tt.content.item = nil
end

local function _forge_apply_ui_polish(forge_state)
    local windows = forge_state._active_windows
    if not windows then return end

    local overview = nil
    local panel = nil
    local background = nil
    for _, win in pairs(windows) do
        local name = win.NAME
        if name == "HeroWindowWeaveForgeOverview" then overview = win
        elseif name == "HeroWindowWeaveForgePanel" then panel = win
        elseif name == "HeroWindowWeaveForgeBackground" then background = win
        end
    end

    -- === OVERVIEW: hide Athanor level, hide weapon level, fix power ===
    if overview then
        _forge_hide_widget(overview, "forge_level_title")
        _forge_hide_widget(overview, "forge_level_text")
        _forge_hide_widget(overview, "upgrade_button")
        _forge_hide_widget(overview, "upgrade_text")
        _forge_hide_widget(overview, "upgrade_bg")
        _forge_hide_widget(overview, "top_hdr_background_write_mask")

        for i = 1, 3 do
            _forge_hide_widget(overview, "viewport_level_title_" .. i)
            _forge_hide_widget(overview, "viewport_level_value_" .. i)
            _forge_hide_widget(overview, "viewport_panel_divider_" .. i)

            local highlight = _forge_get_widget(overview, "viewport_button_text_highlight_" .. i)
            if highlight and highlight.style then
                if highlight.style.background_top then
                    highlight.style.background_top.color = {255, 123, 123, 123}
                end
                if highlight.style.background_bottom then
                    highlight.style.background_bottom.color = {255, 123, 123, 123}
                end
                if highlight.style.background_top_light then
                    highlight.style.background_top_light.color = {200, 123, 123, 123}
                end
                if highlight.style.background_bottom_light then
                    highlight.style.background_bottom_light.color = {200, 123, 123, 123}
                end
            end

            local btn_highlight = _forge_get_widget(overview, "viewport_button_highlight_" .. i)
            if btn_highlight and btn_highlight.style then
                for sk, sv in pairs(btn_highlight.style) do
                    if type(sv) == "table" and sv.color then
                        sv.color = {sv.color[1], 123, 123, 123}
                    end
                end
            end
        end

        local items_backend = Managers.backend and Managers.backend:get_interface("items")
        if items_backend then
            local player = Managers.player and Managers.player:local_player()
            if player then
                local profile_index = player:profile_index()
                local profile = SPProfiles[profile_index]
                local career_index = player:career_index()
                local career = profile.careers[career_index]
                local career_name = career.name
                local slot_map = {[1] = "slot_melee", [3] = "slot_ranged"}
                for vp_idx, slot_name in pairs(slot_map) do
                    local bid = items_backend:get_loadout_item_id(career_name, slot_name)
                    if bid then
                        local item = items_backend:get_item_from_id(bid)
                        if item then
                            _forge_set_text(overview, "viewport_power_value_" .. vp_idx, tostring(item.power_level or 300))
                        end
                    end
                end
            end
        end
    end

    -- === VIEWPORT 2 (amulet): repurposed as the modded jewellery + talents
    -- editor entry point. We keep it visible (vanilla draws it via
    -- `_initialize_viewports` when `amulet_introduced = true`, see hook below)
    -- and let it route to the weave properties window on click. Phase B will
    -- swap the routing to a custom 3-subsection editor.
    if overview then
        -- Re-label the amulet viewport so it's clear it's the unified jewellery
        -- editor (vanilla title is "Weave Amulet"). The click flows through to
        -- HeroWindowWeaveProperties which auto-uses amulet_slot_layout when
        -- selected_item is nil — that's the 3-section UI the user wants.
        _forge_set_text(overview, "viewport_title_2", "JEWELLERY")
        _forge_set_text(overview, "viewport_sub_title_2", "Necklace + Charm + Trinket")

        if not overview._wt_panels_init then
            overview._wt_panels_init = true
            local UIWidgets = rawget(_G, "UIWidgets")
            local UIWidget = rawget(_G, "UIWidget")
            if UIWidgets and UIWidget and UIWidgets.create_simple_item_tooltip then
                -- Standard set of tooltip passes used elsewhere in VT2 (deus
                -- run stats, etc). Renders the same boxed item card the regular
                -- inventory / crafting menus show on hover.
                local tooltip_passes = {
                    "item_titles",
                    "skin_applied",
                    "ammunition",
                    "fatigue",
                    "item_power_level",
                    "properties",
                    "traits",
                    "weapon_skin_title",
                    "keywords",
                    "light_attack_stats",
                    "heavy_attack_stats",
                    "detailed_stats_light",
                    "detailed_stats_heavy",
                    "detailed_stats_push",
                    "detailed_stats_ranged_light",
                    "detailed_stats_ranged_heavy",
                }
                local ok_def, tt_def = pcall(UIWidgets.create_simple_item_tooltip, "viewport_panel_2", tooltip_passes)
                if ok_def and tt_def then
                    local ok, tt = pcall(UIWidget.init, tt_def)
                    if ok and tt then
                        -- Anchor near the bottom-left of viewport_panel_2 so
                        -- the tooltip box reads naturally when the mouse is
                        -- on the melee or ranged weapon viewport.
                        tt.offset = { 10, 200, 30 }
                        tt.content.item = nil
                        overview._cim_tooltip_widget = tt
                        if overview._top_widgets then
                            overview._top_widgets[#overview._top_widgets + 1] = tt
                        end
                        mod:info("Forge tooltip: ready")
                    else
                        mod:echo("Forge tooltip init err: " .. tostring(tt))
                    end
                else
                    mod:echo("Forge tooltip create err: " .. tostring(tt_def))
                end
            else
                mod:echo("Forge tooltip: create_simple_item_tooltip not available")
            end
        end

        local hovered_vp = nil
        local vp1_btn = _forge_get_widget(overview, "viewport_button_1")
        local vp3_btn = _forge_get_widget(overview, "viewport_button_3")
        if _forge_is_hovered(vp1_btn) then
            hovered_vp = 1
        elseif _forge_is_hovered(vp3_btn) then
            hovered_vp = 3
        end

        if hovered_vp then
            local slot_name = (hovered_vp == 1) and "slot_melee" or "slot_ranged"
            local items_backend = Managers.backend and Managers.backend:get_interface("items")
            local player = Managers.player and Managers.player:local_player()
            if player and items_backend then
                local profile_index = player:profile_index()
                local profile = SPProfiles[profile_index]
                local career_index = player:career_index()
                local career = profile.careers[career_index]
                local career_name = career.name
                local bid = items_backend:get_loadout_item_id(career_name, slot_name)
                local item = bid and items_backend:get_item_from_id(bid)
                if item then
                    _forge_populate_item_panels(overview, item)
                else
                    _forge_hide_item_panels(overview)
                end
            else
                _forge_hide_item_panels(overview)
            end
        else
            _forge_hide_item_panels(overview)
        end
    end

    -- === PANEL: hide essence, wheel rings, rebrand header ===
    if panel then
        _forge_hide_widget(panel, "essence_icon")
        _forge_hide_widget(panel, "essence_text")
        _forge_hide_widget(panel, "essence_panel")
        _forge_hide_widget(panel, "essence_tooltip")
        _forge_hide_widget(panel, "loadout_power_title")
        _forge_hide_widget(panel, "loadout_power_tooltip")

        local power_w = _forge_get_widget(panel, "loadout_power_text")
        if power_w and power_w.content then
            power_w.content.text = "MOD WEAPON CRAFTING"
            power_w.content.visible = true
            if power_w.style and power_w.style.text then
                power_w.style.text.font_size = 28
                power_w.style.text.text_color = {255, 255, 255, 255}
            end
            if power_w.style and power_w.style.text_shadow then
                power_w.style.text_shadow.font_size = 28
            end
        end

        _forge_hide_widget(panel, "background_wheel_1")
        _forge_hide_widget(panel, "hdr_background_wheel_1")
        for i = 1, 3 do
            _forge_hide_widget(panel, "wheel_ring_1_" .. i)
            _forge_hide_widget(panel, "wheel_ring_2_" .. i)
            _forge_hide_widget(panel, "hdr_wheel_ring_1_" .. i)
            _forge_hide_widget(panel, "hdr_wheel_ring_2_" .. i)
        end

        _forge_set_style_color(panel, "top_glow_smoke_1", "texture_id", {200, 180, 20, 10})
    end

    -- === BACKGROUND: change smoke colors to deep red ===
    if background and not _forge_bg_colored then
        _forge_set_style_color(background, "bottom_glow_smoke_1", "texture_id", {200, 180, 20, 10})
        _forge_set_style_color(background, "bottom_glow_smoke_2", "texture_id", {255, 200, 30, 10})
        _forge_set_style_color(background, "bottom_glow_smoke_3", "texture_id", {200, 180, 25, 15})
        _forge_set_style_color(background, "bottom_glow_embers_1", "texture_id", {130, 255, 60, 20})
        _forge_set_style_color(background, "bottom_glow_embers_3", "texture_id", {130, 255, 60, 20})
        _forge_bg_colored = true
    end

    -- === PROPERTIES sub-menu: hide level/mastery, fix power ===
    local properties_win = nil
    for _, win in pairs(windows) do
        if win.NAME == "HeroWindowWeaveProperties" then properties_win = win end
    end
    if properties_win then
        _forge_hide_widget(properties_win, "viewport_level_title")
        _forge_hide_widget(properties_win, "viewport_level_value")
        _forge_hide_widget(properties_win, "viewport_panel_divider")
        _forge_hide_widget(properties_win, "mastery_text")
        _forge_hide_widget(properties_win, "mastery_title_text")
        _forge_hide_widget(properties_win, "mastery_icon")
        _forge_hide_widget(properties_win, "mastery_tooltip")
        -- upgrade_button is repurposed as our "Craft New" button (see hook on
        -- HeroWindowWeaveProperties._upgrade_magic_level below). Keep visible
        -- and re-label per slot type.
        local craft_label = "CRAFT"
        local p = properties_win._params
        local sn = p and p.selected_slot_name
        if sn == "slot_melee" then craft_label = "CRAFT NEW WEAPON"
        elseif sn == "slot_ranged" then craft_label = "CRAFT NEW WEAPON"
        elseif sn == "slot_necklace" then craft_label = "CRAFT NEW NECKLACE"
        elseif sn == "slot_charm" then craft_label = "CRAFT NEW CHARM"
        elseif sn == "slot_trinket" then craft_label = "CRAFT NEW TRINKET"
        end
        _forge_set_text(properties_win, "upgrade_text", craft_label)
        _forge_hide_widget(properties_win, "upgrade_essence_warning")
        _forge_hide_widget(properties_win, "background_wheel")
        _forge_hide_widget(properties_win, "hdr_background_wheel")
        for i = 1, 3 do
            _forge_hide_widget(properties_win, "wheel_ring_" .. i)
            _forge_hide_widget(properties_win, "hdr_wheel_ring_" .. i)
        end

        _forge_set_style_color(properties_win, "cluster_background_effect_1", "texture_id", {200, 180, 20, 10})

        local params = properties_win._params
        local sel_item = params and params.selected_item
        if sel_item and sel_item.backend_id then
            local items_backend = Managers.backend and Managers.backend:get_interface("items")
            if items_backend then
                local item = items_backend:get_item_from_id(sel_item.backend_id)
                if item then
                    _forge_set_text(properties_win, "viewport_power_value", tostring(item.power_level or 300))
                end
            end
        end
    end
end

mod:hook_safe("HeroViewStateWeaveForge", "update", function(self, dt, t)
    if _custom_forge_active then
        _forge_apply_ui_polish(self)
    end
end)

-- --- Backend safety hooks (prevent crashes for non-weave items) ---

-- CLARIFY: 16+ Weaves backend hooks below all follow the same pattern: when
-- our custom forge is active, return faked values (max forge level, infinite
-- essence, zero costs, etc.) so the Athanor UI doesn't gate on weave progression.
-- When the custom forge is NOT active, fall through to the original — leaves
-- vanilla Weaves mode untouched. The custom forge is opened only via our
-- `open_forge` keybind, so non-mod weaves play stays clean.
mod:hook("BackendInterfaceWeavesPlayFab", "get_forge_level", function(func, self)
    if _custom_forge_active then return 999 end
    return func(self)
end)

mod:hook("BackendInterfaceWeavesPlayFab", "get_essence", function(func, self)
    if _custom_forge_active then return 999999 end
    return func(self)
end)

mod:hook("BackendInterfaceWeavesPlayFab", "get_maximum_essence", function(func, self)
    if _custom_forge_active then return 999999 end
    return func(self)
end)

mod:hook("BackendInterfaceWeavesPlayFab", "get_total_essence", function(func, self)
    if _custom_forge_active then return 999999 end
    return func(self)
end)

mod:hook("BackendInterfaceWeavesPlayFab", "get_property_required_forge_level", function(func, self, property_name)
    if _custom_forge_active then return 0 end
    return func(self, property_name)
end)

mod:hook("BackendInterfaceWeavesPlayFab", "get_property_mastery_costs", function(func, self, property_name)
    if _custom_forge_active then return {0, 0, 0, 0, 0} end
    return func(self, property_name)
end)

mod:hook("BackendInterfaceWeavesPlayFab", "get_trait_required_forge_level", function(func, self, trait_key)
    if _custom_forge_active then return 0 end
    return func(self, trait_key)
end)

mod:hook("BackendInterfaceWeavesPlayFab", "get_trait_mastery_cost", function(func, self, trait_key)
    if _custom_forge_active then return 0 end
    return func(self, trait_key)
end)

mod:hook("BackendInterfaceWeavesPlayFab", "get_talent_mastery_cost", function(func, self, talent_name)
    if _custom_forge_active then return 0 end
    return func(self, talent_name)
end)

mod:hook("BackendInterfaceWeavesPlayFab", "get_career_magic_level", function(func, self, career_name)
    if _custom_forge_active then return 999 end
    local ok, result = pcall(func, self, career_name)
    if ok then return result end
    return 0
end)

mod:hook("BackendInterfaceWeavesPlayFab", "get_item_magic_level", function(func, self, item_backend_id)
    if _custom_forge_active then return 999 end
    local ok, result = pcall(func, self, item_backend_id)
    if ok then return result end
    return 0
end)

mod:hook("BackendInterfaceWeavesPlayFab", "max_magic_level", function(func, self)
    if _custom_forge_active then return 999 end
    return func(self)
end)

mod:hook("BackendInterfaceWeavesPlayFab", "forge_magic_level_cap", function(func, self)
    if _custom_forge_active then return 999 end
    return func(self)
end)

mod:hook("BackendInterfaceWeavesPlayFab", "magic_item_cost", function(func, self, item_key)
    if _custom_forge_active then return 0 end
    return func(self, item_key)
end)

mod:hook("BackendInterfaceWeavesPlayFab", "get_average_power_level", function(func, self, career_name)
    if _custom_forge_active then return 300 end
    local ok, result = pcall(func, self, career_name)
    if ok then return result end
    return 300
end)

mod:hook("BackendInterfaceWeavesPlayFab", "magic_item_upgrade_cost", function(func, self, num_levels, item_backend_id)
    if _custom_forge_active then return 0 end
    local ok, result = pcall(func, self, num_levels, item_backend_id)
    if ok then return result end
    return 0
end)

mod:hook("BackendInterfaceWeavesPlayFab", "career_upgrade_cost", function(func, self, num_levels, career_name)
    if _custom_forge_active then return 0 end
    local ok, result = pcall(func, self, num_levels, career_name)
    if ok then return result end
    return 0
end)

-- --- Forge loadout (redirect weave loadout to our own table) ---

mod:hook("BackendInterfaceWeavesPlayFab", "get_loadout_item_id", function(func, self, career_name, slot_name)
    if _custom_forge_active then
        local loadout = _forge_loadout[career_name]
        if loadout and loadout[slot_name] then
            return loadout[slot_name]
        end
        local items_backend = Managers.backend:get_interface("items")
        if items_backend then
            local ok, bid = pcall(items_backend.get_loadout_item_id, items_backend, career_name, slot_name)
            if ok then return bid end
        end
        return nil
    end
    return func(self, career_name, slot_name)
end)

mod:hook("BackendInterfaceWeavesPlayFab", "set_loadout_item", function(func, self, item_backend_id, career_name, slot_name)
    if _custom_forge_active then
        _forge_loadout[career_name] = _forge_loadout[career_name] or {}
        _forge_loadout[career_name][slot_name] = item_backend_id
        return true
    end
    return func(self, item_backend_id, career_name, slot_name)
end)

-- --- Property/trait/talent storage (redirect to our own data) ---

-- Maps amulet trait-slot index → adventure jewellery slot. The amulet layout
-- has 3 trait slots and 3 property layers; vanilla `WeaveCareerProgression`
-- (`weave_loadout_settings.lua:282-295`) orders them by accessory POOL:
--   slot 1 = offence_accessory (CHARM)
--   slot 2 = defence_accessory (NECKLACE)
--   slot 3 = utility_accessory (TRINKET)
-- The picker for slot N reads its `category` from that table and renders the
-- matching property/trait pool, so we MUST seed/apply against the same order
-- or the bubble grid shows charm options where the player sees necklace data.
--
-- VT2's career_settings names the charm slot `slot_ring` (legacy) and the
-- trinket slot `slot_trinket_1` (note the suffix). `slot_charm`/`slot_trinket`
-- return nil from `get_loadout_item_id`.
local _AMULET_SLOT_BY_INDEX = {
    [1] = "slot_ring",         -- offence_accessory → charm
    [2] = "slot_necklace",     -- defence_accessory → necklace
    [3] = "slot_trinket_1",    -- utility_accessory → trinket
}
local _AMULET_INDEX_BY_SLOT = {}
for idx, slot in pairs(_AMULET_SLOT_BY_INDEX) do _AMULET_INDEX_BY_SLOT[slot] = idx end
local _AMULET_LAYER_SIZE = 10  -- matches amulet_slot_layout's per-layer count

-- Per-slot dirty tracking for the amulet's CRAFT button. The auto-apply
-- mutates equipped items in-place on every bubble click (session-only for
-- vanilla), so the user's bubble edits are already applied by the time they
-- reach CRAFT — but for vanilla items those edits don't survive a restart.
-- CRAFT solves that by creating a new modded item per dirty slot. We mark a
-- slot dirty on any property/trait set/remove against the amulet (item_backend_id == nil).
-- (`_amulet_dirty` is forward-declared near the top of the Athanor section so
-- the on_exit hook can reset it; the table itself was created there.)

local function _mark_amulet_property_dirty(slot_index)
    local layer = math.ceil((slot_index or 0) / _AMULET_LAYER_SIZE)
    if layer >= 1 and layer <= 3 then _amulet_dirty[layer] = true end
end

local function _mark_amulet_trait_dirty(slot_index)
    if slot_index and slot_index >= 1 and slot_index <= 3 then
        _amulet_dirty[slot_index] = true
    end
end

local function _seed_one_item(item, props_out, traits_out, slot_index)
    if not item then return end
    local layer_offset = (slot_index - 1) * _AMULET_LAYER_SIZE
    if item.properties then
        local wp = rawget(_G, "WeaveProperties")
        local wp_props = wp and wp.properties
        local num_slots = 5
        local next_slot = layer_offset + 1
        for prop_key, value in pairs(item.properties) do
            local weave_key = "weave_" .. prop_key
            if wp_props and wp_props[weave_key] then
                local filled = math.max(1, math.ceil(value * num_slots))
                local indices = {}
                for i = 1, filled do
                    indices[i] = next_slot
                    next_slot = next_slot + 1
                end
                props_out[weave_key] = indices
            else
                mod:info("Forge seed: no weave mapping for prop '%s' (tried '%s')", prop_key, weave_key)
            end
        end
    end
    if item.traits and item.traits[1] then
        local wt = rawget(_G, "WeaveTraits")
        local wt_traits = wt and wt.traits
        local trait_key = item.traits[1]
        local weave_key = "weave_" .. trait_key
        if wt_traits and wt_traits[weave_key] then
            traits_out[weave_key] = slot_index
        else
            mod:info("Forge seed: no weave mapping for trait '%s' (tried '%s')", trait_key, weave_key)
        end
    end
end

local function _forge_seed_item(career_name, item_backend_id)
    local key = (career_name or "") .. "|" .. (item_backend_id or "")
    if _forge_item_props[key] then return _forge_item_props[key] end

    local props = {}
    local traits = {}
    local items_backend = Managers.backend:get_interface("items")

    if item_backend_id then
        -- Single-item case: weapon (melee/ranged) editor.
        local item = items_backend and items_backend:get_item_from_id(item_backend_id)
        if item then _seed_one_item(item, props, traits, 1) end
    elseif items_backend and career_name then
        -- Amulet case: aggregate the three equipped accessories into one
        -- bubble grid (necklace=layer 1, charm=layer 2, trinket=layer 3).
        for slot_index, slot_name in ipairs(_AMULET_SLOT_BY_INDEX) do
            local bid = items_backend:get_loadout_item_id(career_name, slot_name)
            local item = bid and items_backend:get_item_from_id(bid)
            _seed_one_item(item, props, traits, slot_index)
        end
    end

    _forge_item_props[key] = {properties = props, traits = traits}
    return _forge_item_props[key]
end

-- Amulet apply: bubble-grid edits live under the (career, nil) key. Each
-- property's slot indices span 1..30 — layer N (size 10) = accessory N.
-- Group per-layer fills, convert back to fractional values, write to each
-- accessory's `item.properties` / `item.traits` (and persist if modded).
local function _forge_apply_to_amulet(career_name)
    local key = (career_name or "") .. "|"
    local data = _forge_item_props[key]
    if not data then return end

    local items_backend = Managers.backend:get_interface("items")
    if not items_backend then return end

    local num_slots = 5

    -- Group property fills by layer (= accessory slot 1/2/3)
    local per_slot_props = { {}, {}, {} }
    for weave_key, slot_indices in pairs(data.properties or {}) do
        local prop_key = weave_key:gsub("^weave_", "")
        local layer_counts = { 0, 0, 0 }
        for _, idx in ipairs(slot_indices) do
            local layer = math.ceil(idx / _AMULET_LAYER_SIZE)
            if layer >= 1 and layer <= 3 then
                layer_counts[layer] = layer_counts[layer] + 1
            end
        end
        for layer, count in ipairs(layer_counts) do
            if count > 0 then
                per_slot_props[layer][prop_key] = math.min(count / num_slots, 1.0)
            end
        end
    end

    -- Map traits by slot index → accessory
    local per_slot_trait = {}
    for weave_key, slot_index in pairs(data.traits or {}) do
        if slot_index >= 1 and slot_index <= 3 then
            per_slot_trait[slot_index] = weave_key:gsub("^weave_", "")
        end
    end

    -- Apply to each accessory
    for slot_index, slot_name in ipairs(_AMULET_SLOT_BY_INDEX) do
        local bid = items_backend:get_loadout_item_id(career_name, slot_name)
        local item = bid and items_backend:get_item_from_id(bid)
        if item then
            local new_props = per_slot_props[slot_index] or {}
            local new_traits = per_slot_trait[slot_index] and { per_slot_trait[slot_index] } or {}
            item.properties = new_props
            item.traits = new_traits

            local cjson_mod = rawget(_G, "cjson")
            if cjson_mod and item.CustomData then
                item.CustomData.properties = cjson_mod.encode(new_props)
                item.CustomData.traits = cjson_mod.encode(new_traits)
            end

            local saved = _forged_weapons[bid]
            if saved then
                saved.properties = new_props
                saved.traits = new_traits
                saved.trait = new_traits[1]
                _forge_save()
            end
        end
    end
end

local function _forge_apply_to_item(career_name, item_backend_id)
    if not item_backend_id then
        _forge_apply_to_amulet(career_name)
        return
    end
    local items_backend = Managers.backend:get_interface("items")
    local item = items_backend and items_backend:get_item_from_id(item_backend_id)
    if not item then return end

    local data = _forge_seed_item(career_name, item_backend_id)
    local num_slots = 5

    local new_props = {}
    for weave_key, slots in pairs(data.properties) do
        local prop_key = weave_key:gsub("^weave_", "")
        local value = #slots / num_slots
        new_props[prop_key] = math.min(value, 1.0)
    end
    item.properties = new_props

    local new_traits = {}
    for weave_key, _ in pairs(data.traits) do
        local trait_key = weave_key:gsub("^weave_", "")
        new_traits[#new_traits + 1] = trait_key
    end
    item.traits = new_traits

    local cjson_mod = rawget(_G, "cjson")
    if cjson_mod and item.CustomData then
        item.CustomData.properties = cjson_mod.encode(new_props)
        item.CustomData.traits = cjson_mod.encode(new_traits)
    end

    -- Persist edits to bubble grid back into our forged_weapons save entry.
    local saved = _forged_weapons[item_backend_id]
    if saved then
        saved.properties = new_props
        saved.traits = new_traits
        saved.trait = new_traits[1]
        _forge_save()
    end
end

mod:hook("BackendInterfaceWeavesPlayFab", "get_loadout_properties", function(func, self, career_name, item_backend_id)
    if _custom_forge_active then
        local data = _forge_seed_item(career_name, item_backend_id)
        return data.properties
    end
    return func(self, career_name, item_backend_id)
end)

mod:hook("BackendInterfaceWeavesPlayFab", "get_loadout_traits", function(func, self, career_name, item_backend_id)
    if _custom_forge_active then
        local data = _forge_seed_item(career_name, item_backend_id)
        return data.traits
    end
    return func(self, career_name, item_backend_id)
end)

-- Adventure-talent helpers. The amulet UI's talent picker runs against the
-- weave talent system, but `WeaveLoadoutSettings[career].talent_tree` is
-- literally `TalentTrees[profile][index]` (see weave_loadout_settings_*.lua),
-- i.e. the same tree adventure mode uses. So we can map the player's
-- adventure picks (numeric column 1..3 per row) into the
-- `{[talent_name] = row}` shape the bubble grid expects.
local function _get_career_talent_tree(career_name)
    local cs = CareerSettings[career_name]
    if not cs then return nil end
    local TalentTrees = rawget(_G, "TalentTrees")
    if not TalentTrees then return nil end
    local tree = TalentTrees[cs.profile_name]
    return tree and tree[cs.talent_tree_index]
end

mod:hook("BackendInterfaceWeavesPlayFab", "get_loadout_talents", function(func, self, career_name)
    if not _custom_forge_active then return func(self, career_name) end
    local talents_iface = Managers.backend and Managers.backend:get_interface("talents")
    if not talents_iface then return {} end
    local picks = talents_iface:get_talents(career_name)
    if not picks then return {} end
    local tree = _get_career_talent_tree(career_name)
    if not tree then return {} end

    local result = {}
    for row, pick in ipairs(picks) do
        local row_talents = tree[row]
        if row_talents and pick and row_talents[pick] then
            result[row_talents[pick]] = row
        end
    end
    return result
end)

mod:hook("BackendInterfaceWeavesPlayFab", "get_mastery", function(func, self, career_name, item_backend_id)
    if _custom_forge_active then return 0, 0 end
    local ok, a, b = pcall(func, self, career_name, item_backend_id)
    if ok then return a, b end
    return 0, 0
end)

mod:hook("BackendInterfaceWeavesPlayFab", "set_loadout_property", function(func, self, career_name, property_key, slot_index, item_backend_id)
    if _custom_forge_active then
        local data = _forge_seed_item(career_name, item_backend_id)
        local props = data.properties
        if not props[property_key] then
            props[property_key] = {}
        end
        props[property_key][#props[property_key] + 1] = slot_index
        if not item_backend_id then _mark_amulet_property_dirty(slot_index) end
        _forge_apply_to_item(career_name, item_backend_id)
        return
    end
    return func(self, career_name, property_key, slot_index, item_backend_id)
end)

mod:hook("BackendInterfaceWeavesPlayFab", "remove_loadout_property", function(func, self, career_name, property_key, slot_index, item_backend_id)
    if _custom_forge_active then
        local data = _forge_seed_item(career_name, item_backend_id)
        local slots = data.properties[property_key]
        if slots then
            for i, s in ipairs(slots) do
                if s == slot_index then
                    table.remove(slots, i)
                    break
                end
            end
            if #slots == 0 then
                data.properties[property_key] = nil
            end
        end
        if not item_backend_id then _mark_amulet_property_dirty(slot_index) end
        _forge_apply_to_item(career_name, item_backend_id)
        return
    end
    return func(self, career_name, property_key, slot_index, item_backend_id)
end)

mod:hook("BackendInterfaceWeavesPlayFab", "set_loadout_trait", function(func, self, career_name, trait_key, slot_index, item_backend_id)
    if _custom_forge_active then
        local data = _forge_seed_item(career_name, item_backend_id)
        data.traits[trait_key] = slot_index
        if not item_backend_id then _mark_amulet_trait_dirty(slot_index) end
        _forge_apply_to_item(career_name, item_backend_id)
        return
    end
    return func(self, career_name, trait_key, slot_index, item_backend_id)
end)

mod:hook("BackendInterfaceWeavesPlayFab", "remove_loadout_trait", function(func, self, career_name, trait_key, item_backend_id)
    if _custom_forge_active then
        local data = _forge_seed_item(career_name, item_backend_id)
        local removed_slot = data.traits[trait_key]
        data.traits[trait_key] = nil
        if not item_backend_id then _mark_amulet_trait_dirty(removed_slot) end
        _forge_apply_to_item(career_name, item_backend_id)
        return
    end
    return func(self, career_name, trait_key, item_backend_id)
end)

mod:hook("BackendInterfaceWeavesPlayFab", "set_loadout_talent", function(func, self, career_name, talent_key, slot_index)
    if not _custom_forge_active then return func(self, career_name, talent_key, slot_index) end
    local tree = _get_career_talent_tree(career_name)
    local row_talents = tree and tree[slot_index]
    if not row_talents then return end

    -- Find which column in row `slot_index` this talent_key is.
    local column
    for c, t_name in ipairs(row_talents) do
        if t_name == talent_key then column = c; break end
    end
    if not column then return end

    local talents_iface = Managers.backend and Managers.backend:get_interface("talents")
    if not talents_iface then return end

    local picks = talents_iface:get_talents(career_name)
    if not picks then picks = {} end
    -- Adventure expects 6 picks; default missing rows to column 1 to avoid
    -- nil entries when serialized.
    for i = 1, 6 do
        if not picks[i] then picks[i] = 1 end
    end
    picks[slot_index] = column
    talents_iface:set_talents(career_name, picks)
end)

mod:hook("BackendInterfaceWeavesPlayFab", "remove_loadout_talent", function(func, self, career_name, talent_key)
    if not _custom_forge_active then return func(self, career_name, talent_key) end
    -- No-op: the bubble grid emits remove → set on each pick swap. We commit
    -- the new pick in `set_loadout_talent` directly; vanilla expected pair
    -- semantics aren't needed because adventure rows always have one talent.
end)

-- CLARIFY: while either forge is open, suppress backend commits entirely so the
-- simulated mutations (Athanor property/trait edits, standard-forge salvage/upgrade/
-- skin/etc) don't leak to PlayFab and trigger the anti-tamper "Backend rejected
-- the challenge response -1" kick. The standard-forge module sets
-- `mod._cim_standard_forge_active` while its UI is open; we check both flags here.
-- Single registration: standard_forge.lua MUST NOT install its own commit hook,
-- otherwise VMF warns "Attempting to rehook active hook [commit]" and drops the
-- second registration → standard-forge mutations leak to PlayFab.
mod:hook("BackendManagerPlayFab", "commit", function(func, self, skip_queue, commit_complete_callback)
    if _custom_forge_active or mod._cim_standard_forge_active then return end
    return func(self, skip_queue, commit_complete_callback)
end)

-- --- Weapon list: show ALL weapons, not just weave "magic" rarity ---

mod:hook("HeroWindowWeaveForgeWeapons", "_setup_weapon_list", function(func, self)
    if not _custom_forge_active then return func(self) end

    local backend_items = Managers.backend:get_interface("items")
    local selected_slot_name = self._selected_slot_name
    local career_name = self._career_name
    local career_settings = CareerSettings[career_name]
    local item_slot_types = career_settings.item_slot_types_by_slot_name[selected_slot_name]
    local weapon_layout = {}
    local seen_names = {}

    for key, item_data in pairs(ItemMasterList) do
        local slot_type = item_data.slot_type
        if slot_type and table.contains(item_slot_types, slot_type) then
            local can_wield = item_data.can_wield
            if can_wield and table.contains(can_wield, career_name) then
                local rarity = item_data.rarity
                if item_data.item_type ~= "weapon_skin" and rarity ~= "magic" and rarity ~= "promo" then
                    local dn = item_data.display_name or key
                    if not seen_names[dn] then
                        seen_names[dn] = true
                        weapon_layout[#weapon_layout + 1] = {
                            key = key,
                            item_data = item_data,
                            backend_id = nil,
                        }
                    end
                end
            end
        end
    end

    self:_populate_list(weapon_layout)

    -- Strip weave-specific "Magic Level: 100" and "1800" power text from each entry; this is just a crafting template list.
    local scrollbar_data = self._scrollbars and self._scrollbars.weapons
    local list_widgets = scrollbar_data and scrollbar_data.list_widgets
    if list_widgets then
        for _, widget in ipairs(list_widgets) do
            local c = widget.content
            c.level_title = ""
            c.power_text = ""
            c.power_title = ""
            c.magic_level = 0
            c.level_progress = 0
        end
    end
end)

-- Keep the level/power fields blank — vanilla `_sync_backend_loadout` repopulates them every refresh.
mod:hook("HeroWindowWeaveForgeWeapons", "_sync_backend_loadout", function(func, self)
    func(self)
    if not _custom_forge_active then return end
    local scrollbar_data = self._scrollbars and self._scrollbars.weapons
    local list_widgets = scrollbar_data and scrollbar_data.list_widgets
    if list_widgets then
        for _, widget in ipairs(list_widgets) do
            local c = widget.content
            c.level_title = ""
            c.power_text = ""
            c.power_title = ""
        end
    end
end)

-- --- Weapon select: present item without locked/essence state ---

mod:hook("HeroWindowWeaveForgeWeapons", "_present_item", function(func, self, item_key, activate_spin)
    if not _custom_forge_active then return func(self, item_key, activate_spin) end

    local viewport_data = self._viewport_data
    if viewport_data and viewport_data.item_previewer then
        viewport_data.item_previewer:destroy()
        viewport_data.item_previewer = nil
    end

    local backend_items = Managers.backend:get_interface("items")
    local item = backend_items:get_item_from_key(item_key)
    local display_item = item

    if not display_item then
        local entry = rawget(ItemMasterList, item_key)
        if entry then
            local item_data = table.clone(entry)
            item_data.key = item_key
            display_item = { data = item_data, key = item_key }
        end
    end

    local viewport_widget = viewport_data.widget
    local item_previewer = self:_create_item_previewer(viewport_widget, display_item, activate_spin)
    viewport_data.item_previewer = item_previewer
    viewport_data.item = display_item

    local item_data = display_item.data
    local power_level = display_item.power_level or 300

    local widgets_by_name = self._widgets_by_name
    widgets_by_name.viewport_level_value.content.visible = false
    widgets_by_name.viewport_level_title.content.visible = false
    widgets_by_name.viewport_power_value.content.text = tostring(power_level)
    widgets_by_name.viewport_power_title.content.visible = true
    widgets_by_name.viewport_power_value.content.visible = true
    widgets_by_name.viewport_title.content.text = Localize(item_data.display_name)
    widgets_by_name.viewport_sub_title.content.text = Localize(item_data.item_type)

    self:_set_presentation_locked_state(false)
    self._selected_item_locked = false
    self:_setup_weapon_stats(display_item)

    return item_key
end)

-- --- Weapon select: never show locked/unlock UI in custom forge ---

mod:hook("HeroWindowWeaveForgeWeapons", "_set_presentation_locked_state", function(func, self, locked)
    if not _custom_forge_active then return func(self, locked) end
    func(self, false)
end)

-- --- Weapon select: "CRAFT" button instead of "Equip" ---

mod:hook("HeroWindowWeaveForgeWeapons", "_update_equip_button_status", function(func, self, equipable_item, is_item_equipped)
    if not _custom_forge_active then return func(self, equipable_item, is_item_equipped) end

    local viewport_data = self._viewport_data
    if viewport_data then
        local equip_button = viewport_data.equip_button
        equip_button.content.button_hotspot.disable_button = not self._selected_item_id
        equip_button.content.title_text = "CRAFT"
    end
end)

-- --- Weapon select: on_list_index_selected — always enable craft button ---

mod:hook("HeroWindowWeaveForgeWeapons", "_on_list_index_selected", function(func, self, index)
    if not _custom_forge_active then return func(self, index) end

    local scrollbars = self._scrollbars
    local scrollbar_data = scrollbars.weapons
    local list_widgets = scrollbar_data.list_widgets

    for i, widget in ipairs(list_widgets) do
        local content = widget.content
        local hotspot = content.button_hotspot
        local is_selected = i == index

        hotspot.is_selected = is_selected

        if is_selected then
            self._selected_backend_id = self:_present_item(content.key)
            self._selected_item_id = content.key
        end
    end

    self._selected_list_index = index
    self:_update_equip_button_status(true, false)
end)

-- Build an Athanor-crafted item via the PlayFab backend mirror so it shows up
-- as a real inventory item (purple `promo` rarity, eligible for cosmetic skin
-- changes). Unlike MoreItemsLibrary's `add_mod_items_to_local_backend`, this
-- path doesn't tag the entry as a mod template — so the cosmetics screen and
-- skin swapper treat it as a normal owned weapon.
local function _athanor_inject_item(weapon_data, backend_id)
    local backend_mirror = Managers.backend and Managers.backend:get_backend_mirror()
    if not backend_mirror then return nil, "backend mirror not ready" end

    -- Pre-check ItemMasterList: backend_mirror:add_item calls
    -- `ItemMasterList[item.ItemId]` (playfab_mirror_base.lua:2504), and the
    -- table's __index Crashifies on unknown keys → game-closing crash.
    -- Saved crafts can reference cwv_* items that the
    -- character_weapon_variants mod hasn't registered yet at this stage of
    -- backend init. Skip injection for unknown keys (re-craft is recoverable).
    local item_key = weapon_data.item_key
    if not item_key or not rawget(ItemMasterList, item_key) then
        return nil, "item_key '" .. tostring(item_key) .. "' not in ItemMasterList yet"
    end

    local cjson_mod = rawget(_G, "cjson")
    local props = weapon_data.properties or {}
    local traits = weapon_data.traits or (weapon_data.trait and {weapon_data.trait}) or {}

    local custom_data = {
        power_level = tostring(weapon_data.power_level or 300),
        rarity = weapon_data.rarity or "modded",
    }
    if cjson_mod then
        custom_data.properties = cjson_mod.encode(props)
        custom_data.traits = cjson_mod.encode(traits)
    end
    if weapon_data.skin then custom_data.skin = weapon_data.skin end

    local item = {
        ItemId = item_key,
        ItemInstanceId = backend_id,
        CustomData = custom_data,
    }

    local ok, err = pcall(backend_mirror.add_item, backend_mirror, backend_id, item)
    if not ok then return nil, err end
    return backend_id
end

-- Re-add every saved mirror-path craft (Athanor + standard forge) to the live
-- backend mirror after PlayFab finishes its sync. Items flagged `via_mirror = false`
-- go through the legacy MIL path via `_forge_inject_all` instead.
-- Tracks bids whose first injection attempt was skipped (ItemMasterList not
-- ready). Retried on each subsequent `_create_interfaces` call AND on game
-- state transitions, so once CWV / other mods finish loading their items,
-- the saved crafts make it back into the inventory.
local _pending_inject = {}

_athanor_inject_all = function()
    local count, skipped = 0, 0
    _pending_inject = {}
    for bid, w in pairs(_forged_weapons) do
        if w.via_mirror then
            local mirror = Managers.backend and Managers.backend:get_backend_mirror()
            -- If the item is already in the mirror (a previous _create_interfaces
            -- call already injected it), skip the re-add. add_item is idempotent
            -- but logging extra "restored" lines is misleading.
            local already_in = mirror and mirror._inventory_items and mirror._inventory_items[bid]
            if already_in then
                count = count + 1
            else
                local ok, err = _athanor_inject_item(w, bid)
                if ok then
                    count = count + 1
                else
                    skipped = skipped + 1
                    _pending_inject[bid] = w
                    mod:info("Skipped saved craft %s: %s", tostring(w.item_key), tostring(err))
                end
            end
        end
    end
    if count > 0 then mod:info("Restored %d crafted weapons (mirror path)", count) end
    if skipped > 0 then
        mod:echo(string.format("[cim] %d saved crafts deferred (waiting for sibling mods to register their ItemMasterList entries — will retry on next state transition)", skipped))
    end
end

-- Retry any deferred injections. Called on `_create_interfaces` re-fires and
-- on game-state changes. Cheap when `_pending_inject` is empty.
local function _athanor_retry_pending()
    if not next(_pending_inject) then return end
    local recovered = 0
    for bid, w in pairs(_pending_inject) do
        local ok = _athanor_inject_item(w, bid)
        if ok then
            _pending_inject[bid] = nil
            recovered = recovered + 1
        end
    end
    if recovered > 0 then
        mod:echo(string.format("[cim] Re-injected %d previously-deferred craft(s)", recovered))
    end
end

mod.on_game_state_changed = function()
    _athanor_retry_pending()
end

-- --- Weapon select: craft item on equip press ---

mod:hook("HeroWindowWeaveForgeWeapons", "_equip_item", function(func, self, backend_id_or_key)
    if not _custom_forge_active then return func(self, backend_id_or_key) end

    local item_key = self._selected_item_id
    if not item_key then
        mod:echo("Craft failed: no weapon selected")
        return
    end

    local new_backend_id = Application.guid()
    local weapon_data = {
        item_key = item_key,
        properties = {},
        traits = {},
        power_level = 300,
        rarity = "modded",
        via_mirror = true,
    }

    local injected, err = _athanor_inject_item(weapon_data, new_backend_id)
    if not injected then
        mod:echo("Craft failed: " .. tostring(err))
        return
    end

    _forged_weapons[new_backend_id] = weapon_data
    _forge_save()

    local career_name = self._career_name
    local slot_name = self._selected_slot_name
    local backend_items = Managers.backend:get_interface("items")
    local ok2, err2 = pcall(backend_items.set_loadout_item, backend_items, new_backend_id, career_name, slot_name)
    if not ok2 then
        mod:echo("Equip failed: " .. tostring(err2))
    end

    local _master = rawget(ItemMasterList, item_key)
    local _name = (_master and _master.display_name) or item_key
    mod:echo("Crafted & saved: " .. tostring(Localize(_name)) .. " [" .. tostring(weapon_data.rarity) .. "]")

    self:_sync_backend_loadout()
    self._equip_pulse_duration = 0.5
end)

-- --- Overview: show the amulet viewport (modded jewellery + talents editor entry point) ---
-- Vanilla gates the central amulet viewport behind the WoM tutorial via
-- `amulet_introduced`. For the modded forge we always want it visible — it's
-- the entry point to the jewellery + talents editor (see AMULET_OF_ASHUR.md).

mod:hook("HeroWindowWeaveForgeOverview", "_initialize_viewports", function(func, self)
    if _custom_forge_active then
        self.amulet_introduced = true
    end
    return func(self)
end)

-- --- Amulet (viewport_2) click: let vanilla open its native amulet layout ---
-- `HeroWindowWeaveProperties.on_enter` (line 167-196) selects between two
-- pre-built layouts based on `self:_selected_item()`:
--   * non-nil → `weapon_slot_layout` (1 trait + 10 properties — for melee/ranged)
--   * nil      → `amulet_slot_layout` (3 traits + 30 properties × 3 layers + 6 talents)
-- The amulet viewport's `data.item` is nil, so a click flows through to
-- `weave_properties` with `selected_item = nil` and the WoM-style 3-section
-- amulet layout renders automatically. We don't override the click anymore;
-- our `BackendInterfaceWeavesPlayFab` hooks supply the bubble grid's data.
--
-- The `_forge_seed_item` / `_forge_apply_to_item` chain handles the 3-item
-- case via the `career_name + nil item_backend_id` key (the amulet's params
-- carry no `item_backend_id`); we read all three accessory slots and write
-- back to all three on apply. (See _forge_seed_amulet below.)

-- --- Craft button (repurposed upgrade_button) ---
-- The properties window's upgrade_button is the most natural anchor for a
-- "Craft New" action. Hijack `_upgrade_magic_level` so pressing it instead
-- creates a new modded item with the player's current bubble-grid edits and
-- equips it in place of the existing item.
--
-- Vanilla's `_set_essence_upgrade_cost` (hero_window_weave_properties.lua:1856)
-- runs each refresh and sets:
--   * `button_content.title_text` = "Fully Upgraded" when `essence_amount` is
--     nil (it always is in modded — our weaves hooks return 0 essence).
--   * `disable_button = true` when `script_data["eac-untrusted"]` is true
--     (it always is in modded realm).
-- Post-hook to overwrite both so the button reads "CRAFT" and is clickable.
mod:hook_safe("HeroWindowWeaveProperties", "_set_essence_upgrade_cost", function(self, essence_amount, can_afford, magic_cap_reached)
    if not _custom_forge_active then return end
    local widgets_by_name = self._widgets_by_name
    local btn = widgets_by_name and widgets_by_name.upgrade_button
    if not btn then return end
    local label = "CRAFT"
    local item = self:_selected_item()
    if not item then
        label = "CRAFT MODDED JEWELLERY"
    else
        local slot_type = item.data and item.data.slot_type
        if slot_type == "melee" or slot_type == "ranged" then
            label = "CRAFT NEW WEAPON"
        end
    end
    btn.content.title_text = label
    btn.content.button_hotspot.disable_button = false
    if btn.style and btn.style.price_icon then btn.style.price_icon.color[1] = 0 end
    if btn.style and btn.style.price_icon_disabled then btn.style.price_icon_disabled.color[1] = 0 end
    -- Also clear the "not enough essence" warning that vanilla shows when cap
    -- is reached — we don't use essence in modded.
    local warn = widgets_by_name.upgrade_essence_warning
    if warn and warn.content then warn.content.visible = false end
end)

mod:hook("HeroWindowWeaveProperties", "_upgrade_magic_level", function(func, self)
    if not _custom_forge_active then return func(self) end

    local item = self:_selected_item()
    local item_data = item and item.data
    local item_key = item_data and (item_data.key or item_data.name)

    -- Amulet case: no selected_item. Iterate dirty accessory slots; for each,
    -- create a new modded item with the current bubble state and equip it.
    if not item then
        local backend_items = Managers.backend and Managers.backend:get_interface("items")
        local career_name = self._career_name
        if not backend_items or not career_name then
            mod:echo("[cim] Craft: backend / career not ready")
            return
        end
        local crafted = 0
        for slot_index, slot_name in ipairs(_AMULET_SLOT_BY_INDEX) do
            if _amulet_dirty[slot_index] then
                local src_bid = backend_items:get_loadout_item_id(career_name, slot_name)
                local src_item = src_bid and backend_items:get_item_from_id(src_bid)
                local src_key = src_item and (src_item.key or src_item.ItemId)
                if src_key then
                    local new_props = {}
                    if src_item.properties then
                        for k, v in pairs(src_item.properties) do new_props[k] = v end
                    end
                    local new_traits = {}
                    if src_item.traits then
                        for i, t in ipairs(src_item.traits) do new_traits[i] = t end
                    end

                    local new_bid = Application.guid()
                    local weapon_data = {
                        item_key = src_key,
                        properties = new_props,
                        traits = new_traits,
                        power_level = 300,
                        rarity = "modded",
                        via_mirror = true,
                    }
                    local injected, err = _athanor_inject_item(weapon_data, new_bid)
                    if injected then
                        if mod._cim_register_craft then mod._cim_register_craft(new_bid, weapon_data) end
                        pcall(backend_items.set_loadout_item, backend_items,
                              new_bid, career_name, slot_name)
                        crafted = crafted + 1
                        _amulet_dirty[slot_index] = false
                    else
                        mod:echo("[cim] Craft " .. slot_name .. " failed: " .. tostring(err))
                    end
                end
            end
        end
        if crafted > 0 then
            mod:echo("[cim] Crafted " .. crafted .. " modded accessor" ..
                     (crafted == 1 and "y" or "ies"))
        else
            mod:echo("[cim] No accessory edits to craft (Apply auto-runs on bubble click)")
        end
        return
    end

    if not item_key then
        mod:echo("[cim] Craft: no selected item")
        return
    end

    local backend_items = Managers.backend and Managers.backend:get_interface("items")
    if not backend_items then
        mod:echo("[cim] Craft: backend not ready")
        return
    end

    -- The bubble-grid `_forge_apply_to_item` already mutated `item.properties`
    -- and `item.traits` in-place on each click, so the "current bubble state"
    -- IS the item's current properties/traits. Clone them into the new craft.
    local new_props = {}
    if item.properties then
        for k, v in pairs(item.properties) do new_props[k] = v end
    end
    local new_traits = {}
    if item.traits then
        for i, t in ipairs(item.traits) do new_traits[i] = t end
    end

    local new_backend_id = Application.guid()
    local weapon_data = {
        item_key = item_key,
        properties = new_props,
        traits = new_traits,
        power_level = 300,
        rarity = "modded",
        via_mirror = true,
    }

    local injected, err = _athanor_inject_item(weapon_data, new_backend_id)
    if not injected then
        mod:echo("[cim] Craft failed: " .. tostring(err))
        return
    end

    if mod._cim_register_craft then
        mod._cim_register_craft(new_backend_id, weapon_data)
    end

    -- Equip the new item in the same slot as the source. `self._selected_slot_name`
    -- is set by our amulet click router (or the existing weave overview routing
    -- for melee/ranged).
    local career_name = self._career_name
    local slot_name = self._params and self._params.selected_slot_name
    if career_name and slot_name then
        local ok, eerr = pcall(backend_items.set_loadout_item, backend_items,
                               new_backend_id, career_name, slot_name)
        if not ok then mod:echo("[cim] Craft equip failed: " .. tostring(eerr)) end
    end

    local display = item_key
    local master = rawget(ItemMasterList, item_key)
    if master and master.display_name then
        local lok, loc = pcall(Localize, master.display_name)
        if lok and loc then display = loc end
    end
    mod:echo("[cim] Crafted new " .. tostring(slot_name and slot_name:gsub("^slot_", "") or "item")
             .. ": " .. display .. " [promo]")
end)

-- Console commands let the user pick which slot the amulet click edits.
-- Phase A.5 will replace these with on-screen buttons inside the editor.
mod:command("amulet_n", "Amulet edits necklace next click", function()
    mod._cim_amulet_slot = "slot_necklace"
    mod:echo("[cim] Amulet → necklace")
end)
mod:command("amulet_c", "Amulet edits charm next click", function()
    mod._cim_amulet_slot = "slot_charm"
    mod:echo("[cim] Amulet → charm")
end)
mod:command("amulet_t", "Amulet edits trinket next click", function()
    mod._cim_amulet_slot = "slot_trinket"
    mod:echo("[cim] Amulet → trinket")
end)

-- ============================================================
-- Diagnostic commands
-- ============================================================

local function _forge_dump_widgets(window_name, win)
    local w = win._widgets_by_name
    if not w then
        mod:info("DUMP [%s] _widgets_by_name=nil, checking fields:", window_name)
        for k, v in pairs(win) do
            if type(v) == "table" and k:find("widget") then
                mod:info("  field: %s (table, #%d)", k, #v)
            elseif type(v) ~= "function" then
                mod:info("  field: %s = %s", k, tostring(v))
            end
        end
        return
    end
    mod:info("=== DUMP [%s] ===", window_name)
    for name, widget in pairs(w) do
        local parts = {}
        if widget.content then
            for k, v in pairs(widget.content) do
                if type(v) == "string" and #v < 60 then
                    parts[#parts + 1] = k .. '="' .. v .. '"'
                elseif type(v) == "boolean" or type(v) == "number" then
                    parts[#parts + 1] = k .. "=" .. tostring(v)
                end
            end
        end
        local sparts = {}
        if widget.style then
            for sk, sv in pairs(widget.style) do
                if type(sv) == "table" then
                    if sv.color then
                        local c = sv.color
                        sparts[#sparts + 1] = sk .. ".color={" .. tostring(c[1]) .. "," .. tostring(c[2]) .. "," .. tostring(c[3]) .. "," .. tostring(c[4]) .. "}"
                    end
                    if sv.text_color then
                        local c = sv.text_color
                        sparts[#sparts + 1] = sk .. ".text_color={" .. tostring(c[1]) .. "," .. tostring(c[2]) .. "," .. tostring(c[3]) .. "," .. tostring(c[4]) .. "}"
                    end
                    if sv.font_size then
                        sparts[#sparts + 1] = sk .. ".font_size=" .. tostring(sv.font_size)
                    end
                end
            end
        end
        mod:info("  [%s] content: %s", name, table.concat(parts, ", "))
        if #sparts > 0 then
            mod:info("    style: %s", table.concat(sparts, ", "))
        end
    end
    mod:info("=== END [%s] ===", window_name)
end

mod:command("forge_dump", "Dump all forge window widget names to log", function()
    if not _custom_forge_active then
        mod:echo("Open the forge first (B key), then run this command")
        return
    end
    local ingame_ui = Managers.ui and Managers.ui._ingame_ui
    if not ingame_ui then
        mod:echo("No ingame_ui")
        return
    end
    local view_name = ingame_ui.current_view
    if not view_name then
        mod:echo("No current_view")
        return
    end
    local hero_view = ingame_ui.views and ingame_ui.views[view_name]
    if not hero_view then
        mod:echo("No view object for: " .. tostring(view_name))
        return
    end
    mod:info("=== FORGE UI DUMP ===")
    mod:info("current_view = %s", tostring(view_name))

    local forge_state = nil
    if hero_view._machine and hero_view._machine._state then
        forge_state = hero_view._machine._state
        mod:info("forge_state via _machine._state: %s (NAME=%s)", tostring(forge_state), tostring(forge_state.NAME))
    end
    if not forge_state then
        mod:echo("Could not find forge state on hero_view._machine._state")
        return
    end

    mod:info("--- forge_state fields ---")
    for k, v in pairs(forge_state) do
        if type(v) ~= "function" then
            local vstr = tostring(v)
            if type(v) == "table" then
                local count = 0
                for _ in pairs(v) do count = count + 1 end
                vstr = "table(" .. count .. ")"
            end
            mod:info("  state.%s = %s (%s)", k, vstr, type(v))
        end
    end

    local found = 0
    local active_windows = forge_state._active_windows
    if active_windows then
        mod:info("--- _active_windows ---")
        for idx, win in pairs(active_windows) do
            local win_name = win.NAME or win.__class_name or tostring(win)
            mod:info("Window[%s]: %s", tostring(idx), tostring(win_name))
            _forge_dump_widgets(tostring(idx) .. "_" .. tostring(win_name), win)
            found = found + 1
        end
    else
        mod:info("_active_windows is nil, scanning forge_state for _widgets_by_name:")
        for k, v in pairs(forge_state) do
            if type(v) == "table" and rawget(v, "_widgets_by_name") then
                mod:info("  Found _widgets_by_name on state.%s", k)
                _forge_dump_widgets(k, v)
                found = found + 1
            end
        end
    end
    mod:info("=== END FORGE UI DUMP (found %d windows) ===", found)
    mod:echo("Dump written to log (" .. found .. " windows found)")
end)

mod:command("forge_dump_props", "Dump properties sub-menu widgets and seed data", function()
    if not _custom_forge_active then
        mod:echo("Open the forge first (B key)")
        return
    end
    local ingame_ui = Managers.ui and Managers.ui._ingame_ui
    if not ingame_ui then mod:echo("No ingame_ui") return end
    local view_name = ingame_ui.current_view
    local hero_view = ingame_ui.views and ingame_ui.views[view_name]
    if not hero_view or not hero_view._machine then mod:echo("No hero_view") return end
    local forge_state = hero_view._machine._state
    if not forge_state then mod:echo("No forge_state") return end
    local windows = forge_state._active_windows
    if not windows then mod:echo("No _active_windows") return end

    mod:echo("Layout: " .. tostring(forge_state._selected_layout_name))
    local found_props = false
    for idx, win in pairs(windows) do
        mod:echo("Window[" .. tostring(idx) .. "]: " .. tostring(win.NAME))
        if win.NAME == "HeroWindowWeaveProperties" then
            found_props = true
            local wbn = win._widgets_by_name
            if wbn then
                local names = {}
                for name, widget in pairs(wbn) do
                    local info = name
                    if widget.content then
                        if widget.content.text then
                            info = info .. "=" .. tostring(widget.content.text)
                        end
                        if widget.content.visible == false then
                            info = info .. " [HIDDEN]"
                        end
                    end
                    names[#names + 1] = info
                end
                table.sort(names)
                for _, n in ipairs(names) do
                    mod:echo("  " .. n)
                end
            end
            mod:echo("_item_backend_id: " .. tostring(win._item_backend_id))
            mod:echo("_career_name: " .. tostring(win._career_name))
            local p = win._params
            if p then
                mod:echo("params.selected_item: " .. tostring(p.selected_item))
                if p.selected_item then
                    mod:echo("  .key: " .. tostring(p.selected_item.key or p.selected_item.data and p.selected_item.data.key))
                    mod:echo("  .backend_id: " .. tostring(p.selected_item.backend_id))
                end
                mod:echo("params.selected_unit_name: " .. tostring(p.selected_unit_name))
                mod:echo("params.selected_slot_name: " .. tostring(p.selected_slot_name))
            end
            mod:echo("_viewport_widget: " .. tostring(win._viewport_widget))
            mod:echo("_viewport_widget_definition: " .. tostring(win._viewport_widget_definition))
            mod:echo("_item_previewer: " .. tostring(win._item_previewer))
            mod:echo("_unit_previewer: " .. tostring(win._unit_previewer))
            mod:echo("_previewer_initialized: " .. tostring(win._previewer_initialized))
        end
    end
    if not found_props then
        mod:echo("HeroWindowWeaveProperties not active — click a weapon first")
    end

    local items_backend = Managers.backend and Managers.backend:get_interface("items")
    if items_backend then
        local player = Managers.player and Managers.player:local_player()
        if player then
            local pi = player:profile_index()
            local profile = SPProfiles[pi]
            local ci = player:career_index()
            local career_name = profile.careers[ci].name
            for _, slot in ipairs({"slot_melee", "slot_ranged"}) do
                local bid = items_backend:get_loadout_item_id(career_name, slot)
                if bid then
                    local item = items_backend:get_item_from_id(bid)
                    if item then
                        mod:echo(slot .. ": " .. tostring(item.key) .. " power=" .. tostring(item.power_level))
                        if item.properties then
                            for pk, pv in pairs(item.properties) do
                                local wk = "weave_" .. pk
                                local wp = rawget(_G, "WeaveProperties")
                                local mapped = wp and wp.properties and wp.properties[wk] and "YES" or "NO"
                                mod:echo("  prop: " .. pk .. "=" .. tostring(pv) .. " -> " .. wk .. " mapped=" .. mapped)
                            end
                        end
                        if item.traits then
                            for i, tk in ipairs(item.traits) do
                                local wk = "weave_" .. tk
                                local wt = rawget(_G, "WeaveTraits")
                                local mapped = wt and wt.traits and wt.traits[wk] and "YES" or "NO"
                                mod:echo("  trait: " .. tk .. " -> " .. wk .. " mapped=" .. mapped)
                            end
                        end
                    end
                end
            end
        end
    end
end)

mod:command("forge_dump_backend", "Dump forge backend hook returns to log", function()
    if not _custom_forge_active then
        mod:echo("Open the forge first (B key)")
        return
    end
    local weaves = Managers.backend and Managers.backend:get_interface("weaves")
    local items = Managers.backend and Managers.backend:get_interface("items")
    if not weaves or not items then
        mod:echo("Backend not available")
        return
    end
    local player = Managers.player:local_player()
    local profile_index = player:profile_index()
    local profile = SPProfiles[profile_index]
    local career_index = player:career_index()
    local career = profile.careers[career_index]
    local career_name = career.name
    mod:info("=== FORGE BACKEND DUMP career=%s ===", career_name)
    for _, slot in ipairs({"slot_melee", "slot_ranged"}) do
        local bid = weaves:get_loadout_item_id(career_name, slot)
        mod:info("  get_loadout_item_id(%s, %s) = %s", career_name, slot, tostring(bid))
        if bid then
            local item = items:get_item_from_id(bid)
            mod:info("  item from backend: %s", item and tostring(item.key) or "nil")
            if item then
                mod:info("    power_level: %s", tostring(item.power_level))
                mod:info("    rarity: %s", tostring(item.rarity))
                if item.properties then
                    for pk, pv in pairs(item.properties) do
                        mod:info("    prop: %s = %s", pk, tostring(pv))
                    end
                else
                    mod:info("    properties: nil")
                end
                if item.traits then
                    for i, t in ipairs(item.traits) do
                        mod:info("    trait[%d]: %s", i, tostring(t))
                    end
                else
                    mod:info("    traits: nil")
                end
            end
            local props = weaves:get_loadout_properties(career_name, bid)
            mod:info("  get_loadout_properties result:")
            if props then
                for pk, pv in pairs(props) do
                    mod:info("    %s = %s", pk, tostring(pv))
                end
            else
                mod:info("    nil")
            end
            local traits = weaves:get_loadout_traits(career_name, bid)
            mod:info("  get_loadout_traits result:")
            if traits then
                for tk, tv in pairs(traits) do
                    mod:info("    %s = %s", tostring(tk), tostring(tv))
                end
            else
                mod:info("    nil")
            end
        end
    end
    mod:info("  get_forge_level: %s", tostring(weaves:get_forge_level()))
    mod:info("  get_essence: %s", tostring(weaves:get_essence()))
    mod:info("=== END FORGE BACKEND DUMP ===")
    mod:echo("Backend dump written to log")
end)

-- Dump everything relevant to the equipped melee/ranged so we can reason about rarity/icons together.
mod:command("craft_dump", "Dump equipped item + rarity/localization/network data", function()
    local items = Managers.backend and Managers.backend:get_interface("items")
    local weaves = Managers.backend and Managers.backend:get_interface("weaves")
    local mirror = Managers.backend and Managers.backend:get_backend_mirror()
    if not items or not mirror then
        mod:echo("Backend not ready")
        return
    end
    local player = Managers.player:local_player()
    local profile_index = player:profile_index()
    local profile = SPProfiles[profile_index]
    local career_index = player:career_index()
    local career = profile.careers[career_index]
    local career_name = career.name

    local NL2 = rawget(_G, "NetworkLookup")
    local nl_rarities = NL2 and NL2.rarities
    local nl_promo_idx = nl_rarities and rawget(nl_rarities, "promo")

    mod:info("=== CRAFT DUMP career=%s ===", career_name)
    mod:info("[NetworkLookup] rarities.promo index = %s", tostring(nl_promo_idx))
    mod:info("[UISettings.item_rarity_textures]")
    if UISettings and UISettings.item_rarity_textures then
        for _, r in ipairs({"plentiful","common","rare","exotic","unique","magic","promo","default"}) do
            mod:info("  [%s] = %s", r, tostring(UISettings.item_rarity_textures[r]))
        end
    end
    mod:info("[RaritySettings]")
    local RS = rawget(_G, "RaritySettings")
    if RS then
        for _, r in ipairs({"plentiful","common","rare","exotic","unique","magic","promo"}) do
            local entry = rawget(RS, r)
            mod:info("  [%s] exists=%s display=%s", r, tostring(entry ~= nil),
                entry and tostring(entry.display_name) or "<nil>")
        end
    end

    for _, slot in ipairs({"slot_melee","slot_ranged"}) do
        mod:info("--- slot=%s ---", slot)
        local items_bid = items:get_loadout_item_id(career_name, slot)
        local weaves_bid = weaves and weaves:get_loadout_item_id(career_name, slot)
        mod:info("  items.get_loadout_item_id  = %s", tostring(items_bid))
        mod:info("  weaves.get_loadout_item_id = %s", tostring(weaves_bid))
        local item = items_bid and items:get_item_from_id(items_bid)
        if item then
            local data = item.data or (item.key and rawget(ItemMasterList, item.key)) or {}
            mod:info("  item.key       = %s", tostring(item.key))
            mod:info("  item.ItemId    = %s", tostring(item.ItemId))
            mod:info("  item.rarity    = %s", tostring(item.rarity))
            mod:info("  data.rarity    = %s", tostring(data.rarity))
            mod:info("  display_name   = %s -> %s", tostring(data.display_name), tostring(Localize(data.display_name or "")))
            mod:info("  inventory_icon = %s", tostring(data.inventory_icon))
            mod:info("  power_level    = %s", tostring(item.power_level))
            local resolved_bg = UISettings and UISettings.item_rarity_textures and UISettings.item_rarity_textures[item.rarity]
            mod:info("  -> rarity_bg lookup = %s", tostring(resolved_bg))
            if item.CustomData then
                for k, v in pairs(item.CustomData) do
                    mod:info("  CustomData[%s] = %s", tostring(k), tostring(v))
                end
            else
                mod:info("  CustomData = nil")
            end
            if item.properties then
                for k, v in pairs(item.properties) do
                    mod:info("  properties[%s] = %s", tostring(k), tostring(v))
                end
            else
                mod:info("  properties = nil")
            end
            if item.traits then
                for i, t in ipairs(item.traits) do
                    mod:info("  traits[%d] = %s", i, tostring(t))
                end
            else
                mod:info("  traits = nil")
            end
        else
            mod:info("  no item resolved for backend_id=%s", tostring(items_bid))
        end
    end

    mod:info("--- recently-added items (rarity=promo) ---")
    local inv = mirror._inventory_items or {}
    local count = 0
    for bid, it in pairs(inv) do
        if it and it.rarity == "promo" then
            count = count + 1
            mod:info("  [%s] key=%s rarity=%s pl=%s", tostring(bid), tostring(it.key), tostring(it.rarity), tostring(it.power_level))
            if count >= 10 then mod:info("  ...truncated"); break end
        end
    end
    if count == 0 then mod:info("  (none found)") end
    mod:info("=== END CRAFT DUMP ===")
    mod:echo(string.format("Craft dump written. promo items: %d, NL.rarities.promo idx: %s", count, tostring(nl_promo_idx)))
end)

-- ============================================================
-- Manual console crafting commands (cim forge*)
-- ============================================================

mod:command("forge", "Start forging a weapon (usage: cim forge <weapon_key>)", function(item_key)
    if not item_key then
        mod:echo("Usage: cim forge <weapon_key>")
        mod:echo("  Then: cim forge_trait <trait_name>")
        mod:echo("  Then: cim forge_props <prop1>=<value> <prop2>=<value>")
        mod:echo("  Then: cim forge_confirm")
        mod:echo("Use 'wt dump_weapons' to see available weapon keys.")
        return
    end
    if not ItemMasterList then
        mod:echo("Forge: ItemMasterList not loaded yet")
        return
    end
    local master = rawget(ItemMasterList, item_key)
    if not master then
        mod:echo("Forge: unknown weapon key '" .. item_key .. "'")
        return
    end
    _forge_pending = {
        item_key = item_key,
        properties = {},
        trait = nil,
        skin = nil,
        power_level = 300,
    }
    local display = item_key
    if master.display_name then
        local ok, loc = pcall(Localize, master.display_name)
        if ok and loc then display = loc end
    end
    mod:echo("Forge: preparing " .. display .. " (" .. item_key .. ")")
    mod:echo("  Set trait: cim forge_trait <trait_name>")
    mod:echo("  Set props: cim forge_props <prop>=<0-1> ...")
    mod:echo("  Set skin:  cim forge_skin <skin_key>")
    mod:echo("  Set power: cim forge_power <1-300>")
    mod:echo("  Confirm:   cim forge_confirm")
    mod:echo("  Cancel:    cim forge_cancel")
end)

mod:command("forge_trait", "Set trait for pending forge (usage: cim forge_trait <trait_name>)", function(trait)
    if not _forge_pending then
        mod:echo("Forge: no weapon pending — run 'cim forge <weapon_key>' first")
        return
    end
    if not trait then
        mod:echo("Usage: cim forge_trait <trait_name>")
        return
    end
    _forge_pending.trait = trait
    mod:echo("Forge: trait set to " .. trait)
end)

mod:command("forge_props", "Set properties for pending forge (usage: cim forge_props crit_chance=0.5 attack_speed=1)", function(...)
    if not _forge_pending then
        mod:echo("Forge: no weapon pending — run 'cim forge <weapon_key>' first")
        return
    end
    local args = {...}
    if #args == 0 then
        mod:echo("Usage: cim forge_props <prop>=<value> ...")
        mod:echo("  Values are 0.0-1.0 (fraction of max)")
        return
    end
    for _, arg in ipairs(args) do
        local key, val = arg:match("^([^=]+)=(.+)$")
        if key and val then
            local num = tonumber(val)
            if num then
                _forge_pending.properties[key] = num
                mod:echo("  " .. key .. " = " .. tostring(num))
            else
                mod:echo("  Invalid value for " .. key .. ": " .. val)
            end
        else
            mod:echo("  Invalid format: " .. arg .. " (expected key=value)")
        end
    end
end)

mod:command("forge_skin", "Set skin for pending forge (usage: cim forge_skin <skin_key>)", function(skin)
    if not _forge_pending then
        mod:echo("Forge: no weapon pending — run 'cim forge <weapon_key>' first")
        return
    end
    if not skin then
        _forge_pending.skin = nil
        mod:echo("Forge: skin cleared")
        return
    end
    _forge_pending.skin = skin
    mod:echo("Forge: skin set to " .. skin)
end)

mod:command("forge_power", "Set power level for pending forge (usage: cim forge_power <1-300>)", function(val)
    if not _forge_pending then
        mod:echo("Forge: no weapon pending — run 'cim forge <weapon_key>' first")
        return
    end
    local num = tonumber(val)
    if not num or num < 1 or num > 300 then
        mod:echo("Usage: cim forge_power <1-300>")
        return
    end
    _forge_pending.power_level = math.floor(num)
    mod:echo("Forge: power level set to " .. _forge_pending.power_level)
end)

mod:command("forge_cancel", "Cancel pending forge", function()
    if not _forge_pending then
        mod:echo("Forge: nothing pending")
        return
    end
    _forge_pending = nil
    mod:echo("Forge: cancelled")
end)

mod:command("forge_confirm", "Create the forged weapon", function()
    if not _forge_pending then
        mod:echo("Forge: no weapon pending — run 'cim forge <weapon_key>' first")
        return
    end

    local rnd = math.random(1000000)
    local backend_id = _forge_pending.item_key .. "_" .. rnd .. "_forged"

    if _forge_inject_item(_forge_pending, backend_id) then
        _forged_weapons[backend_id] = {
            item_key = _forge_pending.item_key,
            properties = _forge_pending.properties,
            trait = _forge_pending.trait,
            skin = _forge_pending.skin,
            power_level = _forge_pending.power_level,
            via_mirror = false,
        }
        _forge_save()

        local master = rawget(ItemMasterList, _forge_pending.item_key)
        local display = _forge_pending.item_key
        if master and master.display_name then
            local ok, loc = pcall(Localize, master.display_name)
            if ok and loc then display = loc end
        end
        mod:echo("Forge: created " .. display .. " [" .. backend_id .. "]")
        _forge_pending = nil
    end
end)

-- Diagnostic for salvage visibility: dumps every saved craft + whether it's
-- currently in the backend mirror, what rarity the mirror says, what
-- slot_type it has, and whether our salvage filter would surface it.
mod:command("salvage_debug", "Why isn't my modded craft showing in salvage?", function()
    local items_iface = Managers.backend and Managers.backend:get_interface("items")
    local mirror = Managers.backend and Managers.backend:get_backend_mirror()
    if not items_iface or not mirror then
        mod:echo("Backend not ready")
        return
    end

    local inv = mirror._inventory_items or {}
    local saved_count, in_mirror, promo_in_mirror = 0, 0, 0
    mod:echo("--- saved crafts (_forged_weapons) ---")
    for bid, w in pairs(_forged_weapons) do
        saved_count = saved_count + 1
        local item = inv[bid]
        local in_inv = item ~= nil
        if in_inv then in_mirror = in_mirror + 1 end
        local rarity = item and item.rarity or "<not in mirror>"
        local slot_type = item and item.data and item.data.slot_type or "<no data>"
        if rarity == "promo" then promo_in_mirror = promo_in_mirror + 1 end
        local in_inv_str = in_inv and "Y" or "N"
        mod:echo(string.format("  inv=%s  rarity=%s  slot=%s  key=%s  bid=%s",
            in_inv_str, tostring(rarity), tostring(slot_type), tostring(w.item_key), tostring(bid)))
    end
    mod:echo(string.format("Saved: %d  In mirror: %d  Promo in mirror: %d",
        saved_count, in_mirror, promo_in_mirror))

    mod:echo("--- all promo-rarity items in mirror ---")
    local extra_promo = 0
    for bid, item in pairs(inv) do
        if item and item.rarity == "promo" and not _forged_weapons[bid] then
            extra_promo = extra_promo + 1
            local slot_type = item.data and item.data.slot_type or "<no data>"
            mod:echo(string.format("  rarity=promo  slot=%s  key=%s  bid=%s",
                tostring(slot_type), tostring(item.key or item.ItemId), tostring(bid)))
        end
    end
    if extra_promo == 0 then mod:echo("  (none beyond saved crafts)") end
end)

mod:command("forge_list", "List all forged weapons", function()
    local count = 0
    for bid, w in pairs(_forged_weapons) do
        count = count + 1
        local display = w.item_key
        local _entry = ItemMasterList and rawget(ItemMasterList, w.item_key)
        if _entry and _entry.display_name then
            local ok, loc = pcall(Localize, _entry.display_name)
            if ok and loc then display = loc end
        end
        local parts = { display }
        if w.trait then parts[#parts + 1] = "trait=" .. w.trait end
        local prop_strs = {}
        for k, v in pairs(w.properties) do
            prop_strs[#prop_strs + 1] = k .. "=" .. tostring(v)
        end
        if #prop_strs > 0 then parts[#parts + 1] = table.concat(prop_strs, ", ") end
        parts[#parts + 1] = "power=" .. tostring(w.power_level or 300)
        mod:echo("[" .. count .. "] " .. table.concat(parts, " | ") .. "  id=" .. bid)
    end
    if count == 0 then
        mod:echo("Forge: no forged weapons")
    else
        mod:echo("Forge: " .. count .. " weapon(s)")
    end
end)

mod:command("forge_delete", "Delete a forged weapon (usage: cim forge_delete <backend_id or index>)", function(id_or_idx)
    if not id_or_idx then
        mod:echo("Usage: cim forge_delete <backend_id or index from forge_list>")
        return
    end

    local idx = tonumber(id_or_idx)
    local target_bid = nil

    if idx then
        local count = 0
        for bid, _ in pairs(_forged_weapons) do
            count = count + 1
            if count == idx then
                target_bid = bid
                break
            end
        end
        if not target_bid then
            mod:echo("Forge: no weapon at index " .. tostring(idx))
            return
        end
    else
        if _forged_weapons[id_or_idx] then
            target_bid = id_or_idx
        else
            mod:echo("Forge: no weapon with id '" .. id_or_idx .. "'")
            return
        end
    end

    if _forge_detect_mil() then
        pcall(_more_items_lib.remove_mod_items_from_local_backend, _more_items_lib, {target_bid}, "crafting_in_modded")
    end
    _forged_weapons[target_bid] = nil
    _forge_save()
    if Managers.backend then
        local items = Managers.backend:get_interface("items")
        if items then items:_refresh() end
    end
    mod:echo("Forge: deleted " .. target_bid)
end)
