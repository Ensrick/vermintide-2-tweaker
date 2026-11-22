-- qa/runtime/cim/wp_cim_11_auto_equip.lua
-- WP-CIM-11 rig case: with the dormant loadout-persistence path removed, the
-- live craft auto-equip still equips the exact crafted id, and the removed
-- round-trip check is no longer in the cim_dev suite. Class R; no issue
-- (issue = 0).
--
-- Engine reads (Vermintide-2-Source-Code):
--   * BackendUtils.get_loadout_item_id / set_loadout_item:
--     scripts/managers/backend/backend_utils.lua:14, 22
--   * mirror._inventory_items rows: scripts/managers/backend_playfab/playfab_mirror_base.lua:2494-2545
--   * items:get_item_from_id: scripts/managers/backend_playfab/backend_interface_item_playfab.lua:384-389
--   * item.key: playfab_mirror_base.lua:1785; masterlist rows: item_master_list.lua:111
--   * SimpleInventoryExtension.get_item_data:
--     scripts/unit_extensions/default_player_unit/inventory/simple_inventory_extension.lua:1365-1370
-- Modded Progression must not be loaded: its Fresh profile routes the items
-- interface by design, so the equipped id is not a mirror row and the Fresh
-- equip handler refuses an id missing from its own view
-- (modded_progression/_mp_fresh_profile_runtime.lua H.get_loadout_item_id,
-- H.set_loadout_item; rig run 20261115-162744 logged "[mp:fresh] route state=active").
-- Run it with qa/runtime/plans/cim-cases.json, which leaves mp out.
-- The case never calls a backend commit; it equips and re-equips in the rig
-- profile only and deletes its craft before the assertions that can end it.
-- #1933: the delete waits until the hero inventory no longer holds the craft
-- (equipped slot or queued resync spawn,
-- simple_inventory_extension.lua:1372-1398, 1428-1440, 546-568).

local MOD_ID = "cim_dev"
local SLOT = "slot_melee"

-- The equipped melee item key from the live loadout: the items interface,
-- then the native mirror row, then the hero's spawned melee.
local function equipped_melee_key(items, mirror, backend_id)
    if backend_id == nil then return nil, "no equipped id" end
    local ok, row = pcall(items.get_item_from_id, items, backend_id)
    if ok and type(row) == "table" and type(row.key) == "string" then return row.key, "items interface" end
    row = rawget(mirror._inventory_items, backend_id)
    if type(row) == "table" and type(row.key) == "string" then return row.key, "mirror inventory" end
    local player = Managers.player:local_player()
    local unit = player and player.player_unit
    local inventory = unit and Unit.alive(unit) and ScriptUnit.has_extension(unit, "inventory_system")
    local data = inventory and inventory:get_item_data(SLOT)
    if type(data) == "table" and type(data.key) == "string" then return data.key, "hero inventory" end
    return nil, "no source had a key"
end

return {
    issue = 0,
    class = "R",
    arena = "keep",
    mods = { MOD_ID },
    timeout = 120,
    covers = "WP-CIM-11 RIG: auto-equip of a craft still works; removed round-trip check is gone",

    run = function(T)
        T.require(rawget(_G, "MODDED_REALM") == true, "modded realm")
        local cim = get_mod(MOD_ID)
        T.require(cim ~= nil and type(cim._cim_temper_runtime_state) == "table", "cim_dev loaded")
        T.require(type(cim._cim_auto_equip_crafted_weapon) == "function", "auto-equip exported")
        T.require(cim:get("auto_equip_new_weapons") == true, "auto-equip setting on (default)")
        T.require(get_mod("mp") == nil, "Modded Progression not loaded (its Fresh profile routes the items interface)")
        T.require(T.local_hero(30) ~= nil, "local hero alive")

        local backend = Managers.backend
        local mirror = backend:get_backend_mirror()
        local career = Managers.player:local_player():career_name()
        local original = BackendUtils.get_loadout_item_id(career, SLOT)
        local key, key_source = equipped_melee_key(backend:get_interface("items"), mirror, original)
        T.note("original_id", tostring(original))
        T.note("original_in_mirror_inventory", tostring(original ~= nil and rawget(mirror._inventory_items, original) ~= nil))
        T.note("key_source", key_source)
        T.require(type(key) == "string", "melee item key known")
        T.note("item_key", key)

        T.step("craft one weapon")
        local bid = Application.guid()
        local crafted, reason = cim._cim_temper_runtime_state.commit_craft({
            item_key = key, properties = {}, traits = {}, power_level = 300,
            rarity = "modded", via_mirror = true, career_name = career,
        }, bid, { raw_item_key = key })
        T.note("craft", tostring(crafted) .. " " .. tostring(reason))
        local injected = rawget(mirror._inventory_items, bid) ~= nil

        T.step("auto-equip the craft")
        local ok, mode = false, "not run"
        if injected then
            ok, mode = cim._cim_auto_equip_crafted_weapon(career, SLOT, bid)
        end
        T.note("auto_equip", tostring(ok) .. " " .. tostring(mode))
        local equipped = BackendUtils.get_loadout_item_id(career, SLOT)

        -- #1933: deleting the craft while it is equipped (or queued on the hero)
        -- must be refused; deleting it crashed get_skin on the next resync spawn
        -- (rig run 20261122-054737-cim-cases-fc202dd9).
        local function delete_craft()
            if type(cim._cim277_delete_owned_ids) ~= "function" then return 0, "delete not exported" end
            local ok_delete, removed, err = pcall(cim._cim277_delete_owned_ids, { bid })
            if not ok_delete then return 0, tostring(removed) end
            return removed, err
        end
        local held_removed, held_err = delete_craft()
        T.note("delete_while_equipped", tostring(held_removed) .. " " .. tostring(held_err))

        T.step("cleanup")
        pcall(BackendUtils.set_loadout_item, original, career, SLOT)
        -- Put the original back on the hero, wait until no hero inventory slot or
        -- queued spawn holds the craft, then delete it.
        local hero = T.local_hero(30)
        local hero_inventory = hero and ScriptUnit.has_extension(hero, "inventory_system")
        if hero_inventory then
            pcall(hero_inventory.create_equipment_in_slot, hero_inventory, SLOT, original)
        end
        local deletion = cim._cim277_owned_deletion
        local function hero_holds_craft()
            if not (deletion and hero_inventory) then return false end
            return deletion.held_ids({ hero_inventory })[bid] == true
        end
        T.wait_until(function() return not hero_holds_craft() end, 20, "hero released the craft")
        local removed, delete_err = delete_craft()
        T.note("delete", tostring(removed) .. " " .. tostring(delete_err))

        T.expect(injected, "craft injected")
        T.expect(ok == true, "auto-equip returned true")
        T.expect_eq(equipped, bid, "the exact crafted id is equipped")
        T.expect_eq(held_removed, 0, "delete refused while the craft is equipped (#1933)")
        T.expect(tostring(held_err):find("still equipped", 1, true) ~= nil, "refusal names the equipped craft (#1933)")
        T.expect_eq(BackendUtils.get_loadout_item_id(career, SLOT), original, "original item re-equipped")
        T.expect(not hero_holds_craft(), "hero released the craft before the delete")
        T.expect_eq(removed, 1, "craft deleted after the hero released it")

        T.step("the removed round-trip check is gone")
        if type(cim._cim_rt_last) ~= "table" then
            T.cmd("cim_regression_test")
        end
        local last = cim._cim_rt_last
        T.expect(type(last) == "table", "_cim_rt_last present (WP-CIM-05)")
        local found = false
        for _, result in ipairs(type(last) == "table" and last.results or {}) do
            if result.name == "modded_loadout_round_trip_save_then_clear" then found = true end
        end
        T.expect(not found, "modded_loadout_round_trip_save_then_clear is not registered")
    end,
}
