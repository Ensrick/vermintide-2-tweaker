-- Pure end-score minimum policy for issue #1151.
local M = {}

local function minimum_numeric(scores)
    local minimum
    local count = 0
    if type(scores) ~= "table" then return nil, count end
    for _, score in pairs(scores) do
        if type(score) == "number" then
            count = count + 1
            minimum = minimum == nil and score or math.min(minimum, score)
        end
    end
    return minimum, count
end

function M.repair(score_panel_scores)
    local changed = {}
    if type(score_panel_scores) ~= "table" then return changed end
    for _, group in pairs(score_panel_scores) do
        if type(group) == "table" then
            for _, row in ipairs(group) do
                if type(row) == "table" and row.stat_name == "damage_taken" then
                    local minimum, count = minimum_numeric(row.player_scores)
                    if minimum ~= nil and row.highscore ~= minimum then
                        changed[#changed + 1] = {
                            old = row.highscore,
                            new = minimum,
                            count = count,
                        }
                        row.highscore = minimum
                    end
                end
            end
        end
    end
    return changed
end

return M
