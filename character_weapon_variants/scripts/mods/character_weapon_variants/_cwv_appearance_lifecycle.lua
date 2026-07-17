-- Bounded exact-appearance identity and lifecycle replay ledger (#660).
--
-- Only compact semantic identity crosses VMF: provider, exact item key, selected
-- skin key, vanilla base key, and the locally-derived descriptor fingerprint.
-- Unit paths never cross the wire and no modded identifier enters a vanilla
-- NetworkLookup.  Receivers reconstruct from their own resident registries and
-- fail closed when the same descriptor cannot be proven locally.
local M = { SCHEMA = 2 }

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
    end

    return self
end

return M
