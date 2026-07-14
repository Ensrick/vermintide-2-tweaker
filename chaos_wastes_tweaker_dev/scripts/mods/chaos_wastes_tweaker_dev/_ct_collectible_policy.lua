-- Pure identity policy for Adventure collectibles inside a Chaos Wastes run.
-- The caller owns realm/authority detection; this module only decides and
-- builds an immutable network-spawn rewrite (#351).
local M = {}

M.CONVERT_TO_COIN = {
    loot_die = true,
    lorebook_page = true,
    painting_scrap = true,
}

function M.route_name(pickup_name, injected_adventure, authoritative)
    if not injected_adventure then return pickup_name, false, "not_injected_adventure" end
    if not authoritative then return pickup_name, false, "not_authoritative" end
    if not M.CONVERT_TO_COIN[pickup_name] then return pickup_name, false, "not_collectible" end
    return "deus_soft_currency", true, "converted"
end

local function shallow_copy(source)
    local copy = {}
    for key, value in pairs(source or {}) do copy[key] = value end
    return copy
end

function M.rewrite_network_spawn(unit_name, unit_template_name, extension_init_data,
        coin_settings, injected_adventure, authoritative)
    local pickup_data = type(extension_init_data) == "table" and extension_init_data.pickup_system
    local original_name = type(pickup_data) == "table" and pickup_data.pickup_name
    local final_name, converted, reason = M.route_name(original_name,
        injected_adventure, authoritative)
    if not converted then
        return unit_name, unit_template_name, extension_init_data, false, original_name, reason
    end
    if type(coin_settings) ~= "table" or type(coin_settings.unit_name) ~= "string" then
        return unit_name, unit_template_name, extension_init_data, false, original_name,
            "coin_settings_missing"
    end

    local rewritten = shallow_copy(extension_init_data)
    rewritten.pickup_system = shallow_copy(pickup_data)
    rewritten.pickup_system.pickup_name = final_name
    return coin_settings.unit_name,
        coin_settings.unit_template_name or "pickup_unit",
        rewritten, true, original_name, reason
end

return M
