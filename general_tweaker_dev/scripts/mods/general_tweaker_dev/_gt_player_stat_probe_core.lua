-- _gt_player_stat_probe_core.lua -- pure bounded issue #797 stat policy.
--
-- BuffExtension does not retain an independently addressable contribution for
-- every talent/property. It retains application stages keyed by 0, by a
-- stacking name, or by an individual numeric index. This module preserves
-- those keys and the active-buff identities that feed them. Deterministic
-- numeric stages use the exact BuffExtension.apply_buffs_to_value equation;
-- proc/function/table stages are reported as unsupported and are never called.
local M = {}

M.MAX_STAT_TYPES = 256
M.MAX_CONTRIBUTIONS = 1024
M.MAX_ACTIVE_BUFFS = 1024
M.TRACE_OFFSETS = { 0, 0.25, 1, 3, 10 }
M.SAMPLE_SECONDS = 0.25

local function _finite(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

local function _sorted_keys(value, limit)
    local keys = {}
    local truncated = false
    if type(value) ~= "table" then return keys, truncated end
    for key in pairs(value) do
        if limit and #keys >= limit then
            truncated = true
            break
        end
        keys[#keys + 1] = key
    end
    table.sort(keys, function(left, right)
        if type(left) == type(right) then
            if type(left) == "number" then return left < right end
            return tostring(left) < tostring(right)
        end
        return type(left) < type(right)
    end)
    return keys, truncated
end

local function _source_map(active_buffs)
    local map = {}
    local keys, truncated = _sorted_keys(active_buffs, M.MAX_ACTIVE_BUFFS)
    for _, key in ipairs(keys) do
        local buff = active_buffs[key]
        local template = type(buff) == "table" and buff.template or nil
        local stat = type(template) == "table" and template.stat_buff or nil
        if stat then
            local stage_key = tostring(buff.stat_buff_index == nil and "?" or buff.stat_buff_index)
            local stat_map = map[tostring(stat)] or {}
            local sources = stat_map[stage_key] or {}
            sources[#sources + 1] = {
                parent = tostring(buff.buff_template_name or "?"),
                child = tostring(buff.buff_type or template.name or "?"),
                id = tostring(buff.id or key),
                lifetime = _finite(buff.duration)
                    and buff.duration < math.huge and "timed" or "persistent",
            }
            stat_map[stage_key] = sources
            map[tostring(stat)] = stat_map
        end
    end
    return map, truncated
end

function M.normalize(stat_buffs, application_methods, active_buffs)
    local snapshot = {
        rows = {},
        by_stat = {},
        truncated = false,
        source_truncated = false,
        contributions = 0,
        stat_types = 0,
    }
    local sources, source_truncated = _source_map(active_buffs)
    local stat_keys, stat_truncated = _sorted_keys(stat_buffs, M.MAX_STAT_TYPES)
    snapshot.source_truncated = source_truncated
    snapshot.truncated = stat_truncated
    for _, raw_stat in ipairs(stat_keys) do
        snapshot.stat_types = snapshot.stat_types + 1
        local stat = tostring(raw_stat)
        local stage_table = stat_buffs[raw_stat]
        local row = {
            stat = stat,
            method = type(application_methods) == "table"
                and tostring(application_methods[stat] or "unknown") or "unknown",
            stages = {},
            raw = stage_table,
        }
        -- Preserve the table's native `pairs` traversal order: this is the
        -- same order BuffExtension.apply_buffs_to_value uses for sequential
        -- non-root stages. Sorting here would change the engine equation.
        for stage_key, entry in pairs(stage_table or {}) do
            if snapshot.contributions >= M.MAX_CONTRIBUTIONS then
                snapshot.truncated = true
                break
            end
            if type(entry) == "table" then
                local key_text = tostring(stage_key)
                row.stages[#row.stages + 1] = {
                    key = stage_key,
                    key_text = key_text,
                    bonus = entry.bonus,
                    multiplier = entry.multiplier,
                    proc_chance = entry.proc_chance,
                    value = entry.value,
                    sources = sources[stat] and sources[stat][key_text] or {},
                }
                snapshot.contributions = snapshot.contributions + 1
            end
        end
        if #row.stages > 0 then
            snapshot.rows[#snapshot.rows + 1] = row
            snapshot.by_stat[stat] = row
        end
        if snapshot.contributions >= M.MAX_CONTRIBUTIONS then break end
    end
    return snapshot
end

-- Exact deterministic subset of BuffExtension.apply_buffs_to_value. The engine
-- iterates stages, applies non-root stages in order, then applies accumulated
-- root multiplier/bonus. Calling the engine method would roll proc state, so
-- unsupported stages make the entire final explicitly unavailable.
function M.evaluate(row, base)
    if not _finite(base) then
        return { supported = false, reason = "base-unavailable", base = base }
    end
    local final = base
    local root_multiplier, root_bonus = 1, 0
    local contributions = {}
    for i, stage in ipairs(row and row.stages or {}) do
        local chance = stage.proc_chance == nil and 1 or stage.proc_chance
        if row.method == "proc" or not _finite(chance) or chance < 1 then
            return { supported = false, reason = "proc-stage", base = base }
        end
        if not _finite(stage.bonus or 0) then
            return { supported = false, reason = "dynamic-bonus", base = base }
        end
        if not _finite(stage.multiplier or 0) then
            return {
                supported = false,
                reason = type(stage.multiplier) .. "-multiplier",
                base = base,
            }
        end
        local bonus, multiplier = stage.bonus or 0, stage.multiplier or 0
        if stage.key == 0 then
            root_multiplier = root_multiplier + multiplier
            root_bonus = root_bonus + bonus
            contributions[#contributions + 1] = {
                key_text = stage.key_text,
                kind = "root-aggregate",
                bonus = bonus,
                multiplier = multiplier,
                sources = stage.sources,
            }
        else
            local before = final
            final = final * (multiplier + 1) + bonus
            contributions[#contributions + 1] = {
                key_text = stage.key_text,
                kind = "ordered-stage",
                delta = final - before,
                bonus = bonus,
                multiplier = multiplier,
                sources = stage.sources,
            }
        end
    end
    local before_root = final
    final = final * root_multiplier + root_bonus
    for i = #contributions, 1, -1 do
        if contributions[i].kind == "root-aggregate" then
            contributions[i].delta = final - before_root
            break
        end
    end
    return {
        supported = true,
        base = base,
        final = final,
        contributions = contributions,
    }
end

function M.fingerprint(snapshot)
    local parts = {}
    for _, row in ipairs(snapshot and snapshot.rows or {}) do
        parts[#parts + 1] = row.stat .. ":" .. row.method
        for _, stage in ipairs(row.stages) do
            parts[#parts + 1] = table.concat({
                stage.key_text,
                tostring(stage.bonus),
                tostring(stage.multiplier),
                tostring(stage.proc_chance),
                tostring(stage.value),
                tostring(#stage.sources),
            }, ":")
        end
    end
    parts[#parts + 1] = snapshot and snapshot.truncated and "truncated" or "complete"
    return table.concat(parts, "|")
end

function M.new_cache()
    return {
        next_sample = 0,
        identity = nil,
        stat_fingerprint = nil,
        rebuilds = 0,
        samples = 0,
        formatted = 0,
        allocated_rows = 0,
        allocated_lines = 0,
        max_rows = 0,
        max_lines = 0,
    }
end

function M.cache_due(cache, now, identity, stat_fingerprint)
    now = tonumber(now) or 0
    local edge = cache.identity ~= identity or cache.stat_fingerprint ~= stat_fingerprint
    if not edge and now < cache.next_sample then return false, false end
    cache.next_sample = now + M.SAMPLE_SECONDS
    cache.samples = cache.samples + 1
    if edge then
        cache.identity = identity
        cache.stat_fingerprint = stat_fingerprint
        cache.rebuilds = cache.rebuilds + 1
    end
    return true, edge
end

function M.record_allocation(cache, rows, lines)
    rows, lines = tonumber(rows) or 0, tonumber(lines) or 0
    cache.formatted = cache.formatted + 1
    cache.allocated_rows = cache.allocated_rows + rows
    cache.allocated_lines = cache.allocated_lines + lines
    cache.max_rows = math.max(cache.max_rows, rows)
    cache.max_lines = math.max(cache.max_lines, lines)
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
