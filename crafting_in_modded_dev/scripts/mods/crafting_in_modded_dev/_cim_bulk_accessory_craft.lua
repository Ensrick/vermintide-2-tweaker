local M = {}

local SLOTS = {
    "slot_ring",
    "slot_necklace",
    "slot_trinket_1",
}

function M.craft_all(craft_one)
    if type(craft_one) ~= "function" then
        return 0
    end

    local crafted = 0
    for slot_index, slot_name in ipairs(SLOTS) do
        if craft_one(slot_index, slot_name) then
            crafted = crafted + 1
        end
    end
    return crafted
end

return M
