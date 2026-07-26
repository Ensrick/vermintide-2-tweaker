-- Pure policy for Career Tweaker rework-family master controls (issue #445).
-- No engine globals: exercised by qa/lua/tests/test_crt_rework_master_policy.lua.

local M = {}

-- One metadata owner serves runtime policy, localization, and engine-free QA.
-- Keeping the player-facing attribution beside the setting-family matcher
-- prevents a new rework from joining a master catalog while missing its label.
M.FAMILIES = {
    ensrick = {
        master_id = "rework_master_ensrick",
        setting_prefix = "rework_",
        label_prefix = "[Ensrick]",
    },
    tourney = {
        master_id = "rework_master_tourney",
        setting_prefix = "trn_",
        label_prefix = "[TB]",
    },
}

M.MASTER_ENSRICK = M.FAMILIES.ensrick.master_id
M.MASTER_TOURNEY = M.FAMILIES.tourney.master_id
M.MASTER_ALL = "rework_master_all"

function M.family_for_setting(setting_id)
    if type(setting_id) ~= "string" then return nil end
    if setting_id == M.MASTER_ALL then return nil end
    for family, metadata in pairs(M.FAMILIES) do
        if setting_id ~= metadata.master_id
                and setting_id:sub(1, #metadata.setting_prefix) == metadata.setting_prefix then
            return family, metadata
        end
    end
    return nil
end

function M.is_leaf_localization_key(key)
    local family = M.family_for_setting(key)
    return family ~= nil
        and not key:find("_group$")
        and not key:find("_description$")
        and not key:find("_tooltip$")
end

function M.decorate_label(setting_id, text)
    local _, metadata = M.family_for_setting(setting_id)
    if not metadata or type(text) ~= "string" then return text end

    -- Normalize the superseded 0.3.69 suffix form as well as the current
    -- prefix. This makes the transform idempotent under localization reloads.
    text = text:gsub(" %[Ensrick's Reworks%]$", "")
    text = text:gsub(" %[Tourney Balance%]$", "")
    text = text:gsub("^%[Ensrick%]%s+", "")
    text = text:gsub("^%[Tourney Balance%]%s+", "")
    text = text:gsub("^%[TB%]%s+", "")
    return metadata.label_prefix .. " " .. text
end

-- Reconcile the two reversible owners without letting one engine restore a
-- stale snapshot over the other's newly-applied value. Tourney is the
-- lower-priority owner at exact conflicts, so restore it first, rebuild the
-- Ensrick owner, then apply only the non-conflicting Tourney leaves.
function M.reconcile_engines(balance, tourney)
    if tourney and type(tourney.restore) == "function" then tourney.restore() end
    if balance and type(balance.apply) == "function" then balance.apply() end
    if tourney and type(tourney.apply) == "function" then tourney.apply() end
end

-- Execute one family/all preset as a bounded transaction. The writer owns the
-- synchronous VMF callback guard; only after every desired setting is visible
-- do the reversible engines and cross-owner live-state reconciler each run once.
function M.apply_bounded_master(policy, family, enabled, current,
                                write_changes, reconcile, reconcile_live_state)
    local changes = policy:plan(family, enabled, current)
    if not write_changes(changes) then return false, changes end
    reconcile()
    reconcile_live_state()
    return true, changes
end

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

    -- Return only writes that differ from the current snapshot. A family
    -- master selects its complete family and clears the rival; the explicit
    -- "all" preset enables or clears both. Master flags are included so stock
    -- VMF and Mod Tweaker agree without per-leaf apply fanout.
    function policy:plan(family, enabled, current)
        current = current or {}
        local desired = {}
        if family == "all" then
            for i = 1, #self.ensrick_ids do desired[self.ensrick_ids[i]] = enabled and true or false end
            for i = 1, #self.tourney_ids do desired[self.tourney_ids[i]] = enabled and true or false end
            desired[M.MASTER_ENSRICK] = false
            desired[M.MASTER_TOURNEY] = false
            desired[M.MASTER_ALL] = enabled and true or false
        else
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
            desired[M.MASTER_ALL] = false
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
    -- Exactly one radio indicator is active: one complete family with the
    -- rival empty, or the all-master when both families are complete.
    function policy:derive_masters(current)
        current = current or {}
        local all_ensrick = all_equal(self.ensrick_ids, current, true)
        local all_tourney = all_equal(self.tourney_ids, current, true)
        return {
            [M.MASTER_ENSRICK] = all_ensrick and not all_tourney,
            [M.MASTER_TOURNEY] = all_tourney and not all_ensrick,
            [M.MASTER_ALL] = all_ensrick and all_tourney,
        }
    end

    return policy
end

return M
