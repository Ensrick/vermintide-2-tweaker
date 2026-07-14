-- Pure independent bot-coin policy for issue #466.
local M = {}

local function amount(value)
    value = tonumber(value)
    if not value or value ~= value or value < 0 then return 0 end
    return math.floor(value)
end

function M.credit(balance, earned)
    return amount(balance) + amount(earned)
end

function M.charge(balance, cost)
    balance, cost = amount(balance), amount(cost)
    if balance < cost then return false, balance end
    return true, balance - cost
end

function M.weapon_cost(cost_settings, chest_type, current_rarity, target_rarity, fallback)
    local chest = cost_settings and cost_settings.deus_chest
    local by_type = chest and chest[chest_type]
    local by_current = type(by_type) == "table" and by_type[current_rarity]
    local resolved = type(by_current) == "table" and by_current[target_rarity]
    if type(resolved) == "number" then return amount(resolved) end
    return amount(fallback)
end

function M.shop_boon_cost(cost_settings, rarity, discount)
    local shop = cost_settings and cost_settings.shop
    local base = shop and shop.power_ups and shop.power_ups[rarity]
    base = amount(base)
    discount = tonumber(discount) or 0
    if discount < 0 then discount = 0 elseif discount > 1 then discount = 1 end
    return amount(base - math.floor(base * discount + 0.5))
end

function M.grant_cost(source, altar_cost)
    -- A boon altar grant is the only untagged present=true grant in the audited
    -- vanilla call map. Chest of Trials and end-of-level rewards are free.
    if source == "boon_altar" then return amount(altar_cost) end
    return 0
end

return M
