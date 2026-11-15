--[[
#1654 (WP-CIM-04): helpers for the boot restore of saved crafts.

The restore loops in the entry (`_athanor_inject_all`, `_athanor_retry_pending`)
inject every saved craft with `{ restore = true, defer_refresh = true }`
(_cim_synthetic_item_contract.lua: no autosave, no "new item" marker, a
postcondition mismatch keeps the row) and then refresh the item caches once per
pass instead of once per item. This module owns that refresh and the
kept-with-warning report; the entry chunk is at its line ceiling.

  mod._cim_refresh_backend_items()  dirtify_interfaces + items:_refresh(); also
                                    the per-craft refresh in _athanor_inject_item
  mod._cim_note_restore_warning(bid, record, warning)
                                    prints "[cim:1654] restore kept ..." once per
                                    (bid, field) and stores mod._cim_restore_warnings[bid]
]]

return function(context)
    local mod = assert(context.mod, "restore pass needs mod")
    local print_line = context.print_line or function() end
    local get_managers = context.get_managers or function() return rawget(_G, "Managers") end

    mod._cim_restore_warnings = mod._cim_restore_warnings or {}
    local printed = {}

    -- Moved unchanged from the inner refresh_backend of _athanor_inject_item.
    mod._cim_refresh_backend_items = function()
        local managers = get_managers()
        local backend = managers and managers.backend
        if not backend then return false, "backend_unavailable" end
        if type(backend.dirtify_interfaces) == "function" then
            backend:dirtify_interfaces()
        end
        if type(backend.get_interface) ~= "function" then
            return false, "items_interface_unavailable"
        end
        local items_iface = backend:get_interface("items")
        if type(items_iface) ~= "table"
                or type(items_iface._refresh) ~= "function" then
            return false, "items_refresh_unavailable"
        end
        items_iface:_refresh()
        return true
    end

    -- Ids the restore path injected this session, with whether the id already
    -- carried the "new item" marker before the add (a craft from an earlier
    -- session keeps its persisted marker until the player views it). Read by
    -- issue1654_saved_crafts_restored: a restore must never add the marker.
    mod._cim_restored_ids = mod._cim_restored_ids or {}
    mod._cim_note_restored = function(bid, was_new)
        mod._cim_restored_ids[bid] = { was_new = was_new == true }
    end

    mod._cim_note_restore_warning = function(bid, record, warning)
        local field = tostring(warning):gsub("^mismatch:", "")
        mod._cim_restore_warnings[bid] = tostring(warning)
        local token = tostring(bid) .. "|" .. field
        if printed[token] then return end
        printed[token] = true
        pcall(print_line, "[cim:1654] restore kept bid=%s key=%s field=%s",
            tostring(bid), tostring(type(record) == "table" and record.item_key), field)
    end
end
