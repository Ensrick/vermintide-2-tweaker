-- Engine-free readiness + bounded-edge REPLAY policy for persisted
-- Loremaster/offhand appearance state (#660 S3 slice; cold-join cluster
-- #233/#149/#203, pattern in #416/#476/#401).
--
-- Two concerns, both pure so the regression suite can pin the exact semantics:
--   1. inventory_ready  - player-unit existence is not enough; exact-item
--      state cannot be emitted until at least one weapon slot has realized
--      item_data.
--   2. the REPLAY RECONCILER - the coalescing state machine that decides WHEN
--      to re-drive the surviving persisted records at bounded lifecycle edges
--      (peer-ready / session-ready / lobby-return). It never touches the
--      engine: the caller injects the persisted stores and an apply function
--      and reuses the mod's proven emit/apply machinery for HOW.

local Policy = {}

function Policy.inventory_ready(inventory)
    local equipment = type(inventory) == "table"
        and (inventory._equipment or inventory.equipment) or nil
    local slots = type(equipment) == "table" and equipment.slots or nil
    if type(slots) ~= "table" then return false end

    for _, slot_name in ipairs({ "slot_melee", "slot_ranged" }) do
        local slot = slots[slot_name]
        if type(slot) == "table" and type(slot.item_data) == "table" then
            return true
        end
    end

    return false
end

-- ---------------------------------------------------------------------------
-- Replay reconciler (pure)
-- ---------------------------------------------------------------------------

-- Generation token for a persisted record. Two records that render the SAME
-- appearance produce the same string; any field change (armoury key, vanilla
-- key, hand, mesh path) yields a new generation, so the next edge re-applies.
-- This is what "one apply per (peer, slot, generation)" coalesces on - it is
-- derived from the persisted record, never from live customization state.
function Policy.record_generation(record)
    if type(record) ~= "table" then return "none" end
    if record.offhand_unit ~= nil then
        return "mesh|" .. tostring(record.hand_field or "left_hand_unit")
            .. "|" .. tostring(record.offhand_unit)
    end
    return "la|" .. tostring(record.kind) .. "|" .. tostring(record.armoury_key)
        .. "|" .. tostring(record.vanilla_key)
        .. "|" .. tostring(record.hand_field or "left_hand_unit")
end

-- Coalescing key: exact per-hand target of one record. LA hat/armor entries
-- carry no hand_field (keyed "-"); offhand/illusion + vanilla mesh entries key
-- on their hand so a left + right pick on one slot stay independent.
local function _rec_key(peer, slot, record)
    local hand = type(record) == "table" and record.hand_field or nil
    return tostring(peer) .. "|" .. tostring(slot) .. "|" .. tostring(hand or "-")
end

-- Fresh coalescing state. `applied[key] = generation` last successfully
-- retained; `deferred[key] = true` when the last attempt could not apply yet.
function Policy.new_replay_state()
    return { applied = {}, deferred = {} }
end

-- Reset coalescing for one peer (a single joining peer's husk is new) so its
-- surviving records re-apply on the next edge.
function Policy.invalidate(state, peer)
    if type(state) ~= "table" then return end
    local prefix = tostring(peer) .. "|"
    for _, tbl in ipairs({ state.applied, state.deferred }) do
        if type(tbl) == "table" then
            for k in pairs(tbl) do
                if type(k) == "string" and k:sub(1, #prefix) == prefix then
                    tbl[k] = nil
                end
            end
        end
    end
end

-- Reset all coalescing (a husk-recreating transition destroys every remote
-- husk, so the freshly spawned ones must re-apply even at an unchanged
-- generation).
function Policy.invalidate_all(state)
    if type(state) ~= "table" then return end
    state.applied = {}
    state.deferred = {}
end

local function _normalize_status(status)
    if status == true or status == "applied" then return "applied" end
    if status == "skip" or status == "terminal" then return "skip" end
    return "defer" -- false / nil / "defer" / anything else -> retry next edge
end

-- Extract the replay record list from the persisted peer stores. This is the
-- source of truth the reconciler replays - the surviving synced stores, NOT
-- the live customization menu selection.
--   equips_by_peer  : _la_equips_by_peer[peer][slot] =
--       { kind, armoury_key, vanilla_key, hand_field, wearer_career }
--   offhand_by_peer : _offhand_mesh_by_peer[peer][slot][hand_field] = unit_path
--   opts.only_peer  : restrict to one peer (peer-ready edge for a joiner)
-- Returns an array of { peer, slot, kind, record }.
function Policy.build_records(equips_by_peer, offhand_by_peer, opts)
    opts = opts or {}
    local only_peer = opts.only_peer
    local out = {}
    if type(equips_by_peer) == "table" then
        for peer, slots in pairs(equips_by_peer) do
            if (only_peer == nil or peer == only_peer) and type(slots) == "table" then
                for slot, entry in pairs(slots) do
                    if type(entry) == "table" and entry.kind and entry.armoury_key then
                        out[#out + 1] = { peer = peer, slot = slot, kind = entry.kind, record = entry }
                    end
                end
            end
        end
    end
    if type(offhand_by_peer) == "table" then
        for peer, slots in pairs(offhand_by_peer) do
            if (only_peer == nil or peer == only_peer) and type(slots) == "table" then
                for slot, hands in pairs(slots) do
                    if type(hands) == "table" then
                        for hand_field, unit_path in pairs(hands) do
                            if type(unit_path) == "string" and unit_path ~= "" then
                                out[#out + 1] = {
                                    peer = peer, slot = slot, kind = "offhand_mesh",
                                    record = { offhand_unit = unit_path, hand_field = hand_field },
                                }
                            end
                        end
                    end
                end
            end
        end
    end
    return out
end

-- Reconcile one bounded edge. `records` is the Policy.build_records output;
-- `apply(peer, slot, record)` reuses the caller's emit/apply machinery and
-- returns a status:
--   "applied" / true  -> engine re-drove a ready wearer; mark this generation
--   "defer"   / false -> wearer/husk not ready; retry on the NEXT edge (never
--                        per-frame - only edges call this)
--   "skip"            -> terminal (store entry gone / suppressed); never retry
-- Coalesces on (peer, slot, hand -> generation): a generation already applied
-- is not re-applied, so a per-frame re-fire of the same edge does no work.
-- Returns { per_peer = { [peer] = applied_count }, applied, deferred,
-- coalesced, skipped } for a bounded diagnostic (per_peer includes every peer
-- that had a record considered).
function Policy.reconcile_edge(state, edge, records, apply)
    local result = {
        edge = edge, per_peer = {},
        applied = 0, deferred = 0, coalesced = 0, skipped = 0,
    }
    if type(state) ~= "table" then return result end
    state.applied = state.applied or {}
    state.deferred = state.deferred or {}
    if type(records) ~= "table" then return result end

    for i = 1, #records do
        local rec = records[i]
        if type(rec) == "table" and rec.peer ~= nil and rec.slot ~= nil then
            local peer = rec.peer
            result.per_peer[peer] = result.per_peer[peer] or 0
            local key = _rec_key(peer, rec.slot, rec.record)
            local gen = Policy.record_generation(rec.record)
            if state.applied[key] == gen and not state.deferred[key] then
                result.coalesced = result.coalesced + 1
            else
                local status = _normalize_status(apply and apply(peer, rec.slot, rec.record))
                if status == "applied" then
                    state.applied[key] = gen
                    state.deferred[key] = nil
                    result.per_peer[peer] = result.per_peer[peer] + 1
                    result.applied = result.applied + 1
                elseif status == "skip" then
                    state.applied[key] = gen
                    state.deferred[key] = nil
                    result.skipped = result.skipped + 1
                else
                    state.deferred[key] = true
                    result.deferred = result.deferred + 1
                end
            end
        end
    end

    return result
end

return Policy
