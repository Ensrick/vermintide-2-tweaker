-- Engine-free composition policy for multiple Chaos Wastes modifiers (#289).
local M = {}

-- Documented ladder (MODIFIER_STACK_FEASIBILITY_289.md): one modifier initially,
-- two after two completed levels, three after four. `PROOF_MAX_TARGET` caps the
-- current bounded slice at the two-modifier proof: the singular node curse plus
-- at most ONE curated extra. Widening it is a separate, evidence-gated step.
M.LADDER = { base_count = 1, levels_per_step = 2, maximum = 3 }
M.PROOF_MAX_TARGET = 2
M.LADDER_DEPTHS = 4

-- The curated pair. Both are vanilla Chaos Wastes pool curses (the Slaanesh
-- column of `deus_map_populate_settings.lua:19-23`), both declare NO `packages`
-- (`mutator_curse_empathy.lua:273-276`; `mutator_curse_abundance_of_life.lua:3-6`),
-- neither spawns units, touches lighting/shading (#104) or owns an objective,
-- and both are vanilla `NetworkLookup.mutator_templates` entries
-- (`network_lookup.lua:266`). Order is the deterministic pick order.
M.ALLOWLIST = { "curse_empathy", "curse_abundance_of_life" }

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

local function _set(names)
    local out = {}
    for _, name in ipairs(names) do out[name] = true end
    return out
end

function M.ramp_target(completed_level_count, base_count, levels_per_step, maximum)
    local completed = math.max(0, math.floor(tonumber(completed_level_count) or 0))
    local base = math.max(1, math.floor(tonumber(base_count) or 1))
    local interval = math.max(1, math.floor(tonumber(levels_per_step) or 2))
    local cap = math.max(base, math.floor(tonumber(maximum) or 3))
    return math.min(cap, base + math.floor(completed / interval))
end

-- The documented ladder at a depth: 1/1/2/2/3 for 0/1/2/3/4+ completed levels.
function M.ladder_target(completed_level_count)
    return M.ramp_target(completed_level_count, M.LADDER.base_count,
        M.LADDER.levels_per_step, M.LADDER.maximum)
end

-- Extras this slice may add on top of the node curse: 0/0/1/1/1 for 0/1/2/3/4+.
function M.extra_count(completed_level_count)
    return math.max(0, math.min(M.ladder_target(completed_level_count), M.PROOF_MAX_TARGET) - 1)
end

function M.ladder_label()
    local rows = {}
    for depth = 0, M.LADDER_DEPTHS do rows[#rows + 1] = M.ladder_target(depth) end
    return table.concat(rows, "/")
end

function M.extra_label()
    local rows = {}
    for depth = 0, M.LADDER_DEPTHS do rows[#rows + 1] = M.extra_count(depth) end
    return table.concat(rows, "/")
end

function M.is_allowlisted(name)
    for _, entry in ipairs(M.ALLOWLIST) do
        if entry == name then return true end
    end
    return false
end

-- Deterministic string hash; never consumes gameplay RNG.
function M.hash(...)
    local hash = 17
    for i = 1, select("#", ...) do
        local text = tostring(select(i, ...))
        for j = 1, #text do
            hash = (hash * 33 + string.byte(text, j)) % 1000003
        end
        hash = (hash * 33 + 124) % 1000003
    end
    return hash
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

-- Pure selector for the curated extra. `input` carries the node's singular curse,
-- vanilla's composed mission list, the completed level count, and the run seed
-- plus node key that make the pick repeatable on every call for the same mission.
-- `is_excluded(name)` lets the runtime reject a disabled curse or a template that
-- is missing or declares packages. Returns the extra name and "selected", or nil
-- and the reason nothing was added.
function M.select_extra(input, is_excluded)
    input = type(input) == "table" and input or {}
    local node_curse = input.node_curse
    if type(node_curse) ~= "string" or node_curse == "" then
        return nil, "no_node_curse"
    end
    local vanilla = type(input.vanilla) == "table" and input.vanilla or {}
    local present = _set(_copy_names(vanilla))
    if not present[node_curse] then
        return nil, "node_curse_inactive"
    end
    if type(input.completed) ~= "number" then
        return nil, "no_completed_count"
    end
    if M.extra_count(input.completed) < 1 then
        return nil, "below_ladder"
    end
    local candidates = {}
    for _, name in ipairs(M.ALLOWLIST) do
        local excluded = name == node_curse or present[name]
        if not excluded and type(is_excluded) == "function" then
            excluded = is_excluded(name) == true
        end
        if not excluded then candidates[#candidates + 1] = name end
    end
    if #candidates == 0 then
        return nil, "no_candidate"
    end
    local index = (M.hash(input.run_seed, input.node_key, input.completed) % #candidates) + 1
    return candidates[index], "selected"
end

function M.inspect(snapshot, mutator_templates, network_lookup)
    snapshot = type(snapshot) == "table" and snapshot or {}
    local templates = type(mutator_templates) == "table" and mutator_templates or {}
    local lookup = type(network_lookup) == "table" and network_lookup or {}
    local effective, duplicates = _unique_sorted(snapshot.effective)
    local active = _unique_sorted(snapshot.active)
    local events = _unique_sorted(snapshot.events)
    local minor = _unique_sorted(snapshot.minor)
    local level_mutators = _unique_sorted(snapshot.level_mutators)
    local twitch = _unique_sorted(snapshot.twitch)
    local completed = math.max(0, math.floor(tonumber(snapshot.completed) or 0))
    local result = {
        completed = completed,
        target = M.ramp_target(snapshot.completed, snapshot.base_count,
            snapshot.levels_per_step, snapshot.maximum),
        proof_target = math.min(M.ladder_target(completed), M.PROOF_MAX_TARGET),
        extra_count = M.extra_count(completed),
        node_curse = type(snapshot.node_curse) == "string" and snapshot.node_curse or "none",
        effective = effective,
        active = active,
        events = events,
        minor = minor,
        level_mutators = level_mutators,
        effective_signature = M.signature(effective),
        active_signature = M.signature(active),
        duplicate_count = duplicates,
        missing_template = {},
        missing_wire = {},
        package_names = {},
        unexpected_active = {},
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
    -- Anything active that vanilla's own composed list, the level's mutators, or a
    -- Twitch activation does not explain must be a CT extra from the allowlist,
    -- and never more of them than the proof allows. On a client the vanilla list
    -- is local and the extra arrives only through activation, so this is the
    -- client-side parity rule; on the host the hooked list already contains it.
    local explained = _set(effective)
    for _, name in ipairs(level_mutators) do explained[name] = true end
    for _, name in ipairs(twitch) do explained[name] = true end
    local unexpected_allowlisted = true
    for _, name in ipairs(active) do
        if not explained[name] then
            result.unexpected_active[#result.unexpected_active + 1] = name
            if not M.is_allowlisted(name) then unexpected_allowlisted = false end
        end
    end
    if #result.unexpected_active > M.PROOF_MAX_TARGET - 1 then
        unexpected_allowlisted = false
    end
    result.unexpected_allowlisted = unexpected_allowlisted
    result.transport_ready = result.duplicate_count == 0
        and #result.missing_template == 0 and #result.missing_wire == 0
    result.singular_node_schema_blocks_ramp = result.target > M.PROOF_MAX_TARGET
    return result
end

return M
