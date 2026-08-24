-- Exact-instance offhand commit policy (#702).
--
-- Persistence is authoritative and must not depend on a live render owner.
-- Peer delivery is best-effort: when the owner unit is unavailable the caller's
-- existing bounded self-rebroadcast path converges after equipment exists.
local M = {}

local function _commit_entry(persistence, entry)
    if persistence and type(persistence.commit_offhand_entry) == "function" then
        return persistence.commit_offhand_entry(entry)
    end
    return false, "persistence-unavailable"
end

-- Apply completion is the durable transaction boundary. Do not defer the
-- first persistence write to screen exit: the process can terminate or
-- another mod can rebuild the view after Apply succeeds. This path is exact
-- backend-item only and intentionally performs no peer delivery or re-wield;
-- drain() retains ownership of those bounded exit-time effects.
function M.commit_for_backend(pending, persistence, backend_id)
    if type(backend_id) ~= "string" or backend_id == "" then return 0 end

    local committed_count = 0
    for _, entry in pairs(pending or {}) do
        if type(entry) == "table" and entry.backend_id == backend_id then
            local committed, action = _commit_entry(persistence, entry)
            if committed then committed_count = committed_count + 1 end
            if printf then
                printf("[cos:702] OFFHAND-APPLY-COMMIT bid=%s hand=%s action=%s persisted=%s",
                    tostring(entry.backend_id), tostring(entry.hand_field),
                    tostring(action), tostring(committed))
            end
        end
    end
    return committed_count
end

local function _emit_for_key(send, entry, key, kind)
    if not key then return end
    if kind == "mesh" then
        send(entry.player_unit, key, entry.hand_field, entry.offhand_unit)
    elseif kind == "revert" then
        send(entry.player_unit, key, "offhand", entry.vanilla_key, entry.hand_field)
    else
        send(entry.player_unit, key, "offhand", entry.armoury_key,
            entry.vanilla_key, entry.hand_field)
    end
end

local function _emit_peer(mod, entry, send_apply, owner_alive)
    if not owner_alive then return false end
    local kind, send
    if entry.offhand_unit ~= nil then
        kind, send = "mesh", mod._send_offhand_mesh
    elseif entry.revert then
        kind, send = "revert", mod._send_la_revert
    else
        kind, send = "apply", send_apply
    end
    if type(send) ~= "function" then return false end

    mod:info("[cos-la-sync] EMIT-%s-ON-EXIT weapon=%s template=%s hand=%s",
        string.upper(kind), tostring(entry.weapon_key),
        tostring(entry.template_key), tostring(entry.hand_field))
    _emit_for_key(send, entry, entry.weapon_key, kind)
    if entry.template_key and entry.template_key ~= entry.weapon_key then
        _emit_for_key(send, entry, entry.template_key, kind)
    end
    return true
end

function M.drain(mod, pending, persistence, send_apply, is_alive)
    local committed_count = 0
    is_alive = is_alive or function(unit)
        return unit ~= nil and Unit and Unit.alive(unit)
    end

    for _, entry in pairs(pending or {}) do
        if entry then
            local committed, action = _commit_entry(persistence, entry)
            local emitted = _emit_peer(mod, entry, send_apply,
                entry.player_unit and is_alive(entry.player_unit))
            if committed then committed_count = committed_count + 1 end
            if committed and not emitted then
                mod._la_self_rebroadcast_pending = true
            end
            if printf then
                printf("[cos:702] OFFHAND-COMMIT bid=%s hand=%s action=%s persisted=%s peer_emit=%s",
                    tostring(entry.backend_id), tostring(entry.hand_field),
                    tostring(action), tostring(committed),
                    emitted and "sent" or "deferred")
            end
        end
    end
    return committed_count
end

return M
