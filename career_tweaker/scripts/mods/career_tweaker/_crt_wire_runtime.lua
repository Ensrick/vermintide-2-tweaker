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
