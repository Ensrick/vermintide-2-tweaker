--[[
illusion_swap.lua — modded-realm weapon illusion swap.

Migrated from cosmetics_tweaker v0.8.49 so cim ships its own copy of the
"change cosmetics in modded realm" UI. cosmetics_tweaker yields when the
release `cim` mod is present. Its ownership check does not identify the
friends-only `cim_dev` id, so persistence must also observe vanilla's shared
Apply Skin completion seam instead of assuming this module owned the craft.

Differences from cosmetics_tweaker's version:
  * No `_custom_skin_keys` registry — cim doesn't ship custom illusions of
    its own; this module only unlocks the vanilla illusion-apply pipeline
    in modded realm. (cosmetics_tweaker's own custom skins still work
    because they live in WeaponSkins.skins and the unlocked-skins hook
    fires from its module.)
  * Persists the chosen skin to the cim forge save when applied to a
    modded item, so the cosmetic survives a game restart.
  * No offhand/shield picker (separate feature, intentionally not migrated).

What it does (6 hooks + helpers, mirroring the original plus persistence):
  1. `BackendInterfaceItemPlayfab.get_weapon_skin_from_skin_key` —
     return a synthetic backend id for any skin the player doesn't
     "own", so the illusion grid can reference it.
  2. `HeroWindowItemCustomization._enable_craft_button` — temporarily
     clear `eac-untrusted` so the Apply button is usable for skin
     swaps. Force-clears hotspot held flags on disable to prevent the
     fast-completion sound loop.
  3. `HeroWindowItemCustomization._on_illusion_index_pressed` — clear
     `content.locked = false` on the clicked widget so the Apply button
     enables for skins the player hasn't earned.
  4. `HeroWindowItemCustomization._update_state_craft_button` —
     temporarily clear `eac-untrusted` so the state check doesn't bake
     in the modded gate.
  5. `BackendInterfaceCraftingPlayfab.craft` — when in modded realm
     applying a weapon skin, write `item.skin` directly on the local
     backend mirror instead of sending to PlayFab. Persist via cim's
     forge save if the target is a modded craft.
  6. `BackendInterfaceCraftingPlayfab.update` — deferred completion
     (one frame) to match vanilla async timing.
  7. `HeroWindowItemCustomization._apply_weapon_skin_craft_complete` —
     record the final resolved illusion by exact item ID regardless of which
     mod owned the craft bypass.

DLC ownership is respected: skins with a `required_dlc` field in
ItemMasterList only unlock if the player owns that DLC.
]]

local mod = get_mod("cim_dev")
local _is_modded_realm = mod._cim_is_modded_realm or function() return false end
local _with_eac_off = mod._cim_with_eac_off or function(func, self, ...)
    return func(self, ...)
end

local _fake_skin_backend_ids = {}
local _pending_local_craft = nil

-- Issue #563: local illusion overrides for server-owned (vanilla) item
-- instances. PlayFabMirrorBase.inventory_request_cb clears and repopulates
-- `_inventory_items`, and `_update_data` derives item.skin from the server's
-- CustomData.skin (playfab_mirror_base.lua:1420-1461, 1723-1779). Persisting
-- only the skin on the live mirror therefore cannot survive the next mirror
-- population. Store the user's local choice by the exact ItemInstanceId and
-- reapply only after BackendManagerPlayFab:is_mirror_ready() says the mirror is
-- complete (backend_manager_playfab.lua:1166-1171). Never key this by template:
-- two copies of the same weapon must be able to carry different illusions.
local _CIM563_OVERRIDE_SETTING = "vanilla_skin_overrides_by_backend_id"
local _cim563_ready_seen = false
local _cim563_last_mirror = nil

local function _cim563_skin_exists(skin_key)
    return type(skin_key) == "string"
        and WeaponSkins
        and WeaponSkins.skins
        and rawget(WeaponSkins.skins, skin_key) ~= nil
end

-- Pure planner exposed for the runtime regression check. It deliberately
-- accepts two items with the same ItemId and selects by inventory[backend_id]
-- only; that is the invariant issue #563 must preserve.
mod._cim563_plan_vanilla_skin_rehydrate = function(saved, inventory, skin_exists)
    local apply, prune, invalid_skin = {}, {}, {}
    if type(saved) ~= "table" or type(inventory) ~= "table" then
        return apply, prune, invalid_skin
    end
    skin_exists = skin_exists or _cim563_skin_exists
    for backend_id, skin_key in pairs(saved) do
        if type(backend_id) ~= "string" or type(skin_key) ~= "string" then
            prune[#prune + 1] = backend_id
        else
            local item = rawget(inventory, backend_id)
            if not item then
                prune[#prune + 1] = backend_id
            else
                local slot_type = item.data and item.data.slot_type
                if slot_type ~= "melee" and slot_type ~= "ranged" then
                    prune[#prune + 1] = backend_id
                elseif skin_exists(skin_key) then
                    apply[backend_id] = { item = item, skin = skin_key }
                else
                    -- Keep the record: the skin may belong to a temporarily
                    -- disabled sibling mod. Only a missing ITEM id is stale.
                    invalid_skin[#invalid_skin + 1] = backend_id
                end
            end
        end
    end
    return apply, prune, invalid_skin
end

-- Pure copy-on-write reducer for explicit illusion choices. The returned map
-- is the complete next persisted state, so callers publish one mod:set rather
-- than exposing an old-value/delete/new-value transition to mirror rehydrate.
-- `keep_override=false` is used for CIM-owned crafts: their forge record owns
-- the skin, and any stale vanilla-instance override for the same id must go.
mod._cim563_plan_explicit_skin_choice = function(saved, backend_id, skin_key, keep_override)
    local next_saved = {}
    if type(saved) == "table" then
        for id, value in pairs(saved) do next_saved[id] = value end
    end
    if type(backend_id) ~= "string" or backend_id == "" then
        return next_saved, "ignored"
    end

    local previous = next_saved[backend_id]
    if keep_override and type(skin_key) == "string" and skin_key ~= "" then
        next_saved[backend_id] = skin_key
        return next_saved, previous == skin_key and "unchanged" or "saved"
    end
    if previous ~= nil then
        next_saved[backend_id] = nil
        return next_saved, "cleared"
    end
    return next_saved, "unchanged"
end

-- One authoritative persistence entry point shared by CIM's local craft path
-- and the HeroWindow completion observer below. The latter is essential when
-- cosmetics_tweaker owns the modded-realm craft bypass (notably cim_dev
-- coexistence): its craft mutates the mirror directly and never enters
-- `_cim_try_illusion_apply`.
mod._cim563_commit_explicit_skin_choice = function(backend_id, item, skin_key, source)
    if type(backend_id) ~= "string" or backend_id == "" or type(item) ~= "table" then
        return false, "ignored"
    end

    local is_modded = mod._cim_is_modded_backend_id
        and mod._cim_is_modded_backend_id(backend_id) == true
    if is_modded then
        local craft = mod._cim_get_craft and mod._cim_get_craft(backend_id)
        if craft and type(skin_key) == "string" and skin_key ~= "" and craft.skin ~= skin_key then
            craft.skin = skin_key
            if mod._cim_persist_crafts then mod._cim_persist_crafts() end
            pcall(printf, "[cim:563] craft_saved source=%s bid=%s item=%s skin=%s",
                tostring(source), tostring(backend_id),
                tostring(item.ItemId or item.key), tostring(skin_key))
        end
    end

    local saved = mod:get(_CIM563_OVERRIDE_SETTING)
    local next_saved, action = mod._cim563_plan_explicit_skin_choice(
        saved, backend_id, skin_key, not is_modded
    )
    if action == "saved" or action == "cleared" then
        mod:set(_CIM563_OVERRIDE_SETTING, next_saved)
        pcall(printf, "[cim:563] explicit_%s source=%s bid=%s item=%s skin=%s",
            action, tostring(source), tostring(backend_id),
            tostring(item.ItemId or item.key), tostring(skin_key))
    end
    return true, action
end

local function _cim563_rehydrate_ready_mirror(mirror)
    local inventory = mirror and mirror._inventory_items
    if type(inventory) ~= "table" then return false end

    local saved = mod:get(_CIM563_OVERRIDE_SETTING)
    if type(saved) ~= "table" then saved = {} end
    local apply, prune, invalid_skin = mod._cim563_plan_vanilla_skin_rehydrate(saved, inventory)
    local applied = 0
    for backend_id, row in pairs(apply) do
        local item = row.item
        item.skin = row.skin
        item.bypass_skin_ownership_check = true
        if item.CustomData then item.CustomData.skin = row.skin end
        applied = applied + 1
        pcall(printf, "[cim:563] rehydrated bid=%s item=%s skin=%s",
            tostring(backend_id), tostring(item.ItemId or item.key), tostring(row.skin))
    end

    for _, backend_id in ipairs(prune) do
        saved[backend_id] = nil
        pcall(printf, "[cim:563] pruned_missing bid=%s", tostring(backend_id))
    end
    if #prune > 0 then mod:set(_CIM563_OVERRIDE_SETTING, saved) end

    if applied > 0 and Managers.backend and Managers.backend.dirtify_interfaces then
        pcall(Managers.backend.dirtify_interfaces, Managers.backend)
    end
    pcall(printf, "[cim:563] ready_rehydrate applied=%d pruned=%d deferred_skin=%d saved=%d",
        applied, #prune, #invalid_skin, (function()
            local n = 0
            for _ in pairs(saved) do n = n + 1 end
            return n
        end)())
    mod._cim563_last_rehydrate = {
        applied = applied,
        pruned = #prune,
        deferred_skin = #invalid_skin,
    }
    return true
end

mod._cim563_reset_vanilla_skin_rehydrate = function()
    _cim563_ready_seen = false
end

mod._cim563_update_vanilla_skin_overrides = function()
    local backend = Managers and Managers.backend
    local mirror = backend and backend.get_backend_mirror and backend:get_backend_mirror()
    if mirror ~= _cim563_last_mirror then
        _cim563_last_mirror = mirror
        _cim563_ready_seen = false
    end

    local ready = false
    if backend and type(backend.is_mirror_ready) == "function" then
        local ok, value = pcall(backend.is_mirror_ready, backend)
        ready = ok and value == true
    end
    if not ready then
        -- A PlayFab inventory refresh drives readiness false while requests are
        -- pending. Arm the next true edge so server data cannot overwrite the
        -- local selection permanently.
        _cim563_ready_seen = false
        return
    end
    if _cim563_ready_seen then return end
    if _cim563_rehydrate_ready_mirror(mirror) then
        _cim563_ready_seen = true
    end
end

-- DLC ownership gate.
local function _skin_requires_unowned_dlc(skin_key)
    -- ItemMasterList.__index calls Crashify on unknown keys
    -- (item_master_list.lua:133). Skin keys can be LA-bridge entries
    -- that live only in WeaponSkins.skins, so use rawget.
    local item_data = rawget(ItemMasterList, skin_key)
    if not item_data or not item_data.required_dlc then return false end
    if not Managers.unlock then return false end
    return not Managers.unlock:is_dlc_unlocked(item_data.required_dlc)
end

-- ============================================================
-- 1. Synthetic backend ids for unowned skins
-- ============================================================
mod:hook("BackendInterfaceItemPlayfab", "get_weapon_skin_from_skin_key", function(func, self, skin_key)
    local id, item = func(self, skin_key)
    if id then return id, item end

    local iml_entry = rawget(ItemMasterList, skin_key)
    if _is_modded_realm() and iml_entry and not _skin_requires_unowned_dlc(skin_key) then
        local fake_id = "cim_fake_" .. skin_key
        _fake_skin_backend_ids[fake_id] = skin_key
        local fake_item = {
            skin = skin_key,
            ItemId = skin_key,
            data = iml_entry,
            key = skin_key,
            rarity = iml_entry and iml_entry.rarity or "exotic",
        }
        return fake_id, fake_item
    end
end)

-- ============================================================
-- 2-4. Customization UI button hooks
-- ============================================================
mod:hook("HeroWindowItemCustomization", "_enable_craft_button", function(func, self, enable, disable_edges)
    if enable and _is_modded_realm() and self._current_recipe_name == "apply_weapon_skin" then
        _with_eac_off(func, self, enable, disable_edges)
        return
    end
    func(self, enable, disable_edges)
    if not enable and self._current_recipe_name == "apply_weapon_skin" then
        local widget = self._widgets_by_name and self._widgets_by_name.craft_button
        if widget and widget.content and widget.content.button_hotspot then
            widget.content.button_hotspot.is_held = false
            widget.content.button_hotspot.input_pressed = false
        end
    end
end)

mod:hook("HeroWindowItemCustomization", "_on_illusion_index_pressed", function(func, self, index, ignore_item_spawn, mark_as_equipped)
    local widget = self._illusion_widgets and self._illusion_widgets[index]
    if _is_modded_realm() and not ignore_item_spawn then
        if widget and widget.content then
            local skin_key = widget.content.skin_key
            if skin_key and not _skin_requires_unowned_dlc(skin_key) then
                widget.content.locked = false
                -- Selection is preview-only, so do not persist here. Retain the
                -- latest intent on this window instance and consume it only if
                -- Apply completes. This also protects against a mirror-ready
                -- callback overwriting the live mirror between craft start and
                -- UI completion: completion commits the user's B, not stale A.
                self._cim563_pending_explicit_skin = skin_key
            end
        end
    end
    return func(self, index, ignore_item_spawn, mark_as_equipped)
end)

-- NOTE: `_update_state_craft_button` is hooked in `standard_forge.lua`
-- (loaded before this file). The eac-clearing wrap for the
-- `apply_weapon_skin` recipe lives in that consolidated hook — VMF
-- rejects a second `mod:hook*` on the same class+method with
-- "Attempting to rehook active hook" and silently drops the body.

-- ============================================================
-- 5. Local craft (write skin to backend mirror; persist for modded items)
-- ============================================================
-- Exposed as a helper rather than a direct hook because standard_forge.lua
-- already registers a `craft` hook — a second hook would be rejected by
-- VMF with "Attempting to rehook active hook [craft]" and silently dropped.
-- standard_forge.lua's craft hook calls this helper BEFORE its `_is_active`
-- check, so illusion-apply works regardless of which UI is open.
--
-- Returns: id, recipe  on successful local apply
--          nil          when this is not an illusion-apply craft (caller
--                       should defer to the next handler / vanilla)
mod._cim_try_illusion_apply = function(self, career_name, item_backend_ids, recipe_override)
    if not _is_modded_realm() then return nil end

    local backend_items = Managers.backend:get_interface("items")
    local weapon_backend_id, skin_key

    for _, bid in ipairs(item_backend_ids) do
        if _fake_skin_backend_ids[bid] then
            skin_key = _fake_skin_backend_ids[bid]
        else
            local item = backend_items:get_item_from_id(bid)
            if not item then
                local fake_items = backend_items.get_all_fake_backend_items and backend_items:get_all_fake_backend_items()
                item = fake_items and fake_items[bid]
            end
            if item then
                local slot_type = item.data and item.data.slot_type
                if slot_type == "melee" or slot_type == "ranged" then
                    weapon_backend_id = bid
                elseif slot_type == "weapon_skin" then
                    skin_key = item.skin or item.key
                end
            end
        end
    end

    if not weapon_backend_id or not skin_key then return nil end

    if _skin_requires_unowned_dlc(skin_key) then
        mod:warning("[cim] Cannot apply illusion — requires DLC you don't own.")
        return nil
    end

    local mirror = self._backend_mirror
    local weapon_item = mirror and mirror._inventory_items and mirror._inventory_items[weapon_backend_id]
    if not weapon_item then return nil end

    weapon_item.skin = skin_key
    weapon_item.bypass_skin_ownership_check = true
    if weapon_item.CustomData then
        weapon_item.CustomData.skin = skin_key
    end

    -- Commit immediately for CIM's own local craft path. The completion hook
    -- below repeats this idempotently, covering alternate craft owners.
    mod._cim563_commit_explicit_skin_choice(
        weapon_backend_id, weapon_item, skin_key, "cim_local_craft"
    )

    local id = self:_new_id()
    _pending_local_craft = { interface = self, id = id }

    mod:info("Applied illusion '%s' locally (modded realm)", skin_key)
    return id, { name = "apply_weapon_skin" }
end

mod:hook_safe("BackendInterfaceCraftingPlayfab", "update", function(self, dt)
    if _pending_local_craft and _pending_local_craft.interface == self then
        self._craft_requests[_pending_local_craft.id] = {}
        Managers.backend:dirtify_interfaces()
        _pending_local_craft = nil
    end
end)

-- Vanilla dispatches every successful Apply Skin craft through this method
-- after the backend reports completion, then re-presents and equips the
-- resolved item (hero_window_item_customization.lua:2502-2547). Observe that
-- shared semantic completion instead of assuming CIM owned the craft hook.
-- This covers Keep and in-mission HeroWindow customization, including the
-- cosmetics_tweaker local-mirror bypass seen in the reopened #563 log.
mod:hook_safe("HeroWindowItemCustomization", "_apply_weapon_skin_craft_complete", function(self, result)
    if not _is_modded_realm() then return end
    local pending_skin = self and self._cim563_pending_explicit_skin
    if self then self._cim563_pending_explicit_skin = nil end
    local backend_id = self and self._item_backend_id
    local item = backend_id and self._get_item and self:_get_item(backend_id)
    if type(item) ~= "table" then return end
    local skin_key = pending_skin or item.skin
    if (type(skin_key) ~= "string" or skin_key == "") and item.key
        and WeaponSkins and WeaponSkins.default_skins then
        skin_key = WeaponSkins.default_skins[item.key]
    end
    mod._cim563_commit_explicit_skin_choice(
        backend_id, item, skin_key, "item_customization_complete"
    )
end)

-- ============================================================
-- 7. Unlock all DLC-owned weapon illusions in modded realm
-- ============================================================
-- Without this, vanilla locked illusions (e.g. "Sword of Bitter Dreams") show
-- as locked in the customization grid even though we'd happily craft a fake
-- backend id for them. The grid's Apply button stays disabled because the
-- backend says the skin isn't unlocked.
--
-- Fix: when in modded realm, mark every WeaponSkins.skins entry as unlocked
-- on the local backend mirror — except skins gated behind unowned DLC. The
-- DLC gate is the same `_skin_requires_unowned_dlc` used elsewhere in this
-- file, so paid cosmetic DLC paywalls are still respected.
mod:hook_safe("BackendInterfaceCraftingPlayfab", "get_unlocked_weapon_skins", function(self)
    if not _is_modded_realm() then return end
    local mirror = self._backend_mirror
    if not mirror or not mirror._unlocked_weapon_skins then return end
    if not WeaponSkins or not WeaponSkins.skins then return end
    for skin_key, _ in pairs(WeaponSkins.skins) do
        if not _skin_requires_unowned_dlc(skin_key) then
            mirror._unlocked_weapon_skins[skin_key] = true
        end
    end
end)

-- ============================================================
-- Discoverability: skin-swap help (feedback #8)
-- ============================================================
-- New users routinely ask "how do I change a weapon skin?" — the path is the
-- vanilla Apply Skin tab on the Customization menu (gear icon next to an item),
-- which we've already unlocked in modded realm. There's no in-UI signposting
-- that this works, so a chat command is the cheapest fix.
mod:command("cim_skins", "How to change a weapon skin in modded realm", function()
    mod:echo("[cim] To change a weapon skin in modded realm:")
    mod:echo("  1) Open Inventory (I) and select the weapon you want to re-skin.")
    mod:echo("  2) Click the gear/cog icon next to the weapon (Customization).")
    mod:echo("  3) Pick the Apply Skin tab — ALL illusions are unlocked here in")
    mod:echo("     modded realm, including DLC skins you own.")
    mod:echo("  4) Pick an illusion in the grid, then click Apply.")
    mod:echo("  Note: skin choices are persisted per exact item across restarts.")
end)

-- ============================================================
-- Diagnostic: dump inventory state to help diagnose visibility issues
-- ============================================================
mod:command("inv_dump", "Dump modded item visibility state to log + console", function()
    local backend = Managers and Managers.backend
    local items_iface = backend and backend:get_interface("items")
    if not items_iface then
        mod:echo("[inv_dump] No items backend interface")
        return
    end

    local eac = _is_modded_realm() and "true" or "false"
    local sf_active = mod._cim_standard_forge_active and "true" or "false"
    local show_only = mod:get("show_only_modded_weapons") and "true" or "false"
    local mech = Managers.mechanism and Managers.mechanism:current_mechanism_name() or "?"
    mod:echo(string.format("[inv_dump] eac=%s sf_active=%s show_only=%s mech=%s",
        eac, sf_active, show_only, mech))
    mod:info(string.format("[inv_dump] eac=%s sf_active=%s show_only=%s mech=%s",
        eac, sf_active, show_only, mech))

    local player = Managers.player and Managers.player:local_player()
    local profile_index = player and player:profile_index()
    local career_index = player and player:career_index()
    local hero_data = profile_index and SPProfiles and SPProfiles[profile_index]
    local career = hero_data and hero_data.careers and hero_data.careers[career_index]
    local career_name = career and career.name or "?"
    mod:echo("[inv_dump] career=" .. career_name)
    mod:info("[inv_dump] career=" .. career_name)

    local all = items_iface.get_all_backend_items and items_iface:get_all_backend_items() or {}
    local count_modded, count_vanilla = 0, 0
    local sample_modded = {}
    for bid, item in pairs(all) do
        local is_modded = mod._cim_is_modded_item and mod._cim_is_modded_item(item)
        if is_modded then
            count_modded = count_modded + 1
            if #sample_modded < 8 then
                local data = item.data or {}
                local can_wield = data.can_wield or {}
                local can_wield_str = table.concat(can_wield, ",")
                local wieldable = false
                for _, c in ipairs(can_wield) do if c == career_name then wieldable = true break end end
                local mechs = data.mechanisms and table.concat(data.mechanisms, ",") or "<nil>"
                sample_modded[#sample_modded + 1] = string.format(
                    "  bid=%s key=%s rarity=%s slot=%s wield=%s wieldable_by_career=%s mech=%s",
                    tostring(bid), tostring(item.key or data.key), tostring(item.rarity),
                    tostring(data.slot_type), can_wield_str, tostring(wieldable), mechs)
            end
        else
            count_vanilla = count_vanilla + 1
        end
    end
    mod:echo(string.format("[inv_dump] modded=%d vanilla=%d", count_modded, count_vanilla))
    mod:info(string.format("[inv_dump] modded=%d vanilla=%d", count_modded, count_vanilla))
    for _, line in ipairs(sample_modded) do
        mod:echo(line)
        mod:info(line)
    end

    -- Run the actual filter the loadout grid uses to see if it would surface them
    local backend_common = backend:get_interface("common")
    if backend_common and backend_common.filter_items then
        -- Pass `all` (bid-keyed dict) directly. Earlier versions built a
        -- sequential array which made filter_items iterate with numeric keys
        -- (1, 2, 3) as backend_ids, causing get_item_rarity to crash on the
        -- first item (items[1] was nil because the dict is bid-keyed).
        local filter = "available_in_current_mechanism and ( can_wield_by_current_career and ( ( slot_type == melee or slot_type == ranged ) and item_rarity ~= magic ) )"
        local result = backend_common:filter_items(all, filter, { profile_index = profile_index, career_index = career_index })
        local r_modded, r_total = 0, #result
        for _, it in ipairs(result) do
            if mod._cim_is_modded_item and mod._cim_is_modded_item(it) then r_modded = r_modded + 1 end
        end
        mod:echo(string.format("[inv_dump] FILTERED-melee+ranged total=%d modded=%d",
            r_total, r_modded))
        mod:info(string.format("[inv_dump] FILTERED-melee+ranged total=%d modded=%d (filter=%s)",
            r_total, r_modded, filter))
    end
end)

-- Dump the state of every saved cim craft (`_forged_weapons`) vs the live
-- backend mirror. Tells us EXACTLY which of our saved crafts made it into
-- the mirror, which got dropped, and what state they're in (rarity / slot /
-- can_wield / skin / loadout-equipped). Use this when items don't appear in
-- the inventory grid — answer's almost always one of: (a) item not in mirror,
-- (b) mirror has it but `item.data` is nil, (c) `can_wield` doesn't match
-- the current career, (d) item got filtered by something else.
mod:command("mirror_dump", "Dump every saved cim craft and its mirror state", function()
    local backend = Managers and Managers.backend
    local items_iface = backend and backend:get_interface("items")
    if not items_iface or not mod._cim_get_craft then
        mod:echo("[mirror_dump] backend or cim helpers not ready")
        return
    end

    local crafts = {}
    -- Build the list from cim's POV. The helper `_cim_get_craft` only returns
    -- one entry — we need to iterate the underlying _forged_weapons. Re-derive
    -- via mod:get since that's the persistent source of truth.
    local saved = mod:get("forged_weapons")
    if type(saved) ~= "table" then
        mod:echo("[mirror_dump] no saved crafts (forged_weapons setting is nil or non-table)")
        return
    end

    local all = items_iface.get_all_backend_items and items_iface:get_all_backend_items() or {}
    local backend_mirror = backend.get_backend_mirror and backend:get_backend_mirror()
    local mirror_items = backend_mirror and backend_mirror._inventory_items or {}

    local loadout
    if items_iface.get_loadout then loadout = items_iface:get_loadout() end
    local equipped_bids = {}
    if type(loadout) == "table" then
        for career_name, slots in pairs(loadout) do
            if type(slots) == "table" then
                for slot_name, bid in pairs(slots) do
                    if bid then equipped_bids[bid] = career_name .. "/" .. slot_name end
                end
            end
        end
    end

    local n_saved, n_in_mirror, n_in_items_iface = 0, 0, 0
    mod:echo("[mirror_dump] ---- per-craft ----")
    mod:info("[mirror_dump] ---- per-craft ----")
    for bid, w in pairs(saved) do
        n_saved = n_saved + 1
        local in_mirror = mirror_items[bid] ~= nil
        local in_items = all[bid] ~= nil
        if in_mirror then n_in_mirror = n_in_mirror + 1 end
        if in_items then n_in_items_iface = n_in_items_iface + 1 end

        local item = all[bid] or mirror_items[bid]
        local data = item and item.data
        local rarity = item and item.rarity or "<no-item>"
        local slot = data and data.slot_type or "<no-data>"
        local can_wield = data and data.can_wield and table.concat(data.can_wield, ",") or "<no-can_wield>"
        local equipped = equipped_bids[bid] or "<not-equipped>"

        local line = string.format(
            "  bid=%s key=%s rarity=%s slot=%s wield=%s in_mirror=%s in_items=%s equipped=%s",
            tostring(bid), tostring(w.item_key), tostring(rarity), tostring(slot),
            tostring(can_wield), tostring(in_mirror), tostring(in_items), tostring(equipped))
        mod:echo(line)
        mod:info(line)
    end
    mod:echo(string.format("[mirror_dump] saved=%d in_mirror=%d in_items_iface=%d",
        n_saved, n_in_mirror, n_in_items_iface))
    mod:info(string.format("[mirror_dump] saved=%d in_mirror=%d in_items_iface=%d",
        n_saved, n_in_mirror, n_in_items_iface))
end)
