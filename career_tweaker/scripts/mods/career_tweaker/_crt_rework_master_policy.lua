-- Pure policy for Career Tweaker rework-family master controls (issue #445).
-- No engine globals: exercised by qa/lua/tests/test_crt_rework_master_policy.lua.

local M = {}

M.MASTER_ENSRICK = "rework_master_ensrick"
M.MASTER_TOURNEY = "rework_master_tourney"

local function sorted_ids(source)
    local ids, seen = {}, {}
    for key, value in pairs(source or {}) do
        local id = type(key) == "number" and value or key
        if type(id) == "string" and not seen[id] then
            seen[id] = true
            ids[#ids + 1] = id
        end
    end
    table.sort(ids)
    return ids
end

local function all_equal(ids, current, expected)
    if #ids == 0 then return false end
    for i = 1, #ids do
        if (current[ids[i]] and true or false) ~= expected then return false end
    end
    return true
end

function M.new(ensrick_source, tourney_source)
    local policy = {
        ensrick_ids = sorted_ids(ensrick_source),
        tourney_ids = sorted_ids(tourney_source),
        members = {},
    }
    for i = 1, #policy.ensrick_ids do policy.members[policy.ensrick_ids[i]] = "ensrick" end
    for i = 1, #policy.tourney_ids do policy.members[policy.tourney_ids[i]] = "tourney" end

    function policy:is_member(setting_id)
        return self.members[setting_id]
    end

    -- Return only writes that differ from the current snapshot. Enabling one
    -- master turns its complete family on and the rival family off. Disabling
    -- a master clears only its own family, preserving the other family/custom
    -- state. Master flags are included so stock VMF and Mod Tweaker agree.
    function policy:plan(family, enabled, current)
        current = current or {}
        local desired = {}
        local own = family == "ensrick" and self.ensrick_ids or self.tourney_ids
        local rival = family == "ensrick" and self.tourney_ids or self.ensrick_ids
        local own_master = family == "ensrick" and M.MASTER_ENSRICK or M.MASTER_TOURNEY
        local rival_master = family == "ensrick" and M.MASTER_TOURNEY or M.MASTER_ENSRICK

        for i = 1, #own do desired[own[i]] = enabled and true or false end
        desired[own_master] = enabled and true or false
        if enabled then
            for i = 1, #rival do desired[rival[i]] = false end
            desired[rival_master] = false
        end

        local changes = {}
        for id, value in pairs(desired) do
            if (current[id] and true or false) ~= value then
                changes[#changes + 1] = { id = id, value = value }
            end
        end
        table.sort(changes, function(a, b) return a.id < b.id end)
        return changes
    end

    -- An individual leaf edit makes the controls reflect the exact state.
    -- "Master on" means the complete family is enabled and its rival is empty;
    -- partial/custom selections intentionally show both masters off.
    function policy:derive_masters(current)
        current = current or {}
        local ensrick = all_equal(self.ensrick_ids, current, true)
            and all_equal(self.tourney_ids, current, false)
        local tourney = all_equal(self.tourney_ids, current, true)
            and all_equal(self.ensrick_ids, current, false)
        return {
            [M.MASTER_ENSRICK] = ensrick and true or false,
            [M.MASTER_TOURNEY] = tourney and true or false,
        }
    end

    return policy
end

return M
