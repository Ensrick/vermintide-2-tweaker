-- _mod_tweaker_tooltip.lua - native-style Mod Tweaker tooltip factory/layout.
--
-- Owns popup passes, wrapped text measurement, fade and screen-edge anchoring.
-- Definitions injects native geometry/render helpers once; resolution remains
-- late-read and measurement failures retain the existing one-line fallback.
--
-- Owned by: _mod_tweaker_definitions.lua. Consumed via: mod:dofile + new(env).

local M = {}

function M.new(env)
    local UIWidget = assert(env.UIWidget, "tooltip requires UIWidget")
    local Colors = assert(env.Colors, "tooltip requires Colors")
    local ROW_W, ROW_H = assert(env.row_w), assert(env.row_h)
    local LABEL_BASE_X = assert(env.label_base_x, "tooltip requires label origin")
    local font_by_resolution = assert(env.font_by_resolution, "tooltip requires font resolver")
    local word_wrap = assert(env.word_wrap, "tooltip requires word wrapping")
    local font_height = assert(env.font_height, "tooltip requires font height")
    local get_resolution_lookup = assert(env.get_resolution_lookup, "tooltip requires resolution reader")

    -- (#207) HOVER INFO POPUP — native options-menu tooltip, HAND-BUILT for the borrowed
    -- renderer. Native settings rows carry an `option_tooltip` pass (ui_passes.lua:3350) that
    -- composes UITooltipPasses.generic_text + a box drawn by UITooltipPasses.background: a
    -- `{255,3,3,3}` fill rect + the `item_tooltip_frame_01` frame (ui_passes_tooltips.lua:21-71).
    -- item_tooltip_frame_01's texture IS `menu_frame_12` (ui_frame_settings.lua:921-941) — the
    -- SAME frame gut's window chrome (background_frame) already draws, so it's PROVEN resident on
    -- the borrowed HeroView / level-world renderer. So this popup reproduces the native box the
    -- proven way: a plain `rect` "panel" fill (dark {255,3,3,3}, NO atlas/material lookup) + a
    -- `texture_frame` menu_frame_12 border (the real settings-tooltip frame, sized per-frame),
    -- plus plain `text` passes, on the mt_tooltip scenegraph node (parented to mt_list so it
    -- scrolls with the rows, z above them) drawn LAST in the view's draw loop so it overlays +
    -- isn't culled. Title = the row label (font_title, larger size 22); description = the node's
    -- localized `tooltip`, word-wrapped below it (font_default, size 18). The view sets
    -- content.title / content.desc + the geometry + the fade alpha every frame via layout_tooltip.
    local TT_W             = math.min(600, ROW_W)   -- native tooltip width 600, clamped to gut's panel
    local TT_PAD_X         = 16
    local TT_PAD_Y         = 12
    local TT_GAP           = 6                       -- vertical gap between title + description
    local TT_TITLE_SIZE    = 22
    local TT_DESC_SIZE     = 18
    local TT_SCREEN_MARGIN = 8                       -- px margin from a screen edge before flipping the box's side
    -- (#207) menu_frame_12 9-slice BORDER — the SAME ornate frame the NATIVE settings option
    -- tooltip draws: vanilla option_tooltip -> UITooltipPasses.background uses item_tooltip_frame_01,
    -- whose texture IS menu_frame_12, over a {255,3,3,3} fill (ui_passes_tooltips.lua:21-71 /
    -- ui_frame_settings.lua:921-941). menu_frame_12 is already proven to resolve on the borrowed
    -- renderer (gut's window chrome background_frame uses it via UIWidgets.create_frame). We draw it
    -- as a texture_frame pass whose area_size + offset are set per-frame in layout_tooltip so the
    -- frame resizes with the box. Metrics copied verbatim from UIFrameSettings.menu_frame_12.
    local TT_FRAME_TEXTURE   = "menu_frame_12"
    local TT_FRAME_TEX_SIZE  = { 64, 64 }
    local TT_FRAME_TEX_SIZES = { corner = { 11, 11 }, vertical = { 5, 1 }, horizontal = { 1, 5 } }

    -- One reusable tooltip widget. The view sets content.title / content.desc and every frame
    -- calls layout_tooltip to size/position the box + ramp the fade alpha. Mirrors the dropdown
    -- popup's z-ordering (drawn above rows). The border is the native menu_frame_12 9-slice (the
    -- SAME frame the real settings tooltip uses — see TT_FRAME_* above), NOT a flat grey rect.
    local function create_tooltip_popup()
        local passes = {
            -- Dark panel FILL (native settings-tooltip background = {255,3,3,3}).
            { pass_type = "rect", style_id = "panel" },
            -- TITLE (header, larger) over a word-wrapped DESCRIPTION below it.
            { pass_type = "text", style_id = "title", text_id = "title" },
            { pass_type = "text", style_id = "desc",  text_id = "desc" },
            -- menu_frame_12 BORDER, drawn LAST (highest z) so its edges sit crisply over the fill.
            -- area_size + offset are driven per-frame by layout_tooltip so it wraps the box exactly.
            { pass_type = "texture_frame", style_id = "frame", texture_id = "frame" },
        }
        local content = { title = "", desc = "", frame = TT_FRAME_TEXTURE }
        local style = {
            panel = { offset = { 0, 0, 60 }, size = { TT_W, 10 }, color = { 255, 3, 3, 3 } },
            title = {
                font_type = "hell_shark", font_size = TT_TITLE_SIZE,
                horizontal_alignment = "left", vertical_alignment = "top",
                localize = false, word_wrap = true,
                text_color = Colors.get_color_table_with_alpha("font_title", 255),
                offset = { 0, 0, 62 }, size = { TT_W - TT_PAD_X * 2, 30 },
            },
            desc = {
                font_type = "hell_shark", font_size = TT_DESC_SIZE,
                horizontal_alignment = "left", vertical_alignment = "top",
                localize = false, word_wrap = true,
                text_color = Colors.get_color_table_with_alpha("font_default", 255),
                offset = { 0, 0, 62 }, size = { TT_W - TT_PAD_X * 2, 30 },
            },
            -- menu_frame_12 9-slice; color[1] (alpha) ramped by the fade. area_size/offset per-frame.
            frame = {
                texture_size = TT_FRAME_TEX_SIZE, texture_sizes = TT_FRAME_TEX_SIZES,
                color = { 255, 255, 255, 255 },
                offset = { 0, 0, 63 }, area_size = { TT_W, 10 },
            },
        }
        return UIWidget.init({
            scenegraph_id = "mt_tooltip",
            element = { passes = passes },
            content = content,
            style = style,
            offset = { 0, 0, 0 },
        })
    end

    -- Measure one word-wrapped text block: returns (line_count, line_height) in UNSCALED UI
    -- space, mirroring the native generic_text / text-pass measurement (ui_passes.lua:1992-2000
    -- / 4001-4007): word_wrap with the SCALED font size + the raw box width, line height =
    -- (font_max - font_min) * inv_scale. Caller pcall-guards; on failure falls back to 1 line.
    local function _tt_measure(renderer, style, text, inner_w)
        local font, scaled = font_by_resolution(style)
        local lines = word_wrap(renderer, text, font[1], scaled, inner_w)
        local _, fmin, fmax = font_height(renderer.gui, style.font_type, scaled)
        local line_h = (fmax - fmin) * get_resolution_lookup().inv_scale
        return math.max(1, #lines), line_h
    end

    -- Lay out + fade the tooltip popup for the hovered row, every frame. `row_list_y` is the
    -- hovered row's offset Y (its bottom edge, in mt_list_start / mt_tooltip space, which share
    -- the {40,0} origin); `world_row_y` is that same bottom edge in screen/design space (for the
    -- on-screen flip test); `alpha` is the fade [0..1].
    -- (#207) Anchors the box ABOVE the row by default (its bottom edge flush to the row's top),
    -- matching the native options tooltip; FLIPS it BELOW only when drawing above would run off the
    -- TOP of the visible screen. Box height fits the wrapped title + description. Mutates in place.
    -- (#880) `prefer_below` (optional, from row._tip_prefer_below): dialogue transcript
    -- popups anchor directly UNDER their row, flipping ABOVE only when drawing below
    -- would run off the BOTTOM of the screen. Absent/nil keeps the native above-with-flip.
    local function layout_tooltip(widget, renderer, title, desc, row_list_y, world_row_y, alpha, prefer_below)
        local style, content = widget.style, widget.content
        content.title = tostring(title or "")
        content.desc  = tostring(desc or "")
        local inner_w = TT_W - TT_PAD_X * 2

        -- Measure wrapped heights (native generic_text approach). Fallback = 1 line each.
        local title_lines, title_lh = 1, TT_TITLE_SIZE + 8
        local desc_lines,  desc_lh  = 1, TT_DESC_SIZE + 6
        pcall(function() title_lines, title_lh = _tt_measure(renderer, style.title, content.title, inner_w) end)
        pcall(function() desc_lines,  desc_lh  = _tt_measure(renderer, style.desc,  content.desc,  inner_w) end)
        local title_h = title_lines * title_lh
        local desc_h  = desc_lines  * desc_lh
        local box_h   = TT_PAD_Y + title_h + TT_GAP + desc_h + TT_PAD_Y

        -- (#207) DEFAULT = draw the box ABOVE the row (its bottom edge flush to the row's top), like
        -- the native options tooltip. `box_top` is the box's TOP edge in offset space (offset is
        -- bottom-left, +Y up). Drawing above puts the box's TOP at world Y = world_row_y + ROW_H +
        -- box_h; flip to BELOW only if that runs off the TOP of the visible screen. Screen height is
        -- read in the SAME design space as world_row_y (res_h * inv_scale; falls back to 1080).
        local screen_h = 1080
        pcall(function()
            local r = get_resolution_lookup()
            if r and r.res_h and r.inv_scale then screen_h = r.res_h * r.inv_scale end
        end)
        local above_top_world = world_row_y + ROW_H + box_h
        -- Explicit branch, not and/or (bug class 26): both anchor modes flip at their
        -- own screen edge only.
        local draw_below
        if prefer_below then
            draw_below = (world_row_y - box_h) >= TT_SCREEN_MARGIN
        else
            draw_below = above_top_world > (screen_h - TT_SCREEN_MARGIN)
        end
        local box_top    = draw_below and row_list_y or (row_list_y + ROW_H + box_h)
        local box_bottom = box_top - box_h
        local x0 = LABEL_BASE_X
        if x0 + TT_W > ROW_W then x0 = math.max(0, ROW_W - TT_W) end

        style.panel.offset[1], style.panel.offset[2] = x0, box_bottom
        style.panel.size[1],   style.panel.size[2]   = TT_W, box_h
        -- menu_frame_12 border wraps the fill exactly (same rect); area_size drives the 9-slice.
        style.frame.offset[1],    style.frame.offset[2]    = x0, box_bottom
        style.frame.area_size[1], style.frame.area_size[2] = TT_W, box_h
        style.title.offset[1] = x0 + TT_PAD_X
        style.title.offset[2] = box_top - TT_PAD_Y - title_h
        style.title.size[1],   style.title.size[2]   = inner_w, title_h
        style.desc.offset[1]  = x0 + TT_PAD_X
        style.desc.offset[2]  = box_top - TT_PAD_Y - title_h - TT_GAP - desc_h
        style.desc.size[1],    style.desc.size[2]    = inner_w, desc_h

        -- Fade: alpha [0..1] -> 0..255 on EVERY pass color (panel, frame, both texts).
        local a = math.floor(math.clamp(alpha or 0, 0, 1) * 255 + 0.5)
        style.panel.color[1]      = a
        style.frame.color[1]      = a
        style.title.text_color[1] = a
        style.desc.text_color[1]  = a
    end

    return { create_tooltip_popup = create_tooltip_popup, layout_tooltip = layout_tooltip }
end

return M
