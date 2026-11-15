-- qa/runtime/cim/issue_1654_store_backup.lua
-- WP-CIM-06b rig case (card file name issue_cim_store_backup.lua, renamed to the
-- issue_<N>_<slug> convention): the crafted-store backup is taken at session
-- start, so a craft made later does not change it; /cim_restore_backup runs as
-- a dry run; the live store is serializable. Advances #1654 and #277 (class R).
--
-- The case never calls a backend commit. It crafts into the rig profile only
-- and deletes its craft before the assertions that can end the case.

local MOD_ID = "cim_dev"
local SLOT = "slot_melee"

local function count(t)
    local n = 0
    if type(t) == "table" then for _ in pairs(t) do n = n + 1 end end
    return n
end

return {
    issue = 1654,
    class = "R",
    arena = "keep",
    mods = { MOD_ID },
    timeout = 120,
    covers = "WP-CIM-06b RIG: session-start backup unchanged by a later craft; dry-run restore command",

    run = function(T)
        T.require(rawget(_G, "MODDED_REALM") == true, "modded realm")
        local cim = get_mod(MOD_ID)
        T.require(cim ~= nil and type(cim._cim_temper_runtime_state) == "table", "cim_dev loaded")
        T.require(T.local_hero(30) ~= nil, "local hero alive")

        local before = count(cim:get("forged_weapons_backup"))
        T.note("backup_ids_before", before)

        local backend = Managers.backend
        local mirror = backend:get_backend_mirror()
        local items = backend:get_interface("items")
        local career = Managers.player:local_player():career_name()
        local equipped = items:get_loadout_item_id(career, SLOT)
        local row = equipped and rawget(mirror._inventory_items, equipped)
        local key = row and row.key
        T.require(type(key) == "string", "melee item key known")

        T.step("craft one item after session start")
        local bid = Application.guid()
        local ok, reason = cim._cim_temper_runtime_state.commit_craft({
            item_key = key, properties = {}, traits = {}, power_level = 300,
            rarity = "modded", via_mirror = true, career_name = career,
        }, bid, { raw_item_key = key })
        T.note("craft", tostring(ok) .. " " .. tostring(reason))
        local after = count(cim:get("forged_weapons_backup"))
        local crafted = cim:get("forged_weapons")
        local recorded = type(crafted) == "table" and crafted[bid] ~= nil

        T.step("dry-run restore command")
        T.cmd("cim_restore_backup")

        T.step("cleanup")
        if type(cim._cim277_delete_owned_ids) == "function" then
            pcall(cim._cim277_delete_owned_ids, { bid })
        end

        T.expect(recorded, "the craft reached the live store")
        T.expect_eq(after, before, "backup id count unchanged by a later craft")
        T.expect_rt(MOD_ID, "issue_cim_store_serializable")
    end,
}
