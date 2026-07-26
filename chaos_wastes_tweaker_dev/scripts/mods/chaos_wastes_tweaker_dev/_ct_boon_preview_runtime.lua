-- _ct_boon_preview_runtime.lua
-- Bounded lazy tooltip widget/runtime helpers for issue #1004.

local M = {}

function M.install(mod)
    if mod._ct_boon_preview_tooltip_runtime_installed then return end
    mod._ct_boon_preview_tooltip_runtime_installed = true

    function mod._ct_build_boon_tooltip_widget(boon, ui_renderer)
        local policy = mod._ct_boon_preview_tooltip
        local ui_utils = rawget(_G, "UIUtils")
        if not (boon and ui_renderer and ui_utils
            and type(ui_utils.get_text_height) == "function") then return nil end
        local function measure(text, width, font_size)
            return ui_utils.get_text_height(ui_renderer, { width, 0 }, {
                font_size = font_size,
                font_type = "hell_shark",
                word_wrap = true,
            }, text)
        end
        local box = policy.layout_description(boon.description, measure)
        if not box then return nil end
        local paged = #box.pages > 1
        local body_bottom = paged and 40 or 14
        local widget = UIWidget.init({
            scenegraph_id = "reward_divider",
            element = {
                passes = {
                    { pass_type = "rect", style_id = "frame" },
                    { pass_type = "rect", style_id = "background" },
                    { pass_type = "text", style_id = "title", text_id = "title" },
                    { pass_type = "text", style_id = "description", text_id = "description" },
                    { pass_type = "text", style_id = "page_indicator", text_id = "page_indicator" },
                },
            },
            content = {
                title = boon.display or boon.name,
                description = box.pages[1],
                page_indicator = paged and ("1/" .. #box.pages) or "",
            },
            style = {
                frame = {
                    color = { 255, 176, 124, 54 },
                    offset = { box.x, box.y, 20 },
                    size = { box.width, box.height },
                },
                background = {
                    color = { 245, 12, 12, 12 },
                    offset = { box.x + 2, box.y + 2, 21 },
                    size = { box.width - 4, box.height - 4 },
                },
                title = {
                    font_size = 22,
                    font_type = "hell_shark_header",
                    horizontal_alignment = "left",
                    vertical_alignment = "center",
                    text_color = { 255, 255, 214, 138 },
                    size = { box.width - 32, 32 },
                    offset = { box.x + 16, box.y + box.height - 48, 22 },
                },
                description = {
                    font_size = box.font_size,
                    font_type = "hell_shark",
                    horizontal_alignment = "left",
                    vertical_alignment = "top",
                    word_wrap = true,
                    text_color = { 255, 235, 235, 235 },
                    size = { box.body_width, box.body_height },
                    offset = { box.x + 16, box.y + body_bottom, 22 },
                },
                page_indicator = {
                    font_size = 14,
                    font_type = "hell_shark",
                    horizontal_alignment = "right",
                    vertical_alignment = "center",
                    text_color = { 255, 190, 190, 190 },
                    size = { box.body_width, 24 },
                    offset = { box.x + 16, box.y + 10, 22 },
                },
            },
            offset = { 0, 0, 0 },
        })
        widget._ct_pages = box.pages
        widget._ct_page_index = 1
        widget._ct_measured_layout = box
        widget._ct_page_hint_key = nil
        widget._ct_controller_page_latched = false
        return widget
    end

    function mod._ct_update_boon_tooltip_hint(widget, gamepad_active)
        local pages = widget and widget._ct_pages
        if type(pages) ~= "table" or #pages < 2 then return end
        local key = mod._ct_boon_preview_tooltip.page_hint_key(gamepad_active)
        if widget._ct_page_hint_key == key then return end
        widget._ct_page_hint_key = key
        local hint = mod:localize(key)
        if hint == key then hint = gamepad_active and "Right shoulder: next page"
            or "Mouse wheel: pages" end
        local index = widget._ct_page_index or 1
        widget.content.page_indicator = index .. "/" .. #pages .. "  " .. hint
    end

    function mod._ct_scroll_boon_tooltip(widget, page_delta, wrap_forward)
        local pages = widget and widget._ct_pages
        if type(pages) ~= "table" or #pages < 2
            or type(page_delta) ~= "number" or page_delta == 0 then return end
        local index = widget._ct_page_index or 1
        if wrap_forward and page_delta > 0 then
            index = index % #pages + 1
        else
            index = math.max(1, math.min(#pages, index + page_delta))
        end
        widget._ct_page_index = index
        widget.content.description = pages[index]
        widget._ct_page_hint_key = nil
    end
end

return M
