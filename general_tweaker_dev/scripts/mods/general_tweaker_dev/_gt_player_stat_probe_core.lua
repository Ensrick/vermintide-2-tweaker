-- _gt_player_stat_probe_core.lua -- pure bounded snapshot policy for issue #797.
--
-- Normalizes opaque BuffExtension stat rows without invoking proc-bearing
-- application functions. It also owns the finite five-sample trace cadence so
-- both runtime diagnostics and offline tests share one bound.
--
-- Owned by: _gt_diag_player_stats.lua. Consumed via: mod:dofile and offline tests.
local M = {}

M.MAX_STAT_TYPES = 256
M.MAX_CONTRIBUTIONS = 1024
M.TRACE_OFFSETS = { 0, 0.25, 1, 3, 10 }

local function _sorted_keys(value)
    local keys = {}
    if type(value) ~= "table" then return keys end
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(left, right) return tostring(left) < tostring(right) end)
    return keys
end

local function _finite(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

function M.normalize(stat_buffs, application_methods)
    local snapshot = {
        rows = {},
        truncated = false,
        contributions = 0,
        stat_types = 0,
    }
    for _, raw_stat_name in ipairs(_sorted_keys(stat_buffs)) do
        if snapshot.stat_types >= M.MAX_STAT_TYPES then
            snapshot.truncated = true
            break
        end
        snapshot.stat_types = snapshot.stat_types + 1
        local stat_name = tostring(raw_stat_name)
        local source = stat_buffs[raw_stat_name]
        local row = {
            stat = stat_name,
            method = type(application_methods) == "table"
                and tostring(application_methods[stat_name] or "unknown") or "unknown",
            bonus = 0,
            multiplier = 0,
            values = 0,
            dynamic = 0,
            conditional = 0,
            entries = 0,
        }
        if type(source) == "table" then
            for _, index in ipairs(_sorted_keys(source)) do
                if snapshot.contributions >= M.MAX_CONTRIBUTIONS then
                    snapshot.truncated = true
                    break
                end
                local entry = source[index]
                if type(entry) == "table" then
                    row.entries = row.entries + 1
                    snapshot.contributions = snapshot.contributions + 1
                    if _finite(entry.bonus) then row.bonus = row.bonus + entry.bonus end
                    if _finite(entry.multiplier) then
                        row.multiplier = row.multiplier + entry.multiplier
                    elseif entry.multiplier ~= nil then
                        row.dynamic = row.dynamic + 1
                    end
                    if entry.value ~= nil then row.values = row.values + 1 end
                    if _finite(entry.proc_chance) and entry.proc_chance < 1 then
                        row.conditional = row.conditional + 1
                    end
                end
            end
        end
        if row.entries > 0 then snapshot.rows[#snapshot.rows + 1] = row end
        if snapshot.contributions >= M.MAX_CONTRIBUTIONS then break end
    end
    return snapshot
end

function M.fingerprint(snapshot)
    local parts = {}
    for i, row in ipairs(snapshot and snapshot.rows or {}) do
        parts[i] = table.concat({ row.stat, row.method, tostring(row.entries),
            string.format("%.6f", row.bonus), string.format("%.6f", row.multiplier),
            tostring(row.values), tostring(row.dynamic), tostring(row.conditional) }, ":")
    end
    parts[#parts + 1] = snapshot and snapshot.truncated and "truncated" or "complete"
    return table.concat(parts, "|")
end

function M.new_trace(now)
    return { started_at = tonumber(now) or 0, next_sample = 1, records = {} }
end

function M.take_due(trace, now)
    if not trace then return nil end
    local offset = M.TRACE_OFFSETS[trace.next_sample]
    if offset == nil or (tonumber(now) or 0) < trace.started_at + offset then return nil end
    trace.next_sample = trace.next_sample + 1
    return offset
end

function M.record(trace, offset, fingerprint)
    if not trace or #trace.records >= #M.TRACE_OFFSETS then return false end
    trace.records[#trace.records + 1] = { offset = offset, fingerprint = fingerprint }
    return true
end

function M.complete(trace)
    return trace and trace.next_sample > #M.TRACE_OFFSETS
end

return M
