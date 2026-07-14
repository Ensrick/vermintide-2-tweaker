return function(H, repo_root)
    local path = repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/"
        .. "_ct_chest_count_audit_core.lua"
    local Core = assert(loadfile(path))()

    H.test("CT settled chest audit distinguishes both over-cap paths", function()
        H.equal(Core.classify(5, 3, 3), "over_cap_raw_level_units")
        H.equal(Core.classify(5, 3, 5), "over_cap_pickup_path")
        H.equal(Core.classify(5, 3, 6), "over_cap_count_order_mismatch")
    end)

    H.test("CT settled chest audit reports healthy and malformed counts", function()
        H.equal(Core.classify(3, 3, 3), "within_cap_pickup_path")
        H.equal(Core.classify(0, 0, 0), "within_cap_pickup_path")
        H.equal(Core.classify(3, 3, 2), "within_cap_raw_level_units")
        H.equal(Core.classify(2, 3, 3), "within_cap_count_order_mismatch")
        H.equal(Core.classify(nil, 3, 3), "invalid")
    end)

    H.test("CT issue 349 audit is wired after delayed census", function()
        local main_path = repo_root
            .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/"
            .. "chaos_wastes_tweaker_dev.lua"
        local file = assert(io.open(main_path, "rb"))
        local source = file:read("*a")
        file:close()
        local tally = assert(string.find(source, "[ct-spawn-tally]", 1, true))
        local finalize = assert(string.find(source, "mod._ct_chest132.finalize(_level", 1, true))
        H.truthy(finalize > tally)
    end)

    H.test("CT chest audit finalizes once and includes zero-chest missions", function()
        local state = {}
        Core.begin(state, "dlc_dwarf_interior_khorne_path1")
        local class, actual = Core.finalize(state,
            "dlc_dwarf_interior_khorne_path1", 0, 0)
        H.equal(class, "within_cap_pickup_path")
        H.equal(actual, 0)
        H.equal(Core.finalize(state, "dlc_dwarf_interior_khorne_path1", 0, 0), nil)

        Core.begin(state, "dlc_dwarf_interior_khorne_path1")
        H.equal(Core.appeared(state, "dlc_dwarf_interior_khorne_path1"), 1)
        H.equal(Core.appeared(state, "dlc_dwarf_interior_khorne_path1"), 2)
        H.equal(Core.finalize(state, "other_level", 2, 2), nil)
    end)
end
