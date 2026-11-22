-- WP-WT-05: computed 3P animation coverage for every non-native cross-career
-- pair in weapon_unlock_map. For each pair the real Unit.animation_event funnel
-- (qa/lua/fixtures/wt_anim_funnel_env.lua) fires the wield event and every
-- event the weapon's template fires on the 3P body (fixture
-- qa/lua/tests/fixtures/wt_anim_vocab.lua, generated from the decompiled
-- weapon templates by qa/lua/fixtures/gen_wt_anim_vocab.lua). A row
-- `group|weapon|event|delivered` is reported for every call whose delivered
-- event is outside the receiver group's native vocabulary V(group), or that
-- delivered nothing.
--
-- V(group) is a PROXY: the union of events the native weapons of the group's
-- careers fire (from _wt_native_weapon_ownership.lua). It proves the hero's
-- skeleton authors the event under some native weapon, not that it plays
-- correctly in the chosen stance; that stays a visual (class V) question. The
-- rig cases qa/runtime/wt/issue_948_anim_targets_<hero>.lua check existence on
-- the real skeletons.
--
-- The test fails when a row appears that is not in the baseline
-- qa/lua/tests/fixtures/wt_anim_coverage_baseline.txt, and when a baseline row
-- no longer occurs. Set WT_ANIM_COVERAGE_OUT to a path to write the fresh rows
-- (review, then copy over the baseline for an intended change).

return function(H, repo_root)
    local load_env = dofile(repo_root .. "/qa/lua/fixtures/wt_anim_funnel_env.lua")
    local wt_root = repo_root .. "/weapon_tweaker/scripts/mods/weapon_tweaker/"
    local vocab = dofile(repo_root .. "/qa/lua/tests/fixtures/wt_anim_vocab.lua")
    local unlock = dofile(wt_root .. "wt_unlock_data.lua")
    local native = dofile(wt_root .. "_wt_native_weapon_ownership.lua")
    local wield_patches = dofile(wt_root .. "wt_wield_patches.lua")
    local baseline_path = repo_root .. "/qa/lua/tests/fixtures/wt_anim_coverage_baseline.txt"

    local groups = {
        { name = "es", careers = { "es_mercenary", "es_huntsman", "es_knight", "es_questingknight" } },
        { name = "dr", careers = { "dr_ranger", "dr_ironbreaker", "dr_slayer", "dr_engineer" } },
        { name = "we", careers = { "we_waywatcher", "we_maidenguard", "we_shade", "we_thornsister" } },
        { name = "wh", careers = { "wh_captain", "wh_bountyhunter", "wh_zealot" } },
        { name = "wh_priest", careers = { "wh_priest" } },
        { name = "bw", careers = { "bw_adept", "bw_scholar", "bw_unchained", "bw_necromancer" } },
    }

    local function sorted_keys(t)
        local keys = {}
        for k in pairs(t or {}) do keys[#keys + 1] = k end
        table.sort(keys)
        return keys
    end

    local function lookup(catalog, template, career)
        local row = catalog and catalog[template]
        return row and row[career]
    end

    local function native_vocab(group)
        local v = {}
        for _, weapon in ipairs(sorted_keys(vocab.item_template)) do
            for _, career in ipairs(group.careers) do
                if native.is_native(career, weapon) then
                    local tpl = vocab.templates[vocab.item_template[weapon]]
                    for event in pairs(tpl and tpl.events or {}) do v[event] = true end
                end
            end
        end
        return v
    end

    local function compute()
        local rows, missing_template = {}, {}
        for _, group in ipairs(groups) do
            local V = native_vocab(group)
            local env = load_env(repo_root, function(_, event) return V[event] == true end)
            local current
            local function rec(_, event) current[#current + 1] = event end
            for _, career in ipairs(group.careers) do
                for _, weapon in ipairs(unlock.weapon_unlock_map[career] or {}) do
                    if not native.is_native(career, weapon) then
                        local t = vocab.item_template[weapon]
                        local tpl = t and vocab.templates[t]
                        if not tpl then
                            missing_template[weapon] = true
                        else
                            local unit = { career = career }
                            env.husk_wield(function() end, {
                                _unit = unit,
                                _equipment = { slots = { slot_melee = { item_data = {
                                    key = weapon, template = t } } } },
                            }, "slot_melee")
                            local wield = lookup(wield_patches.patches, t, career)
                                or lookup(wield_patches.bulk, t, career) or tpl.wield
                            local events = { wield }
                            for _, event in ipairs(sorted_keys(tpl.events)) do events[#events + 1] = event end
                            for _, event in ipairs(events) do
                                if event then
                                    current = {}
                                    env.anim(rec, unit, event)
                                    local bad = #current == 0
                                    for _, d in ipairs(current) do
                                        if not V[d] then bad = true end
                                    end
                                    if bad then
                                        rows[group.name .. "|" .. weapon .. "|" .. event .. "|"
                                            .. table.concat(current, ",")] = true
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        return sorted_keys(rows), sorted_keys(missing_template)
    end

    local function read_lines(path)
        local f = io.open(path, "rb")
        if not f then return nil end
        local text = f:read("*a"):gsub("\r\n", "\n")
        f:close()
        local out = {}
        for line in text:gmatch("([^\n]*)\n") do
            if line ~= "" then out[#out + 1] = line end
        end
        return out
    end

    H.test("WT cross-career 3P coverage matches the computed baseline", function()
        local rows, missing = compute()
        H.equal(#missing, 0, "weapons without a vocab template: " .. table.concat(missing, ","))
        local out_path = os.getenv("WT_ANIM_COVERAGE_OUT")
        if out_path and out_path ~= "" then
            local f = assert(io.open(out_path, "wb"))
            f:write(table.concat(rows, "\n") .. "\n")
            f:close()
        end
        local baseline = read_lines(baseline_path)
        H.truthy(baseline ~= nil, "missing baseline " .. baseline_path)
        local have, want = {}, {}
        for _, row in ipairs(rows) do have[row] = true end
        for _, row in ipairs(baseline) do want[row] = true end
        local new_rows, gone_rows = {}, {}
        for _, row in ipairs(rows) do if not want[row] then new_rows[#new_rows + 1] = row end end
        for _, row in ipairs(baseline) do if not have[row] then gone_rows[#gone_rows + 1] = row end end
        if #new_rows > 0 or #gone_rows > 0 then
            error(string.format("coverage changed: %d new row(s), first %s; %d baseline row(s) gone, first %s",
                #new_rows, tostring(new_rows[1]), #gone_rows, tostring(gone_rows[1])), 0)
        end
    end)
end
