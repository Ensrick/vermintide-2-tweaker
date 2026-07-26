-- Source-derived fixture for CT #1004.
--
-- Provenance: Vermintide-2-Source-Code commit
-- c5e4968b1fbb00c49884e56d640ef990a9c04dd0.
--   scripts/ui/views/ingame_player_list_ui_v2_definitions.lua:15-22,106-115,173-185
--   scripts/helpers/ui_utils.lua:330-349
--   scripts/settings/controller_settings.lua:5125-5586
--
-- Keep this fixture independent from the shipped policy. Updating production
-- constants or input bindings requires reviewing the cited source first.

local M = {}

M.provenance = {
    commit = "c5e4968b1fbb00c49884e56d640ef990a9c04dd0",
    geometry_path = "scripts/ui/views/ingame_player_list_ui_v2_definitions.lua",
    metric_path = "scripts/helpers/ui_utils.lua",
    input_path = "scripts/settings/controller_settings.lua",
}

M.geometry = {
    banner_right = {
        horizontal_alignment = "right",
        scale = "fit_height",
        width = 660,
        height = 1080,
    },
    reward_divider = {
        parent = "banner_right",
        horizontal_alignment = "left",
        vertical_alignment = "top",
        x = 20,
        y = -700,
        width = 264,
        height = 32,
    },
}

M.page_actions = {
    win32 = {
        right_press = { "mouse", "right", "pressed" },
        right_hold = { "mouse", "right", "held" },
    },
    xb1 = {
        right_press = { "gamepad", "right_shoulder", "pressed" },
        right_hold = { "gamepad", "right_shoulder", "held" },
    },
    ps4 = {
        right_press = { "gamepad", "r1", "pressed" },
        right_hold = { "gamepad", "r1", "held" },
    },
    ps_pad = {
        right_press = { "ps_pad", "r1", "pressed" },
        right_hold = { "ps_pad", "r1", "held" },
    },
}

-- Faithful dependency-injected port of UIUtils.get_text_height. The adapter
-- executes the production call order and formula without requiring Stingray.
function M.get_text_height(deps, ui_renderer, size, text_style, text)
    local font, scaled_font_size = deps.UIFontByResolution(text_style)
    if text_style.localize then text = deps.Localize(text) end
    if text_style.upper_case then text = deps.TextToUpper(text) end
    local _, font_min, font_max = deps.UIGetFontHeight(
        ui_renderer.gui, text_style.font_type, scaled_font_size)
    local texts = deps.word_wrap(
        ui_renderer, text, font[1], scaled_font_size, size[1])
    local text_start_index = 1
    local max_texts = #texts
    local num_texts = math.min(#texts - (text_start_index - 1), max_texts)
    local full_font_height = (font_max + math.abs(font_min))
        * deps.inv_scale * num_texts
    return full_font_height, num_texts
end

return M
