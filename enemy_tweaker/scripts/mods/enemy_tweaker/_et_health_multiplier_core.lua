-- Engine-free math and breed policy for Issue #369.

local M = {}

M.MIN_MULTIPLIER = 0.1
M.MAX_MULTIPLIER = 5.0

local HOSTILE_RACES = {
    skaven = true,
    chaos = true,
    beastmen = true,
    undead = true,
}

function M.sanitize_multiplier(value)
    value = tonumber(value) or 1
    if value ~= value then value = 1 end -- NaN
    if value < M.MIN_MULTIPLIER then return M.MIN_MULTIPLIER end
    if value > M.MAX_MULTIPLIER then return M.MAX_MULTIPLIER end
    return value
end

function M.is_hostile_breed(breed)
    if type(breed) ~= "table" or not HOSTILE_RACES[breed.race] then return false end
    if breed.pet_skeleton_type ~= nil then return false end
    local template = breed.unit_template
    if type(template) == "string" and template:find("pet_skeleton", 1, true) then return false end
    return true
end

function M.scaled_max_health(base_health, multiplier)
    base_health = tonumber(base_health)
    if not base_health or base_health <= 0 or base_health >= math.huge then return nil end
    return base_health * M.sanitize_multiplier(multiplier)
end

function M.rescaled_damage(old_max, old_damage, new_max)
    old_max = tonumber(old_max) or 0
    old_damage = tonumber(old_damage) or 0
    new_max = tonumber(new_max) or 0
    if old_max <= 0 or new_max <= 0 then return 0 end
    local fraction = math.max(0, math.min(1, old_damage / old_max))
    local damage = math.floor(new_max * fraction * 4 + 0.5) / 4
    return math.max(0, math.min(new_max, damage))
end

return M
