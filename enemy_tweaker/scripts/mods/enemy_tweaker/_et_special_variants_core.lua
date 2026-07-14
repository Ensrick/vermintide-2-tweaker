-- _et_special_variants_core.lua -- pure issue #452 asset census.
--
-- The premium Versus skins are player cosmetic attachments, not AI breed base
-- units. This module only classifies the tables/assets a future custom-breed
-- implementation must compose. It performs no engine access or mutation.

local M = {}

-- AttachmentNodeLinking rows are an ordered list of { source, target } node
-- pairs. AttachmentUtils.link treats `source` as the owner unit and `target`
-- as the spawned attachment. Return a de-duplicated owner-node list so runtime
-- diagnostics can compare the premium mesh contract with a naturally spawned AI unit
-- without linking or spawning anything.
function M.owner_nodes(linking)
    local result, seen = {}, {}
    if type(linking) ~= "table" then return result end
    for i = 1, #linking do
        local row = linking[i]
        local source = type(row) == "table" and row.source or nil
        if type(source) == "string" and source ~= "" and not seen[source] then
            seen[source] = true
            result[#result + 1] = source
        end
    end
    return result
end

M.CANDIDATES = {
    {
        id = "bile_blight_globadier",
        base_breed = "skaven_poison_wind_globadier",
        skin = "skaven_wind_globadier_skin_1001",
        behavior_boundary = "new bile ground/camera effects and bounded networked curse-stack buff",
    },
    {
        id = "shadowskulk_gutter_runner",
        base_breed = "skaven_gutter_runner",
        skin = "skaven_gutter_runner_skin_1001",
        behavior_boundary = "proximity visibility state plus pounce/downed damage policy",
    },
    {
        id = "mist_runner_packmaster",
        base_breed = "skaven_pack_master",
        skin = "skaven_pack_master_skin_1001",
        behavior_boundary = "hook-state speed/hoist timing and explicit stagger immunity",
    },
    {
        id = "festerblight_warpfire_thrower",
        base_breed = "skaven_warpfire_thrower",
        skin = "skaven_warpfire_thrower_skin_1001",
        behavior_boundary = "portable lingering fire area, detonation radius, and super-armor data",
    },
    {
        id = "putrescent_kin_ratling_gunner",
        base_breed = "skaven_ratling_gunner",
        skin = "skaven_ratling_gunner_skin_1001",
        behavior_boundary = "burst duration, cone spread, stamina damage, and super-armor data",
    },
}

function M.audit(env)
    env = env or {}
    local rows = {}
    local missing = 0
    local resident = 0

    for i = 1, #M.CANDIDATES do
        local c = M.CANDIDATES[i]
        local breed = type(env.breeds) == "table" and env.breeds[c.base_breed] or nil
        local actions = type(env.actions) == "table" and env.actions[c.base_breed] or nil
        local item = type(env.items) == "table" and env.items[c.skin] or nil
        local cosmetic = type(env.cosmetics) == "table" and env.cosmetics[c.skin] or nil
        local attachment = cosmetic and cosmetic.third_person_attachment
        local unit = type(attachment) == "table" and attachment.unit or nil
        local linking = type(attachment) == "table" and attachment.attachment_node_linking or nil
        local owner_nodes = M.owner_nodes(linking)
        local behavior = type(breed) == "table" and breed.behavior or nil
        local inventory = type(breed) == "table" and breed.default_inventory_template or nil
        local base_unit = type(breed) == "table" and breed.base_unit or nil
        local behavior_present = type(behavior) == "string"
            and type(env.behaviors) == "table" and env.behaviors[behavior] ~= nil or false
        local inventory_present = type(inventory) == "string"
            and type(env.inventories) == "table" and env.inventories[inventory] ~= nil or false
        local wire_present = type(env.breed_lookup) == "table"
            and rawget(env.breed_lookup, c.base_breed) ~= nil or false
        local unit_resident
        if type(unit) == "string" and type(env.can_get_unit) == "function" then
            local ok, result = pcall(env.can_get_unit, unit)
            unit_resident = ok and result and true or false
        end

        local base_unit_resident
        if type(base_unit) == "string" and type(env.can_get_unit) == "function" then
            local ok, result = pcall(env.can_get_unit, base_unit)
            base_unit_resident = ok and result and true or false
        end

        local structure_ready = breed ~= nil and actions ~= nil and item ~= nil
            and cosmetic ~= nil and type(unit) == "string" and #owner_nodes > 0
            and behavior_present and inventory_present and wire_present
        if not structure_ready then missing = missing + 1 end
        if unit_resident then resident = resident + 1 end

        rows[#rows + 1] = {
            id = c.id,
            base_breed = c.base_breed,
            skin = c.skin,
            base_present = breed ~= nil,
            actions_present = actions ~= nil,
            item_present = item ~= nil,
            cosmetic_present = cosmetic ~= nil,
            attachment_unit = unit,
            unit_resident = unit_resident,
            base_unit = base_unit,
            base_unit_resident = base_unit_resident,
            behavior = behavior,
            behavior_present = behavior_present,
            inventory = inventory,
            inventory_present = inventory_present,
            wire_present = wire_present,
            linking_present = type(linking) == "table",
            owner_nodes = owner_nodes,
            owner_node_count = #owner_nodes,
            structure_ready = structure_ready,
            player_attachment = type(unit) == "string"
                and unit:find("/dark_pact_skins/", 1, true) ~= nil or false,
            behavior_boundary = c.behavior_boundary,
        }
    end

    return rows, {
        candidates = #M.CANDIDATES,
        missing = missing,
        resident = resident,
    }
end

return M
