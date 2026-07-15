-- _gut_loadout_slot_policy.lua
--
-- Pure saved-loadout slot validation policy for Tweaker: GUI dev.
--
-- Vanilla treats CareerSettings[career].item_slot_types_by_slot_name as the
-- authoritative capability map when validating backend gear.  Keep this
-- helper engine-free so the exact live-table contract can be covered offline.
-- In particular, do not cache or clone a career row: Career Tweaker can add or
-- remove Foot Knight's secondary-melee capability while the process is live.
--
-- Source provenance:
--   Vermintide-2-Source-Code/scripts/managers/backend_playfab/
--   playfab_mirror_base.lua:1662-1713 (_verify_items_are_usable)
--   playfab_mirror_base.lua:3387-3402 (_find_valid_item_for_slot)

local M = {}

local function _contains(values, wanted)
    if type(values) ~= "table" then
        return false
    end

    for i = 1, #values do
        if values[i] == wanted then
            return true
        end
    end

    return false
end

function M.accepted_slot_types(career_settings, career_name, slot_name)
    local career = type(career_settings) == "table" and career_settings[career_name]
    local slot_map = type(career) == "table" and career.item_slot_types_by_slot_name

    return type(slot_map) == "table" and slot_map[slot_name] or nil
end

-- Returns true when item_data is currently valid for career_name/slot_name.
-- The item table is never copied or rewritten; WT/CWV instances therefore keep
-- their exact backend identity and are judged by the same slot/can_wield data
-- as vanilla items.
function M.validate(item_data, slot_name, career_name, career_settings)
    if type(item_data) ~= "table" then
        return false, "item has no data"
    end

    local can_wield = item_data.can_wield
    if type(can_wield) == "table" and not _contains(can_wield, career_name) then
        return false, string.format("career %s cannot wield %s",
            tostring(career_name), tostring(item_data.display_name or "?"))
    end

    local accepted = M.accepted_slot_types(career_settings, career_name, slot_name)
    if type(accepted) ~= "table" then
        return false, string.format("career %s has no capability for slot %s",
            tostring(career_name), tostring(slot_name))
    end

    if _contains(accepted, item_data.slot_type) then
        return true
    end

    return false, string.format("slot_type mismatch (item=%s, slot=%s)",
        tostring(item_data.slot_type), tostring(slot_name))
end

return M
