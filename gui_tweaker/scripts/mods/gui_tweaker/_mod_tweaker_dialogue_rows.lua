-- _mod_tweaker_dialogue_rows.lua - bounded Character Dialogue row factory.
--
-- Owns one caller-height row with state/media controls and compact transcript.
-- Shared text, separator and list geometry come from the definitions owner;
-- this factory adds no hooks, lifecycle callbacks or dialogue transport.
--
-- Owned by: _mod_tweaker_definitions.lua. Consumed via: mod:dofile + new(env).

local M = {}

function M.new(env)
    local UIWidget = assert(env.UIWidget, "dialogue rows require UIWidget")
    local Colors = assert(env.Colors, "dialogue rows require Colors")
    local ROW_W = assert(env.row_w, "dialogue rows require row width")
    local INDENT_PER_DEPTH = assert(env.indent_per_depth, "dialogue rows require indent")
    local LABEL_BASE_X = assert(env.label_base_x, "dialogue rows require label origin")
    local LIST_SG = assert(env.list_sg, "dialogue rows require list scenegraph")
    local _text_style = assert(env.text_style, "dialogue rows require text style")
    local _append_separator = assert(env.append_separator, "dialogue rows require separator")

    -- #605: one compact Character Dialogue event row. State and media controls stay
    -- fixed in the same logical/rendered row. The media control is one toggle: a
    -- native triangle pass while stopped/paused, and two rect bars while playing.
    -- Only the bounded virtual window creates these widgets.
    local function create_dialogue_row(text, state_text, base_offset, depth, transcript, row_h)
        -- #605 The dialogue row is TWO lines (codename, then the spoken transcript)
        -- so it owns its own height. ROW_H stays 32 for every other Mod Tweaker row;
        -- inflating the shared constant would make every mod's settings list taller.
        -- The height is SUPPLIED by the caller from Character Dialogue's own
        -- browser_row_height: the virtual-window planner spaces rows by that value,
        -- so hardcoding a second copy here would misalign every row the moment the
        -- owning mod changed it. The literal is only a standalone-render fallback.
        local DIALOGUE_ROW_H = tonumber(row_h) or 48
        local y = base_offset[2] - DIALOGUE_ROW_H
        base_offset[2] = y
        local ind = INDENT_PER_DEPTH * (depth or 0)
        local media_w, state_w, gap = 32, 104, 8
        local media_x = ROW_W - media_w - 10
        local state_x = media_x - state_w - gap
        local label_x = LABEL_BASE_X + ind
        local label_w = math.max(80, state_x - label_x - 12)
        local progress_x, progress_w = label_x, label_w
        -- Control boxes centre inside the taller row instead of hugging its floor.
        local ctrl_h = 26
        local ctrl_y = y + math.floor((DIALOGUE_ROW_H - ctrl_h) / 2)
        -- Codename sits on the upper line, transcript on the lower one.
        local name_y, script_y = y + 25, y + 5
        local button_color = { 220, 12, 12, 12 }
        local border_color = { 180, 90, 90, 90 }
        local text_color = Colors.get_color_table_with_alpha("font_button_normal", 255)
        local glyph_color = { 255, 160, 146, 101 }
        local function showing_play(content) return not content.media_is_playing end
        local function showing_pause(content) return content.media_is_playing end
        local function showing_progress(content) return content.progress_visible end
        local passes = {
            { pass_type = "hotspot", content_id = "state_hotspot", style_id = "state_hotspot" },
            { pass_type = "hotspot", content_id = "media_hotspot", style_id = "media_hotspot" },
            -- (#880) Full-row HOVER hotspot: the transcript-popup capture (and hover polish)
            -- reads row_hs.is_hover only - its on_release is NEVER read, so it cannot steal
            -- the state/media control clicks (same hover-only contract as _append_highlight).
            { pass_type = "hotspot", content_id = "row_hs", style_id = "row_hs" },
            { pass_type = "text", style_id = "label", text_id = "label" },
            -- #605 transcript line. Drawn only when the subtitle key resolved to
            -- prose; enemy barks frequently have none, and an empty second line
            -- would just add dead space to every one of those rows.
            { pass_type = "text", style_id = "transcript", text_id = "transcript",
              content_check_function = function(c) return c.has_transcript end },
            { pass_type = "rect", style_id = "progress_track", content_check_function = showing_progress },
            { pass_type = "rect", style_id = "progress_fill", content_check_function = showing_progress },
            { pass_type = "rect", style_id = "state_bg" },
            { pass_type = "border", style_id = "state_border" },
            { pass_type = "text", style_id = "state_text", text_id = "state_text" },
            { pass_type = "rect", style_id = "media_bg" },
            { pass_type = "border", style_id = "media_border" },
            { pass_type = "triangle", style_id = "play_glyph", content_check_function = showing_play },
            { pass_type = "rect", style_id = "pause_bar_left", content_check_function = showing_pause },
            { pass_type = "rect", style_id = "pause_bar_right", content_check_function = showing_pause },
        }
        -- #605 The preview is ONE line: a mission-intro transcript runs for
        -- paragraphs and the GUI is meant to stay compact. Overflow ends in an
        -- ellipsis, and the full prose stays available in the hover popup.
        local script_text, has_script = "", false
        if type(transcript) == "string" and transcript ~= "" then
            local budget = math.max(16, math.floor(label_w / 6.5))
            script_text = transcript:gsub("%s+", " ")
            if #script_text > budget then
                script_text = script_text:sub(1, math.max(1, budget - 3)) .. "..."
            end
            has_script = true
        end
        local content = {
            state_hotspot = {}, media_hotspot = {}, row_hs = {},
            label = tostring(text), state_text = tostring(state_text or "DEFAULT"),
            transcript = script_text, has_transcript = has_script,
            media_is_playing = false, progress_visible = false,
        }
        local function box(x, w, z, color)
            return { offset = { x, ctrl_y, z or 2 }, size = { w, ctrl_h }, color = color }
        end
        local function button_text(x, w)
            local s = _text_style(x, ctrl_y + 5, w, 16, text_color, "center")
            s.upper_case = true
            return s
        end
        local style = {
            label = _text_style(label_x, name_y, label_w, 17, Colors.get_color_table_with_alpha("font_default", 255)),
            -- Dimmer and a size down: the transcript is the thing you READ, but the
            -- codename stays the row's identity, so the transcript must not out-shout it.
            transcript = _text_style(label_x, script_y, label_w, 15, { 255, 168, 158, 138 }),
            row_hs = { offset = { 0, y, 0 }, size = { ROW_W, DIALOGUE_ROW_H } },
            state_hotspot = box(state_x, state_w, 8), media_hotspot = box(media_x, media_w, 8),
            progress_track = { offset = { progress_x, y + 1, 4 }, size = { progress_w, 3 }, color = { 150, 45, 45, 45 } },
            progress_fill = { offset = { progress_x, y + 1, 5 }, size = { 0, 3 }, color = { 255, 168, 118, 44 } },
            state_bg = box(state_x, state_w, 2, button_color), state_border = box(state_x, state_w, 3, border_color),
            state_text = button_text(state_x, state_w),
            media_bg = box(media_x, media_w, 2, button_color), media_border = box(media_x, media_w, 3, border_color),
            play_glyph = {
                offset = { media_x + 10, ctrl_y + 7, 4 }, size = { 12, 12 },
                triangle_alignment = "right", color = glyph_color,
            },
            pause_bar_left = { offset = { media_x + 10, ctrl_y + 7, 4 }, size = { 4, 12 }, color = glyph_color },
            pause_bar_right = { offset = { media_x + 18, ctrl_y + 7, 4 }, size = { 4, 12 }, color = glyph_color },
        }
        style.state_border.thickness, style.media_border.thickness = 1, 1
        style._dialogue_progress_width = progress_w
        _append_separator(passes, style, y)
        return UIWidget.init({
            scenegraph_id = LIST_SG, element = { passes = passes }, content = content,
            style = style, offset = { 0, 0, 0 },
        })
    end

    return { create_dialogue_row = create_dialogue_row }
end

return M
