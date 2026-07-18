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

M.WIRE_IDENTITY_VERSION = 2
M.TIMED_DURATION_SECONDS = 20
M.TIMED_MAX_STACKS = 1
M.TIMED_SYNC_TYPE = "LocalAndServer"

local function _positive_integer(value)
    return type(value) == "number" and value > 0 and math.floor(value) == value
end

local function _feed_hash(seed, multiplier, modulus, text)
    local value = seed
    for i = 1, #text do
        -- Products remain far below Lua's exact-integer limit (2^53).
        value = (value * multiplier + string.byte(text, i)) % modulus
    end
    return value
end

-- Returns a compact fingerprint whose canonical input contains every registered
-- CRT wire name and its actual process-local numeric lookup id. A missing or
-- malformed mapping fails closed instead of manufacturing partial identity.
function M.build_wire_identity(registry, lookup)
    if type(registry) ~= "table" or type(lookup) ~= "table" then
        return nil, "registry-or-lookup-missing"
    end

    local names = {}
    for name, present in pairs(registry) do
        if present == true then
            if type(name) ~= "string" or name == "" then
                return nil, "invalid-registry-name"
            end
            names[#names + 1] = name
        end
    end
    table.sort(names)
    if #names == 0 then return nil, "registry-empty" end

    local canonical = { "crt-wire-v", tostring(M.WIRE_IDENTITY_VERSION), "\n" }
    for i = 1, #names do
        local name = names[i]
        local id = rawget(lookup, name)
        if not _positive_integer(id) or rawget(lookup, id) ~= name then
            return nil, "lookup-mismatch:" .. name
        end
        canonical[#canonical + 1] = name
        canonical[#canonical + 1] = "="
        canonical[#canonical + 1] = tostring(id)
        canonical[#canonical + 1] = "\n"
    end

    local input = table.concat(canonical)
    local h1 = _feed_hash(104729, 131, 2147483647, input)
    local h2 = _feed_hash(130363, 257, 2147483629, input)
    return string.format("crt-wire-v%d:%d:%08x:%08x",
        M.WIRE_IDENTITY_VERSION, #names, h1, h2), nil, names
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

return M
