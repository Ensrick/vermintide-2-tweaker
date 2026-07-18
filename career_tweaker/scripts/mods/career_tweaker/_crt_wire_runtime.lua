-- Runtime adapter for Career Tweaker's issue-776 timed-buff wire contract.
-- Pure policy lives in `_crt_wire_policy.lua`; this module is the only owner of
-- the engine-facing `BuffSystem:add_buff_synced` call.

local M = {}
local logged = {}

local function log_once(key, fmt, ...)
    if logged[key] then return end
    logged[key] = true
    pcall(printf, "[crt:776] " .. fmt, ...)
end

-- Adapt the established issue-425 presence beacon without changing the copied
-- shared library (and therefore without forcing unrelated mods to rebuild).
-- The proxy appends this process's exact catalog identity to every beacon and
-- only forwards an incoming acknowledgement to the presence library when the
-- remote identity is byte-for-byte equal. A later mismatch revokes an earlier
-- acknowledgement synchronously through the library's public API.
function M.wrap_parity_transport(mod, identity)
    if type(mod) ~= "table" or type(identity) ~= "string" or identity == "" then
        return nil, "mod-or-identity-invalid"
    end

    local parity_instance = nil
    local rejected = {}
    local mismatch_logged = {}
    local proxy = {}

    local function revoke(peer_id)
        if not parity_instance or type(peer_id) ~= "string" then return end
        pcall(parity_instance.forget_peer, parity_instance, peer_id)
        pcall(parity_instance.require_peer, parity_instance, peer_id)
    end

    function proxy:network_send(channel, recipient, schema, is_reply)
        return mod:network_send(channel, recipient, schema, is_reply, identity)
    end

    function proxy:network_register(channel, receiver)
        return mod:network_register(channel,
            function(sender_peer_id, schema, is_reply, remote_identity)
                if remote_identity ~= identity then
                    if type(sender_peer_id) == "string" and not rejected[sender_peer_id] then
                        rejected[sender_peer_id] = true
                        revoke(sender_peer_id)
                    end
                    if not mismatch_logged[sender_peer_id] then
                        mismatch_logged[sender_peer_id] = true
                        log_once("catalog-mismatch:" .. tostring(sender_peer_id),
                            "wire catalog mismatch sender=%s got=%s want=%s; parity revoked",
                            tostring(sender_peer_id), tostring(remote_identity), identity)
                    end
                    return
                end
                rejected[sender_peer_id] = nil
                return receiver(sender_peer_id, schema, is_reply)
            end)
    end

    function proxy:_bind_parity_instance(instance)
        parity_instance = instance
        for peer_id in pairs(rejected) do revoke(peer_id) end
    end

    function proxy:debug(...) return mod:debug(...) end
    function proxy:echo(...) return mod:echo(...) end
    function proxy:localize(...) return mod:localize(...) end

    setmetatable(proxy, {
        __index = mod,
        __newindex = function(_, key, value) mod[key] = value end,
    })
    return proxy
end

function M.ensure_timed_proc(PF, policy, parity_live, log_block, log_clear)
    if type(PF) ~= "table" or PF.crt_wire_safe_add_timed_buff ~= nil then return end
    PF.crt_wire_safe_add_timed_buff = function(unit, buff, params)
        if not parity_live() then
            log_block("add_timed_buff")
            return
        end
        local alive = rawget(_G, "ALIVE")
        local template = buff and buff.template
        local buff_name = template and template.buff_to_add
        local sync_types = rawget(_G, "BuffSyncType")
        local sync_type = sync_types and policy
            and sync_types[policy.TIMED_SYNC_TYPE]
        local managers = rawget(_G, "Managers")
        local entity = managers and managers.state and managers.state.entity
        local buff_system = entity and entity.system and entity:system("buff_system")
        if not (alive and alive[unit] and type(buff_name) == "string"
                and buff_system and type(buff_system.add_buff_synced) == "function"
                and sync_type ~= nil) then
            log_once("dependency-block",
                "timed sync blocked: dependency/target unavailable (fail-closed; no rpc_add_buff fallback)")
            return
        end
        log_clear()
        log_once("route:" .. buff_name,
            "timed sync route=%s sync=%s duration=%ss max_stacks=%s refresh=true",
            buff_name, policy.TIMED_SYNC_TYPE,
            tostring(policy.TIMED_DURATION_SECONDS),
            tostring(policy.TIMED_MAX_STACKS))
        return buff_system:add_buff_synced(unit, buff_name, sync_type)
    end
end

return M
