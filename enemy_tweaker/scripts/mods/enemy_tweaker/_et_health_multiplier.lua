local mod = get_mod("enemy_tweaker")

-- #369: scale the final spawn health selected by ConflictDirector instead of
-- mutating shared Breeds.max_health arrays. This composes with boss balance and
-- spawn-specific modifiers, and GenericHealthExtension replicates max health.
local ET = mod._et
local Core = ET.HealthMultiplierCore
local BreedData = require("scripts/mods/enemy_tweaker/enemy_tweaker_breeds")

local DIFFICULTIES = {}
for _, difficulty in ipairs(BreedData.DIFFICULTIES) do
    DIFFICULTIES[difficulty.key] = true
end

local function active_difficulty()
    local manager = Managers.state and Managers.state.difficulty
    local difficulty = manager and manager:get_difficulty()
    return DIFFICULTIES[difficulty] and difficulty or nil
end

local function active_multiplier(difficulty)
    if not difficulty then return 1 end
    return Core.sanitize_multiplier(mod:get(BreedData.setting_key(difficulty, "health_multiplier")))
end

local function host_active()
    return Managers.player and Managers.player.is_server
end

mod:hook("GenericHealthExtension", "init", function(func, self, extension_init_context, unit, extension_init_data)
    local difficulty = active_difficulty()
    local breed = extension_init_data and extension_init_data.breed
    local base_health = extension_init_data and extension_init_data.health
    local scaled_health = Core.scaled_max_health(base_health, active_multiplier(difficulty))

    if not host_active() or not difficulty or not Core.is_hostile_breed(breed) or not scaled_health then
        return func(self, extension_init_context, unit, extension_init_data)
    end

    local multiplier = active_multiplier(difficulty)
    local init_data = extension_init_data
    if multiplier ~= 1 then
        init_data = {}
        for key, value in pairs(extension_init_data) do init_data[key] = value end
        init_data.health = scaled_health
    end

    local result = func(self, extension_init_context, unit, init_data)
    self._et369_base_max_health = base_health
    self._et369_applied_multiplier = multiplier
    return result
end)

local function apply_live_health_multiplier()
    if not host_active() then return end
    local difficulty = active_difficulty()
    if not difficulty then return end
    local multiplier = active_multiplier(difficulty)
    local entity = Managers.state and Managers.state.entity
    local health_system = entity and entity:system("health_system")
    local extensions = health_system and health_system.unit_extensions
    if type(extensions) ~= "table" then return end

    local changed = 0
    for _, extension in pairs(extensions) do
        local base_health = extension._et369_base_max_health
        if base_health and not extension.dead and extension._et369_applied_multiplier ~= multiplier then
            local old_max = extension:get_max_health()
            local old_damage = extension:get_damage_taken()
            local requested_max = Core.scaled_max_health(base_health, multiplier)
            if requested_max and old_max and old_max > 0 then
                local applied_max = extension:set_max_health(requested_max) or extension:get_max_health()
                extension.unmodified_max_health = applied_max
                extension:set_server_damage_taken(Core.rescaled_damage(old_max, old_damage, applied_max))
                extension._et369_applied_multiplier = multiplier
                changed = changed + 1
            end
        end
    end
    if changed > 0 then
        mod:info("[et:369] difficulty=%s multiplier=%.1f live_enemies=%d", difficulty, multiplier, changed)
    end
end

mod._et_apply_health_multipliers = apply_live_health_multiplier

ET.rt_register("issue369_health_multiplier_wired", function()
    if type(mod._et_apply_health_multipliers) ~= "function" then
        return "live health multiplier apply is not wired"
    end
    if not DIFFICULTIES.normal or not DIFFICULTIES.cataclysm_3 then
        return "difficulty identity map is incomplete"
    end
end)
