-- _dcp_score_record.lua -- Pure score-record cosmetic resolution for issue #435.
--
-- End-of-round records already contain each subject's resolved skin and hat.
-- This module owns the deterministic skin-first lookup and subject label so
-- the runtime hook and engine-free regression test share one implementation.
--
-- Owned by: dynamic_cosmetic_portraits.lua entry point. Consumed via: mod:dofile.

local M = {}

function M.resolve_portrait_set(record, skin_portrait_map, hat_portrait_map)
    if type(record) ~= "table"
            or type(skin_portrait_map) ~= "table"
            or type(hat_portrait_map) ~= "table" then
        return nil
    end

    local skin_key = record.hero_skin
    if type(skin_key) == "string" then
        local skin_set = skin_portrait_map[skin_key]
        if skin_set then return skin_set end
    end

    local hat = record.hat
    local hat_key = type(hat) == "table" and hat.item_name
    if type(hat_key) == "string" then
        return hat_portrait_map[hat_key]
    end

    return nil
end

function M.subject(record)
    if type(record) ~= "table" then return "unknown" end
    local kind = record.is_player_controlled and "remote" or "bot"
    return kind .. ":" .. tostring(record.local_player_id or "?")
end

return M
