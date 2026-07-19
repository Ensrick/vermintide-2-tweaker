-- Runtime adapter for issue #277's destructive CIM craft cleanup command.
-- Policy and identity stay in the pure core/contract modules; this installer
-- owns only the one-time VMF command registration and narrow runtime accessors.

return function(deps)
    local mod = assert(deps.mod)
    local core = assert(deps.core)
    local contract = assert(deps.contract)
    local get_forged_weapons = assert(deps.get_forged_weapons)
    local get_item_master = assert(deps.get_item_master)
    local get_backend_items = assert(deps.get_backend_items)
    local get_backend_mirror = assert(deps.get_backend_mirror)
    local delete_owned_ids = assert(deps.delete_owned_ids)

    mod:command("forge_delete_all",
        "Delete every unequipped CIM-crafted weapon and accessory (run once to preview, then /forge_delete_all CONFIRM)",
        function(confirm)
            local forged = get_forged_weapons()
            local item_master = get_item_master()
            local items = get_backend_items()
            local mirror = get_backend_mirror()
            if type(forged) ~= "table" or type(item_master) ~= "table"
                    or not items or not mirror
                    or type(mirror._inventory_items) ~= "table" then
                mod:echo("Forge cleanup: backend is not ready; nothing was deleted")
                return
            end

            local craft_ids, retained_out_of_scope, retained_unresolved =
                core.classify(forged, item_master, contract)
            if #craft_ids == 0 then
                mod._cim277_pending_bulk_delete = nil
                mod:echo(string.format(
                    "Forge cleanup: no resolvable CIM crafts. Retained: %d out-of-scope items, %d unresolved definitions.",
                    #retained_out_of_scope, #retained_unresolved))
                return
            end

            local function is_equipped(backend_id)
                local ok_current, current = pcall(items.equipped_by, items, backend_id)
                local ok_saved, saved = pcall(
                    items.is_equipped_by_any_loadout, items, backend_id)
                if not ok_current or not ok_saved
                        or type(current) ~= "table" or type(saved) ~= "table" then
                    return nil
                end
                return #current > 0 or #saved > 0
            end

            local deletable, blocked, uncertain =
                core.partition_equipped(craft_ids, is_equipped)
            if #uncertain > 0 then
                mod._cim277_pending_bulk_delete = nil
                mod:echo(string.format(
                    "Forge cleanup refused: equip state was unavailable for %d craft(s); nothing was deleted.",
                    #uncertain))
                return
            end
            if #blocked > 0 then
                mod._cim277_pending_bulk_delete = nil
                mod:echo(string.format(
                    "Forge cleanup refused: %d CIM craft(s) are equipped in a current or saved loadout. Unequip all of them first; nothing was deleted.",
                    #blocked))
                for i = 1, math.min(#blocked, 5) do
                    mod:echo("  equipped: " .. blocked[i])
                end
                return
            end

            local signature = core.snapshot_signature(
                deletable, forged, item_master, contract)
            if not signature then
                mod._cim277_pending_bulk_delete = nil
                mod:echo(
                    "Forge cleanup refused: the exact craft snapshot was unreadable; nothing was deleted.")
                return
            end
            if confirm ~= "CONFIRM" then
                mod._cim277_pending_bulk_delete = signature
                mod:echo(string.format(
                    "Forge cleanup preview: DELETE %d exact CIM-crafted weapon(s)/accessory(s). Retain %d out-of-scope items and %d unresolved definitions.",
                    #deletable, #retained_out_of_scope, #retained_unresolved))
                mod:echo(
                    "This cannot be undone. Run /forge_delete_all CONFIRM to delete this exact preview set.")
                return
            end

            if mod._cim277_pending_bulk_delete ~= signature then
                mod._cim277_pending_bulk_delete = nil
                mod:echo(
                    "Forge cleanup refused: the craft set changed or no matching preview exists. Run /forge_delete_all again.")
                return
            end
            mod._cim277_pending_bulk_delete = nil

            local removed, err = delete_owned_ids(deletable)
            if err then
                mod:echo("Forge cleanup refused: " .. err .. "; nothing was deleted")
                return
            end
            mod:echo(string.format(
                "Forge cleanup: deleted %d CIM craft(s). Retained %d out-of-scope items and %d unresolved definitions.",
                removed, #retained_out_of_scope, #retained_unresolved))
        end)
end
