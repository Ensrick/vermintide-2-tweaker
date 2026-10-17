-- _et_diag_capacity_authority.lua - #324 bounded capacity-authority probe.
--
-- In 12 of 12 tester logs on 0.7.64-dev the #1413 registrar refused both
-- custom breeds at mod load with `damage_source_cap_unavailable`
-- (_et_custom_breed_registrar.lua read_damage_source_cap), so the Skaven
-- Warlord never registers. Half of that is source-proven: `NetworkConstants`
-- is created only by scripts/network_lookup/network_constants.lua:3, which
-- vanilla dofiles at state_loading_restart_network.lua:161 (after
-- LobbyInternal.init_client, :124/:140/:157) and game_network_manager.lua:59,
-- both after Boot loads mods (boot.lua:400-413). Vanilla never calls
-- `Network.type_info` before that network init, so what the engine returns
-- for it at mod load is [unverified], and that answer picks the fix (reader
-- shape versus a capacity proof deferred until the authority exists).
--
-- This owner records exactly what the three planner capacity readers see,
-- once at load and once when `NetworkConstants.damage_source_id` first
-- appears, as engine printf rows in a module-local ledger. It never chats,
-- never writes a global, and changes no registration state. The bound is
-- per module load: a VMF reload re-runs install() with a fresh ledger.
--
-- The registrar reads `Network.type_info` with rawget only. The header row
-- also reports a pcall-guarded normal index (`indexed=`) and whether Network
-- has a metatable (`meta=`); when only the normal index yields a function the
-- axis rows call that one and the header says `via=index`, so "reachable only
-- through __index" never looks like "absent". These are extra pre-init
-- type_info calls vanilla never makes: a load-time crash on this build traces
-- here first.
--
-- Owned by: _et_skaven_warlord_breed.lua (the #324 owner) loads it exactly
-- once through install(); retire with #324 (#500).

local M = {}

M.MAX_ROWS = 8
M.PREFIX = "[et:324]"
M.CHECK_NAME = "issue324_capacity_authority_probe"

local MAX_KEYS = 8
local MAX_TEXT = 48
local MAX_ERROR = 96
local MAX_ROW_LENGTH = 480

-- Planner order (build_plan): damage source, statistics path, health sync.
-- `constant` is the NetworkConstants field the boot file stores
-- (network_constants.lua:20, :61, :6-11 via check_bounderies at :121).
local AXES = {
    { info = "damage_source_id", constant = "damage_source_id",
        lookup = "damage_sources" },
    { info = "statistics_path_lookup", constant = "statistics_path_lookup",
        lookup = "statistics_path_names" },
    { info = "damage_hotjoin_sync", constant = "damage_hotjoin_sync" },
}
M.AXES = AXES

local function clip(text, limit)
    text = tostring(text):gsub("[%c]", " ")
    if #text > limit then return text:sub(1, limit) .. "..." end
    return text
end

local function scalar(value)
    local kind = type(value)
    if kind == "nil" then return "nil" end
    if kind == "number" or kind == "boolean" then return kind .. ":" .. tostring(value) end
    if kind == "string" then return "string:" .. clip(value, MAX_TEXT) end
    return kind
end

-- Raw, bounded shape of one value: tables list at most MAX_KEYS sorted keys
-- with scalar values; userdata reports its indexed `max` under pcall.
local function describe(value)
    local kind = type(value)
    if kind == "table" then
        local keys = {}
        for key in next, value do
            keys[#keys + 1] = key
            if #keys > 64 then break end
        end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        local parts = {}
        for i = 1, math.min(#keys, MAX_KEYS) do
            parts[i] = clip(keys[i], 24) .. "=" .. scalar(rawget(value, keys[i]))
        end
        if #keys > MAX_KEYS then parts[#parts + 1] = "+" .. (#keys - MAX_KEYS) end
        return "table{" .. table.concat(parts, ",") .. "}"
    end
    if kind == "userdata" then
        local ok, max = pcall(function() return value.max end)
        return "userdata{max=" .. (ok and scalar(max) or "index_error") .. "}"
    end
    return scalar(value)
end
M.describe = describe

local function result_max(value)
    if type(value) == "table" then return scalar(rawget(value, "max")) end
    if type(value) == "userdata" then
        local ok, max = pcall(function() return value.max end)
        return ok and scalar(max) or "index_error"
    end
    return "n/a"
end

-- Normal (metatable-aware) index under pcall; the registrar never does this.
local function indexed(value, key)
    if type(value) ~= "table" and type(value) ~= "userdata" then return nil, "n/a" end
    local ok, field = pcall(function() return value[key] end)
    if not ok then return nil, "index_error" end
    return field, type(field)
end

local function has_metatable(value)
    if type(value) ~= "table" and type(value) ~= "userdata" then return "n/a" end
    return tostring(getmetatable(value) ~= nil)
end

local function lookup_rows(globals, axis)
    if not axis.lookup then return "n/a" end
    local lookup = rawget(globals, "NetworkLookup")
    local rows = type(lookup) == "table" and rawget(lookup, axis.lookup)
    if type(rows) ~= "table" then return "absent" end
    local ok, count = pcall(function() return #rows end)
    return ok and tostring(count) or "error"
end

-- opts.globals: table read with rawget only (production: _G).
-- opts.emit:    function(row) for one finished row (production: printf).
-- opts.verdicts: optional function() -> { [axis] = "cap:N" | reason }.
function M.new(opts)
    assert(type(opts) == "table" and type(opts.globals) == "table"
        and type(opts.emit) == "function", "capacity probe needs globals and emit")
    local globals, emit, verdicts = opts.globals, opts.emit, opts.verdicts
    local ledger, sampled = {}, {}
    local probe = {}

    local function record(row)
        if #ledger >= M.MAX_ROWS then return false end
        row = clip(row, MAX_ROW_LENGTH)
        ledger[#ledger + 1] = row
        pcall(emit, row)
        return true
    end

    function probe.sample(phase, note)
        phase = clip(phase or "unnamed", 16)
        if sampled[phase] or #ledger >= M.MAX_ROWS then return 0 end
        sampled[phase] = true
        local before = #ledger
        local constants = rawget(globals, "NetworkConstants")
        local network = rawget(globals, "Network")
        local type_info = type(network) == "table" and rawget(network, "type_info") or nil
        local index_fn, index_kind = indexed(network, "type_info")
        local call_fn, via = nil, "none"
        if type(type_info) == "function" then call_fn, via = type_info, "raw"
        elseif type(index_fn) == "function" then call_fn, via = index_fn, "index" end
        local verdict_ok, verdict_rows = false, nil
        if type(verdicts) == "function" then
            verdict_ok, verdict_rows = pcall(verdicts)
        end
        if not verdict_ok or type(verdict_rows) ~= "table" then verdict_rows = nil end
        record(string.format("%s cap-probe phase=%s note=%s NetworkConstants=%s Network=%s type_info=%s indexed=%s meta=%s via=%s",
            M.PREFIX, phase, clip(note or "none", MAX_TEXT), type(constants),
            type(network), type(type_info), index_kind, has_metatable(network), via))
        for i = 1, #AXES do
            local axis = AXES[i]
            local constant = type(constants) == "table"
                and describe(rawget(constants, axis.constant)) or "n/a"
            local call, result = "skipped", nil
            if call_fn then
                local ok, value = pcall(call_fn, axis.info)
                if ok then call, result = "ok", value
                else call = "error:" .. clip(value, MAX_ERROR) end
            end
            local verdict = verdict_rows and verdict_rows[axis.info]
            -- Deciding fields first: a wide shape dump can only clip the tail.
            record(string.format("%s cap-probe phase=%s axis=%s call=%s result_max=%s verdict=%s lookup_rows=%s constant=%s result=%s",
                M.PREFIX, phase, axis.info, call,
                call == "ok" and result_max(result) or "n/a",
                verdict and clip(verdict, MAX_TEXT) or "n/a",
                lookup_rows(globals, axis), constant,
                call == "ok" and describe(result) or "n/a"))
        end
        return #ledger - before
    end

    -- One-shot: fires the "network" sample the first time vanilla's boot file
    -- has stored damage_source_id, then stays inert.
    function probe.poll()
        if sampled.network then return false end
        local constants = rawget(globals, "NetworkConstants")
        if type(constants) ~= "table" or rawget(constants, "damage_source_id") == nil then
            return false
        end
        return probe.sample("network", "authority_appeared") > 0
    end

    function probe.sampled(phase) return sampled[phase] == true end

    function probe.rows()
        local out = {}
        for i = 1, #ledger do out[i] = ledger[i] end
        return out
    end

    local function phase_rows(phase)
        local needle, count = " phase=" .. phase .. " ", 0
        for i = 1, #ledger do
            if ledger[i]:find(needle, 1, true) then count = count + 1 end
        end
        return count
    end

    -- In-game check: a header plus one row per axis must exist for the load
    -- sample and, once the network authority exists (always true in the
    -- Keep), for the network sample too; the ledger stays inside its bound.
    function probe.check()
        probe.poll()
        local expected = #AXES + 1
        local load_rows = phase_rows("load")
        if load_rows ~= expected then
            return "load sample has " .. load_rows .. " rows, expected " .. expected
        end
        local constants = rawget(globals, "NetworkConstants")
        if type(constants) == "table" and rawget(constants, "damage_source_id") ~= nil then
            local network_rows = phase_rows("network")
            if network_rows ~= expected then
                return "network sample has " .. network_rows .. " rows, expected " .. expected
            end
        end
        if #ledger > M.MAX_ROWS then return "ledger exceeded " .. M.MAX_ROWS .. " rows" end
        return nil
    end

    return probe
end

-- Literal raw-printf route so the live-test source authority indexes the
-- `[et:324] cap-probe %s` signature (a rawget printf helper is invisible to
-- it). The row body after the fixed head is the only argument.
local ROW_HEAD = M.PREFIX .. " cap-probe "
local function engine_emit(row)
    local body = row:sub(1, #ROW_HEAD) == ROW_HEAD and row:sub(#ROW_HEAD + 1) or row
    pcall(printf, "[et:324] cap-probe %s", body)
end

-- Production wiring: one probe per module load. The in-game check and the
-- poll hook are registered BEFORE the load sample, so a broken sample shows
-- up as a FAIL ("load sample has 0 rows") instead of a missing check. The
-- load sample is taken in the same boot frame as both registrations; the
-- network sample is driven by the #324 update dispatch.
function M.install(ET, registrar, note)
    local probe = M.new({
        globals = _G,
        emit = engine_emit,
        verdicts = registrar and registrar.capacity_verdicts and function()
            return registrar.capacity_verdicts()
        end or nil,
    })
    ET.capacity_diag_poll = probe.poll
    if type(ET.rt_register) == "function" then
        ET.rt_register(M.CHECK_NAME, probe.check)
    end
    probe.sample("load", note)
    return probe
end

return M
