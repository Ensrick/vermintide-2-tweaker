-- _cos_item_grid_presentation.lua
-- #377/#650/#795 item-grid and illusion-card glow/composite presentation owner.

local M = {}

function M.install(mod, deps)
    if mod._cos_item_grid_presentation_owner then
        return mod._cos_item_grid_presentation_owner
    end

    deps = deps or {}
    local GLOW_BADGE = assert(deps.glow_badge, "glow_badge required")
    local GlowPicker = assert(deps.glow_picker, "glow_picker required")
    local COMPOSITE_ICONS = assert(deps.composite_icons, "composite_icons required")
    local refresh_glow_editor_button = assert(deps.refresh_glow_editor_button,
        "refresh_glow_editor_button required")
    local resolve_composed_appearance = assert(deps.resolve_composed_appearance,
        "resolve_composed_appearance required")

    -- The authored 80x80 texture is a transparent overlay whose mark already
    -- sits in the bottom-right corner; matching the vanilla item-icon rectangle
    -- keeps its placement stable across grids.
    local GLOW_BADGE_TEXTURE = "cos_glow_badge"
    local glow_badge_texture_missing_logged = false
    local glow_badge_grids = setmetatable({}, { __mode = "k" })
    local glow_badge_customization_windows = setmetatable({}, { __mode = "k" })
    local composite_icon_grids = setmetatable({}, { __mode = "k" })

    local function glow_badge_texture_available()
        local available = UIAtlasHelper and UIAtlasHelper.has_texture_by_name
            and UIAtlasHelper.has_texture_by_name(GLOW_BADGE_TEXTURE)
        if not available and not glow_badge_texture_missing_logged then
            glow_badge_texture_missing_logged = true
            mod:warning("[glow-badge] authored texture unavailable; badges disabled")
        end
        return available == true
    end

    local function copy_vec(values, fallback)
        values = values or fallback
        return { values[1], values[2], values[3] }
    end

    local function item_skin_for_glow_badge(item)
        if type(item) ~= "table" then return nil end
        local skin = item.skin
        local bid = item.backend_id
        if (not skin or skin == "") and bid and Managers and Managers.backend then
            local iface = Managers.backend:get_interface("items")
            if iface and iface.get_skin then skin = iface:get_skin(bid) end
        end
        local item_key = item.key or (item.data and (item.data.name or item.data.key))
        if (not skin or skin == "") and item_key and WeaponSkins
                and WeaponSkins.default_skins then
            skin = WeaponSkins.default_skins[item_key]
        end
        return skin
    end

    local function committed_glow_badge_color(backend_id, skin)
        if not backend_id or not skin then return nil end
        return GLOW_BADGE.color(GlowPicker.committed_state_for(backend_id,
            { skin = skin }))
    end

    local function enrich_illusion_glow_badge(widget)
        if not GLOW_BADGE.is_illusion_definition(widget)
                or widget._ct_glow_badge_enriched
                or not glow_badge_texture_available() then return false end
        local passes = widget.element and widget.element.passes
        local icon_style = widget.style and widget.style.icon_texture
        if type(passes) ~= "table" or type(icon_style) ~= "table" then return false end
        widget._ct_glow_badge_enriched = true
        passes[#passes + 1] = {
            pass_type = "texture",
            texture_id = "ct_glow_badge",
            style_id = "ct_glow_badge",
            content_check_function = function(content)
                return content.ct_glow_badge ~= nil
            end,
        }
        widget.content.ct_glow_badge = nil
        widget.style.ct_glow_badge = {
            size = copy_vec(icon_style.size, { 45, 45 }),
            texture_size = copy_vec(icon_style.texture_size, { 45, 45 }),
            offset = copy_vec(icon_style.offset, { 0, 0, 1 }),
            color = { 255, 255, 255, 255 },
        }
        widget.style.ct_glow_badge.offset[3] =
            (widget.style.ct_glow_badge.offset[3] or 0) + 8
        return true
    end

    local function refresh_illusion_glow_badges(self)
        if not self or not self._illusion_widgets then return end
        glow_badge_customization_windows[self] = true
        for _, widget in ipairs(self._illusion_widgets) do
            local skin = widget.content and widget.content.skin_key
            local color = committed_glow_badge_color(self._item_backend_id, skin)
            if widget.content then
                widget.content.ct_glow_badge = color and GLOW_BADGE_TEXTURE or nil
            end
            if color and widget.style and widget.style.ct_glow_badge then
                widget.style.ct_glow_badge.color = color
            end
        end
    end

    local function enrich_item_grid_glow_badges(widget)
        if not widget or widget._ct_glow_badges_enriched
                or not glow_badge_texture_available() then return false end
        -- UIWidget.init builds element.pass_data as a positional twin of passes.
        -- Never mutate a live widget: inserting even an immediate texture pass
        -- shifts stateful native pass data (notably item_tooltip) onto the wrong pass.
        if widget.element and widget.element.pass_data ~= nil then return false end
        local passes = widget.element and widget.element.passes
        local content, style = widget.content, widget.style
        if type(passes) ~= "table" or type(content) ~= "table"
                or type(style) ~= "table" then return false end
        widget._ct_glow_badges_enriched = true
        for row = 1, content.rows or 0 do
            for column = 1, content.columns or 0 do
                local suffix = "_" .. row .. "_" .. column
                local badge_name = "ct_glow_badge" .. suffix
                local icon_style = style["item_icon" .. suffix]
                if icon_style then
                    passes[#passes + 1] = {
                        pass_type = "texture",
                        texture_id = badge_name,
                        style_id = badge_name,
                        content_check_function = function(pass_content)
                            return pass_content[badge_name] ~= nil
                        end,
                    }
                    content[badge_name] = nil
                    style[badge_name] = {
                        size = copy_vec(icon_style.size, { 80, 80 }),
                        offset = copy_vec(icon_style.offset, { 0, 0, 2 }),
                        color = { 255, 255, 255, 255 },
                    }
                    style[badge_name].offset[3] =
                        (style[badge_name].offset[3] or 0) + 8
                end
            end
        end
        return true
    end

    -- #650 inventory/equipment proof adapter. ItemGridUI owns both surfaces, so
    -- a single shared enrichment consumes the public exact-instance descriptor.
    -- The two authored passes are inserted directly after the native item-icon
    -- pass: native rarity/background -> primary -> offhand -> glow -> native frame.
    local function enrich_item_grid_composite_icons(widget)
        if not widget or widget._ct_composite_icons_enriched then return false end
        -- #650 crash invariant: definition enrichment must finish before
        -- UIWidget.init creates the parallel pass_data array.
        if widget.element and widget.element.pass_data ~= nil then return false end
        local passes = widget.element and widget.element.passes
        local content, style = widget.content, widget.style
        if type(passes) ~= "table" or type(content) ~= "table"
                or type(style) ~= "table" then return false end

        local insertions = {}
        for row = 1, content.rows or 0 do
            for column = 1, content.columns or 0 do
                local suffix = "_" .. row .. "_" .. column
                local icon_name = "item_icon" .. suffix
                local icon_style = style[icon_name]
                if type(icon_style) == "table" then
                    for index, pass in ipairs(passes) do
                        if pass.style_id == icon_name and pass.pass_type == "texture" then
                            insertions[#insertions + 1] = {
                                index = index,
                                suffix = suffix,
                                icon_style = icon_style,
                            }
                            break
                        end
                    end
                end
            end
        end

        for insertion_index = #insertions, 1, -1 do
            local insertion = insertions[insertion_index]
            local suffix = insertion.suffix
            local offhand_name = "ct_composite_offhand" .. suffix
            local glow_name = "ct_composite_glow" .. suffix
            table.insert(passes, insertion.index + 1, {
                pass_type = "texture",
                texture_id = offhand_name,
                style_id = offhand_name,
                content_check_function = function(pass_content)
                    return pass_content[offhand_name] ~= nil
                end,
            })
            table.insert(passes, insertion.index + 2, {
                pass_type = "texture",
                texture_id = glow_name,
                style_id = glow_name,
                content_check_function = function(pass_content)
                    return pass_content[glow_name] ~= nil
                end,
            })
            local icon_style = insertion.icon_style
            style[offhand_name] = {
                size = copy_vec(icon_style.size, { 80, 80 }),
                offset = copy_vec(icon_style.offset, { 0, 0, 2 }),
                color = { 255, 255, 255, 255 },
            }
            style[glow_name] = {
                size = copy_vec(icon_style.size, { 80, 80 }),
                offset = copy_vec(icon_style.offset, { 0, 0, 2 }),
                color = { 255, 255, 255, 255 },
            }
            style[offhand_name].offset[3] =
                (style[offhand_name].offset[3] or 0) + 1
            style[glow_name].offset[3] = (style[glow_name].offset[3] or 0) + 2
            content[offhand_name] = nil
            content[glow_name] = nil
        end
        widget._ct_composite_icons_enriched = true
        return #insertions > 0
    end

    local function refresh_item_grid_composite_icons(self)
        local widget = self and self._widget
        local content, style = widget and widget.content, widget and widget.style
        if not content or not style then return end
        composite_icon_grids[self] = true
        self._ct_composite_icon_cells = self._ct_composite_icon_cells or {}
        for row = 1, content.rows or 0 do
            for column = 1, content.columns or 0 do
                local suffix = "_" .. row .. "_" .. column
                local item = content["item" .. suffix]
                if type(item) == "table" then
                    resolve_composed_appearance(item)
                end
                local descriptor = COMPOSITE_ICONS.descriptor_for(item)
                local offhand_name = "ct_composite_offhand" .. suffix
                local glow_name = "ct_composite_glow" .. suffix
                if style[offhand_name] then
                    content[offhand_name] = descriptor
                        and descriptor.offhand_texture or nil
                    content[glow_name] = descriptor and descriptor.glow_texture or nil
                    local icon_name = "item_icon" .. suffix
                    -- ItemGridUI stores each native icon inside its hotspot's
                    -- content table (the native pass has content_id=hotspot_*).
                    local hotspot_content = content["hotspot" .. suffix]
                    local current_icon = type(hotspot_content) == "table"
                        and hotspot_content[icon_name] or nil
                    local identity = item and (item.backend_id or item.ItemInstanceId
                        or item.key or item) or nil
                    local resolved_icon, cell_state = COMPOSITE_ICONS.resolve_cell(
                        self._ct_composite_icon_cells[suffix], {
                            identity = identity,
                            current_icon = current_icon,
                            descriptor = descriptor,
                        })
                    self._ct_composite_icon_cells[suffix] = cell_state
                    if type(hotspot_content) == "table" then
                        hotspot_content[icon_name] = resolved_icon
                    end
                    if descriptor and descriptor.glow_color then
                        style[glow_name].color = {
                            descriptor.glow_color[1], descriptor.glow_color[2],
                            descriptor.glow_color[3], descriptor.glow_color[4],
                        }
                    end
                end
            end
        end
    end

    local function refresh_item_grid_glow_badges(self)
        local widget = self and self._widget
        local content, style = widget and widget.content, widget and widget.style
        if not content or not style then return end
        glow_badge_grids[self] = true
        for row = 1, content.rows or 0 do
            for column = 1, content.columns or 0 do
                local suffix = "_" .. row .. "_" .. column
                local badge_name = "ct_glow_badge" .. suffix
                if style[badge_name] then
                    local item = content["item" .. suffix]
                    local color = item and committed_glow_badge_color(item.backend_id,
                        item_skin_for_glow_badge(item)) or nil
                    content[badge_name] = color and GLOW_BADGE_TEXTURE or nil
                    if color then style[badge_name].color = color end
                end
            end
        end
        refresh_item_grid_composite_icons(self)
    end

    -- Add render passes before UIWidget.init constructs positional pass_data
    -- (ui_widget.lua:17-38); late insertion caused the v0.9.133 item_tooltip crash.
    mod:hook("UIWidget", "init", function(func, widget_definition, ui_renderer)
        local illusion_added = enrich_illusion_glow_badge(widget_definition)
        local glow_added = enrich_item_grid_glow_badges(widget_definition)
        local composite_added = enrich_item_grid_composite_icons(widget_definition)
        if illusion_added then
            printf("[cosmetics:795] glow-badge illusion pass initialized before pass_data")
        elseif composite_added then
            printf("[cosmetics:650] layered item-grid passes initialized before pass_data")
        elseif glow_added then
            printf("[cosmetics:377] glow-badge item-grid passes initialized before pass_data")
        end
        return func(widget_definition, ui_renderer)
    end)

    mod:hook_safe("ItemGridUI", "init", function(self)
        refresh_item_grid_glow_badges(self)
    end)
    mod:hook_safe("ItemGridUI", "add_item_to_slot_index", function(self)
        refresh_item_grid_glow_badges(self)
    end)
    mod:hook_safe("ItemGridUI", "_populate_inventory_page", function(self)
        refresh_item_grid_glow_badges(self)
    end)

    -- Apply alone refreshes live surfaces once; dirty previews never use this seam.
    mod._cos_glow_badges_refresh = function(backend_id, slot_data, revision)
        COMPOSITE_ICONS.invalidate(backend_id)
        for grid in pairs(glow_badge_grids) do
            refresh_item_grid_glow_badges(grid)
        end
        for grid in pairs(composite_icon_grids) do
            refresh_item_grid_composite_icons(grid)
        end
        for window in pairs(glow_badge_customization_windows) do
            refresh_illusion_glow_badges(window)
            refresh_glow_editor_button(window, window._ct_glow_editor_widget
                and window._ct_glow_editor_widget.content.glow_skin)
        end
        mod:info("[glow-badge] committed refresh bid=%s skin=%s revision=%s",
            tostring(backend_id), tostring(slot_data and slot_data.skin),
            tostring(revision))
    end

    local owner = {
        refresh_illusion_glow_badges = refresh_illusion_glow_badges,
    }
    mod._cos_item_grid_presentation_owner = owner
    return owner
end

return M
