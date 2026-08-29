-- Engine-free asset/behavior contract for proposed bosses (#451).
local M = {}

M.CANDIDATES = {
    { id = "chosen_shield", source_breed = "chaos_warrior", model_breed = "chaos_exalted_champion_warcamp", status = "prototype_required" },
    { id = "chosen_greataxe", source_breed = "chaos_warrior", model_breed = "chaos_exalted_champion_warcamp", status = "prototype_required" },
    { id = "stormfiend_ratlings", source_breed = "skaven_stormfiend_boss", status = "arena_coupled" },
    { id = "skaven_warlock", source_breed = "skaven_grey_seer", status = "arena_coupled" },
    { id = "chaos_sorcerer", source_breed = "chaos_exalted_sorcerer", status = "arena_coupled" },
    { id = "troll_chieftain", source_breed = "chaos_troll_chief", status = "arena_coupled" },
}

-- #451 first implementation slice: the greataxe Chosen prototype. Pure
-- override policy applied to a DEEP COPY of the regular Chaos Warrior breed
-- (never the vanilla table). The source breed's own inventory template
-- "warrior_axe" already carries the two-handed chaos greataxe
-- (ai_inventory_templates.lua:1499-1502 item_categories.axe =
-- wpn_chaos_2h_axe_1/2; consumed at :1985-1992), so the greataxe contract is
-- satisfied with zero new asset residency. Stagger policy is the monster gate
-- breed.boss_staggers (damage_utils.lua:791-793 + 918-920: every stagger
-- below explosion resolves to none), matching skaven_storm_vermin_champion
-- (breed_skaven_storm_vermin_champion.lua:16) and chaos_troll
-- (breed_chaos_troll.lua:61).
M.CHOSEN = {
    name = "et_chosen_greataxe",
    source_breed = "chaos_warrior",
    display_name_key = "et_chosen_greataxe_name",
    display_name_en = "Chaos Chosen",
    inventory_template = "warrior_axe",
    max_health = 2000,
    difficulty_count = 8,
    threat_value = 32,
}

local function _pack(...)
    return { n = select("#", ...), ... }
end

local function _call(callback, ...)
    if callback == nil then return { n = 1, true } end
    return _pack(pcall(callback, ...))
end

local function _first_error(has_error, first, result)
    if not result[1] and not has_error then return true, result[2] end
    return has_error, first
end

-- Compose the Chaos Warrior donor lifecycle with the two engine boss ledgers.
-- The donor callback still runs on every engine callback. Boss/angry operations
-- are attempt-once per unit: their latch is written BEFORE the call, so an
-- operation which mutates and then throws cannot be repeated by a second
-- death/despawn callback. Every operation is protected long enough to run the
-- remaining cleanup, after which the first error is rethrown unchanged.
function M.wrap_chosen_lifecycle(breed, services)
    if type(breed) ~= "table" then return nil, "breed_clone_missing" end
    services = type(services) == "table" and services or {}
    for _, name in ipairs({ "add_boss", "add_angry", "remove_boss", "remove_angry" }) do
        if type(services[name]) ~= "function" then
            return nil, "lifecycle_service_missing:" .. name
        end
    end

    local donor_spawn = rawget(breed, "run_on_spawn")
    local donor_death = rawget(breed, "run_on_death")
    local donor_despawn = rawget(breed, "run_on_despawn")
    if donor_spawn ~= nil and type(donor_spawn) ~= "function" then
        return nil, "donor_spawn_invalid"
    end
    if donor_death ~= nil and type(donor_death) ~= "function" then
        return nil, "donor_death_invalid"
    end
    if donor_despawn ~= nil and type(donor_despawn) ~= "function" then
        return nil, "donor_despawn_invalid"
    end

    local states = setmetatable({}, { __mode = "k" })
    local function state_for(unit)
        if unit == nil then error("chosen_lifecycle_unit_missing", 0) end
        local state = states[unit]
        if not state then
            state = {}
            states[unit] = state
        end
        return state
    end
    local function attempt_once(state, key, callback, ...)
        if state[key] then return { n = 1, true } end
        state[key] = true
        return _call(callback, ...)
    end

    breed.run_on_spawn = function(unit, blackboard, ...)
        local donor = _call(donor_spawn, unit, blackboard, ...)
        local failed, first = _first_error(false, nil, donor)
        local state = state_for(unit)
        local boss = attempt_once(state, "boss_added", services.add_boss,
            unit, blackboard)
        failed, first = _first_error(failed, first, boss)
        local angry = attempt_once(state, "angry_added", services.add_angry,
            unit, blackboard)
        failed, first = _first_error(failed, first, angry)
        if angry[1] and type(blackboard) == "table" then
            blackboard.is_angry = true
        end
        if failed then error(first, 0) end
        return unpack(donor, 2, donor.n)
    end

    local function finish(donor_callback, unit, blackboard, ...)
        local donor = _call(donor_callback, unit, blackboard, ...)
        local failed, first = _first_error(false, nil, donor)
        local state = state_for(unit)
        if state.boss_added then
            local boss = attempt_once(state, "boss_removed",
                services.remove_boss, unit, blackboard)
            failed, first = _first_error(failed, first, boss)
        end
        if state.angry_added then
            local angry = attempt_once(state, "angry_removed",
                services.remove_angry, unit, blackboard)
            failed, first = _first_error(failed, first, angry)
            if angry[1] and type(blackboard) == "table" then
                blackboard.is_angry = false
            end
        end
        if failed then error(first, 0) end
        return unpack(donor, 2, donor.n)
    end

    breed.run_on_death = function(unit, blackboard, ...)
        return finish(donor_death, unit, blackboard, ...)
    end
    breed.run_on_despawn = function(unit, blackboard, ...)
        return finish(donor_despawn, unit, blackboard, ...)
    end
    return breed
end

-- Mutates and returns the supplied CLONE table. Engine-free: every engine
-- service (boss infighting, category injection, lifecycle ledgers) is supplied
-- by the runtime owner and is therefore replaceable in offline tests.
function M.apply_chosen_overrides(breed, spec, services)
    spec = spec or M.CHOSEN
    if type(breed) ~= "table" then return nil, "breed_clone_missing" end
    services = type(services) == "table" and services or {}
    if type(services.boss_infighting) ~= "table" then
        return nil, "boss_infighting_missing"
    end
    if type(services.inject_breed_category_mask) ~= "function" then
        return nil, "category_injector_missing"
    end
    local wrapped, wrap_reason = M.wrap_chosen_lifecycle(breed, services)
    if not wrapped then return nil, wrap_reason end
    breed.name = spec.name
    breed.display_name = spec.display_name_key
    local health = {}
    for i = 1, spec.difficulty_count do health[i] = spec.max_health end
    breed.max_health = health
    breed.boss = true
    breed.elite = nil
    breed.boss_staggers = true
    breed.show_health_bar = true
    breed.far_off_despawn_immunity = true
    breed.threat_value = spec.threat_value
    breed.infighting = services.boss_infighting
    breed.default_inventory_template = spec.inventory_template
    local category_ok, category_error = pcall(
        services.inject_breed_category_mask, breed)
    if not category_ok then
        return nil, "category_injector_threw:" .. tostring(category_error)
    end
    if type(breed.category_mask) ~= "number" then
        return nil, "category_mask_missing"
    end
    return breed
end

function M.inspect(context)
    context = type(context) == "table" and context or {}
    local breeds = type(context.breeds) == "table" and context.breeds or {}
    local actions = type(context.actions) == "table" and context.actions or {}
    local behaviors = type(context.behaviors) == "table" and context.behaviors or {}
    local inventories = type(context.inventories) == "table" and context.inventories or {}
    local lookup = type(context.breed_lookup) == "table" and context.breed_lookup or {}
    local resident = type(context.unit_resident) == "function" and context.unit_resident
        or function() return false end
    local result = { rows = {}, missing_breeds = 0, structure_ready = 0, resident_models = 0 }

    for _, candidate in ipairs(M.CANDIDATES) do
        local source = breeds[candidate.source_breed]
        local model = breeds[candidate.model_breed or candidate.source_breed]
        local source_present = type(source) == "table"
        local model_present = type(model) == "table"
        local base_unit = source_present and source.base_unit or nil
        local model_unit = model_present and model.base_unit or nil
        local behavior_key = source_present and source.behavior or nil
        local inventory_key = source_present and source.default_inventory_template or nil
        local row = {
            id = candidate.id,
            status = candidate.status,
            source_breed = candidate.source_breed,
            model_breed = candidate.model_breed or candidate.source_breed,
            source_present = source_present,
            model_present = model_present,
            base_unit = base_unit,
            model_unit = model_unit,
            actions_present = type(actions[candidate.source_breed]) == "table",
            behavior_present = type(behavior_key) == "string"
                and type(behaviors[behavior_key]) == "table",
            inventory_present = inventory_key == nil or type(inventories[inventory_key]) == "table",
            wire_present = lookup[candidate.source_breed] ~= nil,
            source_resident = type(base_unit) == "string" and resident(base_unit) or false,
            model_resident = type(model_unit) == "string" and resident(model_unit) or false,
        }
        row.structure_ready = row.source_present and row.model_present
            and row.actions_present and row.behavior_present
            and row.inventory_present and row.wire_present
        if not row.source_present or not row.model_present then
            result.missing_breeds = result.missing_breeds + 1
        end
        if row.structure_ready then result.structure_ready = result.structure_ready + 1 end
        if row.model_resident then result.resident_models = result.resident_models + 1 end
        result.rows[#result.rows + 1] = row
    end
    return result
end

return M
