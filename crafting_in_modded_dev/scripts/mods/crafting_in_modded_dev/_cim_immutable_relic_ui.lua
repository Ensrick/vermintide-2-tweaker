-- Athanor edit/loadout boundary for provider-owned immutable relics (#822).
-- Kept separate from the entry so the UI hooks and classification remain one
-- cohesive owner under the entry's decomposition ceiling.

local M = {}

function M.install(args)
    local mod = assert(args.mod)
    local contract = assert(args.contract)
    local rejection_seen = {}

    local function editable_backend_id(item_backend_id, surface)
        if type(item_backend_id) ~= "string" or item_backend_id == "" then
            return item_backend_id
        end
        local items_backend = args.get_items_backend()
        local item
        if items_backend and type(items_backend.get_item_from_id) == "function" then
            pcall(function() item = items_backend:get_item_from_id(item_backend_id) end)
        end
        local item_key = contract.canonical_item_key(item or {}, item_backend_id)
        local master = type(item) == "table" and item.data
            or item_key and rawget(_G, "ItemMasterList")
                and rawget(ItemMasterList, item_key)
        if contract.is_immutable_relic_identity(item_key, item or master,
                item_backend_id) then
            local diagnostic_key = tostring(surface) .. ":" .. item_backend_id
            if not rejection_seen[diagnostic_key] then
                rejection_seen[diagnostic_key] = true
                printf("[cim:822] immutable relic omitted from Athanor edit surface=%s bid=%s key=%s",
                    tostring(surface), tostring(item_backend_id), tostring(item_key))
            end
            return nil
        end
        return item_backend_id
    end
    mod._cim_athanor_editable_backend_id = editable_backend_id

    mod:hook("BackendInterfaceWeavesPlayFab", "get_loadout_item_id",
            function(func, self, career_name, slot_name)
        if not args.is_active() then return func(self, career_name, slot_name) end
        local loadout = args.get_loadout()[career_name]
        if loadout and loadout[slot_name] then
            local editable = editable_backend_id(loadout[slot_name], "saved_loadout")
            if not editable then loadout[slot_name] = nil end
            return editable
        end
        local items_backend = args.get_items_backend()
        if items_backend then
            local ok, bid = pcall(items_backend.get_loadout_item_id, items_backend,
                career_name, slot_name)
            if ok then return editable_backend_id(bid, "equipped_fallback") end
        end
        return nil
    end)

    mod:hook("BackendInterfaceWeavesPlayFab", "set_loadout_item",
            function(func, self, item_backend_id, career_name, slot_name)
        if not args.is_active() then
            return func(self, item_backend_id, career_name, slot_name)
        end
        item_backend_id = editable_backend_id(item_backend_id, "set_loadout")
        if not item_backend_id then return false end
        local loadout = args.get_loadout()
        loadout[career_name] = loadout[career_name] or {}
        loadout[career_name][slot_name] = item_backend_id
        return true
    end)

    return editable_backend_id
end

return M
