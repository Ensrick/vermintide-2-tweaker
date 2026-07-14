-- Pure boon-tier and shrine-price census for issue #467.
local M = {}

local RARITY_ORDER = { event = 1, rare = 2, exotic = 3, unique = 4 }

local function boon_name(entry)
    if type(entry) == "string" then return entry end
    if type(entry) ~= "table" then return nil end
    return entry.name or entry[1]
end

function M.audit(array_by_rarity, price_by_rarity, templates, max_records)
    max_records = math.max(0, math.floor(tonumber(max_records) or 192))
    local result = {
        records = {},
        counts = {},
        anomalies = {},
        total = 0,
        truncated = 0,
    }
    local seen = {}

    for rarity, bucket in pairs(array_by_rarity or {}) do
        local price = price_by_rarity and price_by_rarity[rarity]
        if type(price) ~= "number" then
            result.anomalies[#result.anomalies + 1] = "missing_price:" .. tostring(rarity)
        end
        if type(bucket) == "table" then
            for _, entry in ipairs(bucket) do
                local name = boon_name(entry)
                if type(name) == "string" and name ~= "" then
                    result.total = result.total + 1
                    result.counts[rarity] = (result.counts[rarity] or 0) + 1
                    if seen[name] and seen[name] ~= rarity then
                        result.anomalies[#result.anomalies + 1] = string.format(
                            "multi_rarity:%s:%s:%s", name, tostring(seen[name]), tostring(rarity))
                    else
                        seen[name] = rarity
                    end
                    if not (templates and templates[name]) then
                        result.anomalies[#result.anomalies + 1] = "missing_template:" .. name
                    end
                    if #result.records < max_records then
                        result.records[#result.records + 1] = {
                            name = name,
                            rarity = rarity,
                            shop_price = type(price) == "number" and math.floor(price) or nil,
                            display_key = templates and templates[name] and templates[name].display_name or nil,
                            description_key = templates and templates[name]
                                and templates[name].advanced_description or nil,
                        }
                    else
                        result.truncated = result.truncated + 1
                    end
                end
            end
        end
    end

    table.sort(result.records, function(a, b)
        local ao = RARITY_ORDER[a.rarity] or 99
        local bo = RARITY_ORDER[b.rarity] or 99
        if ao ~= bo then return ao < bo end
        return a.name < b.name
    end)
    table.sort(result.anomalies)
    return result
end

function M.validate_plan(plan, known_names)
    local errors = {}
    for name, change in pairs(plan or {}) do
        if type(name) ~= "string" or not (known_names and known_names[name]) then
            errors[#errors + 1] = "unknown_boon:" .. tostring(name)
        elseif type(change) ~= "table" then
            errors[#errors + 1] = "invalid_change:" .. name
        else
            if change.rarity ~= nil and not RARITY_ORDER[change.rarity] then
                errors[#errors + 1] = "invalid_rarity:" .. name .. ":" .. tostring(change.rarity)
            end
            if change.price ~= nil and (type(change.price) ~= "number"
                or change.price ~= change.price or change.price < 0
                or change.price ~= math.floor(change.price)) then
                errors[#errors + 1] = "invalid_price:" .. name
            end
        end
    end
    table.sort(errors)
    return #errors == 0, errors
end

return M
