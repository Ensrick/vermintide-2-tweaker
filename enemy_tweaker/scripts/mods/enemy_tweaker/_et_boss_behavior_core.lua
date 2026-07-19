-- Pure policy for issue #450's runtime boss behavior controls.
-- Engine-facing code supplies live state; this module owns the closed gate so
-- the one-shot threshold can be regression-tested under Lua 5.1.

local M = {}

M.CATACLYSM_RANK = 6
M.HALESCOURGE_THRESHOLD = 0.5
M.HALESCOURGE_BREED = "chaos_exalted_sorcerer"
M.HALESCOURGE_LEVEL = "ground_zero"
M.HALESCOURGE_MONSTERS = { "chaos_troll", "chaos_spawn" }
M.SKARRIK_BREED = "skaven_storm_vermin_warlord"
M.SKARRIK_RANGED_DAMAGE_MULTIPLIER = 0.70
M.DEATHRATTLER_BREED = "skaven_stormfiend_boss"
M.DEATHRATTLER_TRACKING_MULTIPLIER = 0.50

function M.halescourge_gate(state)
    state = state or {}
    if state.triggered then return false, "already_triggered" end
    if not state.enabled then return false, "disabled" end
    if not state.is_server then return false, "not_server" end
    if state.game_mode ~= "adventure" then return false, "not_adventure" end
    if state.level_key ~= M.HALESCOURGE_LEVEL then return false, "wrong_level" end
    if type(state.difficulty_rank) ~= "number"
            or state.difficulty_rank < M.CATACLYSM_RANK then
        return false, "below_cataclysm"
    end
    if not state.in_boss_arena then return false, "outside_boss_arena" end
    if type(state.health_percent) ~= "number" then return false, "health_missing" end
    if state.health_percent <= 0 then return false, "boss_dead" end
    if state.health_percent > M.HALESCOURGE_THRESHOLD then return false, "above_threshold" end
    return true, "ready"
end

function M.monster_for_roll(roll)
    local count = #M.HALESCOURGE_MONSTERS
    if type(roll) ~= "number" then return nil end
    local index = math.floor(roll)
    if index < 1 or index > count then return nil end
    return M.HALESCOURGE_MONSTERS[index]
end

function M.skarrik_ranged_damage(damage, enabled, is_skarrik, is_ranged)
    damage = tonumber(damage)
    if not damage or damage <= 0 or not enabled or not is_skarrik or not is_ranged then
        return damage
    end
    return damage * M.SKARRIK_RANGED_DAMAGE_MULTIPLIER
end

function M.deathrattler_tracking_dt(dt, enabled, is_deathrattler, is_ratling)
    dt = tonumber(dt)
    if not dt or dt <= 0 or not enabled or not is_deathrattler or not is_ratling then
        return dt
    end
    return dt * M.DEATHRATTLER_TRACKING_MULTIPLIER
end

function M.deathrattler_rotation_time(seconds, enabled)
    seconds = tonumber(seconds)
    if not seconds or seconds < 0 or not enabled then return seconds end
    return seconds * M.DEATHRATTLER_TRACKING_MULTIPLIER
end

return M
