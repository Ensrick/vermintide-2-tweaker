-- qa/runtime/cim/issue_1654_craft_two_copies.lua
-- WP-CIM-04 rig case, boot 1 of qa/runtime/plans/cim_restore_two_boot.json.
-- Crafts two saved copies of the hero's current melee key; boot 2
-- (issue_1654_both_restored.lua) proves both come back. #1654 (class R).
--
-- The rig keeps one profile across the plan's boots (WP-H-08,
-- tools/harness/Invoke-RigBoots.ps1: every boot after the first runs with
-- New-RigProfile.ps1 -KeepProfile), so boot 2 sees these crafts. If the ids do not
-- carry over, boot 2 reports INCONCLUSIVE, never FAIL.
--
-- Engine reads (Vermintide-2-Source-Code):
--   * mirror._inventory_items rows: scripts/managers/backend_playfab/playfab_mirror_base.lua:2494-2545
--   * BackendInterfaceItemPlayfab.get_loadout_item_id: backend_interface_item_playfab.lua:512
--   * ItemHelper.unmark_backend_id_as_new: scripts/helpers/item_helper.lua:160
-- The case never calls a backend commit.

local MOD_ID = "cim_dev"
local SLOT = "slot_melee"
-- 3/5 bubbles of a 0.1..0.2 range: the codec-sensitive stamina value of #1654.
local STAMINA = (0.2 * 3 / 5 - 0.1) / (0.2 - 0.1)

return {
    issue = 1654,
    class = "R",
    arena = "keep",
    mods = { MOD_ID },
    timeout = 120,
    covers = "WP-CIM-04 RIG boot 1: two saved copies of one melee key",

    run = function(T)
        T.require(rawget(_G, "MODDED_REALM") == true, "modded realm")
        local cim = get_mod(MOD_ID)
        T.require(cim ~= nil and type(cim._cim_temper_runtime_state) == "table", "cim_dev loaded")
        T.require(T.local_hero(30) ~= nil, "local hero alive")

        local backend = Managers.backend
        local mirror = backend:get_backend_mirror()
        local items = backend:get_interface("items")
        local career = Managers.player:local_player():career_name()
        local equipped = items:get_loadout_item_id(career, SLOT)
        local row = equipped and rawget(mirror._inventory_items, equipped)
        local key = row and row.key
        T.require(type(key) == "string", "melee item key known")
        T.note("item_key", key)

        T.step("craft two copies")
        local ids = {}
        for i, properties in ipairs({ { attack_speed = 0 }, { stamina = STAMINA } }) do
            local bid = Application.guid()
            local ok, reason = cim._cim_temper_runtime_state.commit_craft({
                item_key = key,
                properties = properties,
                traits = {},
                power_level = 300,
                rarity = "modded",
                via_mirror = true,
                career_name = career,
            }, bid, { raw_item_key = key })
            T.note("craft_" .. i, tostring(bid) .. " ok=" .. tostring(ok) .. " reason=" .. tostring(reason))
            ids[#ids + 1] = bid
        end
        for i, bid in ipairs(ids) do
            T.expect(rawget(mirror._inventory_items, bid) ~= nil, "copy " .. i .. " is in the inventory")
        end

        -- A craft marks its id as new and autosaves (item_helper.lua:128-158). Clear
        -- that so boot 2 can prove the restore itself adds no marker. Rig profile only.
        for _, bid in ipairs(ids) do
            pcall(ItemHelper.unmark_backend_id_as_new, bid)
        end
        -- Hand the two ids to boot 2 through the rig profile's cim_dev settings.
        cim:set("rig_1654_ids", ids)
    end,
}
