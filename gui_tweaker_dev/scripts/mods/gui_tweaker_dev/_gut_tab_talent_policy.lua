-- Pure tier normalization for Chaos Wastes held-Tab talents (#250).
local Policy = { TIERS = 6, MAX_LOGS = 16 }

local function talent_id(entry)
    if type(entry) == "table" then
        return entry.talent_id
    end
    return nil
end

function Policy.tier_lookup(talent_tree, id_lookup)
    local by_id = {}
    if type(talent_tree) ~= "table" or type(id_lookup) ~= "table" then
        return by_id
    end

    for tier = 1, Policy.TIERS do
        for _, name in ipairs(talent_tree[tier] or {}) do
            local id = talent_id(id_lookup[name])
            if id ~= nil then
                by_id[id] = tier
            end
        end
    end
    return by_id
end

function Policy.normalize(talent_ids, talent_tree, id_lookup)
    local normalized = {}
    local duplicates = 0
    local unmapped = 0
    local by_id = Policy.tier_lookup(talent_tree, id_lookup)

    for _, id in ipairs(type(talent_ids) == "table" and talent_ids or {}) do
        local tier = by_id[id]
        if not tier then
            unmapped = unmapped + 1
        elseif normalized[tier] == nil then
            -- Deus inserts the initial loadout power-ups before purchased/event
            -- boons. Retaining the first ID therefore preserves the chosen build
            -- when a later boon grants another talent in the same tier.
            normalized[tier] = id
        else
            duplicates = duplicates + 1
        end
    end

    return normalized, duplicates, unmapped
end

function Policy.needs_repair(original, normalized)
    for tier = 1, Policy.TIERS do
        if original[tier] ~= normalized[tier] then
            return true
        end
    end
    return false
end

function Policy.fingerprint(ids)
    local parts = {}
    for tier = 1, Policy.TIERS do
        parts[tier] = tostring(ids[tier] or 0)
    end
    return table.concat(parts, ",")
end

return Policy
