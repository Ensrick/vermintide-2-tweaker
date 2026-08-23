-- _dcp_portrait_resolver.lua -- Pure per-subject cosmetic resolution.
--
-- Live Player objects and end-of-round score records expose their cosmetic
-- identity through different adapters. This module owns the common,
-- deterministic skin-first lookup so both render paths share one policy.
--
-- Owned by: dynamic_cosmetic_portraits.lua entry point. Consumed via: mod:dofile.

local M = {}

function M.resolve_keys(skin_key, hat_key, skin_portrait_map, hat_portrait_map)
    if type(skin_portrait_map) ~= "table"
            or type(hat_portrait_map) ~= "table" then
        return nil
    end

    if type(skin_key) == "string" then
        local skin_set = skin_portrait_map[skin_key]
        if skin_set then return skin_set end
    end

    if type(hat_key) == "string" then
        return hat_portrait_map[hat_key]
    end

    return nil
end

function M.resolve_score_record(record, skin_portrait_map, hat_portrait_map)
    if type(record) ~= "table" then return nil end
    local hat = record.hat
    local hat_key = type(hat) == "table" and hat.item_name
    return M.resolve_keys(record.hero_skin, hat_key,
        skin_portrait_map, hat_portrait_map)
end

return M
