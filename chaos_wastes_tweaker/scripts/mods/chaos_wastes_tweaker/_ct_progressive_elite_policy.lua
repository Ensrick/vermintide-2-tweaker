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

-- The only source-proven ordinary-elite recipe: `elite_base` plus one of the
-- two Geheimnisnacht Chaos Warrior marks, used by the altar event and by
-- Geheimnisnacht Hard Mode [src: geheimnisnacht_2021_generic_terror_events.lua:9-22;
-- mutator_geheimnisnacht_2021_hard_mode.lua:3-12]. Every other CATALOG row is a
-- `BossGrudgeMarks` entry [src: grudge_mark_settings.lua:126-140] and is never
-- selectable by this policy.
M.BASE_RECIPE = "elite_base"
M.ELITE_RECIPES = { "shockwave", "ignore_death_aura" }
M.DEFAULT_STEP_PERCENT = 5
M.MAX_STEPS = 4
M.MAX_STEP_PERCENT = 25
-- Same range as vanilla's `TerrorEventUtils.random(16384)` draw
-- [src: terror_event_utils.lua:81].
M.NAME_INDEX_RANGE = 16384

-- Per-completed-map percentage step. Non-numbers fall back to the default;
-- the result is an integer inside 0..MAX_STEP_PERCENT.
function M.clamp_step(step_percent)
    local value = tonumber(step_percent)
    if value == nil then value = M.DEFAULT_STEP_PERCENT end
    value = math.floor(value + 0.5)
    if value < 0 then value = 0 end
    if value > M.MAX_STEP_PERCENT then value = M.MAX_STEP_PERCENT end
    return value
end

-- Requested curve: 0/5/10/15/20 percent for 0/1/2/3/4+ completed maps. The
-- optional step keeps the shape and rescales it (step 0 disables the chance).
function M.rate(completed_level_count, step_percent)
    local completed = math.max(0, math.floor(tonumber(completed_level_count) or 0))
    return math.min(M.MAX_STEPS, completed) * M.clamp_step(step_percent)
end

function M.rate_table(step_percent)
    local rows = {}
    for depth = 0, M.MAX_STEPS do
        rows[#rows + 1] = M.rate(depth, step_percent)
    end
    return rows
end

function M.rate_label(step_percent)
    return table.concat(M.rate_table(step_percent), "/")
end

function M.classify_breed(breed)
    if type(breed) ~= "table" or breed.boss then return "other" end
    if breed.elite then return "elite" end
    if breed.special then return "special" end
    return "other"
end

function M.is_elite_recipe(name)
    for _, recipe in ipairs(M.ELITE_RECIPES) do
        if recipe == name then return true end
    end
    return false
end

-- Deterministic per-spawn identity hash; never consumes gameplay RNG.
function M.hash(spawn_index, breed_name)
    local hash = math.floor(tonumber(spawn_index) or 0) % 1000003
    local name = type(breed_name) == "string" and breed_name or ""
    for i = 1, #name do
        hash = (hash * 33 + string.byte(name, i)) % 1000003
    end
    return hash
end

function M.bucket(spawn_index, breed_name)
    return M.hash(spawn_index, breed_name) % 100
end

function M.recipe_index(spawn_index, breed_name)
    return (math.floor(M.hash(spawn_index, breed_name) / 100) % #M.ELITE_RECIPES) + 1
end

-- Grudge name index supplied beside CT's list so vanilla does not draw one from
-- the terror-event RNG when it applies the marks.
function M.name_index(spawn_index, breed_name)
    return (M.hash(spawn_index, breed_name) % M.NAME_INDEX_RANGE) + 1
end

function M.would_apply(spawn_index, breed_name, completed_level_count, step_percent)
    return M.bucket(spawn_index, breed_name) < M.rate(completed_level_count, step_percent)
end

-- Pure recipe selector: the allowlisted mark a 0-99 roll selects at this
-- depth, or nil. `pick` chooses between the two allowlisted marks and is
-- normalized into range so no other catalog row can ever be named.
function M.select_recipe(completed_level_count, roll, pick, step_percent)
    local rate = M.rate(completed_level_count, step_percent)
    local value = tonumber(roll)
    if value == nil or value < 0 or value >= rate then return nil end
    local count = #M.ELITE_RECIPES
    local index = math.floor(tonumber(pick) or 1)
    index = ((index - 1) % count) + 1
    return M.ELITE_RECIPES[index]
end

-- Pure selector for one spawn: the enhancement list vanilla expects in
-- `optional_data.enhancements` ({ elite_base, mark }, same order as the
-- Geheimnisnacht recipe) plus the mark name, or nil. Only ordinary elites
-- qualify; specials, monsters and trash never do. `templates` is the vanilla
-- `BreedEnhancements` table (or a test double); a missing template yields nil
-- so vanilla's contract is never half-filled.
function M.enhancements_for(completed_level_count, roll, breed, pick, templates, step_percent)
    if M.classify_breed(breed) ~= "elite" then return nil end
    local recipe = M.select_recipe(completed_level_count, roll, pick, step_percent)
    if not recipe then return nil end
    if type(templates) ~= "table" then return nil end
    local base, mark = templates[M.BASE_RECIPE], templates[recipe]
    if type(base) ~= "table" or type(mark) ~= "table" then return nil end
    return { base, mark }, recipe
end

-- Runtime convenience: derive roll and pick from the spawn identity.
function M.enhancements_for_spawn(spawn_index, breed, completed_level_count, templates, step_percent)
    local name = type(breed) == "table" and breed.name or nil
    return M.enhancements_for(completed_level_count, M.bucket(spawn_index, name), breed,
        M.recipe_index(spawn_index, name), templates, step_percent)
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
