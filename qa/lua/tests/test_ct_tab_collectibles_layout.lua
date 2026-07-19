return function(H, repo_root)
    local path = repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_tab_collectibles_layout.lua"

    local old_get_mod = _G.get_mod
    local fake_mod = {}
    _G.get_mod = function(name)
        H.equal(name, "ct_dev")
        return fake_mod
    end
    local ok, module = pcall(assert(loadfile(path)))
    _G.get_mod = old_get_mod
    if not ok then error(module) end

    H.test("CT #571 ports vanilla two-column collectible offsets exactly", function()
        local layout = fake_mod._ct_compute_native_collectible_offsets({
            { icon_w = 80, icon_h = 80, text_w = 120 },
            { icon_w = 80, icon_h = 80, text_w = 200 },
        })
        H.equal(layout.count, 2)
        H.equal(layout.rows, 1)
        H.equal(layout.offsets[1][1], 0)
        H.equal(layout.offsets[1][2], 80)
        H.equal(layout.offsets[2][1], 300)
        H.equal(layout.offsets[2][2], 80)
        H.equal(layout.bounds[1].text_w, 120)
        H.equal(layout.bounds[2].right_edge, 580)
        H.equal(layout.right_edge, 580)
        H.equal(layout.source, "IngamePlayerListUI._setup_mission_data")
    end)

    H.test("CT #571 starts later native collectible rows at the anchor", function()
        local layout = fake_mod._ct_compute_native_collectible_offsets({
            { icon_w = 80, icon_h = 80, text_w = 100 },
            { icon_w = 80, icon_h = 80, text_w = 120 },
            { icon_w = 80, icon_h = 80, text_w = 90 },
            { icon_w = 80, icon_h = 80, text_w = 110 },
        })
        H.equal(layout.rows, 2)
        H.equal(layout.offsets[3][1], 0)
        H.equal(layout.offsets[3][2], 0)
        H.equal(layout.offsets[4][1], 210)
        H.equal(layout.offsets[4][2], 0)
    end)

    H.test("CT #571 never derives widget offsets from animated world positions", function()
        local f = assert(io.open(path, "rb"))
        local source = f:read("*a"); f:close()
        H.equal(source:find(".world_position", 1, true), nil)
        H.truthy(source:find("widget-local offsets", 1, true))
        H.truthy(source:find("if cw.layout_signature == LAYOUT_MARKER then return end", 1, true))
        H.truthy(source:find("[ct:571] native collectible offsets", 1, true))
        H.equal(source:find("Application.user_setting", 1, true), nil)
        H.equal(source:find("RESOLUTION_LOOKUP", 1, true), nil)
        H.equal(source:find("mod:hook", 1, true), nil)
        H.equal(module.regression(), nil)
    end)
end
