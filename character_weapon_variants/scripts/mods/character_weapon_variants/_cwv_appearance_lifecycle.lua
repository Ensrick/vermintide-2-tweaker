-- Bounded exact-appearance identity and lifecycle replay ledger (#660).
--
-- Only compact semantic identity crosses VMF: provider, exact item key, selected
-- skin key, vanilla base key, and the locally-derived descriptor fingerprint.
-- Unit paths never cross the wire and no modded identifier enters a vanilla
-- NetworkLookup.  Receivers reconstruct from their own resident registries and
-- fail closed when the same descriptor cannot be proven locally.
local M = {
    SCHEMA = 2,
    ACK_SLOT = "cwv_identity_ack",
    REQUEST_SLOT = "cwv_identity_request",
    RETRY_INTERVAL = 0.5,
    MAX_RETRY_ATTEMPTS = 8,
    MAX_REQUEST_GENERATION = 2147483647,
}

local SLOT_ORDER = { "slot_melee", "slot_ranged" }

local function nonempty(value)
    return type(value) == "string" and value ~= "" and value or nil
end

local function valid_slot(slot)
    return slot == "slot_melee" or slot == "slot_ranged"
end

local function state_signature(state)
    if type(state) ~= "table" then return "none" end
    if state.kind == "exact" and state.descriptor then
        return "exact|" .. tostring(state.descriptor.fingerprint)
    end
    return tostring(state.kind) .. "|" .. tostring(state.base_item_key)
        .. "|" .. tostring(state.reason)
end

function M.new(opts)
    opts = opts or {}
    local self = {
        _sent = {},
        _remote = {},
        _deliveries = {},
        _accepted_requests = {},
        _request_delivery = nil,
    }

    function self:payload_for(slot_name, slot_data)
        if not valid_slot(slot_name) then return nil, "slot" end
        local descriptor, base_item_key = opts.resolve_local(slot_data, slot_name)
        base_item_key = nonempty(base_item_key)
            or (descriptor and nonempty(descriptor.base_item_key))
        if descriptor then
            if not nonempty(descriptor.variant_key)
                    or not nonempty(descriptor.fingerprint)
                    or not base_item_key then
                return nil, "descriptor"
            end
            return {
                slot = slot_name,
                provider = nonempty(descriptor.provider) or "cwv",
                item_key = descriptor.variant_key,
                base_item_key = base_item_key,
                skin_key = nonempty(descriptor.skin) or "",
                fingerprint = descriptor.fingerprint,
            }
        end
        -- An explicit native record is not the same as missing evidence. It
        -- prevents a remote base+career heuristic from re-keying a vanilla item.
        return {
            slot = slot_name,
            provider = "",
            item_key = "",
            base_item_key = base_item_key or "",
            skin_key = "",
            fingerprint = "",
        }
    end

    function self:publish(slots, edge, recipient, force)
        if type(slots) ~= "table" then return 0 end
        recipient = recipient or "others"
        local sent = 0
        for _, slot_name in ipairs(SLOT_ORDER) do
            local payload = self:payload_for(slot_name, slots[slot_name])
            if payload then
                local signature = table.concat({
                    payload.provider, payload.item_key, payload.base_item_key,
                    payload.skin_key, payload.fingerprint,
                }, "|")
                local route = tostring(recipient) .. "|" .. slot_name
                if force or self._sent[route] ~= signature then
                    local ok = opts.send(recipient, M.SCHEMA, payload, edge)
                    if ok then
                        self._sent[route] = signature
                        sent = sent + 1
                    end
                end
            end
        end
        return sent
    end

    -- GearUtils.hot_join_sync runs before the joining peer's VMF mod channel is
    -- necessarily ready. A successful local network_send therefore proves only
    -- that the sender accepted the message, not that the receiver handled it.
    -- Retain only exact CWV identities for a short, attempt-bounded retry window;
    -- native fallback records already travel safely on the vanilla equipment
    -- wire and do not need a delivery protocol.
    function self:track_delivery(recipient, slots, edge)
        if not nonempty(recipient) or type(slots) ~= "table" then return 0 end
        local tracked = 0
        for _, slot_name in ipairs(SLOT_ORDER) do
            local payload = self:payload_for(slot_name, slots[slot_name])
            if payload and nonempty(payload.item_key)
                    and nonempty(payload.fingerprint) then
                local route = recipient .. "|" .. slot_name
                self._deliveries[route] = {
                    recipient = recipient,
                    slot = slot_name,
                    fingerprint = payload.fingerprint,
                    payload = payload,
                    edge = edge or "hot_join_retry",
                    elapsed = 0,
                    attempts = 0,
                }
                tracked = tracked + 1
            end
        end
        return tracked
    end

    -- A mission transition can initialize the owner's inventory before another
    -- peer's VMF channel is ready.  The newly ready peer therefore asks every
    -- same-mod peer for its current two-slot semantic identity.  Both the
    -- request and each exact reply are attempt-bounded; duplicate requests are
    -- accepted once per sender generation, so retries cannot multiply replies.
    function self:begin_request(generation, edge)
        if type(generation) ~= "number" or generation < 1
                or generation ~= math.floor(generation) then
            return false
        end
        local payload = {
            slot = M.REQUEST_SLOT,
            generation = generation,
        }
        self._request_delivery = {
            generation = generation,
            payload = payload,
            edge = edge or "peer_ready_request",
            elapsed = 0,
            attempts = 1,
        }
        return opts.send("others", M.SCHEMA, payload,
            self._request_delivery.edge) == true
    end

    function self:step_request(dt)
        local pending = self._request_delivery
        if not pending then return 0, 0 end
        dt = type(dt) == "number" and math.max(dt, 0) or 0
        pending.elapsed = pending.elapsed + dt
        if pending.elapsed < M.RETRY_INTERVAL then return 0, 0 end
        if pending.attempts >= M.MAX_RETRY_ATTEMPTS then
            self._request_delivery = nil
            return 0, 1
        end
        pending.elapsed = 0
        pending.attempts = pending.attempts + 1
        local ok = opts.send("others", M.SCHEMA, pending.payload, pending.edge)
        return ok and 1 or 0, 0
    end

    function self:accept_request(peer_id, schema, payload)
        if schema ~= M.SCHEMA or not nonempty(peer_id)
                or type(payload) ~= "table" or payload.slot ~= M.REQUEST_SLOT
                or type(payload.generation) ~= "number"
                or payload.generation < 1
                or payload.generation > M.MAX_REQUEST_GENERATION
                or payload.generation ~= math.floor(payload.generation) then
            return false
        end
        if self._accepted_requests[peer_id] == payload.generation then
            return false
        end
        self._accepted_requests[peer_id] = payload.generation
        return true
    end

    function self:ack_payload(payload)
        if type(payload) ~= "table" or not valid_slot(payload.slot)
                or not nonempty(payload.item_key)
                or not nonempty(payload.fingerprint) then
            return nil
        end
        return {
            slot = M.ACK_SLOT,
            ack_slot = payload.slot,
            fingerprint = payload.fingerprint,
        }
    end

    function self:accept_ack(peer_id, schema, payload)
        if schema ~= M.SCHEMA or not nonempty(peer_id)
                or type(payload) ~= "table" or payload.slot ~= M.ACK_SLOT
                or not valid_slot(payload.ack_slot)
                or not nonempty(payload.fingerprint) then
            return false
        end
        local route = peer_id .. "|" .. payload.ack_slot
        local pending = self._deliveries[route]
        if not pending or pending.fingerprint ~= payload.fingerprint then
            return false
        end
        self._deliveries[route] = nil
        return true
    end

    function self:step_deliveries(dt)
        local sent, expired = 0, 0
        dt = type(dt) == "number" and math.max(dt, 0) or 0
        for route, pending in pairs(self._deliveries) do
            pending.elapsed = pending.elapsed + dt
            if pending.attempts >= M.MAX_RETRY_ATTEMPTS then
                self._deliveries[route] = nil
                expired = expired + 1
            elseif pending.elapsed >= M.RETRY_INTERVAL then
                -- Do not catch up with a burst after a long frame hitch. One
                -- update can emit at most one retry per pending slot.
                pending.elapsed = 0
                pending.attempts = pending.attempts + 1
                local ok = opts.send(pending.recipient, M.SCHEMA,
                    pending.payload, pending.edge)
                if ok then sent = sent + 1 end
            end
        end
        return sent, expired
    end

    function self:pending_delivery_count()
        local count = 0
        for _ in pairs(self._deliveries) do count = count + 1 end
        return count
    end

    function self:accept(peer_id, schema, payload)
        if not nonempty(peer_id) or type(payload) ~= "table"
                or not valid_slot(payload.slot) then
            return false, nil, "invalid"
        end
        local by_slot = self._remote[peer_id]
        if not by_slot then
            by_slot = {}
            self._remote[peer_id] = by_slot
        end
        local previous = by_slot[payload.slot]
        local next_state
        if schema ~= M.SCHEMA then
            next_state = {
                kind = "unavailable",
                base_item_key = nonempty(payload.base_item_key),
                reason = "schema_mismatch",
            }
        elseif payload.item_key == "" then
            next_state = {
                kind = "native",
                base_item_key = nonempty(payload.base_item_key),
                reason = "explicit_native",
            }
        else
            local descriptor, reason = opts.resolve_remote(payload, peer_id)
            if descriptor and descriptor.fingerprint == payload.fingerprint
                    and descriptor.variant_key == payload.item_key
                    and descriptor.base_item_key == payload.base_item_key
                    and (descriptor.provider or "cwv") == payload.provider
                    and (descriptor.skin or "") == payload.skin_key then
                next_state = {
                    kind = "exact",
                    base_item_key = descriptor.base_item_key,
                    descriptor = descriptor,
                    reason = "exact",
                }
            else
                -- Retain a negative state instead of stale exact identity. This
                -- is the fail-closed result for missing provider/skin/resources.
                next_state = {
                    kind = "unavailable",
                    base_item_key = nonempty(payload.base_item_key),
                    reason = reason or "fingerprint_mismatch",
                }
            end
        end
        by_slot[payload.slot] = next_state
        return state_signature(previous) ~= state_signature(next_state),
            next_state.kind == "exact" and next_state.descriptor or nil,
            next_state.reason
    end

    function self:descriptor(peer_id, slot_name, base_item_key)
        local by_slot = nonempty(peer_id) and self._remote[peer_id]
        local state = by_slot and by_slot[slot_name]
        if not state then return nil, "none" end
        if nonempty(base_item_key) and nonempty(state.base_item_key)
                and state.base_item_key ~= base_item_key then
            return nil, "stale_base"
        end
        if state.kind == "exact" then return state.descriptor, "exact" end
        return nil, state.kind or "unavailable"
    end

    function self:clear_peer(peer_id)
        self._remote[peer_id] = nil
        self._accepted_requests[peer_id] = nil
        if nonempty(peer_id) then
            local prefix = peer_id .. "|"
            for route in pairs(self._deliveries) do
                if route:sub(1, #prefix) == prefix then
                    self._deliveries[route] = nil
                end
            end
        end
    end

    return self
end

return M
