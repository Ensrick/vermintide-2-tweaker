return function(H, repo_root)
    local path = repo_root
        .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_respawn_timer.lua"
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()

    H.test("GUT #285 uses the live team-frame portrait scenegraph", function()
        H.truthy(source:find("widget.ui_scenegraph", 1, true) ~= nil)
        H.truthy(source:find("widget.ui_renderer or renderer", 1, true) ~= nil)
        H.truthy(source:find("frame_scenegraph.portrait_pivot", 1, true) ~= nil)
        H.truthy(source:find(
            "UIRenderer.begin_pass(renderer, frame_scenegraph", 1, true
        ) ~= nil)
        H.equal(source:find("SCENEGRAPH_DEF", 1, true), nil)
        H.equal(source:find("UISceneGraph.get_world_position", 1, true), nil)
    end)

    H.test("GUT #285 keeps the bounded apply marker and widget draw", function()
        H.truthy(source:find("[gut:285] live portrait anchor applied", 1, true) ~= nil)
        H.truthy(source:find("UIRenderer.draw_widget(renderer, _widget)", 1, true) ~= nil)
        H.truthy(source:find("_traced[uid] = nil", 1, true) ~= nil)
    end)
end
