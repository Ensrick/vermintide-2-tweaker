-- qa/runtime/woc/issue_402_career_commit_scrub.lua
-- WP-CIM-07 rig case (woc copy of qa/runtime/cim/issue_402_career_commit_scrub.lua):
-- an equipped Weapons of Chaos relic never reaches an
-- updateHeroAttributes request, while it stays equipped locally. Advances #402
-- and #1688 (class R). Run once without Tweaker: GUI and once with gut_dev
-- loaded; with gut_dev the expected result is zero scrubs and no request
-- containing the id.
--
-- This case calls Managers.backend:commit(true, ...) because the card's rig
-- acceptance copies the CIM-01 case, which needs a real commit to capture the
-- request. A request that carries the id is recorded and NOT forwarded. Run it
-- with the WP-H-14 backend write shield on (rule R9).
--
-- Engine reads (Vermintide-2-Source-Code):
--   * PlayFabRequestQueue.enqueue: scripts/managers/backend_playfab/playfab_request_queue.lua:25
--   * the mirror's request queue: playfab_mirror_base.lua:58
--   * updateHeroAttributes request: playfab_mirror_base.lua:2885-2909
--   * _career_data writes: playfab_mirror_base.lua:1928-1941
--   * items:get_loadout_item_id / set_loadout_item: backend_interface_item_playfab.lua:512, 635
--   * BackendManagerPlayFab.commit: backend_manager_playfab.lua:933

local MOD_ID = "WOC"
local SLOT = "slot_melee"

local state = {}

local function request_contains(request, needle)
    local params = type(request) == "table" and request.FunctionParameter
    local attributes = type(params) == "table" and params.hero_attributes
    if type(attributes) ~= "table" then return false end
    for key, value in pairs(attributes) do
        if tostring(value):find(needle, 1, true) then
            return true, key, tostring(value)
        end
    end
    return false
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
end

local function can_wield(item, career)
    local data = type(item) == "table" and item.data
    if type(data) ~= "table" or data.slot_type ~= "melee" then return false end
    for _, name in ipairs(type(data.can_wield) == "table" and data.can_wield or {}) do
        if name == career then return true end
    end
    return false
end

return {
    issue = 402,
    class = "R",
    arena = "keep",
    mods = { MOD_ID },
    timeout = 150,
    covers = "WP-CIM-07 RIG (woc): WOC relic equipped, commit sent, no request carries the id",

    run = function(T)
        for k in pairs(state) do state[k] = nil end
        T.require(rawget(_G, "MODDED_REALM") == true, "modded realm")
        local woc = get_mod(MOD_ID)
        T.require(woc ~= nil and woc._woc402_guard_installed == true, "woc guard installed")
        local is_woc = woc._woc402_is_owned_id
        T.require(type(is_woc) == "function", "woc id predicate exported")
        local gut_loaded = get_mod("gut_dev") ~= nil or get_mod("gut") ~= nil
        T.note("gut_loaded", tostring(gut_loaded))

        local backend = Managers.backend
        local mirror = backend:get_backend_mirror()
        local items = backend:get_interface("items")
        local career = Managers.player:local_player():career_name()
        local index = mirror._career_loadouts[career]
        T.require(index ~= nil, "selected loadout index known")
        local original_id = items:get_loadout_item_id(career, SLOT)
        T.require(original_id ~= nil, "melee slot equipped")

        local bid
        for id, item in pairs(mirror._inventory_items) do
            if is_woc(id) and can_wield(item, career) then bid = id; break end
        end
        T.require(bid ~= nil, "a WOC melee relic this career can wield is in the inventory")
        T.note("woc_bid", bid)
        state.items, state.career, state.original_id = items, career, original_id

        T.step("equip the WOC relic")
        items:set_loadout_item(bid, career, SLOT)
        local equipped = mirror._career_data[career][index][SLOT] == bid
        if not equipped then cleanup() end
        T.require(equipped, "WOC relic equipped in _career_data")

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
                    leaked[#leaked + 1] = tostring(key) .. "=" .. text:sub(1, 4000)
                    return nil
                end
            end
            return original_enqueue(self, request, ...)
        end

        T.step("commit")
        woc._woc402_last_report = nil
        local done = false
        backend:commit(true, function() done = true end)
        T.wait_until(function() return done end, 90, "commit finished")

        local report = woc._woc402_last_report
        T.note("update_requests", tostring(#recorded))
        T.note("last_report", report and string.format("scrubbed=%s unsafe=%s",
            tostring(report.scrubbed), tostring(report.unsafe)) or "none")
        for i = 1, #leaked do T.note("leaked_request_" .. i, leaked[i]) end
        local still_equipped = mirror._career_data[career][index][SLOT] == bid

        cleanup()
        T.expect(#leaked == 0, "no updateHeroAttributes request contained the WOC id")
        T.expect(still_equipped, "WOC relic still equipped locally")
        if gut_loaded then
            T.expect(report == nil or report.scrubbed == 0,
                "with Tweaker: GUI loaded the guard scrubbed nothing (the store held the write)")
        end
        T.expect_rt(MOD_ID, "issue402_career_commit_guard")
    end,
}
