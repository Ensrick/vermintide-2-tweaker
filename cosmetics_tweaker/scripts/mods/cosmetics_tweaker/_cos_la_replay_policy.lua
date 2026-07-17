-- Engine-free readiness policy for persisted Loremaster/offhand replay.
-- Player-unit existence is not sufficient: exact-item state cannot be emitted
-- until at least one weapon slot has realized item_data.

local Policy = {}

function Policy.inventory_ready(inventory)
    local equipment = type(inventory) == "table"
        and (inventory._equipment or inventory.equipment) or nil
    local slots = type(equipment) == "table" and equipment.slots or nil
    if type(slots) ~= "table" then return false end

    for _, slot_name in ipairs({ "slot_melee", "slot_ranged" }) do
        local slot = slots[slot_name]
        if type(slot) == "table" and type(slot.item_data) == "table" then
            return true
        end
    end

    return false
end

return Policy
