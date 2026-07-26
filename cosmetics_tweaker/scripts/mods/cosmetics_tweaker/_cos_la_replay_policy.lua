-- Engine-free readiness + bounded-edge REPLAY policy for persisted
-- Loremaster/offhand appearance state (#660 S3 slice; cold-join cluster
-- #233/#149/#203, pattern in #416/#476/#401).
--
-- Two concerns, both pure so the regression suite can pin the exact semantics:
--   1. inventory_ready  - player-unit existence is not enough; exact-item
--      state cannot be emitted until every equipped weapon slot has converged
--      on realized item_data.
--   2. the REPLAY RECONCILER - the coalescing state machine that decides WHEN
--      to re-drive the surviving persisted records at bounded lifecycle edges
--      (peer-ready / session-ready / lobby-return). It never touches the
--      engine: the caller injects the persisted stores and an apply function
--      and reuses the mod's proven emit/apply machinery for HOW.

local Policy = {}

-- SimpleInventoryExtension stores the active slot on its equipment table;
-- SimpleHuskInventoryExtension also exposes a legacy/direct mirror.  All
-- replay and pulse callers must prefer the common equipment-owned field so a
-- local wearer and a remote husk take the same transition-repair path.
function Policy.wielded_slot(inventory, equipment)
    equipment = equipment or (type(inventory) == "table"
        and (inventory._equipment or inventory.equipment) or nil)
    if type(equipment) == "table" and equipment.wielded_slot ~= nil then
        return equipment.wielded_slot
    end
    return type(inventory) == "table" and inventory.wielded_slot or nil
end

function Policy.inventory_ready(inventory)
    local equipment = type(inventory) == "table"
        and (inventory._equipment or inventory.equipment) or nil
    local slots = type(equipment) == "table" and equipment.slots or nil
    if type(slots) ~= "table" then return false end

    for _, slot_name in ipairs({ "slot_melee", "slot_ranged" }) do
        local slot = slots[slot_name]
        if type(slot) ~= "table" or type(slot.item_data) ~= "table"
            or slot.item_data.backend_id == nil
        then
            return false
        end
    end

    return true
end

-- An existing owner must republish its durable appearance snapshot when a
-- different peer appears. The joiner's pull can only replay records already
-- present on the host; it cannot reconstruct an owner's unpublished
-- outfit/offhand state. Keep the decision pure so local-player aliases and
-- transition re-adds have an explicit contract.
function Policy.should_publish_local_on_peer_ready(local_peer, added_peer)
    return local_peer ~= nil and added_peer ~= nil and local_peer ~= added_peer
end

-- A local snapshot is complete only after all three durable owners are ready:
-- the authored/LA bridge (semantic identity), the loadout cache (hat/outfit),
-- and the exact-item offhand restore. Consuming the one-shot publish flag
-- before any one of these is ready recreates #629's hat-only cold join.
function Policy.local_snapshot_ready(inventory, bridge_ready, loadout_ready,
        offhand_restore_ready, career_name)
    if bridge_ready ~= true then return false, "bridge" end
    if loadout_ready ~= true then return false, "loadout" end
    if offhand_restore_ready ~= true then return false, "offhand" end
    if type(career_name) ~= "string" or career_name == "" then
        return false, "career"
    end
    if not Policy.inventory_ready(inventory) then return false, "inventory" end
    return true, "ready"
end

-- Rehydrate the ephemeral unit-keyed cosmetic cache from the durable,
-- career-scoped loadout owner. Only identities proven by the current bridge
-- are returned. This does not read menu preview state and never guesses a
-- career or fallback.
function Policy.cached_cosmetic_records(loadout_cache, career_name,
        backend_to_armoury)
    local records = {}
    local slots = type(loadout_cache) == "table"
        and type(career_name) == "string"
        and loadout_cache[career_name] or nil
    if type(slots) ~= "table" or type(backend_to_armoury) ~= "table" then
        return records
    end
    for _, slot in ipairs({ "slot_hat", "slot_skin" }) do
        local item_name = slots[slot]
        local armoury_key = item_name and backend_to_armoury[item_name] or nil
        if type(armoury_key) == "string" and armoury_key ~= "" then
            records[#records + 1] = {
                slot = slot,
                kind = slot == "slot_hat" and "hat" or "armor",
                item_name = item_name,
                armoury_key = armoury_key,
            }
        end
    end
    return records
end

function Policy.replace_cosmetic_equips(equips_by_unit, unit, loadout_cache,
        career_name, backend_to_armoury)
    local records = Policy.cached_cosmetic_records(
        loadout_cache, career_name, backend_to_armoury)
    local previous = type(equips_by_unit) == "table" and equips_by_unit[unit] or nil
    local replacement = {}
    for slot, value in pairs(type(previous) == "table" and previous or {}) do
        if slot ~= "slot_hat" and slot ~= "slot_skin" then
            replacement[slot] = value
        end
    end
    for i = 1, #records do
        replacement[records[i].slot] = records[i].item_name
    end
    equips_by_unit[unit] = replacement
    return #records
end

-- Compatibility name retained for runtime checks and older callers. Its
-- semantics are now replacement, not additive rehydration.
Policy.rehydrate_cosmetic_equips = Policy.replace_cosmetic_equips

local function _equipment_slots(inventory)
    local equipment = type(inventory) == "table"
        and (inventory._equipment or inventory.equipment) or nil
    return type(equipment) == "table" and equipment.slots or nil
end

local function _offhand_matches(saved, live)
    if type(saved) ~= "table" or type(live) ~= "table" then return false end
    if type(saved.armoury_key) == "string" and saved.armoury_key ~= "" then
        return live.la_armoury_key == saved.armoury_key
            or live.armoury_key == saved.armoury_key
    end
    if type(saved.unit_path) == "string" and saved.unit_path ~= "" then
        return live.unit == saved.unit_path
            or live.unit_path == saved.unit_path
    end
    return false
end

-- Compose one complete, immutable replay plan from the three durable owners.
-- A saved shield hand is expected only when its exact backend item is equipped,
-- but every such record must already be present in the restored live selection.
-- This prevents the first realized weapon slot from consuming the edge while
-- the second slot's saved shield is still restoring.
function Policy.compose_local_snapshot(args)
    args = type(args) == "table" and args or {}
    local ready, reason = Policy.local_snapshot_ready(
        args.inventory, args.bridge_ready, args.loadout_ready,
        args.offhand_restore_ready, args.career_name)
    if not ready then return nil, reason end

    local slots = _equipment_slots(args.inventory)
    local snapshot = {
        unit = args.unit,
        career_name = args.career_name,
        cosmetics = Policy.cached_cosmetic_records(
            args.loadout_cache, args.career_name, args.backend_to_armoury),
        offhands = {},
        custom_slots = {},
    }

    for _, slot_name in ipairs({ "slot_melee", "slot_ranged" }) do
        local slot_data = slots[slot_name]
        local item_data = slot_data.item_data
        local backend_id = item_data.backend_id
        local saved_hands = type(args.saved_offhands) == "table"
            and args.saved_offhands[backend_id] or nil
        local live_hands = type(args.offhand_selection) == "table"
            and args.offhand_selection[backend_id] or nil

        for _, hand_field in ipairs({ "right_hand_unit", "left_hand_unit" }) do
            local saved = type(saved_hands) == "table"
                and saved_hands[hand_field] or nil
            if saved then
                local live = type(live_hands) == "table"
                    and live_hands[hand_field] or nil
                if not _offhand_matches(saved, live) then
                    return nil, "offhand-convergence"
                end
                local template_key = item_data.template or item_data.name
                    or slot_name
                if live.la_armoury_key or live.armoury_key then
                    snapshot.offhands[#snapshot.offhands + 1] = {
                        slot = template_key,
                        kind = "offhand",
                        armoury_key = live.la_armoury_key or live.armoury_key,
                        vanilla_key = live.vanilla_skin or live.vanilla_key,
                        hand_field = hand_field,
                    }
                elseif type(live.unit or live.unit_path) == "string"
                        and (live.unit or live.unit_path) ~= "" then
                    snapshot.offhands[#snapshot.offhands + 1] = {
                        slot = template_key,
                        kind = "offhand_mesh",
                        unit_path = live.unit or live.unit_path,
                        hand_field = hand_field,
                    }
                else
                    return nil, "offhand-convergence"
                end
            end
        end

        snapshot.custom_slots[#snapshot.custom_slots + 1] = {
            item_data = item_data,
            skin = slot_data.skin,
        }
    end

    return snapshot, "ready"
end

-- Execute the composed plan and report only positively acknowledged
-- queued/emitted operations. Callers clear the one-shot pending flag solely
-- when `complete` is true; a false/nil adapter result keeps the whole snapshot
-- eligible for retry (the transport's own dedup handles earlier successes).
function Policy.publish_local_snapshot(snapshot, adapters)
    local result = { expected = 0, accepted = 0, failed = 0, complete = false }
    if type(snapshot) ~= "table" or type(adapters) ~= "table" then
        result.failed = 1
        return result
    end

    local function attempt(fn, ...)
        result.expected = result.expected + 1
        local ok = type(fn) == "function" and fn(...) == true
        if ok then
            result.accepted = result.accepted + 1
        else
            result.failed = result.failed + 1
        end
    end

    for i = 1, #(snapshot.cosmetics or {}) do
        local rec = snapshot.cosmetics[i]
        attempt(adapters.send_la, snapshot.unit, rec.slot, rec.kind,
            rec.armoury_key, adapters.vanilla_fallback
                and adapters.vanilla_fallback(rec.item_name,
                    snapshot.career_name) or nil)
    end
    for i = 1, #(snapshot.offhands or {}) do
        local rec = snapshot.offhands[i]
        if rec.kind == "offhand_mesh" then
            attempt(adapters.send_mesh, snapshot.unit, rec.slot,
                rec.hand_field, rec.unit_path)
        else
            attempt(adapters.send_la, snapshot.unit, rec.slot, rec.kind,
                rec.armoury_key, rec.vanilla_key, rec.hand_field)
        end
    end
    for i = 1, #(snapshot.custom_slots or {}) do
        local rec = snapshot.custom_slots[i]
        attempt(adapters.send_custom, snapshot.unit, rec.item_data,
            rec.skin, "game_state_rebroadcast")
    end

    result.complete = result.failed == 0
    return result
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
