-- Pure transaction policy for issue #1033.
--
-- DEFAULT on a WT/Cosmetics category must also replace the modded loadout
-- snapshot with the read-only official snapshot.  This intent is distinct
-- from changed settings: every setting may already equal its default while an
-- old modded loadout still contains a weapon/cosmetic that is no longer legal.
-- Keep the intent on the view until Apply completes successfully.
local M = {}

local LOADOUT_OWNERS = {
    cosmetics_tweaker = true,
    wt = true,
    wt_dev = true,
}

local function category_key(category)
    return category and category.mod_id or "?"
end

function M.affects_loadouts(category)
    if type(category) ~= "table" then return false end
    if LOADOUT_OWNERS[category.mod_id] then return true end
    for _, mod_id in ipairs(category._owner_mod_ids or {}) do
        if LOADOUT_OWNERS[mod_id] then return true end
    end
    return false
end

function M.arm(view, category)
    if type(view) ~= "table" or not M.affects_loadouts(category) then return false end
    view._official_reseed_pending = view._official_reseed_pending or {}
    view._official_reseed_pending[category_key(category)] = true
    return true
end

function M.is_armed(view, category)
    local pending = type(view) == "table" and view._official_reseed_pending
    return type(pending) == "table" and pending[category_key(category)] == true
end

-- Returns attempted, completed, error.  An incomplete settings transaction or
-- unavailable/failing reset owner retains the intent for a later Apply.
function M.finish(view, category, settings_complete, reset_loadouts)
    if not M.is_armed(view, category) then return false, false end
    if not settings_complete then return true, false, "settings transaction incomplete" end
    if type(reset_loadouts) ~= "function" then
        return true, false, "official loadout reset owner unavailable"
    end
    local ok, accepted, detail = pcall(reset_loadouts, "mod_tweaker_default")
    if not ok then return true, false, tostring(accepted) end
    if accepted == false then return true, false, tostring(detail or "reset rejected") end
    view._official_reseed_pending[category_key(category)] = nil
    return true, true
end

function M.clear(view)
    if type(view) == "table" then view._official_reseed_pending = nil end
end

return M
