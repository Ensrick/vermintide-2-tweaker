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
-- The case never calls a backend commit; it equips and re-equips in the rig
-- profile only and deletes its craft before the assertions that can end it.

local MOD_ID = "cim_dev"
local SLOT = "slot_melee"

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
        T.require(T.local_hero(30) ~= nil, "local hero alive")

        local backend = Managers.backend
        local mirror = backend:get_backend_mirror()
        local career = Managers.player:local_player():career_name()
        local original = BackendUtils.get_loadout_item_id(career, SLOT)
        local row = original and rawget(mirror._inventory_items, original)
        local key = row and row.key
        T.require(type(key) == "string", "melee item key known")

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

        T.step("cleanup")
        pcall(BackendUtils.set_loadout_item, original, career, SLOT)
        if type(cim._cim277_delete_owned_ids) == "function" then
            pcall(cim._cim277_delete_owned_ids, { bid })
        end

        T.expect(injected, "craft injected")
        T.expect(ok == true, "auto-equip returned true")
        T.expect_eq(equipped, bid, "the exact crafted id is equipped")
        T.expect_eq(BackendUtils.get_loadout_item_id(career, SLOT), original, "original item re-equipped")

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
