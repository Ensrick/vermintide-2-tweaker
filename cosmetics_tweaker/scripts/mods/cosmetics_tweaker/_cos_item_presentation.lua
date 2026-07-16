-- _cos_item_presentation.lua -- canonical item-card name/icon ownership.
--
-- This engine-free policy resolves one descriptor for inventory, equipment,
-- customization, and Hold-Tab adapters. Custom icons require positive proof
-- from the receiving renderer's local atlas; absent assets keep vanilla data.
--
-- Owned by: cosmetics_tweaker.lua. Consumed via: UIUtils and CIM Tab adapters.

local M = {}

function M.find_peer_record(wearer_peer, candidate_keys, la_store, mesh_store)
    if type(wearer_peer) ~= "string" or wearer_peer == "" then return nil end
    local la_slots = type(la_store) == "table" and la_store[wearer_peer]
    for _, key in ipairs(candidate_keys or {}) do
        local entry = type(la_slots) == "table" and la_slots[key]
        if type(entry) == "table"
                and (entry.hand_field or "left_hand_unit") == "left_hand_unit"
                and (entry.kind == "offhand" or entry.kind == "illusion") then
            return {
                armoury_key = entry.armoury_key,
                vanilla_key = entry.vanilla_key,
            }, "la_peer_cache"
        end
    end

    local mesh_slots = type(mesh_store) == "table" and mesh_store[wearer_peer]
    for _, key in ipairs(candidate_keys or {}) do
        local hands = type(mesh_slots) == "table" and mesh_slots[key]
        local unit_path = type(hands) == "table" and hands.left_hand_unit
        if type(unit_path) == "string" and unit_path ~= "" then
            return { unit_path = unit_path }, "mesh_peer_cache"
        end
    end
    return nil
end

function M.resolve(args)
    args = type(args) == "table" and args or {}
    local out = {
        icon = args.base_icon,
        primary_name = args.primary_name,
        secondary_name = nil,
        ownership = args.ownership,
        changed = false,
    }
    local option = args.secondary_option
    if type(option) ~= "table" or option.follow_main then return out end

    if type(option.name) == "string" and option.name ~= "" then
        out.secondary_name = option.name
        out.changed = true
    end
    if args.ownership == "shield" then
        local icon = option.inventory_icon
        if type(icon) == "string" and icon ~= ""
                and type(args.local_resource_available) == "function"
                and args.local_resource_available(icon) == true then
            out.icon = icon
            out.changed = true
        end
    end
    -- Dual weapons deliberately retain the primary/right-hand icon.
    return out
end

return M
