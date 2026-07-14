return function(H, repo_root)
    local path = repo_root .. "/modded_progression/scripts/mods/modded_progression/_mp_quest_boundary.lua"
    local Boundary = assert(loadfile(path))()

    H.test("MP quest surface excludes every official slice and backend read", function()
        local vanilla_calls = 0
        local local_daily = { slot_1 = { name = "mp_daily_v2_probe" } }
        local surface = Boundary.surface(true, function() return local_daily end, function()
            vanilla_calls = vanilla_calls + 1
            return {
                daily = { official_daily = { name = "daily_collect_tomes" } },
                weekly = { official_weekly = { name = "weekly_collect_dice_2" } },
                event = { official_event = { name = "event_skulls_for_the_skull_throne" } },
            }
        end)
        H.equal(0, vanilla_calls)
        H.equal(local_daily, surface.daily)
        H.deep_equal({}, surface.weekly)
        H.deep_equal({}, surface.event)
    end)

    H.test("official quest surface delegates unchanged", function()
        local official = { daily = {}, weekly = { keep = true }, event = {} }
        local local_calls, vanilla_calls = 0, 0
        local surface = Boundary.surface(false, function()
            local_calls = local_calls + 1
            return {}
        end, function()
            vanilla_calls = vanilla_calls + 1
            return official
        end)
        H.equal(0, local_calls)
        H.equal(1, vanilla_calls)
        H.equal(official, surface)
    end)

    H.test("MP quest refresh rotates locally without backend polling", function()
        local ensured, updated, vanilla = 0, 0, 0
        Boundary.refresh(true, function() ensured = ensured + 1 end,
            function() updated = updated + 1 end,
            function() vanilla = vanilla + 1 end)
        H.equal(1, ensured)
        H.equal(1, updated)
        H.equal(0, vanilla)
    end)

    H.test("official quest refresh preserves the native callback boundary", function()
        local ensured, updated, vanilla = 0, 0, 0
        local callback = function() updated = updated + 1 end
        local result = Boundary.refresh(false, function() ensured = ensured + 1 end,
            callback, function(received)
                vanilla = vanilla + 1
                H.equal(callback, received)
                return "native-refresh"
            end)
        H.equal("native-refresh", result)
        H.equal(0, ensured)
        H.equal(0, updated)
        H.equal(1, vanilla)
    end)
end
