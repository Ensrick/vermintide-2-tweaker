return function(H, repo_root)
    local old_get_mod = _G.get_mod
    local fake_mod = { get = function() return nil end }
    _G.get_mod = function() return fake_mod end
    local path = repo_root .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_hud_customizer.lua"
    local ok, Customizer = pcall(function() return assert(loadfile(path))() end)
    _G.get_mod = old_get_mod
    assert(ok, Customizer)

    H.test("HUD drag geometry keeps movement and rendered bounds nodes separate", function()
        local expected = {
            equipment_ui = "background_panel", buff_ui = "pivot_dragger",
            boss_health = "pivot_dragger", challenge_tracker = "quest",
            loot_objective = "background", news_feed = "news_pivot_1",
        }
        for id, drag_id in pairs(expected) do
            local entry = Customizer.REGISTRY_BY_ID[id]
            H.truthy(entry, id .. " registry entry missing")
            H.equal(entry.drag_scenegraph_node_id, drag_id, id .. " drag node")
        end
    end)

    H.test("HUD drag geometry uses live render bounds without changing move target", function()
        local entry = Customizer.REGISTRY_BY_ID.equipment_ui
        local move = { world_position = { 10, 20, 1 }, size = { 0, 0 } }
        local rendered = { world_position = { 300, 400, 2 }, size = { 624, 66 } }
        local node, size, drag_id = Customizer.drag_geometry({
            pivot = move, background_panel = rendered,
        }, entry)
        H.equal(node, rendered)
        H.equal(size, rendered.size)
        H.equal(drag_id, "background_panel")
        H.equal(entry.scenegraph_node_id, "pivot", "movement target must stay unchanged")
    end)

    H.test("HUD drag geometry safely falls back for absent dynamic bounds", function()
        local entry = Customizer.REGISTRY_BY_ID.news_feed
        local move = { world_position = { 50, 60, 1 }, size = { 0, 0 } }
        local node, size = Customizer.drag_geometry({ pivot = move }, entry)
        H.equal(node, move)
        H.equal(size[1], 420)
        H.equal(size[2], 120)
        H.equal(Customizer.drag_geometry(nil, entry), nil)
    end)
end
