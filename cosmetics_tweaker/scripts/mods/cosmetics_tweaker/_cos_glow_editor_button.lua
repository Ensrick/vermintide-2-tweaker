-- Contextual Edit Glow button owner (#377/#504).
-- Owns button policy, state refresh, and widget construction. The host
-- customization view remains responsible for positioning, input, and drawing.

local M = {}

function M.install(mod, deps)
    if mod._cos_glow_editor_button_owner then
        return mod._cos_glow_editor_button_owner
    end

    local glow_picker = assert(deps.glow_picker, "glow_picker required")
    local glow_badge = assert(deps.glow_badge, "glow_badge required")
    local ui_widget = assert(deps.ui_widget, "ui_widget required")

    mod._glow_editor_button_policy_377 = glow_badge.button

    local function refresh(self, skin_key)
        local widget = self and self._ct_glow_editor_widget
        if not widget then return nil end

        local family = skin_key and glow_picker.classify({ skin = skin_key }) or nil
        local backend_id = self._item_backend_id
        local policy = glow_badge.button(family,
            glow_picker.is_open_for(backend_id, { skin = skin_key }))
        if backend_id == nil then
            policy.available = false
            policy.selected = false
        end
        local content = widget.content
        local hotspot = content and content.button_hotspot
        if not content or not hotspot then return family end

        content.glow_family = family
        content.glow_skin = skin_key
        content.glow_backend_id = backend_id
        content.equipped = policy.selected
        hotspot.disable_button = not policy.available
        hotspot.is_selected = policy.selected

        local icon_style = widget.style and widget.style.icon_texture
        if icon_style then
            local state = glow_picker.committed_state_for(
                backend_id, { skin = skin_key })
            icon_style.color = policy.available
                and (glow_badge.color(state) or { 255, 255, 255, 255 })
                or { 110, 128, 128, 128 }
        end
        local label_style = widget.style and widget.style.glow_editor_label
        if label_style then
            label_style.text_color = policy.available
                and { 255, 255, 255, 255 }
                or { 110, 128, 128, 128 }
        end
        local button_style = widget.style and widget.style.button
        if button_style then
            button_style.color = policy.available
                and (policy.selected and { 245, 90, 65, 20 }
                    or { 230, 30, 30, 38 })
                or { 110, 30, 30, 38 }
        end
        return family
    end

    local function create()
        -- Editor access cannot depend on optional badge art. Some renderer
        -- configurations do not expose the custom texture through the atlas.
        local button_width, button_height = 96, 38
        local definition = {
            element = { passes = {
                { content_id = "button_hotspot", pass_type = "hotspot", style_id = "button" },
                { pass_type = "rect", style_id = "button" },
                { pass_type = "text", text_id = "glow_editor_label", style_id = "glow_editor_label" },
                { pass_type = "texture_frame", style_id = "button_frame", texture_id = "button_frame" },
            } },
            content = {
                button_hotspot = {},
                button_frame = glow_picker.FRAME_TEXTURE,
                glow_editor_label = mod:localize("glow_picker_editor_button"),
            },
            style = {
                button = {
                    size = { button_width, button_height },
                    color = { 230, 30, 30, 38 },
                    offset = { 0, 0, 1 },
                },
                button_frame = glow_picker.frame_style(
                    button_width, button_height, 3),
                glow_editor_label = {
                    size = { button_width, button_height },
                    font_size = 13,
                    font_type = "hell_shark",
                    horizontal_alignment = "center",
                    vertical_alignment = "center",
                    text_color = { 255, 255, 255, 255 },
                    offset = { 0, 0, 3 },
                },
            },
            scenegraph_id = "info_window",
            offset = { 0, 0, 20 },
        }
        local widget = ui_widget.init(definition)
        widget.content.equipped = false
        return widget
    end

    local owner = {
        refresh = refresh,
        create = create,
    }
    mod._cos_glow_editor_button_owner = owner
    return owner
end

return M
