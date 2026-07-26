-- Pure native-loadout policy. Keep this file free of VMF/game globals so the realm and
-- backend-ID boundary can be exercised by the offline Lua harness.
local P = {}
P.MODE_OFF, P.MODE_STORE, P.MODE_READONLY = "off", "store", "readonly"

local COSMETIC_SLOTS = {
    slot_skin = true,
    slot_hat = true,
    slot_frame = true,
    slot_pose = true,
}

local WEAPON_SLOTS = { slot_melee = true, slot_ranged = true }
local MAX_SNAPSHOT_DEPTH = 12
local MAX_SNAPSHOT_NODES = 256

function P.is_cwv_backend_id(backend_id)
    return type(backend_id) == "string"
        and backend_id:match("^cwv_.+_%d%d%d$") ~= nil
end

function P.mode(is_modded, use_non_modded)
    if not is_modded then return P.MODE_OFF end
    return use_non_modded and P.MODE_READONLY or P.MODE_STORE
end

function P.is_cosmetic_slot(slot_name)
    return COSMETIC_SLOTS[slot_name] == true
end

-- BackendUtils receives an inventory/backend id. The PlayFab item interface stores
-- cosmetics by their stable master-list identity instead (override_id or ItemId).
-- Keep that translation pure so LA-cloned-interface capture can be regression tested
-- without booting VMF or constructing a backend mirror.
function P.canonical_equip_value(slot_name, backend_id, item)
    if backend_id == nil then return nil, "missing_backend_id" end
    if not P.is_cosmetic_slot(slot_name) then return backend_id, "backend_id" end
    if type(item) ~= "table" then return nil, "unresolved_item" end
    local value = item.override_id or item.ItemId
    if value == nil then return nil, "missing_cosmetic_identity" end
    return value, item.override_id ~= nil and "override_id" or "ItemId"
end

-- READONLY means vanilla gameplay data remains immutable. Pure cosmetics and exact CWV
-- instances are mod-owned values, however, and must live in the modded overlay instead of
-- being snapped back through a receiver-local equip/resync loop.
function P.readonly_action(slot_name, backend_id)
    if COSMETIC_SLOTS[slot_name] then return "preserve" end
    if WEAPON_SLOTS[slot_name] then
        return P.is_cwv_backend_id(backend_id) and "preserve" or "clear"
    end
    return "block"
end

local function copy_value(value, state, depth)
    if type(value) ~= "table" then return value end
    if depth >= MAX_SNAPSHOT_DEPTH then return nil, "depth-bound" end
    if state.seen[value] then return nil, "cycle" end
    state.nodes = state.nodes + 1
    if state.nodes > MAX_SNAPSHOT_NODES then return nil, "node-bound" end
    state.seen[value] = true
    local copy = {}
    for key, child in pairs(value) do
        state.nodes = state.nodes + 1
        if state.nodes > MAX_SNAPSHOT_NODES then
            state.seen[value] = nil
            return nil, "node-bound"
        end
        local child_copy, detail = copy_value(child, state, depth + 1)
        if detail then
            state.seen[value] = nil
            return nil, detail
        end
        copy[key] = child_copy
    end
    state.seen[value] = nil
    return copy
end

-- A bot designation is a point-in-time equipment choice, not an alias to the
-- player's mutable saved row. Keep the copy limited to the canonical loadout
-- slots so UI-only row metadata can never enter BackendInterfaceItemPlayfab's
-- bot cache.
function P.snapshot_bot_loadout(row, slot_names)
    if type(row) ~= "table" or type(slot_names) ~= "table" then return nil end
    local state = { nodes = 0, seen = {} }
    local snapshot = {}
    for i = 1, #slot_names do
        local slot_name = slot_names[i]
        local value, detail = copy_value(row[slot_name], state, 0)
        if detail then return nil, detail end
        snapshot[slot_name] = value
    end
    return snapshot
end

return P
