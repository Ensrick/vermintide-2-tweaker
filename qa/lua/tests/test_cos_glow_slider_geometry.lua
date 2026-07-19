return function(H, repo_root)
    local module_path = repo_root
        .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_glow_slider_geometry.lua"
    local Geometry = assert(loadfile(module_path))()

    H.test("Cosmetics glow slider maps the rendered track endpoints and quartiles", function()
        local style = {
            size = { 200, 16 },
            offset = { 90, 4, 1 },
        }
        local world_x = 100

        H.equal(Geometry.value_from_cursor(190, world_x, style), 0)
        H.equal(Geometry.value_from_cursor(240, world_x, style), 0.25)
        H.equal(Geometry.value_from_cursor(290, world_x, style), 0.5)
        H.equal(Geometry.value_from_cursor(340, world_x, style), 0.75)
        H.equal(Geometry.value_from_cursor(390, world_x, style), 1)
        H.equal(Geometry.value_from_cursor(120, world_x, style), 0)
        H.equal(Geometry.value_from_cursor(450, world_x, style), 1)
    end)

    H.test("Cosmetics glow slider geometry is independent of resolution-space origin", function()
        local style = {
            size = { 240, 18 },
            offset = { 87.25, 6, 1 },
        }
        local world_x = 475.5
        local left = world_x + style.offset[1]

        H.equal(Geometry.value_from_cursor(left, world_x, style), 0)
        H.equal(Geometry.value_from_cursor(left + 120, world_x, style), 0.5)
        H.equal(Geometry.value_from_cursor(left + 240, world_x, style), 1)
    end)

    H.test("Cosmetics glow slider hitbox and thumb derive from the track rectangle", function()
        local style = {
            size = { 200, 16 },
            offset = { 90, 4, 1 },
        }
        local hotspot = Geometry.hotspot_style(style, 2)

        H.equal(hotspot.offset[1], 88)
        H.equal(hotspot.offset[2], 2)
        H.equal(hotspot.size[1], 204)
        H.equal(hotspot.size[2], 20)
        H.equal(Geometry.thumb_left(style, 0, 12), 84)
        H.equal(Geometry.thumb_left(style, 0.5, 12), 184)
        H.equal(Geometry.thumb_left(style, 1, 12), 284)
        H.equal(Geometry.thumb_left({ size = { 0, 16 } }, 0.5, 12), nil)
    end)

    H.test("Cosmetics glow picker uses the held pass track style directly", function()
        local file = assert(io.open(repo_root
            .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_glow_picker.lua", "rb"))
        local source = file:read("*a")
        file:close()

        H.truthy(source:find(
            "SLIDER_GEOMETRY.value_from_cursor(\n                            scaled[1], world_pos[1], ui_style)",
            1, true))
        H.equal(source:find(
            "world_pos[1] + (ui_style.track and ui_style.track.offset",
            1, true), nil)
    end)
end
