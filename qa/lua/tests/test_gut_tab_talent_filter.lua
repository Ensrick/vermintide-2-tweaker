return function(H, repo_root)
    local path = repo_root
        .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_tab_talent_policy.lua"
    local Policy = assert(loadfile(path))()
    local tree = {
        { "t11", "t12" }, { "t21", "t22" }, { "t31", "t32" },
        { "t41", "t42" }, { "t51", "t52" }, { "t61", "t62" },
    }
    local lookup = {}
    for tier = 1, 6 do
        for column = 1, 2 do
            lookup["t" .. tier .. column] = { talent_id = tier * 10 + column }
        end
    end

    H.test("GUT #250 restores sparse Deus talents to their tree tiers", function()
        local normalized, duplicates, unmapped = Policy.normalize(
            { 11, 21, 31, 51, 61, 22 }, tree, lookup)
        H.equal(normalized[1], 11)
        H.equal(normalized[2], 21)
        H.equal(normalized[3], 31)
        H.equal(normalized[4], nil)
        H.equal(normalized[5], 51)
        H.equal(normalized[6], 61)
        H.equal(duplicates, 1)
        H.equal(unmapped, 0)
        H.truthy(Policy.needs_repair({ 11, 21, 31, 51, 61, 22 }, normalized))
    end)

    H.test("GUT #250 keeps the first talent when a boon duplicates a tier", function()
        local normalized, duplicates = Policy.normalize(
            { 12, 21, 31, 41, 51, 61, 11 }, tree, lookup)
        H.equal(normalized[1], 12)
        H.equal(normalized[6], 61)
        H.equal(duplicates, 1)
        H.equal(Policy.needs_repair({ 12, 21, 31, 41, 51, 61 }, normalized), false)
    end)

    H.test("GUT #250 UI repair is Deus-only, active-only, and bounded", function()
        local runtime_path = repo_root
            .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_tab_talent_refresh.lua"
        local file = assert(io.open(runtime_path, "rb"))
        local source = file:read("*a")
        file:close()
        H.truthy(source:find('self._active ~= true', 1, true) ~= nil)
        H.truthy(source:find('current_mechanism_name() == "deus"', 1, true) ~= nil)
        H.truthy(source:find('log_count < Policy.MAX_LOGS', 1, true) ~= nil)
        H.truthy(source:find('set_deus_talent_ids', 1, true) == nil)
        H.truthy(Policy.MAX_LOGS <= 16)
    end)
end
