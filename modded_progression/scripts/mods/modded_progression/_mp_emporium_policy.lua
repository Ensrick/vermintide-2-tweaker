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
