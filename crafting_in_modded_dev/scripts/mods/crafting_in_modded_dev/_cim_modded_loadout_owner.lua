-- _cim_modded_loadout_owner.lua -- CIM-dev craft auto-equip and exact-loadout owner.
--
-- RESPONSIBILITY
--   * #562 auto-equip of a freshly crafted weapon (`mod._cim_auto_equip_crafted_weapon`,
--     `mod._cim_auto_equip_slot_type`)
--   * #1360 exact five-slot loadout primitives for the community-build importer
--     (`mod._cim_snapshot_exact_loadout`, `mod._cim_write_exact_loadout_item`,
--     `mod._cim_finalize_exact_loadout`)
--   * the sibling-mod restore-callback registry `mod._cim_register_restore_callback`
--     that cosmetics_tweaker calls and requires
--     (cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_glow_cim_bridge.lua:151-158)
--   * the `cim_craft_standard` command
--
-- WP-CIM-11 removed the dormant persisted modded-loadout path that used to live
-- here (the `modded_loadout` store, its flat-to-indexed migration and stale
-- purge, both `set_loadout_item` capture hooks, the restore pass, the live
-- avatar re-equip and the two loadout restore/dump chat commands).
-- It was forced off at every load; Tweaker: GUI owns modded loadout
-- persistence. The players' saved `modded_loadout` setting is left untouched.
-- The registered restore callbacks are stored and never invoked, exactly as
-- before (the old restore returned before reaching them).

local function install(ctx)
    assert(type(ctx) == "table", "CIM modded loadout owner requires context")

    local mod = assert(ctx.mod, "CIM modded loadout owner requires mod")

    local state = mod._cim_modded_loadout_owner_state
    if not state then
        state = {}
        mod._cim_modded_loadout_owner_state = state
    end

    -- mod:dofile is not a singleton. A second install would re-register the
    -- command, so hand back the first install's exports instead.
    if state.exports then
        return state.exports
    end

    -- Resolve the LIVE selected loadout index for a career from the backend mirror,
    -- LA-safe (reads `_backend_mirror` directly). Returns an integer index, or
    -- `fallback` (default 1) when the mirror / career isn't available yet. Never
    -- throws: the auto-equip and exact-loadout paths call it at timing-fragile
    -- moments where the mirror may be nil.
    local function _resolve_selected_index(career_name, fallback)
        fallback = fallback or 1
        if not career_name then return fallback end
        local items_iface = Managers.backend and Managers.backend.get_interface
            and Managers.backend:get_interface("items")
        local mirror = items_iface and items_iface._backend_mirror
        if not mirror then return fallback end
        -- Prefer the direct table read; fall back to the public accessor.
        local ok, idx = pcall(function()
            if mirror._career_loadouts then
                return mirror._career_loadouts[career_name]
            end
        end)
        if ok and type(idx) == "number" then return idx end
        if mirror.get_career_loadouts then
            local ok2, sel = pcall(mirror.get_career_loadouts, mirror, career_name)
            if ok2 and type(sel) == "number" then return sel end
        end
        return fallback
    end

    -- Sibling-mod restore-callback registry. cosmetics_tweaker registers its
    -- LA-illusion / paint / offhand reapply here and requires a `true` return
    -- (_cos_glow_cim_bridge.lua:151-158, _cos_runtime_checks.lua:965). The
    -- callbacks are stored and not invoked: the removed restore pass returned
    -- before reaching them, and whether cosmetics needs them is a question for
    -- the cosmetics track (WP-CIM-11 guardrail).
    local _restore_callbacks = {}
    mod._cim_register_restore_callback = function(fn)
        if type(fn) ~= "function" then
            mod:info("[restore] register_restore_callback ignored: arg not a function")
            return false
        end
        _restore_callbacks[#_restore_callbacks + 1] = fn
        return true
    end

    -- Issue #562: equip the exact freshly-created backend id, not another item with
    -- the same ItemMasterList key. The items interface accepts an explicit loadout
    -- index and writes it through to set_character_data
    -- (backend_interface_item_playfab.lua:635-667). The live keep avatar is a
    -- separate surface: vanilla's inventory equip path writes the loadout and then
    -- queues/recreates the equipment unit (hero_view_state_overview.lua:1070-1139).
    -- Keep those two surfaces together here so craft-time auto-equip cannot regress
    -- into issue #12's historical "new icon, old weapon unit" divergence.
    local _AUTO_EQUIP_WEAPON_SLOTS = {
        slot_melee = "melee",
        slot_ranged = "ranged",
    }

    local function _auto_equip_slot_type(slot_name)
        return _AUTO_EQUIP_WEAPON_SLOTS[slot_name]
    end

    local function _auto_equip_crafted_weapon(career_name, slot_name, backend_id)
        if not mod:get("auto_equip_new_weapons") then return false, "disabled" end

        local expected_slot_type = _auto_equip_slot_type(slot_name)
        if not expected_slot_type then return false, "not a weapon slot" end
        if not career_name or not backend_id then return false, "missing craft identity" end

        local items = Managers.backend and Managers.backend:get_interface("items")
        if not items then return false, "items backend not ready" end

        local item = items:get_item_from_id(backend_id)
        local slot_type = item and item.data and item.data.slot_type
        if slot_type ~= expected_slot_type then
            return false, string.format("crafted slot mismatch (%s for %s)", tostring(slot_type), tostring(slot_name))
        end

        local loadout_index = _resolve_selected_index(career_name, 1)
        local ok_write, write_result = pcall(
            items.set_loadout_item,
            items,
            backend_id,
            career_name,
            slot_name,
            loadout_index
        )
        if not ok_write or write_result == false then
            return false, "loadout write failed: " .. tostring(write_result)
        end

        -- Recreate the current local career's weapon unit immediately. If the
        -- player unit is unavailable during a state transition, the indexed data
        -- write above remains authoritative and the next spawn reads the new bid.
        local live_equipped = false
        local pl = Managers.player and Managers.player:local_player()
        local unit = pl and pl.player_unit
        local profile_index = pl and pl:profile_index()
        local career_index = pl and pl:career_index()
        local profile = SPProfiles and profile_index and SPProfiles[profile_index]
        local current_career = profile and profile.careers and career_index
            and profile.careers[career_index] and profile.careers[career_index].name
        if current_career == career_name and unit and Unit.alive(unit) then
            local inv_ext = ScriptUnit.has_extension(unit, "inventory_system")
            if inv_ext and inv_ext.create_equipment_in_slot then
                local ok_live, live_err = pcall(
                    inv_ext.create_equipment_in_slot,
                    inv_ext,
                    slot_name,
                    backend_id
                )
                if ok_live then
                    live_equipped = true
                else
                    mod._cim_auto_equip_last_err = tostring(live_err)
                    pcall(printf, "[cim:562] live auto-equip failed career=%s slot=%s bid=%s err=%s",
                        tostring(career_name), tostring(slot_name), tostring(backend_id), tostring(live_err))
                end
            end
        end

        local event = Managers.state and Managers.state.event
        if event and event.trigger then
            pcall(event.trigger, event, "event_set_loadout_items")
        end

        mod._cim_auto_equip_last = {
            backend_id = backend_id,
            career_name = career_name,
            slot_name = slot_name,
            loadout_index = loadout_index,
            live_equipped = live_equipped,
        }
        return true, live_equipped and "live" or "loadout"
    end

    mod._cim_auto_equip_crafted_weapon = _auto_equip_crafted_weapon
    mod._cim_auto_equip_slot_type = _auto_equip_slot_type

    -- #1360: exact five-slot community-build transaction primitives. These are
    -- deliberately separate from the default-on craft convenience above:
    -- importing a selected build is an explicit user action and must equip all
    -- five exact backend ids regardless of the auto-equip-new-weapons setting.
    -- The importer snapshots first, writes with readback, and calls finalize only
    -- after talents and every slot have committed, so no half-build is presented.
    local _EXACT_LOADOUT_SLOTS = {
        slot_melee = true, slot_ranged = true, slot_necklace = true,
        slot_ring = true, slot_trinket_1 = true,
    }
    local _EXACT_ACCESSORY_TYPES = {
        slot_necklace = "necklace", slot_ring = "ring",
        slot_trinket_1 = "trinket",
    }

    local function _snapshot_exact_loadout(career_name, slot_names)
        if type(career_name) ~= "string" or type(slot_names) ~= "table" then
            return nil, "arguments"
        end
        local items = Managers.backend and Managers.backend:get_interface("items")
        local mirror = items and items._backend_mirror
        if not items or not mirror or type(mirror.get_character_data) ~= "function" then
            return nil, "items backend not ready"
        end
        local index = _resolve_selected_index(career_name, 1)
        local snapshot = {}
        for i = 1, #slot_names do
            local slot_name = slot_names[i]
            if not _EXACT_LOADOUT_SLOTS[slot_name] then return nil, "slot:" .. tostring(slot_name) end
            local ok, bid = pcall(mirror.get_character_data, mirror,
                career_name, slot_name, index)
            if not ok or type(bid) ~= "string" or not items:get_item_from_id(bid) then
                return nil, "missing current item:" .. tostring(slot_name)
            end
            snapshot[slot_name] = bid
        end
        return { index = index, slots = snapshot }, nil
    end

    local function _write_exact_loadout_item(career_name, slot_name, backend_id, index)
        if not _EXACT_LOADOUT_SLOTS[slot_name] then return false, "slot" end
        local items = Managers.backend and Managers.backend:get_interface("items")
        local item = items and items:get_item_from_id(backend_id)
        local data = item and item.data
        if not items or not data then return false, "item" end
        local accessory_type = _EXACT_ACCESSORY_TYPES[slot_name]
        if accessory_type then
            if data.slot_type ~= accessory_type then return false, "slot_type" end
        elseif data.slot_type ~= "melee" and data.slot_type ~= "ranged" then
            return false, "slot_type"
        end
        local ok, result = pcall(items.set_loadout_item, items, backend_id,
            career_name, slot_name, index)
        if not ok or result == false then return false, "write:" .. tostring(result) end
        local mirror = items._backend_mirror
        if not mirror or type(mirror.get_character_data) ~= "function" then
            return false, "mirror"
        end
        local ok_read, readback = pcall(mirror.get_character_data, mirror,
            career_name, slot_name, index)
        if not ok_read or readback ~= backend_id then
            return false, "readback:" .. tostring(readback)
        end
        return true
    end

    local function _finalize_exact_loadout(career_name, assignments)
        if type(assignments) ~= "table" then return false, "assignments" end
        local player = Managers.player and Managers.player:local_player()
        local unit = player and player.player_unit
        local profile_index = player and player:profile_index()
        local career_index = player and player:career_index()
        local profile = SPProfiles and profile_index and SPProfiles[profile_index]
        local current_career = profile and profile.careers and career_index
            and profile.careers[career_index] and profile.careers[career_index].name
        if current_career == career_name and unit and Unit.alive(unit) then
            local inventory = ScriptUnit.has_extension(unit, "inventory_system")
            if inventory and inventory.create_equipment_in_slot then
                for _, slot_name in ipairs({ "slot_melee", "slot_ranged" }) do
                    local backend_id = assignments[slot_name]
                    if backend_id then
                        local ok, err = pcall(inventory.create_equipment_in_slot,
                            inventory, slot_name, backend_id)
                        if not ok then return false, "live:" .. slot_name .. ":" .. tostring(err) end
                    end
                end
            end
        end
        local event = Managers.state and Managers.state.event
        if event and event.trigger then
            pcall(event.trigger, event, "event_set_loadout_items")
        end
        return true
    end

    mod._cim_snapshot_exact_loadout = _snapshot_exact_loadout
    mod._cim_write_exact_loadout_item = _write_exact_loadout_item
    mod._cim_finalize_exact_loadout = _finalize_exact_loadout

    -- Open the VANILLA standard crafting bench (salvage / craft / re-roll / upgrade
    -- / apply-illusion). Works in the Keep always; in adventure missions when
    -- 'Allow in mission' is ON. Material-clean (unlike the Athanor /forge_hotkey).
    -- mod.open_standard_crafting is defined further down (Athanor section); the
    -- command is registered at load and dispatches at runtime, so order is fine.
    mod:command("cim_craft_standard", "Open the standard crafting bench (salvage / craft / re-roll properties + traits / upgrade rarity / apply illusion). Keep always; in mission with 'Allow in mission' ON. Adventure only.", function()
        if type(mod.open_standard_crafting) == "function" then
            mod.open_standard_crafting()
        else
            mod:echo("Standard crafting opener not initialised yet.")
        end
    end)


    state.exports = {}
    return state.exports
end

return install
