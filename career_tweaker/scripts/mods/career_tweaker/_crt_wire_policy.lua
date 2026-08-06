-- Pure wire-contract policy for Career Tweaker.
--
-- Issue #776 exposed two independent requirements that must stay coupled:
--   * a VMF presence acknowledgement is not proof that process-local
--     NetworkLookup.buff_templates integers mean the same thing on both peers;
--   * vanilla server-controlled buffs reject every sub-buff with duration
--     (BuffSystem._add_buff_helper_function, buff_system.lua:248-260).
--
-- This module owns no hooks or engine globals. Runtime adapters supply the live
-- registry/lookup tables, while offline tests exercise the same decisions.

local M = {}

M.TIMED_DURATION_SECONDS = 20
M.TIMED_MAX_STACKS = 1
M.TIMED_SYNC_TYPE = "LocalAndServer"

function M.make_timed_stat_buff(name, stat_buff, multiplier)
    assert(type(name) == "string" and name ~= "", "timed buff name required")
    assert(type(stat_buff) == "string" and stat_buff ~= "", "stat buff required")
    assert(type(multiplier) == "number", "timed buff multiplier required")
    return {
        stat_buff = stat_buff,
        multiplier = multiplier,
        duration = M.TIMED_DURATION_SECONDS,
        max_stacks = M.TIMED_MAX_STACKS,
        refresh_durations = true,
        name = name,
    }
end

-- Mirrors BuffExtension's max_stacks=1 + refresh_durations=true semantics: one
-- live stack whose deadline is replaced with now+duration on every reapply.
function M.refresh_timed_state(state, now)
    assert(type(now) == "number", "numeric time required")
    state = state or {}
    return {
        stack_count = M.TIMED_MAX_STACKS,
        start_time = now,
        end_time = now + M.TIMED_DURATION_SECONDS,
    }
end

function M.is_expired(state, now)
    return type(state) == "table" and type(state.end_time) == "number"
        and type(now) == "number" and state.end_time <= now
end

-- Returns the first forbidden timed sub-buff index, or nil when vanilla's
-- server-controlled contract is satisfied.
function M.server_controlled_duration_violation(template)
    local buffs = type(template) == "table" and template.buffs
    if type(buffs) ~= "table" then return nil end
    for i = 1, #buffs do
        local sub = buffs[i]
        if type(sub) == "table" and sub.duration ~= nil then
            return i, sub.duration
        end
    end
    return nil
end

-- Receiver-floor decision. CRT owns only ids that resolve locally to a name in
-- its registry; unrelated vanilla/mod names remain untouched.
function M.rpc_add_buff_decision(args)
    args = args or {}
    if args.resolves_to_crt ~= true then return "accept" end
    if args.peer_catalog_exact ~= true then return "drop_catalog_mismatch" end
    if type(args.server_buff_id) == "number" and args.server_buff_id > 0 then
        local index = M.server_controlled_duration_violation(args.template)
        if index then return "drop_server_controlled_duration", index end
    end
    return "accept"
end

-- Optional Mod Tweaker presentation bridge. Gameplay safety never depends on
-- GUT: this only describes which saved rows should be read-only/grey while the
-- owning exact parity gate is closed.
function M.runtime_gate_spec(mod_id, setting_ids, evaluate)
    if type(mod_id) ~= "string" or mod_id == ""
            or type(setting_ids) ~= "table" or type(evaluate) ~= "function" then
        return nil
    end
    local copied, seen = {}, {}
    for i = 1, #setting_ids do
        local setting_id = setting_ids[i]
        if type(setting_id) ~= "string" or setting_id == "" or seen[setting_id] then
            return nil
        end
        seen[setting_id] = true
        copied[#copied + 1] = setting_id
    end
    if #copied == 0 then return nil end
    return { mod_id = mod_id, setting_ids = copied, evaluate = evaluate }
end

function M.try_register_runtime_gate(get_mod_fn, gate_id, spec)
    if type(get_mod_fn) ~= "function" or type(gate_id) ~= "string"
            or gate_id == "" or type(spec) ~= "table" then
        return false, "runtime-gate-arguments-invalid"
    end
    for _, gut_id in ipairs({ "gut_dev", "gut" }) do
        local ok, gut = pcall(get_mod_fn, gut_id)
        local tweaker = ok and type(gut) == "table" and gut.mod_tweaker or nil
        if type(tweaker) == "table"
                and type(tweaker.register_runtime_gate) == "function" then
            return tweaker:register_runtime_gate(gate_id, spec)
        end
    end
    return false, "mod-tweaker-unavailable"
end

return M
