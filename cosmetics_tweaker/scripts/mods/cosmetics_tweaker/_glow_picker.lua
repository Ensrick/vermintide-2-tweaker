-- ============================================================
-- Glow Picker — in-context per-item glow customization popup
-- ============================================================
-- Floating overlay panel anchored top-center of the cosmetic-changing screen
-- (HeroWindowCosmeticsLoadout). Opens contextually for any glow-eligible
-- equipped item, no master toggle. Persists per-item-instance (backend_id-
-- keyed) in a single VMF JSON-blob setting (`glow_per_item`). Supersedes the
-- existing VMF glow override; eventually that menu will be deprecated.
--
-- M1 (this build): scaffolding only — popup panel + close button + placeholder
-- text + lifecycle hooks proven in-game. Confirms the cosmetic-screen
-- integration path works before we commit slider widget code.
-- M2 (next iter): RGB + intensity sliders per visual component, mesh-family
-- detection, persistence read/write.
-- M3: wire per-item override into _glow_rgb_for_var / _glow_var_mult so the
-- saved per-item RGB actually drives the on-screen glow.
-- ============================================================

local mod = get_mod("cosmetics_tweaker")

local GlowPicker = {}

-- Issue #570: automatic UI lifecycle/diagnostic state never belongs in chat.
-- Raw printf keeps failures visible even when VMF mod logging is disabled.
local function _log_only(fmt, ...)
    if rawget(_G, "printf") then
        pcall(printf, "[cos:570] " .. fmt, ...)
    end
end
local function _apply_log_only(fmt, ...)
    if rawget(_G, "printf") then
        pcall(printf, "[cos:574] " .. fmt, ...)
    end
end
GlowPicker.CHAT_DIAGNOSTICS_LOG_ONLY = true

-- --------------------------------------------------------
-- State (module-level, single popup instance)
-- --------------------------------------------------------
GlowPicker._open                  = false
GlowPicker._scenegraph            = nil
GlowPicker._widgets               = nil       -- array passed to UIRenderer.draw_widget
GlowPicker._widgets_by_name       = nil       -- name → widget for input dispatch
GlowPicker._current_backend_id    = nil
GlowPicker._current_slot_data     = nil
GlowPicker._current_identity      = nil
GlowPicker._committed_glow_state  = nil
GlowPicker._dirty                 = false
GlowPicker._built                 = false     -- scenegraph + widgets allocated once

local function _clone(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, child in pairs(value) do copy[key] = _clone(child) end
    return copy
end

-- Backend ids identify the inventory instance; the skin suffix keeps a glow
-- choice attached to the exact illusion variant when an item's illusion changes.
local function _identity_key(backend_id, slot_data)
    if backend_id == nil then return nil end
    local skin = type(slot_data) == "table" and slot_data.skin or nil
    return string.format("backend:%s|skin:%s", tostring(backend_id), tostring(skin or ""))
end
GlowPicker.identity_key = _identity_key

-- --------------------------------------------------------
-- Scenegraph: floating panel, anchored top-center, ~600x400px
-- --------------------------------------------------------
-- v0.9.8: panel grew from 400 → 620 to fit magic-family layout (3
-- component sections × 4 sliders each = 12 sliders + 3 section labels).
-- Rune family still uses just the top 4 slider positions; the rest of
-- the panel area sits empty for rune-family items.
local PANEL_W, PANEL_H = 600, 620
local TOP_INSET        = 80   -- distance from screen top to panel top

local function _make_scenegraph_definition()
    -- audit 2026-06-07 (F11): `UILayer` is a vanilla global (scripts/ui/ui_layer.lua,
    -- popup = 950), but this fn is evaluated as an ARGUMENT to pcall at the _build
    -- call site, so a nil/renamed `UILayer` would raise BEFORE pcall protection
    -- kicks in and crash module-scope. Read defensively via rawget on _G with a
    -- literal fallback so the panel still builds on a layer of 900.
    local _ui_layer = rawget(_G, "UILayer")
    local _popup_layer = (type(_ui_layer) == "table" and _ui_layer.popup) or 900
    return {
        root = {
            is_root = true,
            size    = { 1920, 1080 },
            position = { 0, 0, _popup_layer },
        },
        -- Dim layer behind the popup so the screen reads as visually paused.
        glow_picker_dim = {
            parent = "root",
            horizontal_alignment = "center",
            vertical_alignment   = "center",
            size = { 1920, 1080 },
            position = { 0, 0, 0 },
        },
        -- Main panel anchored top-center.
        glow_picker_panel = {
            parent = "root",
            horizontal_alignment = "center",
            vertical_alignment   = "top",
            size     = { PANEL_W, PANEL_H },
            position = { 0, -TOP_INSET, 5 },
        },
        glow_picker_title = {
            parent = "glow_picker_panel",
            horizontal_alignment = "center",
            vertical_alignment   = "top",
            size     = { PANEL_W - 40, 30 },
            position = { 0, -15, 1 },
        },
        glow_picker_subtitle = {
            parent = "glow_picker_panel",
            horizontal_alignment = "center",
            vertical_alignment   = "top",
            size     = { PANEL_W - 40, 24 },
            position = { 0, -55, 1 },
        },
        glow_picker_placeholder = {
            parent = "glow_picker_panel",
            horizontal_alignment = "center",
            vertical_alignment   = "center",
            size     = { PANEL_W - 40, 60 },
            position = { 0, 0, 1 },
        },
        glow_picker_close_btn = {
            parent = "glow_picker_panel",
            horizontal_alignment = "right",
            vertical_alignment   = "top",
            size     = { 36, 36 },
            position = { -10, -10, 2 },
        },
        glow_picker_apply_btn = {
            parent = "glow_picker_panel",
            horizontal_alignment = "center",
            vertical_alignment   = "bottom",
            size     = { 180, 42 },
            position = { 0, 18, 2 },
        },
        -- v0.9.6 M2: 4 slider rows for R, G, B, intensity. Each row is
        -- 360x24 (label 80 + gap 10 + track 200 + gap 10 + value 60).
        -- Stacked vertically below the subtitle.
        glow_picker_slider_r = {
            parent = "glow_picker_panel",
            horizontal_alignment = "center",
            vertical_alignment   = "top",
            size     = { 360, 24 },
            position = { 0, -110, 1 },
        },
        glow_picker_slider_g = {
            parent = "glow_picker_panel",
            horizontal_alignment = "center",
            vertical_alignment   = "top",
            size     = { 360, 24 },
            position = { 0, -142, 1 },
        },
        glow_picker_slider_b = {
            parent = "glow_picker_panel",
            horizontal_alignment = "center",
            vertical_alignment   = "top",
            size     = { 360, 24 },
            position = { 0, -174, 1 },
        },
        glow_picker_slider_intensity = {
            parent = "glow_picker_panel",
            horizontal_alignment = "center",
            vertical_alignment   = "top",
            size     = { 360, 24 },
            position = { 0, -210, 1 },
        },
        -- v0.9.8 MAGIC family: 3 component sections (Lower Gradient,
        -- Upper Gradient, Dots), each with a header + 4 sliders.
        -- Vertical stack starting at -95 (slightly above where rune
        -- sliders would be), ~152px per section (24 header + 4*32
        -- slider rows). Total ~456px. Rune sliders use -110 to -210
        -- so they overlap visually but only ONE family's widgets are
        -- added to the draw list at a time.
        --
        -- Section 1: Lower Gradient (color_glow_high + color_glow_low)
        glow_picker_label_lower = {
            parent = "glow_picker_panel",
            horizontal_alignment = "center",
            vertical_alignment   = "top",
            size     = { PANEL_W - 60, 22 },
            position = { 0, -95, 1 },
        },
        glow_picker_slider_lower_r = {
            parent = "glow_picker_panel",
            horizontal_alignment = "center",
            vertical_alignment   = "top",
            size     = { 360, 24 },
            position = { 0, -120, 1 },
        },
        glow_picker_slider_lower_g = {
            parent = "glow_picker_panel",
            horizontal_alignment = "center",
            vertical_alignment   = "top",
            size     = { 360, 24 },
            position = { 0, -148, 1 },
        },
        glow_picker_slider_lower_b = {
            parent = "glow_picker_panel",
            horizontal_alignment = "center",
            vertical_alignment   = "top",
            size     = { 360, 24 },
            position = { 0, -176, 1 },
        },
        glow_picker_slider_lower_i = {
            parent = "glow_picker_panel",
            horizontal_alignment = "center",
            vertical_alignment   = "top",
            size     = { 360, 24 },
            position = { 0, -204, 1 },
        },
        -- Section 2: Upper Gradient (color_smoke_high + color_smoke_low)
        glow_picker_label_upper = {
            parent = "glow_picker_panel",
            horizontal_alignment = "center",
            vertical_alignment   = "top",
            size     = { PANEL_W - 60, 22 },
            position = { 0, -240, 1 },
        },
        glow_picker_slider_upper_r = {
            parent = "glow_picker_panel",
            horizontal_alignment = "center",
            vertical_alignment   = "top",
            size     = { 360, 24 },
            position = { 0, -265, 1 },
        },
        glow_picker_slider_upper_g = {
            parent = "glow_picker_panel",
            horizontal_alignment = "center",
            vertical_alignment   = "top",
            size     = { 360, 24 },
            position = { 0, -293, 1 },
        },
        glow_picker_slider_upper_b = {
            parent = "glow_picker_panel",
            horizontal_alignment = "center",
            vertical_alignment   = "top",
            size     = { 360, 24 },
            position = { 0, -321, 1 },
        },
        glow_picker_slider_upper_i = {
            parent = "glow_picker_panel",
            horizontal_alignment = "center",
            vertical_alignment   = "top",
            size     = { 360, 24 },
            position = { 0, -349, 1 },
        },
        -- Section 3: Dots (color_dots)
        glow_picker_label_dots = {
            parent = "glow_picker_panel",
            horizontal_alignment = "center",
            vertical_alignment   = "top",
            size     = { PANEL_W - 60, 22 },
            position = { 0, -385, 1 },
        },
        glow_picker_slider_dots_r = {
            parent = "glow_picker_panel",
            horizontal_alignment = "center",
            vertical_alignment   = "top",
            size     = { 360, 24 },
            position = { 0, -410, 1 },
        },
        glow_picker_slider_dots_g = {
            parent = "glow_picker_panel",
            horizontal_alignment = "center",
            vertical_alignment   = "top",
            size     = { 360, 24 },
            position = { 0, -438, 1 },
        },
        glow_picker_slider_dots_b = {
            parent = "glow_picker_panel",
            horizontal_alignment = "center",
            vertical_alignment   = "top",
            size     = { 360, 24 },
            position = { 0, -466, 1 },
        },
        glow_picker_slider_dots_i = {
            parent = "glow_picker_panel",
            horizontal_alignment = "center",
            vertical_alignment   = "top",
            size     = { 360, 24 },
            position = { 0, -494, 1 },
        },
    }
end

-- v0.9.8: section header widget factory for magic-family section labels.
local function _widget_section_label(scenegraph_id, text)
    return {
        element = {
            passes = {
                { pass_type = "text", style_id = "label", text_id = "label" },
            },
        },
        content = { label = text },
        style = {
            offset = { 0, 0, 0 },
            label = {
                font_type = "hell_shark_header",
                font_size = 18,
                horizontal_alignment = "center",
                vertical_alignment   = "center",
                text_color = { 255, 255, 220, 150 },
                size   = { PANEL_W - 60, 22 },
                offset = { 0, 0, 1 },
            },
        },
        offset        = { 0, 0, 0 },
        scenegraph_id = scenegraph_id,
    }
end

-- v0.9.6 M2: slider widget factory. Minimal hand-rolled slider (track +
-- thumb + label + value text + drag handler). 4 instances stacked in the
-- panel for R / G / B / intensity. The held_function on the hotspot reads
-- cursor X each frame the user holds and computes normalized 0-1 value,
-- which the offset_function uses to position the thumb.
local SLIDER_TRACK_W = 200
local SLIDER_TRACK_H = 16
local SLIDER_THUMB_W = 12
local SLIDER_LABEL_W = 80
local SLIDER_VALUE_W = 60
local SLIDER_GAP     = 10

local function _widget_slider(scenegraph_id, label, min_val, max_val, decimals, thumb_color)
    return {
        element = {
            passes = {
                { content_id = "hotspot", pass_type = "hotspot", style_id = "track" },
                { pass_type = "text", style_id = "label", text_id = "label" },
                { pass_type = "rect", style_id = "track" },
                {
                    content_check_hover = "hotspot",
                    pass_type = "held",
                    style_id  = "track",
                    held_function = function(ui_scenegraph, ui_style, ui_content, input_service)
                        if not (input_service and input_service.get) then return end
                        local cursor = input_service:get("cursor")
                        if not cursor then return end
                        local scaled = cursor
                        if rawget(_G, "UIInverseScaleVectorToResolution") then
                            scaled = UIInverseScaleVectorToResolution(cursor)
                        end
                        local sg_id = ui_content.scenegraph_id
                        local world_pos = UISceneGraph.get_world_position(ui_scenegraph, sg_id)
                        if not world_pos then return end
                        local track_x = world_pos[1] + (ui_style.track and ui_style.track.offset and ui_style.track.offset[1] or 0)
                        local rel = (scaled[1] - track_x) / SLIDER_TRACK_W
                        if rel < 0 then rel = 0 end
                        if rel > 1 then rel = 1 end
                        ui_content.internal_value = rel
                        local real = ui_content.min + (ui_content.max - ui_content.min) * rel
                        if (ui_content.num_decimals or 0) == 0 then
                            real = math.floor(real + 0.5)
                        else
                            local mult = 10 ^ ui_content.num_decimals
                            real = math.floor(real * mult + 0.5) / mult
                        end
                        ui_content.value = real
                        -- v0.9.7: consistent decimal formatting. Integer
                        -- ranges (R/G/B) show "127", decimal ranges
                        -- (intensity) show "1.50" not "1.5".
                        if (ui_content.num_decimals or 0) > 0 then
                            ui_content.value_text = string.format("%." .. ui_content.num_decimals .. "f", real)
                        else
                            ui_content.value_text = tostring(math.floor(real + 0.5))
                        end
                        if ui_content.on_change then
                            local ok = pcall(ui_content.on_change, real)
                            if not ok then ui_content.on_change = nil end  -- detach on error
                        end
                    end,
                },
                {
                    pass_type = "local_offset",
                    offset_function = function(ui_scenegraph, ui_style, ui_content)
                        local rel = ui_content.internal_value or 0
                        local thumb_offset_x = (SLIDER_TRACK_W - SLIDER_THUMB_W) * rel
                        local track_offset_x = ui_style.track and ui_style.track.offset and ui_style.track.offset[1] or 0
                        if ui_style.thumb and ui_style.thumb.offset then
                            ui_style.thumb.offset[1] = track_offset_x + thumb_offset_x
                        end
                    end,
                },
                { pass_type = "rect", style_id = "thumb" },
                { pass_type = "text", style_id = "value_text", text_id = "value_text" },
            },
        },
        content = {
            label          = label,
            value_text     = tostring(min_val),
            internal_value = 0,
            value          = min_val,
            min            = min_val,
            max            = max_val,
            num_decimals   = decimals or 0,
            scenegraph_id  = scenegraph_id,
            hotspot        = {},
            on_change      = nil,
        },
        style = {
            offset = { 0, 0, 0 },
            -- v0.9.7: explicit hotspot style so VMF hit-tests the track
            -- region. Without this, default hotspot used the full 360x24
            -- scenegraph node size including the label area where there's
            -- no visual track to click.
            hotspot = {
                size   = { SLIDER_TRACK_W + 4, SLIDER_TRACK_H + 4 },
                offset = { SLIDER_LABEL_W + SLIDER_GAP - 2, 2, 0 },
            },
            label = {
                font_type = "hell_shark",
                font_size = 16,
                horizontal_alignment = "left",
                vertical_alignment   = "center",
                text_color = { 255, 220, 200, 200 },
                size   = { SLIDER_LABEL_W, SLIDER_TRACK_H },
                offset = { 0, 4, 1 },
            },
            track = {
                size   = { SLIDER_TRACK_W, SLIDER_TRACK_H },
                color  = { 220, 30, 30, 40 },
                offset = { SLIDER_LABEL_W + SLIDER_GAP, 4, 1 },
            },
            thumb = {
                size   = { SLIDER_THUMB_W, SLIDER_TRACK_H },
                color  = thumb_color or { 255, 200, 200, 200 },
                offset = { SLIDER_LABEL_W + SLIDER_GAP, 4, 2 },
            },
            value_text = {
                font_type = "hell_shark",
                font_size = 14,
                horizontal_alignment = "left",
                vertical_alignment   = "center",
                text_color = { 255, 255, 255, 255 },
                size   = { SLIDER_VALUE_W, SLIDER_TRACK_H },
                offset = { SLIDER_LABEL_W + SLIDER_GAP + SLIDER_TRACK_W + SLIDER_GAP, 4, 1 },
            },
        },
        offset        = { 0, 0, 0 },
        scenegraph_id = scenegraph_id,
    }
end

-- --------------------------------------------------------
-- Widget definitions: panel background, title, subtitle, placeholder, X button
-- --------------------------------------------------------
local function _widget_dim_overlay()
    return {
        element = {
            passes = {
                { pass_type = "rect", style_id = "rect" },
            },
        },
        content = { rect = "rect" },
        style = {
            rect = {
                size  = { 1920, 1080 },
                color = { 160, 0, 0, 0 },  -- alpha, r, g, b (semi-opaque black)
            },
        },
        offset    = { 0, 0, 0 },
        scenegraph_id = "glow_picker_dim",
    }
end

local function _widget_panel_bg()
    return {
        element = {
            passes = {
                { pass_type = "rect",   style_id = "rect" },
                { pass_type = "border", style_id = "border" },
            },
        },
        content = {},
        style = {
            rect = {
                size  = { PANEL_W, PANEL_H },
                color = { 245, 18, 18, 24 },  -- dark panel
            },
            border = {
                thickness = 2,
                color     = { 255, 200, 170, 90 },  -- warm parchment edge
            },
        },
        offset    = { 0, 0, 0 },
        scenegraph_id = "glow_picker_panel",
    }
end

local function _widget_title()
    return {
        element = {
            passes = {
                { pass_type = "text", style_id = "text", text_id = "text" },
            },
        },
        content = { text = "Customize Glow" },
        style = {
            text = {
                font_size = 28,
                font_type = "hell_shark_header",
                horizontal_alignment = "center",
                vertical_alignment   = "top",
                text_color = { 255, 240, 230, 200 },
                offset     = { 0, 0, 1 },
                size       = { PANEL_W - 40, 30 },
            },
        },
        offset    = { 0, 0, 1 },
        scenegraph_id = "glow_picker_title",
    }
end

local function _widget_subtitle()
    return {
        element = {
            passes = {
                { pass_type = "text", style_id = "text", text_id = "text" },
            },
        },
        content = { text = "" },
        style = {
            text = {
                font_size = 18,
                font_type = "hell_shark",
                horizontal_alignment = "center",
                vertical_alignment   = "top",
                text_color = { 220, 180, 180, 180 },
                offset     = { 0, 0, 1 },
                size       = { PANEL_W - 40, 24 },
            },
        },
        offset    = { 0, 0, 1 },
        scenegraph_id = "glow_picker_subtitle",
    }
end

local function _widget_placeholder()
    return {
        element = {
            passes = {
                { pass_type = "text", style_id = "text", text_id = "text" },
            },
        },
        content = {
            text = "M1 scaffold: popup hook chain proven. RGB + intensity sliders land in M2.",
        },
        style = {
            text = {
                font_size = 18,
                font_type = "hell_shark",
                horizontal_alignment = "center",
                vertical_alignment   = "center",
                text_color = { 255, 200, 200, 200 },
                offset     = { 0, 0, 1 },
                size       = { PANEL_W - 40, 60 },
                word_wrap  = true,
            },
        },
        offset    = { 0, 0, 1 },
        scenegraph_id = "glow_picker_placeholder",
    }
end

local function _widget_close_button()
    return {
        element = {
            passes = {
                -- Hotspot first so it accepts mouse events
                {
                    content_id = "hotspot",
                    pass_type  = "hotspot",
                },
                -- Background (changes color on hover)
                { pass_type = "rect", style_id = "rect" },
                -- X glyph
                { pass_type = "text", style_id = "text", text_id = "text" },
            },
        },
        content = {
            text     = "X",
            hotspot  = {},
        },
        style = {
            rect = {
                size  = { 36, 36 },
                color = { 200, 60, 20, 20 },
            },
            text = {
                font_size = 22,
                font_type = "hell_shark_header",
                horizontal_alignment = "center",
                vertical_alignment   = "center",
                text_color = { 255, 255, 255, 255 },
                offset     = { 0, 0, 2 },
                size       = { 36, 36 },
            },
        },
        offset    = { 0, 0, 2 },
        scenegraph_id = "glow_picker_close_btn",
    }
end

local function _widget_apply_button()
    return {
        element = {
            passes = {
                { content_id = "hotspot", pass_type = "hotspot" },
                { pass_type = "rect", style_id = "rect" },
                { pass_type = "border", style_id = "border" },
                { pass_type = "text", style_id = "text", text_id = "text" },
            },
        },
        content = { text = "Apply", hotspot = {} },
        style = {
            rect = { size = { 180, 42 }, color = { 210, 55, 75, 35 } },
            border = { thickness = 2, color = { 255, 210, 180, 90 } },
            text = {
                font_size = 22, font_type = "hell_shark_header",
                horizontal_alignment = "center", vertical_alignment = "center",
                text_color = { 255, 245, 235, 205 }, offset = { 0, 0, 2 },
                size = { 180, 42 },
            },
        },
        offset = { 0, 0, 2 },
        scenegraph_id = "glow_picker_apply_btn",
    }
end

local function _update_apply_widget()
    local widget = GlowPicker._widgets_by_name and GlowPicker._widgets_by_name.apply_btn
    if not widget then return end
    local dirty = GlowPicker._dirty == true
    widget.content.text = dirty and "Apply" or "Applied"
    widget.style.rect.color = dirty and { 230, 55, 105, 45 } or { 150, 45, 45, 45 }
    widget.style.border.color = dirty and { 255, 230, 195, 95 } or { 140, 120, 120, 120 }
    widget.style.text.text_color = dirty and { 255, 245, 235, 205 } or { 160, 180, 180, 180 }
end

-- --------------------------------------------------------
-- Build / teardown (idempotent; survives across screen re-enters)
-- --------------------------------------------------------
-- M1.2 diagnostics: every step pcall'd and logged so we can pinpoint exactly
-- where the chain breaks. If you see "[glow_picker:_build] start" but not
-- "[glow_picker:_build] DONE", a UIWidget/UISceneGraph call is throwing.
local function _try(label, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        _log_only("[glow_picker] FAILED at %s: %s", label, tostring(err))
        mod:info("[glow_picker] FAILED at %s: %s", label, tostring(err))
        return nil, err
    end
    return ok
end

local function _build()
    if GlowPicker._built then return true end
    _log_only("[glow_picker:_build] start")
    mod:info("[glow_picker:_build] start. UISceneGraph=%s UIWidget=%s UIRenderer=%s UILayer=%s",
        tostring(UISceneGraph), tostring(UIWidget), tostring(UIRenderer), tostring(UILayer))

    if not (UISceneGraph and UIWidget and UIRenderer) then
        _log_only("[glow_picker:_build] ABORT — missing core UI globals")
        return false
    end

    local sg_ok, sg_err = pcall(UISceneGraph.init_scenegraph, _make_scenegraph_definition())
    if not sg_ok then
        _log_only("[glow_picker:_build] init_scenegraph FAILED: %s", tostring(sg_err))
        return false
    end
    GlowPicker._scenegraph = sg_err  -- pcall returns the value as the 2nd ret
    mod:info("[glow_picker:_build] scenegraph init OK")

    -- v0.9.8: build ALL widgets at boot (rune family 4 + magic family
    -- 3 sections × 4 sliders + 3 section labels = 19). At open_for time
    -- the draw list is filtered to just the active family's widgets.
    local thumb_r = { 255, 220,  60,  60 }
    local thumb_g = { 255,  60, 220,  60 }
    local thumb_b = { 255,  60,  60, 220 }
    local thumb_i = { 255, 220, 220, 220 }
    local widget_factories = {
        { "panel_bg",    _widget_panel_bg      },
        { "title",       _widget_title         },
        { "subtitle",    _widget_subtitle      },
        { "close_btn",   _widget_close_button  },
        { "apply_btn",   _widget_apply_button  },
        -- RUNE family (4 sliders)
        { "slider_r",         function() return _widget_slider("glow_picker_slider_r",         "Red",       0,   255, 0, thumb_r) end },
        { "slider_g",         function() return _widget_slider("glow_picker_slider_g",         "Green",     0,   255, 0, thumb_g) end },
        { "slider_b",         function() return _widget_slider("glow_picker_slider_b",         "Blue",      0,   255, 0, thumb_b) end },
        { "slider_intensity", function() return _widget_slider("glow_picker_slider_intensity", "Intensity", 0.0, 5.0, 2, thumb_i) end },
        -- MAGIC family — Section 1: Lower Gradient
        { "label_lower",      function() return _widget_section_label("glow_picker_label_lower", "Lower Gradient") end },
        { "slider_lower_r",   function() return _widget_slider("glow_picker_slider_lower_r", "Red",       0,   255, 0, thumb_r) end },
        { "slider_lower_g",   function() return _widget_slider("glow_picker_slider_lower_g", "Green",     0,   255, 0, thumb_g) end },
        { "slider_lower_b",   function() return _widget_slider("glow_picker_slider_lower_b", "Blue",      0,   255, 0, thumb_b) end },
        { "slider_lower_i",   function() return _widget_slider("glow_picker_slider_lower_i", "Intensity", 0.0, 5.0, 2, thumb_i) end },
        -- MAGIC family — Section 2: Upper Gradient
        { "label_upper",      function() return _widget_section_label("glow_picker_label_upper", "Upper Gradient") end },
        { "slider_upper_r",   function() return _widget_slider("glow_picker_slider_upper_r", "Red",       0,   255, 0, thumb_r) end },
        { "slider_upper_g",   function() return _widget_slider("glow_picker_slider_upper_g", "Green",     0,   255, 0, thumb_g) end },
        { "slider_upper_b",   function() return _widget_slider("glow_picker_slider_upper_b", "Blue",      0,   255, 0, thumb_b) end },
        { "slider_upper_i",   function() return _widget_slider("glow_picker_slider_upper_i", "Intensity", 0.0, 5.0, 2, thumb_i) end },
        -- MAGIC family — Section 3: Dots
        { "label_dots",       function() return _widget_section_label("glow_picker_label_dots", "Dots") end },
        { "slider_dots_r",    function() return _widget_slider("glow_picker_slider_dots_r", "Red",       0,   255, 0, thumb_r) end },
        { "slider_dots_g",    function() return _widget_slider("glow_picker_slider_dots_g", "Green",     0,   255, 0, thumb_g) end },
        { "slider_dots_b",    function() return _widget_slider("glow_picker_slider_dots_b", "Blue",      0,   255, 0, thumb_b) end },
        { "slider_dots_i",    function() return _widget_slider("glow_picker_slider_dots_i", "Intensity", 0.0, 5.0, 2, thumb_i) end },
    }
    local by_name = {}
    for _, entry in ipairs(widget_factories) do
        local name, factory = entry[1], entry[2]
        local def_ok, def = pcall(factory)
        if not def_ok then
            _log_only("[glow_picker:_build] factory FAILED for %s: %s", name, tostring(def))
            return false
        end
        local w_ok, w = pcall(UIWidget.init, def)
        if not w_ok then
            _log_only("[glow_picker:_build] UIWidget.init FAILED for %s: %s", name, tostring(w))
            return false
        end
        by_name[name] = w
        mod:info("[glow_picker:_build] widget '%s' built", name)
    end

    -- v0.9.8: draw list now decided in open_for() based on detected
    -- family. _build keeps all 23 widgets in _widgets_by_name; the
    -- _widgets array is set per-open.
    GlowPicker._widgets_by_name = by_name

    -- v0.9.8: helper builds the per-component on_change callback. Writes
    -- to the named component table on _current_glow_state, fires live
    -- preview. Supports rune/lower/upper/dots.
    local function _make_on_change(component, field)
        return function(v)
            local s = GlowPicker._current_glow_state
            if not s then return end
            local comp = s[component]
            if not comp then return end
            comp[field] = v
            GlowPicker._dirty = true
            _update_apply_widget()
            GlowPicker._live_preview()
        end
    end
    by_name.slider_r.content.on_change         = _make_on_change("rune",  "r")
    by_name.slider_g.content.on_change         = _make_on_change("rune",  "g")
    by_name.slider_b.content.on_change         = _make_on_change("rune",  "b")
    by_name.slider_intensity.content.on_change = _make_on_change("rune",  "intensity")
    by_name.slider_lower_r.content.on_change   = _make_on_change("lower", "r")
    by_name.slider_lower_g.content.on_change   = _make_on_change("lower", "g")
    by_name.slider_lower_b.content.on_change   = _make_on_change("lower", "b")
    by_name.slider_lower_i.content.on_change   = _make_on_change("lower", "intensity")
    by_name.slider_upper_r.content.on_change   = _make_on_change("upper", "r")
    by_name.slider_upper_g.content.on_change   = _make_on_change("upper", "g")
    by_name.slider_upper_b.content.on_change   = _make_on_change("upper", "b")
    by_name.slider_upper_i.content.on_change   = _make_on_change("upper", "intensity")
    by_name.slider_dots_r.content.on_change    = _make_on_change("dots",  "r")
    by_name.slider_dots_g.content.on_change    = _make_on_change("dots",  "g")
    by_name.slider_dots_b.content.on_change    = _make_on_change("dots",  "b")
    by_name.slider_dots_i.content.on_change    = _make_on_change("dots",  "intensity")

    GlowPicker._built = true
    _log_only("[glow_picker:_build] DONE — 24 widgets ready (RGB sliders + explicit Apply transaction)")
    return true
end

-- --------------------------------------------------------
-- Public API: open / close / introspection
-- --------------------------------------------------------

-- Classify whether an item is glow-eligible based on its skin key + 3p unit
-- path. Returns: nil (not eligible) | "rune" (single component) | "magic"
-- (3 components: lower/upper/dots). Used by the cosmetic-screen button to
-- decide whether to surface the popup entry point at all.
function GlowPicker.classify(slot_data)
    if not slot_data then return nil end
    local skin = slot_data.skin
    local right3p = slot_data.right_unit_3p
    local left3p  = slot_data.left_unit_3p

    -- v0.9.34: PRIMARY signal is the skin's material_settings_name — the same
    -- field the engine itself keys glow on (gear_utils.lua:107/155). The 9
    -- families confirmed in the 2026-06-11 decompile sweep: weaves + versus
    -- carry the 5-channel magic layout; blue_glow / purple_glow / golden_glow /
    -- deep_crimson / life_green / lileath / white_glow are single-channel rune.
    -- This catches every templated skin regardless of key-suffix quirks (the
    -- old suffix-only regex missed bare `_runed` CW deus skins like
    -- dr_deus_01_skin_01_runed, weapon_skins_morris.lua:64).
    if type(skin) == "string" and skin ~= "" then
        local skins = rawget(_G, "WeaponSkins")
        local entry = skins and skins.skins and skins.skins[skin]
        local mat = entry and entry.material_settings_name
        if type(mat) == "string" then
            if mat == "weaves" or mat == "versus" then return "magic" end
            return "rune"
        end
    end

    -- Suffix fallback (LA custom skins set skin="" but rest on a glow-capable
    -- underlying mesh; also covers pre-WeaponSkins-load calls).
    local function suffix_check(s)
        if type(s) ~= "string" then return nil end
        if s:find("_magic_01$") or s:find("_magic_02$") then return "magic" end
        if s:find("_runed$")  -- v0.9.34: bare-suffix CW deus skins
            or s:find("_runed_01$") or s:find("_runed_02$") or s:find("_runed_03$")
            or s:find("_runed_04$") or s:find("_runed_05$") or s:find("_runed_06$")
            or s:find("_runed_02_white$") then return "rune" end
        return nil
    end
    return suffix_check(skin)
        or suffix_check(right3p)
        or suffix_check(left3p)
end

-- v0.9.6 M2: persistence helpers. Single VMF setting `glow_per_item`
-- holds a JSON-encoded `{ [backend_id]: { rune={r,g,b,intensity}, ... } }`
-- map. Read on popup-open, write on popup-close.
local _cjson_warning_shown = false
local _persisted_cache = nil
local function _load_per_item_glow()
    if type(_persisted_cache) == "table" then return _persisted_cache end
    if not cjson then
        if not _cjson_warning_shown then
            _log_only("[glow_picker] cjson global is nil — per-item glow persistence DISABLED; live preview remains available")
            mod:info("[glow_picker] cjson unavailable; persistence layer no-op")
            _cjson_warning_shown = true
        end
        _persisted_cache = {}
        return _persisted_cache
    end
    local raw = mod:get("glow_per_item")
    if not raw or raw == "" then
        _persisted_cache = {}
        return _persisted_cache
    end
    local ok, decoded = pcall(cjson.decode, raw)
    _persisted_cache = (ok and type(decoded) == "table") and decoded or {}
    return _persisted_cache
end

local function _save_per_item_glow(data)
    if not cjson then return end
    local ok, encoded = pcall(cjson.encode, data)
    if ok and encoded then
        mod:set("glow_per_item", encoded)
        _persisted_cache = data
    end
end

local function _persisted_state_for(backend_id, slot_data)
    local all_data = _load_per_item_glow()
    local identity = _identity_key(backend_id, slot_data)
    local state = identity and all_data[identity] or nil
    -- One-time compatibility with the original backend-id-only storage.
    if not state and backend_id ~= nil then state = all_data[backend_id] end
    return type(state) == "table" and _clone(state) or nil, identity
end

-- Called by the equipment spawn path so an applied value is restored after a
-- restart before the picker is opened again.
function GlowPicker.restore_runtime_for(backend_id, slot_data)
    local state, identity = _persisted_state_for(backend_id, slot_data)
    if not state or backend_id == nil then return nil end
    mod._per_item_glow_runtime = mod._per_item_glow_runtime or {}
    mod._per_item_glow_identity_runtime = mod._per_item_glow_identity_runtime or {}
    mod._per_item_glow_runtime[backend_id] = state
    mod._per_item_glow_identity_runtime[backend_id] = identity
    return state, identity
end

-- Update slider widget values from the in-memory state. Called on
-- open_for after loading persisted state. Recomputes internal_value
-- (0-1) from the real value. v0.9.8: handles both rune AND magic
-- families (writes to whichever component sliders are visible).
local function _sync_sliders_from_state()
    if not GlowPicker._widgets_by_name then return end
    local s = GlowPicker._current_glow_state
    if not s then return end
    local by_name = GlowPicker._widgets_by_name
    local function _apply(widget, val)
        if not widget then return end
        local c = widget.content
        c.value = val
        local range = (c.max - c.min)
        c.internal_value = (range > 0) and ((val - c.min) / range) or 0
        if c.internal_value < 0 then c.internal_value = 0 end
        if c.internal_value > 1 then c.internal_value = 1 end
        if (c.num_decimals or 0) > 0 then
            c.value_text = string.format("%." .. c.num_decimals .. "f", val)
        else
            c.value_text = tostring(math.floor(val + 0.5))
        end
    end
    if s.rune then
        _apply(by_name.slider_r,         s.rune.r or 0)
        _apply(by_name.slider_g,         s.rune.g or 0)
        _apply(by_name.slider_b,         s.rune.b or 0)
        _apply(by_name.slider_intensity, s.rune.intensity or 1.0)
    end
    if s.lower then
        _apply(by_name.slider_lower_r, s.lower.r or 0)
        _apply(by_name.slider_lower_g, s.lower.g or 0)
        _apply(by_name.slider_lower_b, s.lower.b or 0)
        _apply(by_name.slider_lower_i, s.lower.intensity or 1.0)
    end
    if s.upper then
        _apply(by_name.slider_upper_r, s.upper.r or 0)
        _apply(by_name.slider_upper_g, s.upper.g or 0)
        _apply(by_name.slider_upper_b, s.upper.b or 0)
        _apply(by_name.slider_upper_i, s.upper.intensity or 1.0)
    end
    if s.dots then
        _apply(by_name.slider_dots_r, s.dots.r or 0)
        _apply(by_name.slider_dots_g, s.dots.g or 0)
        _apply(by_name.slider_dots_b, s.dots.b or 0)
        _apply(by_name.slider_dots_i, s.dots.intensity or 1.0)
    end
end

-- v0.9.6 M2: live preview. While the popup is open, on every slider drag
-- the local player's wielded weapon's glow re-applies with the new RGB.
-- The cosmetics_tweaker glow apply pipeline consults `glow_per_item`
-- (via mod._per_item_glow_runtime — set below on open) FIRST in
-- _glow_rgb_for_var, before falling back to global preset.
function GlowPicker._live_preview()
    -- Drag callbacks happen frequently; this is intentionally cheap.
    -- Sync the runtime override table for our backend_id from the
    -- in-memory state so the existing glow apply pipeline picks it up
    -- on next paint.
    mod._per_item_glow_runtime = mod._per_item_glow_runtime or {}
    if GlowPicker._current_backend_id and GlowPicker._current_glow_state then
        mod._per_item_glow_runtime[GlowPicker._current_backend_id] = GlowPicker._current_glow_state
    end
    -- Re-apply on the wielded weapon if available. Pcall-safe; failures
    -- silent (live preview is best-effort).
    if mod._reapply_glow_on_wielded then
        pcall(mod._reapply_glow_on_wielded)
    end
end

function GlowPicker.open_for(backend_id, slot_data)
    _build()
    GlowPicker._current_backend_id = backend_id
    GlowPicker._current_slot_data  = slot_data
    GlowPicker._current_identity   = _identity_key(backend_id, slot_data)
    GlowPicker._open               = true

    -- v0.9.8: detect family for this item. classify() returns "rune" /
    -- "magic" / nil. The popup builds state + assembles draw list
    -- accordingly.
    local family = GlowPicker.classify(slot_data) or "rune"  -- fallback: rune for unknown
    GlowPicker._current_family = family

    -- Load persisted state (multi-component shape supported).
    local persisted = _persisted_state_for(backend_id, slot_data)
    local item_data = persisted or {}
    GlowPicker._committed_glow_state = persisted and _clone(persisted) or nil
    GlowPicker._dirty = false

    if family == "magic" then
        GlowPicker._current_glow_state = {
            lower = {
                r         = (item_data.lower and item_data.lower.r)         or 180,
                g         = (item_data.lower and item_data.lower.g)         or 100,
                b         = (item_data.lower and item_data.lower.b)         or 255,
                intensity = (item_data.lower and item_data.lower.intensity) or 1.0,
            },
            upper = {
                r         = (item_data.upper and item_data.upper.r)         or 220,
                g         = (item_data.upper and item_data.upper.g)         or 180,
                b         = (item_data.upper and item_data.upper.b)         or 255,
                intensity = (item_data.upper and item_data.upper.intensity) or 1.0,
            },
            dots = {
                r         = (item_data.dots and item_data.dots.r)         or 255,
                g         = (item_data.dots and item_data.dots.g)         or 255,
                b         = (item_data.dots and item_data.dots.b)         or 255,
                intensity = (item_data.dots and item_data.dots.intensity) or 1.0,
            },
        }
    else
        GlowPicker._current_glow_state = {
            rune = {
                r         = (item_data.rune and item_data.rune.r)         or 200,
                g         = (item_data.rune and item_data.rune.g)         or  60,
                b         = (item_data.rune and item_data.rune.b)         or 255,
                intensity = (item_data.rune and item_data.rune.intensity) or 1.0,
            },
        }
    end
    _sync_sliders_from_state()

    -- v0.9.8: assemble family-specific draw list. Magic shows 12
    -- sliders + 3 section labels; rune shows 4 sliders.
    local by_name = GlowPicker._widgets_by_name
    local widgets = { by_name.panel_bg, by_name.title, by_name.subtitle, by_name.close_btn, by_name.apply_btn }
    if family == "magic" then
        widgets[#widgets+1] = by_name.label_lower
        widgets[#widgets+1] = by_name.slider_lower_r
        widgets[#widgets+1] = by_name.slider_lower_g
        widgets[#widgets+1] = by_name.slider_lower_b
        widgets[#widgets+1] = by_name.slider_lower_i
        widgets[#widgets+1] = by_name.label_upper
        widgets[#widgets+1] = by_name.slider_upper_r
        widgets[#widgets+1] = by_name.slider_upper_g
        widgets[#widgets+1] = by_name.slider_upper_b
        widgets[#widgets+1] = by_name.slider_upper_i
        widgets[#widgets+1] = by_name.label_dots
        widgets[#widgets+1] = by_name.slider_dots_r
        widgets[#widgets+1] = by_name.slider_dots_g
        widgets[#widgets+1] = by_name.slider_dots_b
        widgets[#widgets+1] = by_name.slider_dots_i
    else
        widgets[#widgets+1] = by_name.slider_r
        widgets[#widgets+1] = by_name.slider_g
        widgets[#widgets+1] = by_name.slider_b
        widgets[#widgets+1] = by_name.slider_intensity
    end
    GlowPicker._widgets = widgets
    _update_apply_widget()

    -- Push runtime override so live preview applies immediately.
    mod._per_item_glow_runtime = mod._per_item_glow_runtime or {}
    if backend_id then
        mod._per_item_glow_runtime[backend_id] = GlowPicker._current_glow_state
    end

    -- Update subtitle to reflect the current item
    local subtitle = string.format("backend_id: %s • family: %s",
        tostring(backend_id):sub(1, 16), tostring(family))
    if by_name.subtitle then
        by_name.subtitle.content.text = subtitle
    end
    mod:info("[glow_picker] opened for backend_id=%s family=%s widgets=%d",
        tostring(backend_id), tostring(family), #widgets)
end

function GlowPicker.apply()
    if not GlowPicker._open or not GlowPicker._dirty then return false end
    local backend_id = GlowPicker._current_backend_id
    local identity = GlowPicker._current_identity
    local state = GlowPicker._current_glow_state
    if backend_id == nil or identity == nil or type(state) ~= "table" then return false end

    local committed = _clone(state)
    local all_data = _load_per_item_glow()
    all_data[identity] = committed
    _save_per_item_glow(all_data)
    GlowPicker._committed_glow_state = _clone(committed)
    GlowPicker._dirty = false
    mod._per_item_glow_runtime = mod._per_item_glow_runtime or {}
    mod._per_item_glow_identity_runtime = mod._per_item_glow_identity_runtime or {}
    mod._per_item_glow_runtime[backend_id] = _clone(committed)
    mod._per_item_glow_identity_runtime[backend_id] = identity
    mod._active_per_item_glow = _clone(committed)
    mod._active_per_item_glow_identity = identity
    local slot_data = GlowPicker._current_slot_data
    local item_data = type(slot_data) == "table" and slot_data.item_data or nil
    mod._active_per_item_glow_skin = type(slot_data) == "table" and (slot_data.skin or "")
        or (identity:match("|skin:(.*)$") or "")
    mod._active_per_item_glow_slot = type(slot_data) == "table"
        and (slot_data.id or slot_data.slot_name) or nil
    mod._active_per_item_glow_item_name = item_data and item_data.name or nil
    mod._active_per_item_glow_item_template = item_data and item_data.template or nil
    if mod._reapply_glow_on_wielded then pcall(mod._reapply_glow_on_wielded) end
    if mod._emit_per_item_glow then pcall(mod._emit_per_item_glow) end
    _update_apply_widget()
    _apply_log_only("[glow_picker:apply] committed identity=%s family=%s emit=1", identity, tostring(GlowPicker._current_family))
    return true
end

function GlowPicker.close()
    if not GlowPicker._open then return end
    -- Close/cancel discards uncommitted preview edits and repaints the last
    -- applied value (or vanilla when this identity had no saved override).
    local backend_id = GlowPicker._current_backend_id
    if backend_id ~= nil then
        mod._per_item_glow_runtime = mod._per_item_glow_runtime or {}
        mod._per_item_glow_runtime[backend_id] = GlowPicker._committed_glow_state
            and _clone(GlowPicker._committed_glow_state) or nil
        if mod._reapply_glow_on_wielded then pcall(mod._reapply_glow_on_wielded) end
    end
    GlowPicker._open               = false
    GlowPicker._current_backend_id = nil
    GlowPicker._current_slot_data  = nil
    GlowPicker._current_identity   = nil
    GlowPicker._current_glow_state = nil
    GlowPicker._committed_glow_state = nil
    GlowPicker._current_family     = nil
    GlowPicker._dirty              = false
end

function GlowPicker.is_open()
    return GlowPicker._open
end

-- --------------------------------------------------------
-- Per-frame: input + render
-- --------------------------------------------------------
function GlowPicker.handle_input(input_service)
    if not GlowPicker._open then return false end
    local by_name = GlowPicker._widgets_by_name
    if not by_name then return false end
    local close = by_name.close_btn
    local hotspot = close and close.content and close.content.hotspot
    if hotspot and hotspot.on_release then
        hotspot.on_release = false
        GlowPicker.close()
        return true  -- swallowed: don't let click also dispatch to screen
    end
    local apply = by_name.apply_btn
    local apply_hotspot = apply and apply.content and apply.content.hotspot
    if apply_hotspot and apply_hotspot.on_release then
        apply_hotspot.on_release = false
        GlowPicker.apply()
        return true
    end
    -- v0.9.3.7: dim removed → clicks OUTSIDE the panel should pass through
    -- to the cosmetic screen behind. Previously we swallowed all left-
    -- press input while open; without the dim that would block the user
    -- from clicking buttons on the cosmetic screen visible around the
    -- panel.
    --
    -- Scope swallow to clicks INSIDE the panel bounds. The panel is
    -- anchored top-center at (PANEL_W=600, PANEL_H=400) with TOP_INSET=80
    -- offset from screen top. At 1920x1080 the panel covers x=[660..1260],
    -- y=[80..480]. Mouse coords from input_service:get("cursor") are in
    -- 1080p resolution coordinates after UIInverseScaleVectorToResolution
    -- (vanilla pattern). Below we compute panel rect in those coords and
    -- check the cursor.
    if input_service and input_service.get then
        local pressed = input_service:get("left_press")
        if pressed then
            local cursor = input_service:get("cursor")
            if cursor then
                local cx, cy
                if rawget(_G, "UIInverseScaleVectorToResolution") then
                    local scaled = UIInverseScaleVectorToResolution(cursor)
                    cx, cy = scaled[1], scaled[2]
                else
                    cx, cy = cursor[1], cursor[2]
                end
                -- 1920x1080 logical. Panel top-center: x_center=960,
                -- y from TOP_INSET=80 down PANEL_H=400.
                local x_min, x_max = 960 - PANEL_W/2, 960 + PANEL_W/2
                local y_min, y_max = TOP_INSET, TOP_INSET + PANEL_H
                if cx and cy
                    and cx >= x_min and cx <= x_max
                    and cy >= y_min and cy <= y_max then
                    return true  -- click inside panel: swallow
                end
            end
            -- Click outside panel: don't swallow, let cosmetic screen handle.
        end
    end
    return false
end

-- Throttle draw-hook logging so it doesn't spam every frame.
GlowPicker._draw_log_frame = 0
function GlowPicker.draw(ui_renderer, input_service, dt)
    if not GlowPicker._open then return end
    if not GlowPicker._built then
        _log_only("[glow_picker:draw] open=true but built=false — _build never succeeded")
        return
    end
    if not ui_renderer then
        if (GlowPicker._draw_log_frame % 60) == 0 then
            _log_only("[glow_picker:draw] ui_renderer is nil — host hook passed nothing")
        end
        GlowPicker._draw_log_frame = GlowPicker._draw_log_frame + 1
        return
    end
    GlowPicker._draw_log_frame = GlowPicker._draw_log_frame + 1
    -- Log first frame + every 120 frames thereafter to confirm draw loop is alive.
    local should_log = (GlowPicker._draw_log_frame == 1) or (GlowPicker._draw_log_frame % 120 == 0)
    if should_log then
        mod:info("[glow_picker:draw] frame=%d widgets=%d renderer=%s",
            GlowPicker._draw_log_frame, #(GlowPicker._widgets or {}), tostring(ui_renderer))
    end

    local ok_u, err_u = pcall(UISceneGraph.update_scenegraph, GlowPicker._scenegraph)
    if not ok_u then
        _log_only("[glow_picker:draw] update_scenegraph FAILED: %s", tostring(err_u))
        return
    end

    local ok_b, err_b = pcall(UIRenderer.begin_pass, ui_renderer, GlowPicker._scenegraph,
        input_service, dt, nil, { snap_pixel_positions = true })
    if not ok_b then
        _log_only("[glow_picker:draw] begin_pass FAILED: %s", tostring(err_b))
        return
    end

    for i, widget in ipairs(GlowPicker._widgets) do
        local ok_w, err_w = pcall(UIRenderer.draw_widget, ui_renderer, widget)
        if not ok_w and should_log then
            _log_only("[glow_picker:draw] draw_widget #%d FAILED: %s", i, tostring(err_w))
        end
    end

    local ok_e, err_e = pcall(UIRenderer.end_pass, ui_renderer)
    if not ok_e then
        _log_only("[glow_picker:draw] end_pass FAILED: %s", tostring(err_e))
    end
end

return GlowPicker
