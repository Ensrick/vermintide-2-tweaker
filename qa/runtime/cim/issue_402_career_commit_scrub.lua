-- qa/runtime/cim/issue_402_career_commit_scrub.lua
-- WP-CIM-01 rig case: a crafted Crafting in Modded id never reaches an
-- updateHeroAttributes request, while it stays equipped locally.
-- Advances #402 and #1688 (class R). Neither closes on this case alone.
--
-- Engine reads (Vermintide-2-Source-Code):
--   * PlayFabRequestQueue.enqueue(self, request, success_callback, send_eac_challenge, error_callback)
--     scripts/managers/backend_playfab/playfab_request_queue.lua:25
--   * the mirror's request queue instance: playfab_mirror_base.lua:58
--   * updateHeroAttributes request built at playfab_mirror_base.lua:2885-2909
--   * mirror._career_data[career][mirror._career_loadouts[career]][slot] written by
--     set_character_data: playfab_mirror_base.lua:1928-1941
--   * vanilla equip ends in that writer: backend_interface_item_playfab.lua:635-669 (line 665)
--   * items:get_loadout_item_id / set_loadout_item / get_item_from_id:
--     scripts/managers/backend_playfab/backend_interface_item_playfab.lua:512, 635, 384-389
--     (get_item_from_id reads the interface's item table, which is the mirror's
--     inventory table unless game-mode items are active: lines 56-76)
--   * item.key: playfab_mirror_base.lua:1785; masterlist rows: item_master_list.lua:111
--   * SimpleInventoryExtension.get_item_data:
--     scripts/unit_extensions/default_player_unit/inventory/simple_inventory_extension.lua:1365-1370
--   * BackendManagerPlayFab.commit(self, skip_queue, commit_complete_callback):
--     scripts/managers/backend_playfab/backend_manager_playfab.lua:933
--
-- Tweaker: GUI may be loaded (gui_tweaker_dev or the public gut); the case
-- notes which, and its leak check is the same either way.
--
-- Modded Progression must not be loaded: its Fresh profile routes the items
-- interface by design (loadout ids come from the Fresh view and
-- set_loadout_item writes the Fresh profile, never the native mirror:
-- modded_progression/_mp_fresh_profile_runtime.lua header, H.get_loadout_item_id,
-- H.set_loadout_item; rig run 20261115-162744 logged "[mp:fresh] route state=active").
-- Run it with qa/runtime/plans/cim-cases.json, which leaves mp out.
--
-- This case calls Managers.backend:commit (backend write shield on in the rig).

local MOD_ID = "cim_dev"
local SLOT = "slot_melee"

-- Shared between run and cleanup; filled during run only.
local state = {}

local function request_contains(request, needle)
    local params = type(request) == "table" and request.FunctionParameter
    local attributes = type(params) == "table" and params.hero_attributes
    if type(attributes) ~= "table" then return false end
    -- The card's check reads hero_attributes.characters_data; every encoded
    -- attribute is scanned so the vs_characters_data key is covered too.
    for key, value in pairs(attributes) do
        if tostring(value):find(needle, 1, true) then
            return true, key, tostring(value)
        end
    end
    return false
end

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

local function cleanup()
    if state.cleaned then return end
    state.cleaned = true
    if state.queue and state.original_enqueue ~= nil then
        if state.queue_had_own_enqueue then
            state.queue.enqueue = state.original_enqueue
        else
            rawset(state.queue, "enqueue", nil)
        end
    end
    if state.items and state.original_id and state.career then
        pcall(state.items.set_loadout_item, state.items, state.original_id, state.career, SLOT)
    end
    if state.bid then
        local cim = get_mod(MOD_ID)
        if cim and cim._cim277_delete_owned_ids then
            pcall(cim._cim277_delete_owned_ids, { state.bid })
        end
    end
end

return {
    id = "cim-402-career-commit-scrub",
    issue = 402,
    class = "R",
    covers = "WP-CIM-01 RIG acceptance: crafted id equipped, commit sent, no request carries the id",
    arena = "keep",
    mods = { MOD_ID },
    timeout = 150,

    run = function(T)
        for k in pairs(state) do state[k] = nil end
        T.step("preconditions")
        T.require(rawget(_G, "MODDED_REALM") == true, "modded realm")
        local cim = get_mod(MOD_ID)
        T.require(cim ~= nil, "cim_dev loaded")
        T.require(cim._cim402_guard_installed == true, "career commit guard installed")
        T.require(get_mod("mp") == nil, "Modded Progression not loaded (its Fresh profile routes the items interface)")
        local gut = get_mod("gut") and "gut" or (get_mod("gut_dev") and "gut_dev") or "none"
        T.note("tweaker_gui_loaded", gut)

        local backend = Managers.backend
        local mirror = backend:get_backend_mirror()
        local items = backend:get_interface("items")
        local career = Managers.player:local_player():career_name()
        local index = mirror._career_loadouts[career]
        T.require(index ~= nil, "selected loadout index known")
        local original_id = items:get_loadout_item_id(career, SLOT)
        T.require(original_id ~= nil, "melee slot equipped")
        local key, key_source = equipped_melee_key(items, mirror, original_id)
        T.note("career", career)
        T.note("loadout_index", tostring(index))
        T.note("original_id", tostring(original_id))
        T.note("original_in_mirror_inventory", tostring(rawget(mirror._inventory_items, original_id) ~= nil))
        T.note("key_source", key_source)
        T.require(type(key) == "string", "melee item key known")
        T.note("item_key", key)

        state.items = items
        state.career = career
        state.original_id = original_id

        T.step("craft the equipped melee key")
        local bid = Application.guid()
        local crafted, reason = cim._cim_temper_runtime_state.commit_craft({
            item_key = key,
            properties = {},
            traits = {},
            power_level = 300,
            rarity = "modded",
            via_mirror = true,
            career_name = career,
        }, bid, { raw_item_key = key })
        state.bid = bid
        -- The driver has no cleanup hook and T.require ends the case, so undo
        -- the setup before any precondition that can fail after a mutation.
        local injected = crafted ~= false and rawget(mirror._inventory_items, bid) ~= nil
        if not injected then cleanup() end
        T.require(injected, "craft injected: " .. tostring(reason))

        T.step("equip the craft")
        local ok_equip, equip_result = pcall(items.set_loadout_item, items, bid, career, SLOT)
        T.note("equip_result", ok_equip and tostring(equip_result) or ("error: " .. tostring(equip_result)))
        local equipped = mirror._career_data[career][index][SLOT] == bid
        if not equipped then cleanup() end
        T.require(equipped, "craft equipped in _career_data")

        T.step("record updateHeroAttributes requests")
        local queue = mirror._request_queue
        local recorded, leaked = {}, {}
        state.queue = queue
        state.queue_had_own_enqueue = rawget(queue, "enqueue") ~= nil
        state.original_enqueue = queue.enqueue
        local original_enqueue = queue.enqueue
        queue.enqueue = function(self, request, ...)
            if type(request) == "table" and request.FunctionName == "updateHeroAttributes" then
                local carries, key, text = request_contains(request, bid)
                recorded[#recorded + 1] = carries
                if carries then
                    -- Never forward a leaking request to the backend.
                    leaked[#leaked + 1] = tostring(key) .. "=" .. text:sub(1, 4000)
                    return nil
                end
            end
            return original_enqueue(self, request, ...)
        end

        T.step("commit")
        local done = false
        backend:commit(true, function() done = true end)
        T.wait_until(function() return done end, 90, "commit finished")

        T.note("update_requests", tostring(#recorded))
        T.note("last_report", cim._cim402_last_report
            and string.format("scrubbed=%s unsafe=%s",
                tostring(cim._cim402_last_report.scrubbed),
                tostring(cim._cim402_last_report.unsafe))
            or "none")
        for i = 1, #leaked do
            T.note("leaked_request_" .. i, leaked[i])
        end
        T.expect(#leaked == 0, "no updateHeroAttributes request contained the crafted id")
        T.expect(mirror._career_data[career][index][SLOT] == bid, "craft still equipped locally")

        cleanup()
        T.expect_rt(MOD_ID, "issue402_career_commit_guard")
    end,

    cleanup = function()
        cleanup()
    end,
}
