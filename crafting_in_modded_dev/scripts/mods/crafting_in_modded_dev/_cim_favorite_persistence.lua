-- _cim_favorite_persistence.lua -- exact-instance favorite persistence for CIM crafts (#1001).
--
-- Vanilla keeps favorites in PlayerData.favorite_item_ids and prunes every id
-- whose row is absent during BackendInterfaceItemPlayfab._refresh
-- (_unmark_favorites, backend_interface_item_playfab.lua:95-107). CIM injects
-- its synthetic rows after that refresh, so a crafted weapon's green heart
-- survives the session but not a restart. The exact _forged_weapons[backend_id]
-- record therefore owns one durable favorite boolean: a completed vanilla
-- toggle (ItemGridUI.handle_favorite_marking, keyboard/mouse and controller)
-- is captured onto the record, and the mark is re-applied to PlayerData only
-- after the exact row resolves again, on every post-_refresh pass. Records die
-- inside _cim_owned_deletion's transaction, so deletion cannot resurrect a
-- stale favorite. Two crafted copies of one provider weapon keep independent
-- states because the bit lives on the exact backend id, never the weapon key.
-- Pure until install(); the forge state owner supplies every engine dependency.
--
-- Owned by: crafting_in_modded_dev.lua entry point. Consumed via: mod:dofile
-- (manifest) -> mod._cim_favorite_persistence; installed by
-- _cim_forge_state_owner.lua with live records/persist/seam dependencies.

local M = {}

-- Persist one completed favorite toggle onto the exact owned record.
-- Returns (true, new_value) when the stored bit changed, else (false, reason).
-- Foreign ids (native PlayFab rows, other mods' synthetic rows) are refused.
function M.capture(records, backend_id, favorite, persist)
    if type(records) ~= "table" or type(backend_id) ~= "string" then
        return false, "invalid_input"
    end
    local record = records[backend_id]
    if type(record) ~= "table" then
        return false, "foreign_item"
    end
    local next_value = favorite == true
    if (record.favorite == true) == next_value then
        return false, "unchanged"
    end
    record.favorite = next_value
    if type(persist) == "function" then persist() end
    return true, next_value
end

-- Re-apply one stored favorite to vanilla PlayerData, but only once the exact
-- backend row resolves through the live items interface. Fails closed on any
-- resolution or marking error so a half-injected row is retried on the next
-- pass instead of corrupting vanilla state.
function M.restore_one(records, backend_id, resolve_item, mark_favorite)
    if type(records) ~= "table" or type(backend_id) ~= "string" then
        return false, "invalid_input"
    end
    local record = records[backend_id]
    if type(record) ~= "table" or record.favorite ~= true then
        return false, "not_favorite"
    end
    if type(resolve_item) ~= "function" or type(mark_favorite) ~= "function" then
        return false, "runtime_unavailable"
    end
    local ok_item, item = pcall(resolve_item, backend_id)
    if not ok_item or type(item) ~= "table" then
        return false, "item_unavailable"
    end
    local ok_mark, err = pcall(mark_favorite, backend_id, item)
    if not ok_mark then
        return false, "mark_failed:" .. tostring(err)
    end
    return true
end

-- Idempotent sweep over every stored favorite. Returns (restored, deferred);
-- deferred rows stay durable and are retried on the next injection/refresh.
function M.restore_all(records, resolve_item, mark_favorite)
    if type(records) ~= "table" then return 0, 0 end
    local restored, deferred = 0, 0
    for backend_id, record in pairs(records) do
        if type(record) == "table" and record.favorite == true then
            local ok = M.restore_one(records, backend_id, resolve_item,
                mark_favorite)
            if ok then
                restored = restored + 1
            else
                deferred = deferred + 1
            end
        end
    end
    return restored, deferred
end

function M.install(runtime)
    assert(type(runtime) == "table", "favorite persistence runtime required")
    local mod = assert(runtime.mod, "favorite persistence mod required")
    local records = assert(runtime.records,
        "favorite persistence records accessor required")
    local persist = assert(runtime.persist,
        "favorite persistence persist required")
    local managers = assert(runtime.managers,
        "favorite persistence managers accessor required")
    local item_helper = assert(runtime.item_helper,
        "favorite persistence ItemHelper accessor required")
    local rt_register = assert(runtime.rt_register,
        "favorite persistence check registrar required")
    local grid_class = assert(runtime.item_grid_ui,
        "favorite persistence grid class required")
    local backend_items = assert(runtime.backend_items,
        "favorite persistence backend items class required")
    local print_line = runtime.print_line or function() end

    local function resolve_item(backend_id)
        local live = managers()
        local backend = live and live.backend
        local items = backend and backend.get_interface
            and backend:get_interface("items")
        if not (items and items.get_item_from_id) then return nil end
        local ok, item = pcall(items.get_item_from_id, items, backend_id)
        if ok and type(item) == "table" then return item end
        return nil
    end

    local function mark_favorite(backend_id, item)
        local helper = item_helper()
        assert(type(helper) == "table"
            and type(helper.mark_backend_id_as_favorite) == "function",
            "ItemHelper unavailable")
        -- save=false: PlayerData mutation only; vanilla autosaves later and
        -- this can never re-enter _refresh, so the restore seam cannot loop.
        helper.mark_backend_id_as_favorite(backend_id, item, false)
    end

    local api = {}
    function api.restore_one(backend_id)
        return M.restore_one(records(), backend_id, resolve_item, mark_favorite)
    end
    local last_receipt
    function api.restore_all()
        local restored, deferred = M.restore_all(records(), resolve_item,
            mark_favorite)
        if restored > 0 or deferred > 0 then
            local receipt = restored .. "/" .. deferred
            if receipt ~= last_receipt then
                last_receipt = receipt
                print_line("[cim:1001] favorite restore applied=%d deferred=%d",
                    restored, deferred)
            end
        end
        return restored, deferred
    end

    -- ItemGridUI.handle_favorite_marking owns BOTH keyboard/mouse and
    -- controller favorite toggles (all six vanilla callers route through it)
    -- and returns true only after vanilla completed a toggle. Capture the
    -- post-toggle state for exact owned ids only; foreign rows fall through
    -- untouched. Sole CIM hook on this (class, method) pair.
    mod:hook(grid_class, "handle_favorite_marking",
        function(func, self, input_service)
            local handled = func(self, input_service)
            if handled then
                local item
                local live = managers()
                local gamepad = live and live.input
                    and live.input:is_device_active("gamepad")
                if gamepad then
                    item = self:selected_item()
                else
                    item = self:get_item_hovered()
                end
                local backend_id = item and item.backend_id
                if backend_id and records()[backend_id] then
                    local helper = item_helper()
                    if type(helper) == "table"
                            and type(helper.is_favorite_backend_id)
                            == "function" then
                        local ok, favorite = pcall(
                            helper.is_favorite_backend_id, backend_id, item)
                        if ok then
                            local changed = M.capture(records(), backend_id,
                                favorite == true, persist)
                            if changed then
                                print_line(
                                    "[cim:1001] favorite captured bid=%s favorite=%s",
                                    tostring(backend_id),
                                    tostring(favorite == true))
                            end
                        else
                            print_line("[cim:1001] favorite read failed bid=%s",
                                tostring(backend_id))
                        end
                    end
                end
            end
            return handled
        end)

    -- Vanilla's _unmark_favorites runs at the END of _refresh and prunes ids
    -- whose rows were absent during that pass. Restoring right after covers
    -- every seam that surfaces an owned row (boot inject_all, deferred
    -- re-injects on state transitions, mid-session refreshes) and stays a
    -- deferral until the exact row resolves. Sole CIM hook on this pair.
    mod:hook_safe(backend_items, "_refresh", function()
        api.restore_all()
    end)

    rt_register("issue1001_favorite_persistence", function()
        local live_records = records()
        local stored, mismatched, unresolved = 0, 0, 0
        for backend_id, record in pairs(live_records) do
            if record.favorite ~= nil and type(record.favorite) ~= "boolean" then
                return "invalid favorite state: " .. tostring(backend_id)
            end
            if record.favorite == true then
                stored = stored + 1
                local item = resolve_item(backend_id)
                if item then
                    local helper = item_helper()
                    if type(helper) == "table"
                            and type(helper.is_favorite_backend_id)
                            == "function" then
                        local ok, live_state = pcall(
                            helper.is_favorite_backend_id, backend_id, item)
                        if ok and live_state ~= true then
                            mismatched = mismatched + 1
                        end
                    end
                else
                    unresolved = unresolved + 1
                end
            end
        end
        if mismatched > 0 then
            return mismatched .. " stored favorite(s) not marked in PlayerData"
        end
        if stored == 0 then
            return "skip: no favorited crafts saved"
        end
    end)

    return api
end

return M
