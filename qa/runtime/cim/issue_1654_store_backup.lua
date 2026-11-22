-- qa/runtime/cim/issue_1654_store_backup.lua
-- WP-CIM-06b rig case (card file name issue_cim_store_backup.lua, renamed to the
-- issue_<N>_<slug> convention): the crafted-store backup is taken at session
-- start, so a craft made later does not change it; /cim_restore_backup runs as
-- a dry run; the live store is serializable. Advances #1654 and #277 (class R).
--
-- The case never calls a backend commit. It crafts into the rig profile only
-- and deletes its craft before the assertions that can end the case.
--
-- The melee key is read through the items interface first: with Modded
-- Progression's Fresh profile active (rig run 20261115-162744 logged
-- "[mp:fresh] route state=active") the equipped id is not a mirror._inventory_items
-- row (modded_progression/_mp_fresh_profile_runtime.lua H.get_loadout_item_id,
-- H.get_item_from_id). Run it with qa/runtime/plans/cim-cases.json, which leaves mp out.
-- Engine reads (Vermintide-2-Source-Code):
--   * items:get_item_from_id: scripts/managers/backend_playfab/backend_interface_item_playfab.lua:384-389
--   * item.key: playfab_mirror_base.lua:1785; masterlist rows: item_master_list.lua:111
--   * SimpleInventoryExtension.get_item_data:
--     scripts/unit_extensions/default_player_unit/inventory/simple_inventory_extension.lua:1365-1370

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
        local key, key_source = equipped_melee_key(items, mirror, equipped)
        T.note("equipped_id", tostring(equipped))
        T.note("key_source", key_source)
        T.require(type(key) == "string", "melee item key known")
        T.note("item_key", key)

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
