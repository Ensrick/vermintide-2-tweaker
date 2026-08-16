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

-- Issue #273 (capture side). The outer BackendUtils.set_loadout_item hook feeds the
-- DURABLE Adventure store, but vanilla routes Deus weapon chest/shrine swaps through the
-- same 3-arg seam with a RUN-LOCAL backend id (deus_chest_extension.lua:597). Gear slots
-- are therefore capture-eligible only while the durable items interface owns the slot
-- RIGHT NOW -- `owned_by_items` is the caller-resolved true-table-identity ownership
-- verdict (_gut_exit_snapshot_core.lua slot_owned_by_items semantics) and anything but
-- `true` fails closed. Cosmetic slots stay unconditionally eligible: the Deus override
-- maps skin/hat/frame/pose to "items" (backend_interface_deus_base.lua:7-14), so
-- cosmetics legitimately persist through a CW run.
function P.capture_slot_durable(slot_name, owned_by_items)
    if COSMETIC_SLOTS[slot_name] then return true end
    return owned_by_items == true
end

-- Issue #375 audit fix (2026-08-15): vanilla marks exactly slot_necklace / slot_ring /
-- slot_trinket_1 `unequippable = true` (inventory_settings.lua:43/52/61), so an EMPTY
-- accessory slot in an otherwise-complete row is a legitimate player choice that is
-- indistinguishable from data loss. The integrity/repair passes therefore NEVER refill
-- these slots in place: deliberate unequips survive every seed/repair pass, and
-- accessory values enter the store only when a FULL row is copied fresh from official
-- (missing-row add, fresh seed, or the #1033 DEFAULT reseed).
P.UNEQUIPPABLE_SLOTS = {
    slot_necklace = true, slot_ring = true, slot_trinket_1 = true,
}

function P.is_unequippable_slot(slot_name)
    return P.UNEQUIPPABLE_SLOTS[slot_name] == true
end

-- A store row is corrupt-partial when a slot vanilla can NEVER leave empty is missing:
-- weapons fatal at spawn wield, and skin/hat/frame/pose always resolve to some item.
-- A row missing only unequippable accessories is HEALTHY (deliberate unequip).
function P.row_is_corrupt_partial(row, slot_names)
    if type(row) ~= "table" or type(slot_names) ~= "table" then return true end
    for i = 1, #slot_names do
        local slot = slot_names[i]
        if not P.UNEQUIPPABLE_SLOTS[slot] and row[slot] == nil then return true end
    end
    return false
end

-- One-time slot migration (#402): add the official value for any canonical slot an
-- existing row never carried -- EXCEPT unequippable accessories (deliberate-empty).
function P.repair_missing_loadout_slots(entry, official_rows, slot_names)
    if type(entry) ~= "table" or type(entry.loadouts) ~= "table"
        or type(official_rows) ~= "table" or type(slot_names) ~= "table" then
        return 0
    end
    local repaired = 0
    for i = 1, #official_rows do
        local off_row = official_rows[i]
        local st_row = entry.loadouts[i]
        if type(off_row) == "table" and type(st_row) == "table" then
            for s = 1, #slot_names do
                local slot = slot_names[s]
                if not P.UNEQUIPPABLE_SLOTS[slot]
                    and st_row[slot] == nil and off_row[slot] ~= nil then
                    st_row[slot] = off_row[slot]
                    repaired = repaired + 1
                end
            end
        end
    end
    return repaired
end

-- Corrupt-row refill (#375): copy every missing official key (slots, talents) into a
-- row that carries the corruption signature -- EXCEPT unequippable accessory slots,
-- which stay exactly as the player left them.
function P.repair_corrupt_row(st_row, off_row)
    if type(st_row) ~= "table" or type(off_row) ~= "table" then return 0 end
    local filled = 0
    for k, v in pairs(off_row) do
        if st_row[k] == nil and not P.UNEQUIPPABLE_SLOTS[k] then
            st_row[k] = v
            filled = filled + 1
        end
    end
    return filled
end

-- Issue #1033 x #954 reset boundary. A confirmed Equipment DEFAULT must wipe MODDED
-- LOADOUT DATA: the saved loadout rows, the loadout selection, the seed/integrity
-- markers (forcing a fresh official reseed), and the cosmetic overlay. The user's BOT
-- DESIGNATION is NOT modded loadout data: `bot_index`, the detached `bot_loadout`
-- snapshot, and the one-time native-import marker `_bot_designation_snapshot_v2`
-- record an explicit user choice, and dropping the marker would let the next bot read
-- re-import the native PlayerData index -- silently replacing the designated bot
-- equipment the #954 marker exists to make durable. Preserve exactly that designation
-- set across the clear; a career without any designation field is removed outright.
local DESIGNATION_FIELDS = {
    "bot_index", "bot_loadout", "_bot_designation_snapshot_v2",
}

-- Returns nil (drop the row) or a bare re-seedable shell carrying only the preserved
-- designation fields. The shell uses the standard fallback-entry shape
-- (selected_index = 1, empty loadouts) so the reseed/repair path can fill it.
local function preserve_designation(row)
    if type(row) ~= "table" then return nil end
    local kept = nil
    for i = 1, #DESIGNATION_FIELDS do
        local field = DESIGNATION_FIELDS[i]
        if row[field] ~= nil then
            kept = kept or { selected_index = 1, loadouts = {} }
            kept[field] = row[field]
        end
    end
    return kept
end

-- Issue #1033: clear only mod-owned snapshots. Both tables retain identity so
-- the hot mirror hooks keep observing the same working copies. Returns the
-- number of distinct careers cleared plus whether an explicit career existed.
function P.clear_modded_loadouts(store, overlay, career_name)
    if type(store) ~= "table" or type(overlay) ~= "table" then return 0, false end
    if type(career_name) == "string" and career_name ~= "" then
        local existed = store[career_name] ~= nil or overlay[career_name] ~= nil
        store[career_name] = preserve_designation(store[career_name])
        overlay[career_name] = nil
        return existed and 1 or 0, existed
    end
    local seen = {}
    for name in pairs(store) do seen[name] = true end
    for name in pairs(overlay) do seen[name] = true end
    local count = 0
    for name in pairs(seen) do
        store[name] = preserve_designation(store[name])
        overlay[name] = nil
        count = count + 1
    end
    return count, true
end

-- Deterministic list of official Adventure careers eligible for immediate
-- re-seeding. Reading this shape cannot invoke a backend/interface method.
function P.official_seed_careers(mirror, career_name)
    local rows = type(mirror) == "table" and mirror._career_data or nil
    if type(rows) ~= "table" then return {} end
    if type(career_name) == "string" and career_name ~= "" then
        return type(rows[career_name]) == "table" and { career_name } or {}
    end
    local names = {}
    for name, career_rows in pairs(rows) do
        if type(name) == "string" and type(career_rows) == "table" then
            names[#names + 1] = name
        end
    end
    table.sort(names)
    return names
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
