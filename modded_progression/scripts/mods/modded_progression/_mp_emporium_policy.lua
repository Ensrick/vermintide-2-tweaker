-- Pure offer validation for backend-free Silver Shilling purchases (#577).
local M = {}

function M.find_offer(stock, item_id)
    if type(item_id) ~= "string" then return nil end
    for _, offer in ipairs(stock or {}) do
        if type(offer) == "table" and offer.key == item_id then return offer end
    end
    return nil
end

function M.price(offer, currency)
    if type(offer) ~= "table" or type(currency) ~= "string" then return nil end
    local current = type(offer.current_prices) == "table" and offer.current_prices[currency]
    local regular = type(offer.regular_prices) == "table" and offer.regular_prices[currency]
    local value = tonumber(current or regular)
    if not value or value < 0 or value ~= math.floor(value) then return nil end
    return value
end

-- The native peddler stock is built from the official PlayFab mirror, so its
-- `owned` bit cannot be used as the ownership source for a separate modded
-- progression profile. Keep this predicate deliberately narrow: platform,
-- bundle, non-SM, and malformed offers continue to use vanilla ownership and
-- purchase behavior.
function M.is_local_offer(offer, currency)
    if type(offer) ~= "table" or type(offer.key) ~= "string"
            or type(offer.data) ~= "table" or currency ~= "SM" then
        return false
    end
    if offer.dlc_name or offer.steam_itemdefid then return false end
    if type(offer.data.bundle_contains) == "table"
            and next(offer.data.bundle_contains) ~= nil then
        return false
    end
    return M.price(offer, currency) ~= nil
end

function M.is_locally_owned(item_key, unlocks, inventory)
    if type(item_key) ~= "string" then return false end
    if type(unlocks) == "table" and unlocks[item_key] == true then return true end
    for _, item in pairs(type(inventory) == "table" and inventory or {}) do
        if type(item) == "table" and item.ItemId == item_key then return true end
    end
    return false
end

local function projected_offer(offer, currency, owned_fn)
    if not M.is_local_offer(offer, currency) then return offer end
    local copy = {}
    for key, value in pairs(offer) do copy[key] = value end
    copy.owned = type(owned_fn) == "function" and owned_fn(offer.key) == true or false
    return copy
end

-- Return a presentation-only stock projection. Never mutate the native stock:
-- the same peddler object is reused after transitions back to official play.
function M.project_stock(stock, currency, owned_fn)
    local projected = {}
    for index, offer in ipairs(type(stock) == "table" and stock or {}) do
        projected[index] = projected_offer(offer, currency, owned_fn)
    end
    return projected
end

function M.project_offer(offer, currency, owned_fn)
    return projected_offer(offer, currency, owned_fn)
end

-- Remove only a mirror row that MP inserted. Pre-existing rows belong to the
-- official account and must survive the transition back to official play.
function M.cleanup_overlay_record(mirror, record)
    if type(mirror) ~= "table" or type(record) ~= "table" or record.preexisting then
        return false
    end
    local id, key = record.actual_id, record.item_key
    if mirror._inventory_items then mirror._inventory_items[id] = nil end
    if mirror._fake_inventory_items then mirror._fake_inventory_items[id] = nil end
    if record.kind == "weapon_skin" and mirror._unlocked_weapon_skins then
        mirror._unlocked_weapon_skins[key] = nil
    elseif record.kind == "cosmetic" and mirror._unlocked_cosmetics then
        mirror._unlocked_cosmetics[key] = nil
    elseif record.kind == "weapon_pose" and mirror._unlocked_weapon_poses then
        local poses = mirror._unlocked_weapon_poses[record.parent]
        if poses then poses[key] = nil end
    end
    return true
end

function M.validate(args)
    args = args or {}
    local offer = args.offer
    if type(offer) ~= "table" or type(offer.key) ~= "string" then
        return nil, "offer_unavailable"
    end
    if args.currency ~= "SM" then return nil, "currency_not_local" end
    local price = M.price(offer, args.currency)
    if not price or price ~= tonumber(args.expected_price) then
        return nil, "price_mismatch"
    end
    if offer.dlc_name or offer.steam_itemdefid then return nil, "platform_offer" end
    if offer.owned or args.owned then return nil, "already_owned" end
    if args.available == false then return nil, "offer_unavailable" end
    if args.dlc_owned == false then return nil, "dlc_not_owned" end
    if type(offer.data) ~= "table" then return nil, "item_definition_missing" end
    if type(offer.data.bundle_contains) == "table" and next(offer.data.bundle_contains) ~= nil then
        return nil, "bundle_not_local"
    end
    local balance = math.floor(tonumber(args.balance) or 0)
    if balance < price then return nil, "insufficient_funds" end

    local tx_id = "mp_emporium:" .. offer.key
    -- Encode every byte so two unusual catalog keys cannot collapse onto the
    -- same persisted mirror id after punctuation replacement.
    local encoded_key = offer.key:gsub(".", function(char)
        return string.format("%02x", string.byte(char))
    end)
    local backend_id = "mp_emporium_" .. encoded_key
    return {
        tx_id = tx_id,
        item_key = offer.key,
        price = price,
        currency = args.currency,
        backend_id = backend_id,
        item = {
            ItemId = offer.key,
            ItemInstanceId = backend_id,
            UnitCurrency = args.currency,
            UnitPrice = price,
            CustomData = {},
        },
    }
end

return M
