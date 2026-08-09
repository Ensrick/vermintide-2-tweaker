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
M.RUNTIME_GATE_MAX_ATTEMPTS = 30

local function _positive_integer(value)
    return type(value) == "number" and value > 0 and math.floor(value) == value
end

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

-- Live re-verification of the boot-time exact catalog. build_identity proves the
-- name<->id mapping ONCE, at load; any later writer (a mod registering buffs
-- after crt, a lookup table rebuilt across a level transition) can silently move
-- an id out from under the identity crt already broadcast. Re-checking both
-- directions per read is the floor that keeps the advertised identity honest.
-- `ids` is the boot-time snapshot; `expected_count` is passed explicitly because
-- `#` on a table with a nil hole is undefined in Lua.
function M.catalog_intact(names, ids, lookup, expected_count)
    if type(names) ~= "table" or type(ids) ~= "table" or type(lookup) ~= "table" then
        return false
    end
    if not _positive_integer(expected_count) or #names ~= expected_count then
        return false
    end
    for i = 1, expected_count do
        local name, id = names[i], ids[i]
        if type(name) ~= "string" or name == "" or not _positive_integer(id)
                or rawget(lookup, name) ~= id or rawget(lookup, id) ~= name then
            return false
        end
    end
    return true
end

-- The part of the floor that is independent of the peer set. Both conjuncts are
-- necessary: a beacon object that never committed its transport cannot have
-- proven anything about any peer, and an identity built over a catalog that has
-- since shifted is proof of nothing. Reads are contained because a throwing
-- accessor must fail closed rather than escape into a gameplay path.
function M.wire_floor(parity, catalog_intact)
    if type(parity) ~= "table" or type(catalog_intact) ~= "function"
            or type(parity.is_installed) ~= "function" then
        return false
    end
    local ok_installed, installed = pcall(parity.is_installed, parity)
    if not ok_installed or installed ~= true then return false end
    local ok_catalog, intact = pcall(catalog_intact)
    return ok_catalog and intact == true
end

-- SETTLED composite: the floor plus the beacon's debounced applied state. This
-- is the authority for anything that churns talent tables or presentation --
-- apply/restore engines, the tourney port, the receiver floor, the GUT grey-out
-- -- because those must not flicker on an ack race.
function M.wire_safe(parity, catalog_intact)
    if not M.wire_floor(parity, catalog_intact) then return false end
    if type(parity.applied_state) ~= "function" then return false end
    local ok_state, state = pcall(parity.applied_state, parity)
    return ok_state and state == "enabled"
end

-- LIVE composite: the floor plus an instant roster evaluation. Deliberately NOT
-- expressed as wire_safe(): applied_state() is refreshed by a 0.5s poll, while
-- all_peers_have() re-evaluates the roster on every call. Routing a per-send
-- guard through the settled read would leave up to one poll interval in which
-- crt still emits modded buff names at a peer that just joined without crt --
-- the issue-425 CTD. Every individual send consults THIS; nothing else does.
function M.wire_live(parity, catalog_intact)
    if not M.wire_floor(parity, catalog_intact) then return false end
    if type(parity.all_peers_have) ~= "function" then return false end
    local ok_peers, present = pcall(parity.all_peers_have, parity)
    return ok_peers and present == true
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
            local ok_register, registered = pcall(
                tweaker.register_runtime_gate, tweaker, gate_id, spec)
            if ok_register and registered == true then return true end
            -- A malformed optional GUI owner must not escape into this mod's
            -- load/update path. Fall through to the stable alias.
        end
    end
    return false, "mod-tweaker-unavailable"
end

-- One independently testable bounded registration attempt. Both spec creation
-- and the optional GUI call are contained because neither is gameplay
-- authority. The caller owns elapsed-time scheduling; this helper owns the
-- terminal-at-MAX_ATTEMPTS contract so a missing or malformed GUT cannot leave
-- crt polling get_mod() for the rest of the session.
function M.runtime_gate_retry_step(state, make_spec, register)
    state = type(state) == "table" and state or {}
    state.registered = state.registered == true
    state.terminal = state.terminal == true
    if state.registered or state.terminal then return state end
    state.attempts = (tonumber(state.attempts) or 0) + 1

    local ok_spec, spec = pcall(make_spec)
    local registered = false
    if ok_spec and type(spec) == "table" and type(register) == "function" then
        local ok_register, result = pcall(register, spec)
        registered = ok_register and result == true
    end
    state.registered = registered
    if registered or state.attempts >= M.RUNTIME_GATE_MAX_ATTEMPTS then
        state.terminal = true
    end
    return state
end

return M
