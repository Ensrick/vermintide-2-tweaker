-- _gut_mission_vote_policy.lua -- pure classification for the #700 HUD vote bridge.
--
-- The vanilla game-settings vote is intentionally marked non-ingame because it
-- normally runs in the keep's Start Game view. GUT reuses that same vote while an
-- Adventure mission is live, so only that exact context needs the HUD voter UI.
--
-- Owned by: _gut_mission_map.lua. Consumed via: mod:dofile and offline Lua tests.

local Policy = {}

-- IngameVotingUI only calls Localize(vote_template.text) when a title modifier
-- exists. game_settings_vote has no modifier because its normal keep UI
-- localizes the title itself, so promoting that template verbatim exposes the
-- internal key ("game_settings_vote") in the in-mission HUD.
function Policy.localized_title_passthrough(localized_title)
    return localized_title
end

function Policy.promote_template(template)
    if type(template) ~= "table" then
        return nil
    end

    local promoted = {}
    for key, value in pairs(template) do
        promoted[key] = value
    end

    promoted.ingame_vote = true
    if type(promoted.modify_title_text) ~= "function" then
        promoted.modify_title_text = Policy.localized_title_passthrough
    end

    return promoted
end

function Policy.needs_ingame_hud(vote_name, mechanism, level_key, is_in_inn)
    return vote_name == "game_settings_vote"
        and mechanism == "adventure"
        and type(level_key) == "string"
        and level_key ~= "inn_level"
        and not is_in_inn
end

return Policy
