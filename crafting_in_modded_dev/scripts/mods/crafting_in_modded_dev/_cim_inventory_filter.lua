-- _cim_inventory_filter.lua -- modded-realm inventory / salvage grid filtering.
--
-- Owns the two BackendInterface filter hooks that shape which items the
-- modded-realm crafting / inventory grids surface, plus the versus-twin
-- discriminators they depend on:
--   * BackendInterfaceItemPlayfab.get_filtered_items -- re-hide the player's
--     leaked OWNED vs_* twins from the Adventure grid (ALWAYS), drop vanilla
--     weapons when show_only_modded / the standard forge is active, and inject
--     blacksmith templates for the can_craft_with recipe.
--   * BackendInterfaceCommon.filter_items -- surface modded crafts in the salvage
--     grid regardless of equip / loadout state.
--   * _cim_is_versus_key / _cim_is_leaked_versus_twin (also published on the flat
--     mod._cim_* namespace; the get_filtered_items re-hide and the inline
--     versus_twin_rehidden regression check in the entry both consume them).
--
-- Extracted verbatim from crafting_in_modded_dev.lua (v0.8.55-dev OOP split).
-- Consumes mod._cim_is_modded_backend_id / _is_modded_item / _inject_templates /
-- _standard_forge_active / _autodump_filtered_items from the entry AT RUNTIME
-- (resolved when the hooks fire, never at load), so the dofile order is free.
--
-- Owned by: crafting_in_modded_dev.lua entry point. Consumed via: mod:dofile
-- (manifest, exactly once). One hook per (Class, method) mod-wide.
local mod = get_mod("cim_dev")
-- Versus-carousel item key check, by ItemId/key PREFIX rather than the
-- `mechanisms` field. WHY a prefix and not `mechanisms`: cim's
-- `_ensure_item_adventure_visible` clears `ItemMasterList[key].mechanisms = nil`
-- to make a crafted vs_* weapon adventure-visible (the deliberate craft
-- behavior). But `item.data` is a SHARED reference to that same IML entry
-- (PlayFabMirrorBase._update_data sets `item.data = ItemMasterList[item_key]`),
-- so after the clear `_cim_is_versus(item.data)` returns false for EVERY item of
-- that key — including the player's raw owned vs_* twin that leaked into the
-- adventure inventory grid. The `vs_` prefix is the only discriminator that
-- survives the mechanisms clear. (Every Versus weapon key in vanilla — claws,
-- ratling gun, etc. — is `vs_*`; see item_master_list_versus_rewards.lua.)
local function _cim_is_versus_key(item_key)
    return type(item_key) == "string" and item_key:sub(1, 3) == "vs_"
end
mod._cim_is_versus_key = _cim_is_versus_key

-- True for the player's RAW OWNED vanilla vs_* twin that should NOT show in the
-- adventure inventory grid, but FALSE for a cim-crafted vs_* (modded backend_id)
-- which the user deliberately surfaced and must stay visible. Used by the
-- inventory-display re-hide in the get_filtered_items hook. Keys off
-- `_cim_is_modded_backend_id` so a deliberately-crafted unique vs_* is never
-- hidden (memory: reference_vt2_versus_items_hidden_in_adventure).
local function _cim_is_leaked_versus_twin(item)
    if not item then return false end
    local key = item.key or item.ItemId or (item.data and item.data.key)
    if not _cim_is_versus_key(key) then return false end
    -- A modded backend_id means this IS the crafted item — keep it visible.
    return not (mod._cim_is_modded_backend_id and mod._cim_is_modded_backend_id(item.backend_id))
end
mod._cim_is_leaked_versus_twin = _cim_is_leaked_versus_twin

-- Weapon-like slot_types the inventory filter drops in modded realm (moved
-- here with the get_filtered_items hook from the entry's loadout section).
local _WEAPON_SLOT_TYPES = { melee = true, ranged = true, trinket = true, ring = true, necklace = true }

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
    -- v0.7.62-dev DIAGNOSTIC: measure the EXACT layer the inventory grid reads.
    -- Reports whether a just-crafted bid survived this filter (and dumps why if
    -- not). Gated on enable_debug_logging — zero cost when off. This is the
    -- probe that should have existed days ago: older probes checked the broad
    -- get_all_backend_items, not the filtered grid result.
    if mod._cim_autodump_filtered_items then
        pcall(mod._cim_autodump_filtered_items, self, filter, params, items)
    end

    -- Versus-twin re-hide (runs ALWAYS for the adventure inventory grid, even
    -- when the show-only-modded filter is off — the leak is independent of it).
    --
    -- ROOT CAUSE this guards: `_ensure_item_adventure_visible` clears
    -- `ItemMasterList[vs_key].mechanisms = nil` to surface a crafted vs_* weapon
    -- in Adventure (intended). But that IML entry is a GLOBAL shared by the
    -- player's raw OWNED vs_* twin too (item.data is a reference, not a copy —
    -- PlayFabMirrorBase._update_data:1786), so the owned twin ALSO passes the
    -- vanilla `available_in_current_mechanism` filter and leaks into the normal
    -- inventory grid. We can't un-leak it at the data layer (one shared table),
    -- so we re-hide it HERE, at the display layer: drop owned vs_* twins from the
    -- adventure-inventory result while keeping cim-crafted vs_* (modded bid)
    -- visible. Keyed on the vs_ ItemId prefix (the mechanisms field is already
    -- nil post-clear) + _cim_is_modded_backend_id so a deliberately-crafted
    -- unique vs_* is NEVER hidden. INVENTORY display only — the craft list is
    -- untouched (memory: reference_vt2_versus_items_hidden_in_adventure).
    if type(items) == "table" and type(filter) == "string"
       and filter:find("available_in_current_mechanism", 1, true) then
        local kept = {}
        for i = 1, #items do
            local item = items[i]
            if not _cim_is_leaked_versus_twin(item) then
                kept[#kept + 1] = item
            end
        end
        items = kept
    end

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

    -- Synthetic "blacksmith's template" injection for the Craft Item recipe.
    -- Defined in standard_forge.lua. No-op unless the forge UI is open AND the
    -- filter is `can_craft_with`. Lets the player craft career-eligible weapon
    -- families they never unlocked (career-level gates aren't enforced in
    -- modded realm; we just need the UI to surface them).
    if mod._cim_inject_templates then
        filtered = mod._cim_inject_templates(filtered, filter)
    end
    return filtered
end)

-- ============================================================
-- Salvage filter adapter: exact CIM ownership + vanilla safety contract (#628)
-- ============================================================
-- BackendInterfaceCommon.can_salvage requires a weapon/accessory slot, a
-- non-default/non-promo/non-magic rarity, no active equip and no favorite
-- (vanilla source backend_interface_common.lua:404-423). The recipe adds
-- `not is_equipped_by_any_loadout`. Older CIM code bypassed all three safety
-- exclusions and re-added every modded-looking row. This adapter now delegates
-- identity and eligibility to the canonical synthetic-item contract and only
-- restores an exact persisted CIM instance when every vanilla guard passes.

local function _is_salvage_filter(filter_infix)
    if type(filter_infix) ~= "string" then return false end
    return filter_infix:find("can_salvage", 1, true) ~= nil
end

-- issues 628/682: this adapter routes every re-admitted row through the
-- contract (`is_salvage_eligible` -> validate_instance), so declare salvage
-- as a routed provider-gate surface for the unrouted-walk census.
do
    local _contract = mod._cim_synthetic_item_contract
    if _contract and _contract.register_enumerator then
        _contract.register_enumerator("salvage")
    end
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

    local contract = mod._cim_synthetic_item_contract
    if type(contract) ~= "table" then return result end

    for _, item in ipairs(items) do
        local bid = item and item.backend_id
        local record = bid and mod._cim_get_craft and mod._cim_get_craft(bid)
        if bid and record and not seen[bid] then
            local equipped, any_loadout, favorite = true, true, true

            local ok_equipped, careers = pcall(backend_items.equipped_by, backend_items, bid)
            if ok_equipped and type(careers) == "table" then equipped = #careers > 0 end

            local ok_loadout, loadouts = pcall(
                backend_items.is_equipped_by_any_loadout, backend_items, bid)
            if ok_loadout and type(loadouts) == "table" then any_loadout = #loadouts > 0 end

            if ItemHelper and ItemHelper.is_favorite_backend_id then
                local ok_favorite, value = pcall(ItemHelper.is_favorite_backend_id, bid, item)
                if ok_favorite then favorite = value and true or false end
            end

            local eligible = contract.is_salvage_eligible(item, record, {
                is_equipped = equipped,
                is_equipped_by_any_loadout = any_loadout,
                is_favorite = favorite,
            })
            if eligible then
                result[#result + 1] = item
                seen[bid] = true
            end
        end
    end
    return result
end)
