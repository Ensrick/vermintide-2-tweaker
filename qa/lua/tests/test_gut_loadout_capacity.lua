return function(H, repo_root)
    local path = repo_root
        .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_loadout_capacity_policy.lua"
    local Policy = assert(loadfile(path))()

    local function vanilla_rows()
        local rows = {
            { loadout_type = "default", loadout_index = 1 },
            { loadout_type = "default", loadout_index = 2 },
        }
        for i = 1, 6 do
            rows[#rows + 1] = { loadout_type = "custom", loadout_index = i }
        end
        return rows
    end

    H.test("GUT #231 census identifies every vanilla 30-slot blocker", function()
        local result = Policy.inspect(vanilla_rows(), 6, 6,
            function(i) return i <= 6 end,
            function(i) return i <= 6 end, 6)
        H.equal(result.target, 30)
        H.equal(result.custom_count, 6)
        H.equal(result.missing_icon_ranges, "7-30")
        H.equal(result.missing_title_ranges, "7-30")
        H.truthy(result.needs_paging)
        H.equal(result.cutover_ready, false)
    end)

    H.test("GUT #231 census recognizes a complete direct-layout cutover", function()
        local rows = {}
        for i = 1, 30 do rows[i] = { loadout_type = "custom", loadout_index = i } end
        local result = Policy.inspect(rows, 30, 30,
            function() return true end, function() return true end, 30)
        H.truthy(result.data_ready)
        H.truthy(result.assets_ready)
        H.truthy(result.direct_ui_ready)
        H.truthy(result.cutover_ready)
    end)

    H.test("GUT #231 census detects duplicate indices", function()
        local rows = vanilla_rows()
        rows[#rows + 1] = { loadout_type = "custom", loadout_index = 6 }
        local result = Policy.inspect(rows, 30, 30,
            function() return true end, function() return true end, 0)
        H.equal(result.duplicate_count, 1)
        H.equal(result.data_ready, false)
    end)

    H.test("GUT #231 pure policy preserves sparse persisted extent", function()
        local result = Policy.inspect(vanilla_rows(), 6, 6,
            function(i) return i <= 6 end,
            function(i) return i <= 6 end, 30)
        H.equal(result.store_max, 30)
        H.equal(result.custom_count, 6)
        H.equal(result.cutover_ready, false)
    end)

    H.test("GUT #231 consumed automatic census stays retired", function()
        local entry_path = repo_root
            .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/gui_tweaker_dev.lua"
        local file = assert(io.open(entry_path, "rb"))
        local source = file:read("*a")
        file:close()
        H.equal(source:find("_gut_loadout_capacity_probe", 1, true), nil)
        H.equal(source:find("gut_loadout_capacity_probe", 1, true), nil)
    end)
end
