-- Engine-free composition policy for multiple Chaos Wastes modifiers (#289).
local M = {}

local function _copy_names(value)
    local names = {}
    if type(value) ~= "table" then return names end
    for key, row in pairs(value) do
        local name = type(key) == "number" and row or key
        if type(name) == "string" and name ~= "" then
            names[#names + 1] = name
        end
    end
    return names
end

local function _unique_sorted(value)
    local names, seen, duplicates = {}, {}, 0
    for _, name in ipairs(_copy_names(value)) do
        if seen[name] then
            duplicates = duplicates + 1
        else
            seen[name] = true
            names[#names + 1] = name
        end
    end
    table.sort(names)
    return names, duplicates
end

function M.ramp_target(completed_level_count, base_count, levels_per_step, maximum)
    local completed = math.max(0, math.floor(tonumber(completed_level_count) or 0))
    local base = math.max(1, math.floor(tonumber(base_count) or 1))
    local interval = math.max(1, math.floor(tonumber(levels_per_step) or 2))
    local cap = math.max(base, math.floor(tonumber(maximum) or 3))
    return math.min(cap, base + math.floor(completed / interval))
end

function M.signature(value)
    local names = _unique_sorted(value)
    local hash = 17
    for _, name in ipairs(names) do
        for i = 1, #name do
            hash = (hash * 33 + string.byte(name, i)) % 1000003
        end
    end
    return string.format("%d:%06d", #names, hash)
end

function M.inspect(snapshot, mutator_templates, network_lookup)
    snapshot = type(snapshot) == "table" and snapshot or {}
    local templates = type(mutator_templates) == "table" and mutator_templates or {}
    local lookup = type(network_lookup) == "table" and network_lookup or {}
    local effective, duplicates = _unique_sorted(snapshot.effective)
    local active = _unique_sorted(snapshot.active)
    local events = _unique_sorted(snapshot.events)
    local minor = _unique_sorted(snapshot.minor)
    local result = {
        completed = math.max(0, math.floor(tonumber(snapshot.completed) or 0)),
        target = M.ramp_target(snapshot.completed, snapshot.base_count,
            snapshot.levels_per_step, snapshot.maximum),
        node_curse = type(snapshot.node_curse) == "string" and snapshot.node_curse or "none",
        effective = effective,
        active = active,
        events = events,
        minor = minor,
        effective_signature = M.signature(effective),
        active_signature = M.signature(active),
        duplicate_count = duplicates,
        missing_template = {},
        missing_wire = {},
        package_names = {},
    }
    local package_seen = {}
    for _, name in ipairs(effective) do
        local template = templates[name]
        if type(template) ~= "table" then
            result.missing_template[#result.missing_template + 1] = name
        else
            for _, package_name in ipairs(type(template.packages) == "table" and template.packages or {}) do
                if type(package_name) == "string" and not package_seen[package_name] then
                    package_seen[package_name] = true
                    result.package_names[#result.package_names + 1] = package_name
                end
            end
        end
        if lookup[name] == nil then
            result.missing_wire[#result.missing_wire + 1] = name
        end
    end
    table.sort(result.package_names)
    result.transport_ready = result.duplicate_count == 0
        and #result.missing_template == 0 and #result.missing_wire == 0
    result.singular_node_schema_blocks_ramp = result.target > 1
    return result
end

return M
