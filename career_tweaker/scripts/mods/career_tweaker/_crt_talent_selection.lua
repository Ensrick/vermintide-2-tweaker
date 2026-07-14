-- _crt_talent_selection.lua -- pure talent-row snapshot/comparison policy.
--
-- HeroWindowTalents and HeroWindowTalentsConsole both persist a table whose
-- numeric entries are the selected column for each talent row. Keeping this
-- helper engine-free makes the no-change boundary deterministic and testable.

local M = {}

function M.snapshot(selection)
    if type(selection) ~= "table" then return nil end
    local copy = {}
    for key, value in pairs(selection) do
        copy[key] = value
    end
    return copy
end

function M.equal(left, right)
    if type(left) ~= "table" or type(right) ~= "table" then return false end
    for key, value in pairs(left) do
        if right[key] ~= value then return false end
    end
    for key, value in pairs(right) do
        if left[key] ~= value then return false end
    end
    return true
end

return M
