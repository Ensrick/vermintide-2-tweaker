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
GlowPicker._commit_revision       = 0
GlowPicker._has_override          = false     -- #610: true only when a committed override exists
GlowPicker._native_mat            = nil       -- #610: selected illusion's material_settings_name

local function _clone(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, child in pairs(value) do copy[key] = _clone(child) end
    return copy
end

-- #48: exact-instance identity, runtime-rebind, and remote-match policy live in
-- one pure module so the picker and the renderer cannot drift apart. Pure and
-- stateless, so a per-consumer dofile instance is safe.
local INSTANCE_POLICY = mod:dofile("scripts/mods/cosmetics_tweaker/_cos_glow_instance_policy")

-- Backend ids identify the inventory instance; the skin suffix keeps a glow
-- choice attached to the exact illusion variant when an item's illusion changes.
local function _identity_key(backend_id, slot_data)
    return INSTANCE_POLICY.identity_key(backend_id, slot_data)
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
local TOGGLE_Y_NUDGE   = -4   -- #377 follow-up: user-confirmed button was a few pixels high

-- Proven CIM/GUT ornate nine-slice frame contract. This texture is resident on
-- the popup/hero renderers used below; keeping one constructor prevents the
-- persistent toggle, panel, Apply, and Close controls from drifting apart.
GlowPicker.FRAME_TEXTURE = "menu_frame_12"
GlowPicker.FRAME_TEX_SIZE = { 64, 64 }
GlowPicker.FRAME_TEX_SIZES = {
    corner = { 11, 11 },
    vertical = { 5, 1 },
    horizontal = { 1, 5 },
}

function GlowPicker.frame_style(width, height, z, color)
    return {
        texture_size = GlowPicker.FRAME_TEX_SIZE,
        texture_sizes = GlowPicker.FRAME_TEX_SIZES,
        color = color or { 255, 255, 255, 255 },
        offset = { 0, 0, z or 3 },
        area_size = { width, height },
    }
end

-- #377: the persistent Edit Glow toggle belongs to the panel geometry even
-- while the panel is closed. Return its lower-right-aligned origin in the
-- same 1920x1080 virtual canvas used by the customization screen. Keeping the
-- calculation here prevents the caller from drifting away from panel changes.
function GlowPicker.toggle_anchor(button_width, z)
    button_width = tonumber(button_width) or 0
    local panel_right = (1920 + PANEL_W) * 0.5
    local panel_bottom = 1080 - TOP_INSET - PANEL_H
    return { panel_right - button_width, panel_bottom + TOGGLE_Y_NUDGE, z or 20 }
end

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
        -- #610 Restore to Default: clears the per-item override and repaints the
        -- illusion's native glow. Bottom-left so it never crowds the sliders.
        glow_picker_restore_btn = {
            parent = "glow_picker_panel",
            horizontal_alignment = "left",
            vertical_alignment   = "bottom",
            size     = { 176, 42 },
            position = { 18, 18, 2 },
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
                { pass_type = "texture_frame", style_id = "frame", texture_id = "frame" },
            },
        },
        content = { frame = GlowPicker.FRAME_TEXTURE },
        style = {
            rect = {
                size  = { PANEL_W, PANEL_H },
                color = { 245, 18, 18, 24 },  -- dark panel
            },
            frame = GlowPicker.frame_style(PANEL_W, PANEL_H, 3),
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
                { pass_type = "texture_frame", style_id = "frame", texture_id = "frame" },
            },
        },
        content = {
            text     = "X",
            frame    = GlowPicker.FRAME_TEXTURE,
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
            frame = GlowPicker.frame_style(36, 36, 3),
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
                { pass_type = "text", style_id = "text", text_id = "text" },
                { pass_type = "texture_frame", style_id = "frame", texture_id = "frame" },
            },
        },
        content = { text = "Apply", frame = GlowPicker.FRAME_TEXTURE, hotspot = {} },
        style = {
            rect = { size = { 180, 42 }, color = { 210, 55, 75, 35 } },
            frame = GlowPicker.frame_style(180, 42, 3),
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
    widget.style.frame.color = dirty and { 255, 255, 255, 255 } or { 150, 180, 180, 180 }
    widget.style.text.text_color = dirty and { 255, 245, 235, 205 } or { 160, 180, 180, 180 }
end

-- #610 Restore to Default is meaningful only when a committed override exists;
-- grey it out otherwise so it can never persist or paint a no-op.
local function _update_restore_widget()
    local widget = GlowPicker._widgets_by_name and GlowPicker._widgets_by_name.restore_btn
    if not widget then return end
    local enabled = GlowPicker._has_override == true
    local hotspot = widget.content and widget.content.hotspot
    if hotspot then hotspot.disable_button = not enabled end
    widget.style.rect.color = enabled and { 210, 70, 55, 30 } or { 120, 45, 45, 45 }
    widget.style.frame.color = enabled and { 255, 255, 255, 255 } or { 140, 170, 170, 170 }
    widget.style.text.text_color = enabled and { 255, 235, 225, 200 } or { 140, 170, 170, 170 }
end

local function _widget_restore_button()
    return {
        element = {
            passes = {
                { content_id = "hotspot", pass_type = "hotspot" },
                { pass_type = "rect", style_id = "rect" },
                { pass_type = "text", style_id = "text", text_id = "text" },
                { pass_type = "texture_frame", style_id = "frame", texture_id = "frame" },
            },
        },
        content = { text = "Restore Default", frame = GlowPicker.FRAME_TEXTURE, hotspot = {} },
        style = {
            rect = { size = { 176, 42 }, color = { 210, 70, 55, 30 } },
            frame = GlowPicker.frame_style(176, 42, 3),
            text = {
                font_size = 16, font_type = "hell_shark_header",
                horizontal_alignment = "center", vertical_alignment = "center",
                text_color = { 255, 235, 225, 200 }, offset = { 0, 0, 2 },
                size = { 176, 42 },
            },
        },
        offset = { 0, 0, 2 },
        scenegraph_id = "glow_picker_restore_btn",
    }
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
        { "restore_btn", _widget_restore_button },
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
    _log_only("[glow_picker:_build] DONE — widgets ready (RGB sliders + Apply + Restore Default transaction)")
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

-- #610: native-glow resolution. Opening the editor on an untouched illusion
-- must show that illusion's OWN glow, never a fixed placeholder colour (the
-- old magenta 200/60/255 default made every weapon read as forced pink and
-- could be applied/persisted by accident). We reconstruct the picker's
-- 0-255 + intensity display model from the illusion's MaterialSettingsTemplate
-- so a re-apply reproduces the native HDR magnitude faithfully.
--
-- Native shader-var brightness must match the paint pipeline in _cos_glow.lua
-- (_GLOW_VAR_BRIGHTNESS): rune=9, color_glow_high=4, color_smoke_high=0.22,
-- color_dots=8.35. The picker collapses each magic component onto one control,
-- so a component reconstructs from its primary channel (glow_high / smoke_high
-- / dots).
local _NATIVE_BRIGHTNESS = {
    rune_emissive_color = 9,
    color_glow_high     = 4,
    color_smoke_high    = 0.22,
    color_dots          = 8.35,
}

-- Convert an HDR vector3 template entry {x,y,z} into {r,g,b,intensity}:
-- normalize so the brightest channel maps to 255, set intensity so the picker's
-- paint (scale = brightness * intensity / 255) reproduces the native magnitude.
local function _hdr_to_display(entry, brightness)
    if type(entry) ~= "table" then return nil end
    local x = tonumber(entry.x) or 0
    local y = tonumber(entry.y) or 0
    local z = tonumber(entry.z) or 0
    local m = math.max(x, y, z)
    if m <= 0 then return { r = 0, g = 0, b = 0, intensity = 0 } end
    local intensity = m / (brightness or 1)
    if intensity > 5 then intensity = 5 elseif intensity < 0 then intensity = 0 end
    return {
        r = math.floor(x / m * 255 + 0.5),
        g = math.floor(y / m * 255 + 0.5),
        b = math.floor(z / m * 255 + 0.5),
        intensity = intensity,
    }
end
GlowPicker.hdr_to_display = _hdr_to_display

-- Resolve the illusion's native glow into the picker's display model. Returns
-- (display_state, material_settings_name). Fails closed (nil) when the skin has
-- no registered template so an unknown family NEVER invents a colour (#610).
local function _resolve_native(slot_data, family)
    local skin = type(slot_data) == "table" and slot_data.skin or nil
    if type(skin) ~= "string" or skin == "" then return nil, nil end
    local skins = rawget(_G, "WeaponSkins")
    local entry = skins and skins.skins and skins.skins[skin]
    local mat = entry and entry.material_settings_name
    if type(mat) ~= "string" or mat == "" then return nil, nil end
    local templates = rawget(_G, "MaterialSettingsTemplates")
    local template = templates and templates[mat]
    if type(template) ~= "table" then return nil, mat end
    if family == "magic" then
        local lower = _hdr_to_display(template.color_glow_high, _NATIVE_BRIGHTNESS.color_glow_high)
        local upper = _hdr_to_display(template.color_smoke_high, _NATIVE_BRIGHTNESS.color_smoke_high)
        local dots  = _hdr_to_display(template.color_dots, _NATIVE_BRIGHTNESS.color_dots)
        if not (lower or upper or dots) then return nil, mat end
        return { lower = lower, upper = upper, dots = dots }, mat
    end
    local rune = _hdr_to_display(template.rune_emissive_color, _NATIVE_BRIGHTNESS.rune_emissive_color)
    if not rune then return nil, mat end
    return { rune = rune }, mat
end

-- Read-only seam for regression coverage and callers that want the native
-- display state without opening the editor.
function GlowPicker.native_state_for(slot_data)
    local family = GlowPicker.classify(slot_data) or "rune"
    local state = _resolve_native(slot_data, family)
    return state, family
end

-- Shape a family-correct display state from any base table (persisted override,
-- resolved native, or nil). Missing components fall back to neutral white at
-- intensity 0 -- a fail-closed "no visible override", never magenta.
local function _display_component(src, dr, dg, db, di)
    local t = type(src) == "table" and src or nil
    return {
        r = (t and tonumber(t.r)) or dr,
        g = (t and tonumber(t.g)) or dg,
        b = (t and tonumber(t.b)) or db,
        intensity = (t and tonumber(t.intensity)) or di,
    }
end
-- #48: an explicit per-item OFF is durable state, not a colour. Carry it across
-- the shape round trip so a saved disable is not silently rewritten into a
-- colour by the next Apply. The renderer, badge policy, and composite icon
-- builder all already consume `disabled`.
local function _shape_display_state(base, family)
    base = type(base) == "table" and base or {}
    local shaped
    if family == "magic" then
        shaped = {
            lower = _display_component(base.lower, 255, 255, 255, 0),
            upper = _display_component(base.upper, 255, 255, 255, 0),
            dots  = _display_component(base.dots,  255, 255, 255, 0),
        }
    else
        shaped = { rune = _display_component(base.rune, 255, 255, 255, 0) }
    end
    return INSTANCE_POLICY.carry_disabled(shaped, base)
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

-- Read-only presentation seam for #377. Inventory/illusion badges consume the
-- durable Apply transaction, never the mutable live-preview table.
function GlowPicker.committed_state_for(backend_id, slot_data)
    local state, identity = _persisted_state_for(backend_id, slot_data)
    return state, identity
end

function GlowPicker.commit_revision()
    return GlowPicker._commit_revision
end

function GlowPicker.is_open_for(backend_id, slot_data)
    return GlowPicker._open
        and GlowPicker._current_identity == _identity_key(backend_id, slot_data)
end

-- Called by the equipment spawn path so an applied value is restored after a
-- restart before the picker is opened again.
--
-- #48: a persisted MISS must clear the runtime entry, not just bail. The
-- runtime map is keyed by bare backend id while persistence is keyed by
-- backend id AND skin, so an early return left the previous illusion's
-- override painting after an illusion swap on the same instance.
function GlowPicker.restore_runtime_for(backend_id, slot_data)
    local state, identity = _persisted_state_for(backend_id, slot_data)
    local decision = INSTANCE_POLICY.resolve_runtime(state, backend_id, identity)
    if decision.action == "ignore" then return nil end
    mod._per_item_glow_runtime = mod._per_item_glow_runtime or {}
    mod._per_item_glow_identity_runtime = mod._per_item_glow_identity_runtime or {}
    if decision.action == "clear" then
        mod._per_item_glow_runtime[backend_id] = nil
        mod._per_item_glow_identity_runtime[backend_id] = nil
        return nil
    end
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
    local has_override = persisted ~= nil
    GlowPicker._has_override = has_override
    GlowPicker._committed_glow_state = persisted and _clone(persisted) or nil
    GlowPicker._dirty = false

    -- #610: with no committed override, display the illusion's NATIVE glow
    -- (never a magenta placeholder). native_mat is retained so Restore Default
    -- can repaint the untouched template on the live weapon.
    local native, native_mat = _resolve_native(slot_data, family)
    GlowPicker._native_mat = native_mat
    GlowPicker._current_glow_state = _shape_display_state(persisted or native, family)
    _sync_sliders_from_state()

    -- v0.9.8: assemble family-specific draw list. Magic shows 12
    -- sliders + 3 section labels; rune shows 4 sliders.
    local by_name = GlowPicker._widgets_by_name
    local widgets = { by_name.panel_bg, by_name.title, by_name.subtitle,
        by_name.close_btn, by_name.apply_btn, by_name.restore_btn }
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
    _update_restore_widget()

    -- #610: only a committed override drives a live paint. Opening on an
    -- untouched item must NOT push the display state (native/neutral) into the
    -- runtime map, or the weapon would be repainted merely by opening the
    -- editor. The runtime entry is (re)created only on an explicit slider edit
    -- (_live_preview) or Apply.
    mod._per_item_glow_runtime = mod._per_item_glow_runtime or {}
    if backend_id then
        mod._per_item_glow_runtime[backend_id] = has_override
            and GlowPicker._current_glow_state or nil
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
    GlowPicker._has_override = true
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
    GlowPicker._commit_revision = GlowPicker._commit_revision + 1
    if mod._cos_glow_badges_refresh then
        pcall(mod._cos_glow_badges_refresh, backend_id,
            GlowPicker._current_slot_data, GlowPicker._commit_revision)
    end
    _update_apply_widget()
    _update_restore_widget()
    _apply_log_only("[glow_picker:apply] committed identity=%s family=%s emit=1", identity, tostring(GlowPicker._current_family))
    return true
end

-- #610 Restore to Default: drop this exact item + illusion's override,
-- rebroadcast the cleared coop payload, repaint the native template on the live
-- weapon, and reset the sliders to native. Opening/closing/switching never
-- reach here -- only this explicit action clears a persisted override.
function GlowPicker.restore_default()
    if not GlowPicker._open or GlowPicker._has_override ~= true then return false end
    local backend_id = GlowPicker._current_backend_id
    local identity = GlowPicker._current_identity
    if backend_id == nil or identity == nil then return false end
    local slot_data = GlowPicker._current_slot_data
    local family = GlowPicker._current_family or "rune"

    -- Drop the persisted override for this exact identity (and the legacy
    -- backend-id-only key for one-time compatibility).
    local all_data = _load_per_item_glow()
    if all_data[identity] ~= nil then all_data[identity] = nil end
    if all_data[backend_id] ~= nil then all_data[backend_id] = nil end
    _save_per_item_glow(all_data)

    -- Clear the runtime override so no per-item paint is selected anywhere.
    if mod._per_item_glow_runtime then mod._per_item_glow_runtime[backend_id] = nil end
    if mod._per_item_glow_identity_runtime then mod._per_item_glow_identity_runtime[backend_id] = nil end

    -- Clear the active coop payload and broadcast the cleared state so remote
    -- peers stop painting this weapon's override.
    if mod._active_per_item_glow_identity == identity then
        mod._active_per_item_glow = nil
        mod._active_per_item_glow_identity = nil
        mod._active_per_item_glow_skin = nil
        mod._active_per_item_glow_slot = nil
        mod._active_per_item_glow_item_name = nil
        mod._active_per_item_glow_item_template = nil
        if mod._emit_per_item_glow then pcall(mod._emit_per_item_glow) end
    end

    -- Reset display to native, discard dirty, disable Apply/Restore.
    GlowPicker._committed_glow_state = nil
    GlowPicker._dirty = false
    GlowPicker._has_override = false
    local native = _resolve_native(slot_data, family)
    GlowPicker._current_glow_state = _shape_display_state(native, family)
    _sync_sliders_from_state()

    -- Immediately repaint the untouched native template on the live weapon;
    -- otherwise the last override colour lingers until the next weapon spawn.
    if mod._repaint_native_glow_on_wielded then
        pcall(mod._repaint_native_glow_on_wielded, GlowPicker._native_mat)
    end

    -- The committed override is gone, so refresh the grids to drop the badge.
    GlowPicker._commit_revision = GlowPicker._commit_revision + 1
    if mod._cos_glow_badges_refresh then
        pcall(mod._cos_glow_badges_refresh, backend_id, slot_data, GlowPicker._commit_revision)
    end
    _update_apply_widget()
    _update_restore_widget()
    _apply_log_only("[glow_picker:restore] cleared identity=%s family=%s", identity, tostring(family))
    return true
end

function GlowPicker.close()
    if not GlowPicker._open then return end
    -- Close/cancel discards uncommitted preview edits and repaints the last
    -- applied value (or vanilla when this identity had no saved override).
    local backend_id = GlowPicker._current_backend_id
    local committed = GlowPicker._committed_glow_state
    local native_mat = GlowPicker._native_mat
    if backend_id ~= nil then
        mod._per_item_glow_runtime = mod._per_item_glow_runtime or {}
        mod._per_item_glow_runtime[backend_id] = committed and _clone(committed) or nil
        if mod._reapply_glow_on_wielded then pcall(mod._reapply_glow_on_wielded) end
        -- #610: cancelling a preview on an item with NO committed override must
        -- visibly roll back. Reapplying the (absent) override no-ops, so repaint
        -- the native template directly to undo any live-preview paint.
        if not committed and mod._repaint_native_glow_on_wielded then
            pcall(mod._repaint_native_glow_on_wielded, native_mat)
        end
    end
    GlowPicker._open               = false
    GlowPicker._current_backend_id = nil
    GlowPicker._current_slot_data  = nil
    GlowPicker._current_identity   = nil
    GlowPicker._current_glow_state = nil
    GlowPicker._committed_glow_state = nil
    GlowPicker._current_family     = nil
    GlowPicker._native_mat         = nil
    GlowPicker._has_override       = false
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
    local restore = by_name.restore_btn
    local restore_hotspot = restore and restore.content and restore.content.hotspot
    if restore_hotspot and restore_hotspot.on_release then
        restore_hotspot.on_release = false
        if GlowPicker._has_override == true then GlowPicker.restore_default() end
        return true  -- swallow even when disabled so it can't leak to the screen
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
