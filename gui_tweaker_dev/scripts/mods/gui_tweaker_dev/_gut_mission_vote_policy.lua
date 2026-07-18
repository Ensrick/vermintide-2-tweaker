-- _gut_mission_vote_policy.lua -- pure classification for the #700 HUD vote bridge.
--
-- The vanilla game-settings vote is intentionally marked non-ingame because it
-- normally runs in the keep's Start Game view. GUT reuses that same vote while an
-- Adventure mission is live, so only that exact context needs the HUD voter UI.
--
-- Owned by: _gut_mission_map.lua. Consumed via: mod:dofile and offline Lua tests.

local Policy = {}

function Policy.needs_ingame_hud(vote_name, mechanism, level_key, is_in_inn)
    return vote_name == "game_settings_vote"
        and mechanism == "adventure"
        and type(level_key) == "string"
        and level_key ~= "inn_level"
        and not is_in_inn
end

return Policy
