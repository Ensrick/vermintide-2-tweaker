local mod = get_mod("gt_dev")
local policy = mod._gt_bot_hazard_policy
local _printf = rawget(_G, "printf") or function() end

-- Weak unit keys prevent bot replacements/transitions from retaining a ledger.
local ledgers = setmetatable({}, { __mode = "k" })
local log_records = 0
local MAX_LOG_RECORDS = 16 -- four bots x two types x first/full observations

local function game_time()
    local managers = rawget(_G, "Managers")
    local time = managers and managers.time
    if not time or type(time.time) ~= "function" then return nil end
    local ok, value = pcall(time.time, time, "game")
    return ok and value or nil
end

function mod._gt488_scale_bot_hazard_damage(damage, attacked_unit, damage_source, damage_type)
    local managers = rawget(_G, "Managers")
    local players = managers and managers.player
    if not (players and players.is_server) then return damage end
    if mod:get("gt_bot_behavior_improvements") ~= true
        or mod:get("gt_bot_hazard_resistance") ~= true then return damage end
    if not mod._gt_unit_is_bot(attacked_unit) then return damage end

    local hazard = policy.classify(damage_source, damage_type)
    if not hazard then return damage end
    local now = game_time()
    if not now then return damage end

    local ledger = ledgers[attacked_unit]
    if not ledger then ledger = {}; ledgers[attacked_unit] = ledger end
    local scaled, before, after = policy.apply_hit(ledger, hazard, damage, now)
    local marker = before == 0 and "first" or after == policy.MAX_STACKS and "full" or nil
    ledger._logged = ledger._logged or {}
    local log_key = marker and hazard .. ":" .. marker or nil
    if log_key and not ledger._logged[log_key] and log_records < MAX_LOG_RECORDS then
        ledger._logged[log_key] = true
        log_records = log_records + 1
        pcall(_printf,
            "[gt:488] bot-hazard type=%s milestone=%s active_before=%d active_after=%d damage_in=%.3f damage_out=%.3f record=%d/%d",
            hazard, marker, before, after, damage, scaled, log_records, MAX_LOG_RECORDS)
    end
    return scaled
end

mod._GT_488_HAZARD_MARKER = "gt-488-bot-hazard-resistance-v1"

return { policy = policy }
