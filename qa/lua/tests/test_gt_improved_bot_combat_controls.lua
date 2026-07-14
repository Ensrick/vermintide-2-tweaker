return function(H, repo_root)
    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local root = repo_root .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/"
    local policy = dofile(root .. "_gt_improved_bot_combat_policy.lua")
    local data = read(root .. "general_tweaker_dev_data.lua")
    local source = read(root .. "_gt_improved_bot_combat.lua")

    H.test("GT improved combat master preserves prior bundled defaults", function()
        H.equal(policy.feature_enabled(false, true), false)
        H.equal(policy.feature_enabled(true, false), false)
        H.equal(policy.feature_enabled(true, true), true)
        H.equal(policy.feature_enabled(true, nil), true)
    end)

    H.test("GT improved combat distances stay in squared engine units", function()
        H.equal(policy.distance_sq(7.1, 4), 7.1 * 7.1)
        H.equal(policy.distance_sq(nil, 15), 225)
        H.equal(policy.distance_sq(-1, 15), 225)
    end)

    H.test("GT improved combat exposes every requested control family", function()
        local ids = {
            "gt_ibc_smarter_attacks", "gt_ibc_ping_attackers",
            "gt_ibc_limit_special_chase", "gt_ibc_special_chase_distance",
            "gt_ibc_ignore_distant_gunners", "gt_ibc_gunner_cover_distance",
            "gt_ibc_limit_boss_focus", "gt_ibc_boss_engage_distance",
            "gt_ibc_ability_timing",
        }
        for _, id in ipairs(ids) do
            H.truthy(data:find('setting_id = "' .. id .. '"', 1, true)
                or data:find('setting_id      = "' .. id .. '"', 1, true), id)
            H.truthy(source:find(id, 1, true), id .. " is not wired")
        end
        H.truthy(data:find("sub_widgets", 1, true))
    end)
end
