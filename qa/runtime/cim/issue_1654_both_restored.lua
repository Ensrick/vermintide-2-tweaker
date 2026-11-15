-- qa/runtime/cim/issue_1654_both_restored.lua
-- WP-CIM-04 rig case, boot 2 of qa/runtime/plans/cim_restore_two_boot.json.
-- Every restorable saved craft is back in the inventory after a restart, nothing
-- failed, and the restore marked none of boot 1's crafts as new. Closes #1654 on
-- PASS (class R) on the build that carries WP-CIM-04.
--
-- BLOCKED until the rig keeps one profile across two boots (see boot 1). Without
-- that, boot 1's ids are absent and the case is INCONCLUSIVE.
--
-- Engine reads (Vermintide-2-Source-Code):
--   * mirror._inventory_items: scripts/managers/backend_playfab/playfab_mirror_base.lua:2494-2545
--   * PlayerData.new_item_ids: scripts/helpers/item_helper.lua:128-158
-- The case never calls a backend commit.

local MOD_ID = "cim_dev"

return {
    issue = 1654,
    class = "R",
    arena = "keep",
    mods = { MOD_ID },
    timeout = 120,
    covers = "WP-CIM-04 RIG boot 2: both saved copies restored without a new marker",

    host_expect_log = { "[cim:restore] saved=" },
    host_forbid_log = { "mirror_postcondition" },

    run = function(T)
        local cim = get_mod(MOD_ID)
        T.require(cim ~= nil, "cim_dev loaded")
        local ids = cim:get("rig_1654_ids")
        T.require(type(ids) == "table" and #ids == 2,
            "boot 1 crafts carried over (rig keeps one profile across boots)")
        T.require(T.local_hero(30) ~= nil, "local hero alive")

        local mirror = Managers.backend:get_backend_mirror()
        local inventory = mirror and mirror._inventory_items
        T.require(type(inventory) == "table", "backend mirror ready")

        T.step("every restorable saved craft is present")
        local saved, checked, unloadable = cim:get("forged_weapons") or {}, 0, 0
        for bid, record in pairs(saved) do
            local master = type(record) == "table" and type(record.item_key) == "string"
                and rawget(ItemMasterList, record.item_key)
            if type(record) == "table" and record.via_mirror ~= false and master then
                checked = checked + 1
                T.expect(rawget(inventory, bid) ~= nil, "saved craft present: " .. tostring(bid))
            else
                unloadable = unloadable + 1
            end
        end
        T.note("saved_checked", checked)
        T.note("saved_not_loadable", unloadable)
        for _, bid in ipairs(ids) do
            T.expect(rawget(inventory, bid) ~= nil, "boot 1 copy present: " .. tostring(bid))
        end

        T.step("no restore failure and no new marker")
        local failures = {}
        for bid, reason in pairs(cim._cim_restore_failures or {}) do
            -- A record whose ItemMasterList row is missing (provider mod not in
            -- this plan) is deferred, not lost; issue1654_saved_crafts_restored
            -- skips it the same way.
            if not tostring(reason):find("not in ItemMasterList", 1, true) then
                failures[#failures + 1] = tostring(bid) .. "=" .. tostring(reason)
            end
        end
        T.note("restore_failures", table.concat(failures, "; "))
        T.expect(#failures == 0, "no saved craft failed to restore")
        local new_ids = type(rawget(_G, "PlayerData")) == "table" and PlayerData.new_item_ids or {}
        for _, bid in ipairs(ids) do
            T.expect(new_ids[bid] == nil, "restore added no new marker: " .. tostring(bid))
        end

        T.step("cleanup")
        if type(cim._cim277_delete_owned_ids) == "function" then
            pcall(cim._cim277_delete_owned_ids, ids)
        end
        cim:set("rig_1654_ids", nil)

        T.expect_rt(MOD_ID, "issue1654_saved_crafts_restored")
    end,
}
