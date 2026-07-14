-- Engine-free asset/behavior contract for proposed bosses (#451).
local M = {}

M.CANDIDATES = {
    { id = "chosen_shield", source_breed = "chaos_raider", model_breed = "chaos_exalted_champion_warcamp", status = "prototype_required" },
    { id = "chosen_greataxe", source_breed = "chaos_raider", model_breed = "chaos_exalted_champion_warcamp", status = "prototype_required" },
    { id = "stormfiend_ratlings", source_breed = "skaven_stormfiend_boss", status = "arena_coupled" },
    { id = "skaven_warlock", source_breed = "skaven_grey_seer", status = "arena_coupled" },
    { id = "chaos_sorcerer", source_breed = "chaos_exalted_sorcerer", status = "arena_coupled" },
    { id = "troll_chieftain", source_breed = "chaos_troll_chief", status = "arena_coupled" },
}

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
