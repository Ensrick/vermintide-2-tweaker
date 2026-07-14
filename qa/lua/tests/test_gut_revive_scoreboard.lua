return function(H, repo_root)
    local path = repo_root
        .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_revive_scoreboard_policy.lua"
    local Policy = assert(loadfile(path))()

    H.test("GUT repairs only missing On Yer Feet revive credit", function()
        H.truthy(Policy.should_repair({
            is_server = true,
            has_talent = true,
            was_career_revivable = true,
            revives_before = 2,
            revives_after = 2,
        }))
        H.equal(Policy.should_repair({
            is_server = true,
            has_talent = true,
            was_career_revivable = true,
            revives_before = 2,
            revives_after = 3,
        }), false)
    end)

    H.test("GUT revive credit policy fails closed", function()
        H.equal(Policy.should_repair(nil), false)
        H.equal(Policy.should_repair({
            is_server = false,
            has_talent = true,
            was_career_revivable = true,
            revives_before = 2,
            revives_after = 2,
        }), false)
        H.equal(Policy.should_repair({
            is_server = true,
            has_talent = false,
            was_career_revivable = true,
            revives_before = 2,
            revives_after = 2,
        }), false)
        H.equal(Policy.should_repair({
            is_server = true,
            has_talent = true,
            was_career_revivable = false,
            revives_before = 2,
            revives_after = 2,
        }), false)
        H.equal(Policy.should_repair({
            is_server = true,
            has_talent = true,
            was_career_revivable = true,
            revives_after = 2,
        }), false)
    end)
end
