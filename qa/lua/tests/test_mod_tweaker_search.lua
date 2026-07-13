return function(H, repo_root)
    local module_path = repo_root
        .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_mod_tweaker_search.lua"
    local Search = assert(loadfile(module_path))()

    H.test("search cancel restores the exact per-tab snapshot", function()
        local expanded = { outer_a = true, nested_a = true, other_tab = true }
        local tx = Search.begin(expanded, { "outer_a", "nested_a", "outer_b" }, "tab-a")

        -- Filter rendering must not need to write expanded. Plant mutations to prove restore is exact.
        expanded.outer_a = nil
        expanded.nested_a = nil
        expanded.outer_b = true
        Search.restore(expanded, tx)

        H.deep_equal(expanded, { outer_a = true, nested_a = true, other_tab = true })
    end)

    H.test("auto-collapse result commit keeps exactly its ancestor chain", function()
        local expanded = { old_outer = true, old_nested = true, other_tab = true }
        local tx = Search.begin(expanded, { "old_outer", "old_nested", "result_outer" }, "tab-a")
        Search.commit(expanded, tx, { "result_outer" }, true)

        H.deep_equal(expanded, { result_outer = true, other_tab = true })
    end)

    H.test("non-auto-collapse result commit preserves old branches plus ancestors", function()
        local expanded = { old_outer = true, old_nested = true, other_tab = true }
        local tx = Search.begin(expanded, { "old_outer", "old_nested", "result_outer" }, "tab-a")
        Search.commit(expanded, tx, { "result_outer" }, false)

        H.deep_equal(expanded, {
            old_outer = true,
            old_nested = true,
            result_outer = true,
            other_tab = true,
        })
    end)

    H.test("search finish prefers last changed branch then falls back to top result", function()
        local expanded = { old_outer = true, other_tab = true }
        local tx = Search.begin(expanded,
            { "old_outer", "top_outer", "changed_outer" }, "tab-a")
        Search.finish(expanded, tx, { "changed_outer" }, { "top_outer" }, true)
        H.deep_equal(expanded, { changed_outer = true, other_tab = true })

        expanded = { old_outer = true, other_tab = true }
        tx = Search.begin(expanded,
            { "old_outer", "top_outer", "changed_outer" }, "tab-a")
        Search.finish(expanded, tx, nil, { "top_outer" }, true)
        H.deep_equal(expanded, { top_outer = true, other_tab = true })
    end)

    H.test("search finish keeps prior branches when auto-collapse is disabled", function()
        local expanded = { old_outer = true, other_tab = true }
        local tx = Search.begin(expanded, { "old_outer", "top_outer" }, "tab-a")
        Search.finish(expanded, tx, nil, { "top_outer" }, false)
        H.deep_equal(expanded, {
            old_outer = true,
            top_outer = true,
            other_tab = true,
        })
    end)

    H.test("ancestor planner returns outer-to-inner groups and excludes result", function()
        local nodes = {
            { type = "group", key = "outer" },
            { type = "checkbox", key = "plain" },
            { type = "group", key = "inner" },
            { type = "slider", key = "result" },
        }
        local depths = { 0, 1, 1, 2 }
        local ancestors = Search.ancestors(nodes, depths, 4,
            function(node) return node.type end,
            function(node) return node.key end)
        H.deep_equal(ancestors, { "outer", "inner" })

        local top = Search.ancestors(nodes, depths, 1,
            function(node) return node.type end,
            function(node) return node.key end)
        H.deep_equal(top, {})
    end)

    H.test("Mod Tweaker search binds the native inventory magnifier with text clearance", function()
        local path = repo_root
            .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_mod_tweaker_definitions.lua"
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        H.truthy(source:find('ICON_TEXTURE, ICON_SIZE, ICON_X, ICON_Y = "search_filters_icon", 128, -80, -4', 1, true))
        H.truthy(source:find('{ pass_type = "texture", style_id = "search_icon", texture_id = "search_icon" }', 1, true))
        H.truthy(source:find('local TEXT_X = 47', 1, true))
        H.truthy(source:find('offset = { ICON_X, ICON_Y, 3 }', 1, true))
        H.truthy(source:find('offset = { TEXT_X, 0, 4 }, size = { W - TEXT_X - PAD, H }', 1, true))
    end)
end
