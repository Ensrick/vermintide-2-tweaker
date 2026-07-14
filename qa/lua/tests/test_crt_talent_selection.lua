return function(H, repo_root)
    local path = repo_root
        .. "/career_tweaker/scripts/mods/career_tweaker/_crt_talent_selection.lua"
    local Selection = assert(loadfile(path))()

    H.test("CRT talent menu recognizes an unchanged selection", function()
        local current = { 1, 2, 3, 1, 2, 3 }
        local opened = Selection.snapshot(current)
        H.equal(Selection.equal(opened, current), true)
        current[2] = 1
        H.equal(opened[2], 2)
        H.equal(Selection.equal(opened, current), false)
    end)

    H.test("CRT talent menu comparison rejects added removed and invalid rows", function()
        H.equal(Selection.equal({ [1] = 1, [3] = 2 }, { [1] = 1, [3] = 2 }), true)
        H.equal(Selection.equal({ [1] = 1 }, { [1] = 1, [2] = 0 }), false)
        H.equal(Selection.equal({ [1] = 1, [2] = 0 }, { [1] = 1 }), false)
        H.equal(Selection.equal(nil, { 1 }), false)
    end)
end
