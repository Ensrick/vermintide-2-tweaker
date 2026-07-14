-- Engine-free progression/candidate policy for elite modifiers (#323).
local M = {}

M.CATALOG = {
    { name = "commander",        tier = "boss_unproven" },
    { name = "crippling",        tier = "boss_unproven" },
    { name = "crushing",         tier = "boss_unproven" },
    { name = "frenzy",           tier = "boss_unproven" },
    { name = "intangible",       tier = "boss_unproven" },
    { name = "periodic_curse",   tier = "boss_unproven" },
    { name = "periodic_shield",  tier = "boss_unproven" },
    { name = "raging",           tier = "boss_unproven" },
    { name = "ranged_immune",    tier = "boss_unproven" },
    { name = "regenerating",     tier = "boss_unproven" },
    { name = "unstaggerable",    tier = "boss_unproven" },
    { name = "vampiric",         tier = "boss_unproven" },
    { name = "warping",          tier = "boss_unproven" },
    { name = "shockwave",        tier = "elite_source_proven" },
    { name = "ignore_death_aura", tier = "elite_source_proven" },
}

function M.rate(completed_level_count)
    local completed = math.max(0, math.floor(tonumber(completed_level_count) or 0))
    return math.min(20, completed * 5)
end

function M.classify_breed(breed)
    if type(breed) ~= "table" or breed.boss then return "other" end
    if breed.elite then return "elite" end
    if breed.special then return "special" end
    return "other"
end

function M.bucket(spawn_index, breed_name)
    local hash = math.floor(tonumber(spawn_index) or 0) % 1000003
    local name = type(breed_name) == "string" and breed_name or ""
    for i = 1, #name do
        hash = (hash * 33 + string.byte(name, i)) % 1000003
    end
    return hash % 100
end

function M.would_apply(spawn_index, breed_name, completed_level_count)
    return M.bucket(spawn_index, breed_name) < M.rate(completed_level_count)
end

function M.inspect_catalog(enhancements, boss_marks)
    enhancements = type(enhancements) == "table" and enhancements or {}
    boss_marks = type(boss_marks) == "table" and boss_marks or {}
    local result = {
        total = #M.CATALOG,
        templates = 0,
        boss_catalog = 0,
        boss_registered = 0,
        elite_source_proven = 0,
        missing = {},
    }
    for _, row in ipairs(M.CATALOG) do
        if type(enhancements[row.name]) == "table" then
            result.templates = result.templates + 1
        else
            result.missing[#result.missing + 1] = row.name
        end
        if boss_marks[row.name] then result.boss_registered = result.boss_registered + 1 end
        if row.tier == "boss_unproven" then result.boss_catalog = result.boss_catalog + 1 end
        if row.tier == "elite_source_proven" then
            result.elite_source_proven = result.elite_source_proven + 1
        end
    end
    table.sort(result.missing)
    return result
end

return M
