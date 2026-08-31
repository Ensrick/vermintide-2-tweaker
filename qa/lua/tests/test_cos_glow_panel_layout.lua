return function(H, repo_root)
    local path = repo_root
        .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_glow_panel_layout.lua"
    local layout = assert(loadfile(path))()

    H.test("Cosmetics glow editor follows the live Information panel", function()
        local host = { _ui_scenegraph = {
            info_window = {
                size = { 500, 800 },
                world_position = { 1345, 160, 2 },
            },
        } }
        local resolved, reason = layout.resolve(host)
        H.equal(reason, nil)
        H.equal(resolved.x, 1345)
        H.equal(resolved.y, 160)
        H.equal(resolved.width, 500)
        H.equal(resolved.height, 800)

        -- Consume changed native geometry as-is; no duplicate screen-coordinate
        -- formula needs to know how the host arrived at it.
        host._ui_scenegraph.info_window.size = { 620, 900 }
        host._ui_scenegraph.info_window.world_position = { 1810, 210, 2 }
        resolved = assert(layout.resolve(host))
        H.equal(resolved.x, 1810)
        H.equal(resolved.y, 210)
        H.equal(resolved.width, 620)
        H.equal(resolved.height, 900)
    end)

    H.test("Cosmetics glow Information-panel layout fails closed", function()
        local resolved, reason = layout.resolve({ _ui_scenegraph = {} })
        H.equal(resolved, nil)
        H.equal(reason, "missing_info_size")
        resolved, reason = layout.resolve({ _ui_scenegraph = {
            info_window = { size = { -1, 800 }, world_position = { 1, 2 } },
        } })
        H.equal(resolved, nil)
        H.equal(reason, "missing_info_size")
    end)

    H.test("Cosmetics glow toggle and hitbox share native geometry", function()
        local offset = assert(layout.toggle_offset(500, 96, 18, 20))
        H.equal(offset[1], 386)
        H.equal(offset[2], 18)
        H.equal(offset[3], 20)
        local bounds = { x = 1345, y = 160, width = 500, height = 800 }
        H.truthy(layout.contains(bounds, 1345, 160))
        H.truthy(layout.contains(bounds, 1845, 960))
        H.equal(layout.contains(bounds, 1344, 160), false)
        H.equal(layout.contains(bounds, 1846, 960), false)
    end)

    H.test("Cosmetics glow frame and toggle helpers remain layout-owned", function()
        local style_owner = {
            FRAME_TEX_SIZE = { 64, 64 },
            FRAME_TEX_SIZES = {
                corner = { 11, 11 },
                vertical = { 5, 1 },
                horizontal = { 1, 5 },
            },
        }
        local frame_style = layout.make_frame_style(style_owner)
        local frame = frame_style(96, 38, 7)
        H.truthy(frame.texture_size == style_owner.FRAME_TEX_SIZE)
        H.truthy(frame.texture_sizes == style_owner.FRAME_TEX_SIZES)
        H.equal(frame.color[1], 255)
        H.equal(frame.offset[3], 7)
        H.equal(frame.area_size[1], 96)
        H.equal(frame.area_size[2], 38)

        local replacement = { 32, 32 }
        style_owner.FRAME_TEX_SIZE = replacement
        H.truthy(frame_style(1, 2).texture_size == replacement)

        local position_toggle = layout.make_toggle_positioner(18)
        local host = { _ui_scenegraph = { info_window = {
            size = { 500, 800 }, world_position = { 1345, 160, 2 },
        } } }
        local widget = {}
        H.truthy(position_toggle(host, widget, 96, 20))
        H.equal(widget.offset[1], 386)
        H.equal(widget.offset[2], 18)
        H.equal(widget.offset[3], 20)
        H.equal(position_toggle({}, widget, 96, 20), false)
        H.equal(position_toggle(host, false, 96, 20), false)
    end)

    H.test("Cosmetics glow native Information transaction always restores", function()
        local original = { "native title", "native description" }
        local host = { _info_widgets = original }
        local called = false
        local ok, reason = layout.without_native_information(function(draw_host)
            called = true
            H.equal(draw_host._info_widgets, nil)
        end, host)
        H.truthy(ok)
        H.equal(reason, nil)
        H.truthy(called)
        H.equal(host._info_widgets, original)

        local raised, err = pcall(layout.without_native_information,
            function(draw_host)
                H.equal(draw_host._info_widgets, nil)
                error("vanilla draw failed")
            end, host)
        H.equal(raised, false)
        H.truthy(tostring(err):find("vanilla draw failed", 1, true))
        H.equal(host._info_widgets, original)
    end)
end
