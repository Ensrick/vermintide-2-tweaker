-- Issue #1151: vanilla initializes every end-score highscore to zero, then
-- computes Damage Taken with `min(0, score)`. Positive scores therefore never
-- replace zero and nobody receives the row's green-circle credit unless a
-- player took exactly no damage. Recompute only that row from the scores the
-- original method has already accumulated; all other scoreboard data remains
-- vanilla-owned.

local mod = get_mod("gut")
local Policy = mod:dofile(
    "scripts/mods/gui_tweaker/_gut_damage_taken_scoreboard_policy")
local diagnostic_count = 0
local DIAGNOSTIC_CAP = 8

mod:hook_safe("EndViewStateScore", "_group_scores_by_player_and_topic",
    function(self, score_panel_scores)
        local changed = Policy.repair(score_panel_scores)
        for _, change in ipairs(changed) do
            if diagnostic_count >= DIAGNOSTIC_CAP then break end
            diagnostic_count = diagnostic_count + 1
            pcall(printf,
                "[gut:1151] damage_taken minimum old=%s new=%s players=%d record=%d/%d",
                tostring(change.old), tostring(change.new), change.count,
                diagnostic_count, DIAGNOSTIC_CAP)
        end
    end)

return {
    policy = Policy,
    diagnostic_cap = DIAGNOSTIC_CAP,
    rt_checks = {
        {
            name = "issue1151_damage_taken_green_circle_minimum",
            fn = function()
                local rows = { offense = {
                    { stat_name = "damage_taken", highscore = 0,
                        player_scores = { 41, 19, 73 } },
                    { stat_name = "damage_dealt", highscore = 73,
                        player_scores = { 41, 19, 73 } },
                } }
                local changed = Policy.repair(rows)
                if rows.offense[1].highscore ~= 19 then
                    return "positive Damage Taken scores still collapse to zero"
                end
                if rows.offense[2].highscore ~= 73 then
                    return "non-Damage-Taken scoreboard row was mutated"
                end
                if #changed ~= 1 or DIAGNOSTIC_CAP > 8 then
                    return "repair receipt is missing or diagnostic cap is unbounded"
                end
            end,
        },
    },
}
