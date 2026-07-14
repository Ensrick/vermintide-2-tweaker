-- Pure classifier for issue #393's settled high-intensity evidence.
-- Kept engine-free so both the in-game regression harness and external Lua QA
-- can exercise the decision rule without loading a mission.

local M = {}

local EXPECTED_INTENSITY = {
    { "max_intensity", 200 },
    { "decay_per_second", 10 },
    { "decay_delay", 0.5 },
    { "intensity_add_per_percent_dmg_taken", 0.1 },
}

local EXPECTED_DELAYS = {
    "delay_horde_threat_value",
    "delay_specials_threat_value",
    "delay_mini_patrol_threat_value",
}

local function contains(list, wanted)
    if type(list) ~= "table" then return false end
    for i = 1, #list do
        if list[i] == wanted then return true end
    end
    return false
end

local function resolved_delay(value)
    if type(value) == "table" then
        return value.normal
    end
    return value
end

function M.classify(injected, intensity, pacing, cached)
    if not contains(injected, "high_intensity") then
        return "not_injected", "high_intensity absent from event selection"
    end

    local mismatches = {}
    intensity = type(intensity) == "table" and intensity or {}
    pacing = type(pacing) == "table" and pacing or {}
    cached = type(cached) == "table" and cached or {}

    for i = 1, #EXPECTED_INTENSITY do
        local field, expected = EXPECTED_INTENSITY[i][1], EXPECTED_INTENSITY[i][2]
        if intensity[field] ~= expected then
            mismatches[#mismatches + 1] = field .. "=" .. tostring(intensity[field])
        end
    end
    for i = 1, #EXPECTED_DELAYS do
        local field = EXPECTED_DELAYS[i]
        if resolved_delay(pacing[field]) ~= 200 then
            mismatches[#mismatches + 1] = "global." .. field .. "=" .. tostring(resolved_delay(pacing[field]))
        end
        if cached[field] ~= 200 then
            mismatches[#mismatches + 1] = "cached." .. field .. "=" .. tostring(cached[field])
        end
    end

    if #mismatches > 0 then
        return "settings_stomp", table.concat(mismatches, ",")
    end
    return "intact", "vanilla high_intensity writes survived"
end

return M
