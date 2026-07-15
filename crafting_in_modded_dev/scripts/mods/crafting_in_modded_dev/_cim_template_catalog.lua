-- Pure builder for standard-forge acquisition selectors.
--
-- The UI row is deliberately not an owned backend item. It retains an exact
-- reference to the registered ItemMasterList definition so icons, models,
-- skin families, and future metadata remain owned by the weapon provider.
-- Kept engine-free for exhaustive catalog regression coverage.

local M = {}

local function _contains(values, wanted)
    if type(values) ~= "table" then return false end
    for _, value in ipairs(values) do
        if value == wanted then return true end
    end
    return false
end

function M.build(args)
    args = args or {}
    local item_master_list = args.item_master_list
    local career_name = args.career_name
    local craftable_slot_types = args.craftable_slot_types or {}
    local base_power = tonumber(args.base_power) or 5
    local requires_unowned_dlc = args.requires_unowned_dlc or function() return false end
    local versus_shadowed = args.versus_shadowed or function() return false end
    local real_names = args.real_names
    local cache = {}
    local report = { total = 0, cwv = 0 }

    if type(item_master_list) ~= "table" or type(career_name) ~= "string" then
        return cache, report
    end

    for key, data in pairs(item_master_list) do
        if type(data) == "table"
            and data.slot_type and craftable_slot_types[data.slot_type]
            and _contains(data.can_wield, career_name)
            and data.item_type ~= "weapon_skin"
            and data.rarity ~= "magic" and data.rarity ~= "promo"
            and not requires_unowned_dlc(key)
            and not versus_shadowed(data, real_names) then
            local bid = "cim_template_" .. key
            cache[bid] = {
                backend_id = bid,
                cim_acquisition_template = true,
                cim_acquisition_key = key,
                key = key,
                ItemId = key,
                ItemInstanceId = bid,
                rarity = "default",
                data = data,
                properties = {},
                traits = {},
                power_level = base_power,
                CustomData = {
                    power_level = tostring(base_power),
                    rarity = "default",
                    properties = "{}",
                    traits = "[]",
                },
            }
            report.total = report.total + 1
            if data.cwv_definition == true then report.cwv = report.cwv + 1 end
        end
    end

    return cache, report
end

return M
