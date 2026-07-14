return function(H, repo_root)
    local path = repo_root
        .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_simple_ui_bounds_policy.lua"
    local Policy = assert(loadfile(path))()

    H.test("Simple UI windows stay wholly on-screen when they fit", function()
        local left = Policy.confine({ -40, 30 }, { 400, 300 }, 1920, 1080)
        H.equal(left.x, 0)
        H.equal(left.y, 30)
        H.equal(left.changed, true)

        local upper_right = Policy.confine({ 1800, 1000 }, { 400, 300 }, 1920, 1080)
        H.equal(upper_right.x, 1520)
        H.equal(upper_right.y, 780)
    end)

    H.test("oversized Simple UI windows retain a reachable title edge", function()
        local result = Policy.confine({ -500, 200 }, { 2200, 1400 }, 1920, 1080)
        H.equal(result.x, 0)
        H.equal(result.y, -320)
        H.equal(result.y + 1400, 1080)
    end)

    H.test("Simple UI confinement fails closed on incomplete geometry", function()
        H.equal(Policy.confine(nil, { 1, 1 }, 1920, 1080), nil)
        H.equal(Policy.confine({ 0, 0 }, {}, 1920, 1080), nil)
        H.equal(Policy.confine({ 0, 0 }, { 1, 1 }, 0, 1080), nil)
    end)
end
