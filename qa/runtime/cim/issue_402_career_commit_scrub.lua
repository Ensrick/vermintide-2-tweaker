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
--   * items:get_loadout_item_id / set_loadout_item:
--     scripts/managers/backend_playfab/backend_interface_item_playfab.lua:512, 635
--   * item.key: playfab_mirror_base.lua:1785
--   * BackendManagerPlayFab.commit(self, skip_queue, commit_complete_callback):
--     scripts/managers/backend_playfab/backend_manager_playfab.lua:933
--
-- Tweaker: GUI must not be loaded: this case proves the cim-only path.

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
        T.require(get_mod("gut") == nil and get_mod("gut_dev") == nil, "Tweaker: GUI not loaded")
        T.require(cim._cim402_guard_installed == true, "career commit guard installed")

        local backend = Managers.backend
        local mirror = backend:get_backend_mirror()
        local items = backend:get_interface("items")
        local career = Managers.player:local_player():career_name()
        local index = mirror._career_loadouts[career]
        T.require(index ~= nil, "selected loadout index known")
        local original_id = items:get_loadout_item_id(career, SLOT)
        T.require(original_id ~= nil, "melee slot equipped")
        local original_item = rawget(mirror._inventory_items, original_id)
        local key = original_item and original_item.key
        T.require(type(key) == "string", "melee item key known")
        T.note("career", career)
        T.note("loadout_index", tostring(index))
        T.note("original_id", tostring(original_id))
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
        items:set_loadout_item(bid, career, SLOT)
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
