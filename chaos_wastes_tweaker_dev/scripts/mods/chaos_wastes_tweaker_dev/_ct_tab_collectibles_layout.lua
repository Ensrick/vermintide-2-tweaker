-- Chaos Wastes hold-Tab collectible reflow (#571).
-- Loaded beside the existing #533 widget/value integration so the oversized main
-- module does not grow further. This module adds no hook and mutates no vanilla data.
local mod = get_mod("ct_dev")
local M = {}
local ICON_SIZE = 80
local LAYOUT_MARKER = "cw_tab_collectibles_native_reflow_v0.7.262"

-- Pure layout contract. Vanilla IngamePlayerListUI uses two entries per row and
-- wraps by row; retain that policy when localized cells fit, otherwise use one
-- column. Bounds intersect the native right banner with UISceneGraph's safe rect.
function mod._ct_compute_collectible_layout(c)
    local virtual_w = math.max(1, tonumber(c.virtual_w) or 1920)
    local virtual_h = math.max(1, tonumber(c.virtual_h) or 1080)
    local safe_fraction = math.max(0, math.min(0.9, tonumber(c.safe_fraction) or 0))
    local safe_x = virtual_w * safe_fraction * 0.5
    local safe_y = virtual_h * safe_fraction * 0.5
    local node_x = tonumber(c.node_x) or 0
    local node_y = tonumber(c.node_y) or 0
    local banner_right = tonumber(c.banner_right) or virtual_w
    local divider_y = tonumber(c.divider_y) or virtual_h
    local node_h = math.max(1, tonumber(c.node_h) or 90)
    local count = math.max(1, math.floor(tonumber(c.count) or 1))
    local cell_widths = c.cell_widths or {}

    local left = math.max(node_x, safe_x)
    local right = math.min(banner_right, virtual_w - safe_x)
    local available_w = math.max(1, right - left)
    local natural_row_w = 0
    for i = 1, math.min(count, 2) do
        natural_row_w = natural_row_w + (tonumber(cell_widths[i]) or 0)
    end
    local columns = count > 1 and natural_row_w <= available_w and 2 or 1
    local rows = math.ceil(count / columns)

    local bottom = math.max(node_y, safe_y)
    local upper = math.max(bottom + 1, divider_y - 8)
    local pitch_budget = rows > 1 and math.max(1, upper - bottom - node_h) / (rows - 1) or ICON_SIZE
    local scale = math.max(0.45, math.min(1, pitch_budget / ICON_SIZE))
    return {
        base_x = left - node_x,
        base_y = bottom - node_y,
        available_w = available_w,
        columns = columns,
        rows = rows,
        scale = scale,
        row_pitch = ICON_SIZE * scale,
        safe_left = safe_x,
        safe_right = virtual_w - safe_x,
        safe_bottom = safe_y,
        upper = upper,
    }
end

-- Called only after UIRenderer.begin_pass has applied fit_height/current-resolution
-- transforms. Signature invalidation makes the steady frame allocation-free.
function mod._ct_layout_deus_collectibles(self)
    local cw = self._ct_deus_collectibles
    local sg = self._ui_scenegraph
    local loot = sg and sg.loot_objective
    local banner = sg and sg.banner_right
    local divider = sg and sg.collectibles_divider
    local rl = rawget(_G, "RESOLUTION_LOOKUP")
    if not (cw and loot and banner and divider and rl) then return end

    local safe_percent = Application.user_setting("safe_rect") or 0
    local virtual_w = (rl.res_w or 1920) * (rl.inv_scale or 1)
    local virtual_h = (rl.res_h or 1080) * (rl.inv_scale or 1)
    local signature = table.concat({
        tostring(virtual_w), tostring(virtual_h), tostring(rl.scale), tostring(safe_percent),
        tostring(loot.world_position[1]), tostring(loot.world_position[2]),
        tostring(banner.world_position[1]), tostring(divider.world_position[2]),
    }, "|")
    if cw.layout_signature == signature then return end

    local renderer = self._ui_top_renderer or self._ui_renderer
    local cell_widths = {}
    for i, row in ipairs(cw.rows) do
        local style = row.widget.style.text
        local text_w = (renderer and UIUtils.get_text_width(renderer, style, row.title)) or 260
        cell_widths[i] = ICON_SIZE + text_w + 20
    end
    local layout = mod._ct_compute_collectible_layout({
        virtual_w = virtual_w,
        virtual_h = virtual_h,
        safe_fraction = safe_percent * 0.01,
        node_x = loot.world_position[1],
        node_y = loot.world_position[2],
        node_h = loot.size[2],
        banner_right = banner.world_position[1] + banner.size[1],
        divider_y = divider.world_position[2],
        count = #cw.rows,
        cell_widths = cell_widths,
    })

    local scale = layout.scale
    local icon_w = ICON_SIZE * scale
    local col_w = layout.available_w / layout.columns
    for i, row in ipairs(cw.rows) do
        local widget = row.widget
        local col = (i - 1) % layout.columns
        local row_index = math.floor((i - 1) / layout.columns)
        widget.offset[1] = layout.base_x + col * col_w
        widget.offset[2] = layout.base_y + (layout.rows - 1 - row_index) * layout.row_pitch

        local styles = widget.style
        styles.icon.texture_size[1], styles.icon.texture_size[2] = icon_w, icon_w
        styles.background_icon.texture_size[1], styles.background_icon.texture_size[2] = icon_w, icon_w
        local text_w = math.max(1, col_w - icon_w - 4)
        for _, name in ipairs({ "text", "text_shadow", "counter_text", "counter_text_disabled", "counter_text_shadow" }) do
            local s = styles[name]
            s.font_size = math.max(14, math.floor(32 * scale + 0.5))
            s.dynamic_font_size = true
            s.word_wrap = false
            s.area_size = { text_w, 40 * scale }
        end
        styles.text.offset[1], styles.text.offset[2] = icon_w, 30 * scale
        styles.text_shadow.offset[1], styles.text_shadow.offset[2] = icon_w + 1, 30 * scale - 1
        styles.counter_text.offset[1], styles.counter_text.offset[2] = icon_w, -40 * scale
        styles.counter_text_disabled.offset[1], styles.counter_text_disabled.offset[2] = icon_w, -40 * scale
        styles.counter_text_shadow.offset[1], styles.counter_text_shadow.offset[2] = icon_w + 1, -40 * scale - 1
    end
    cw.layout_signature = signature
    cw.layout = layout
    pcall(printf,
        "[ct:571] collectible layout res=%dx%d ui_scale=%.3f safe_rect=%.1f%% available=%.1f columns=%d rows=%d icon_scale=%.3f shift=(%.1f,%.1f)",
        rl.res_w or -1, rl.res_h or -1, rl.scale or -1, safe_percent, layout.available_w,
        layout.columns, layout.rows, layout.scale, layout.base_x, layout.base_y)
end

function M.regression()
    if LAYOUT_MARKER ~= "cw_tab_collectibles_native_reflow_v0.7.262" then
        return "#571 REGRESSION: layout marker mismatch"
    end
    if type(mod._ct_compute_collectible_layout) ~= "function" or type(mod._ct_layout_deus_collectibles) ~= "function" then
        return "#571 REGRESSION: layout helpers missing"
    end
    local cases = {
        { name = "16:9", virtual_w = 1920, virtual_h = 1080, node_x = 1280, node_y = 0, divider_y = 195, banner_right = 1920, safe_fraction = 0 },
        { name = "ultrawide", virtual_w = 2580, virtual_h = 1080, node_x = 1940, node_y = 0, divider_y = 195, banner_right = 2580, safe_fraction = 0 },
        -- hud_clamp_ui_scaling at 4K keeps scale=1; fit_height adds 1080 virtual
        -- units below the native right-banner content.
        { name = "ui-scale-clamped", virtual_w = 3840, virtual_h = 2160, node_x = 3200, node_y = 1080, divider_y = 1275, banner_right = 3840, safe_fraction = 0 },
        { name = "ultrawide-safe-rect", virtual_w = 2580, virtual_h = 1080, node_x = 1940, node_y = 0, divider_y = 195, banner_right = 2580, safe_fraction = 0.10 },
    }
    for _, c in ipairs(cases) do
        c.node_h, c.count, c.cell_widths = 90, 2, { 280, 280 }
        local l = mod._ct_compute_collectible_layout(c)
        local left = c.node_x + l.base_x
        local right = left + l.available_w
        if left < l.safe_left - 0.01 or right > l.safe_right + 0.01 then
            return string.format("#571 REGRESSION: %s horizontal safe bound failed", c.name)
        end
        local top = c.node_y + l.base_y + (l.rows - 1) * l.row_pitch + c.node_h
        if top > l.upper + 0.01 then
            return string.format("#571 REGRESSION: %s vertical safe bound failed", c.name)
        end
    end
    local wrapped = mod._ct_compute_collectible_layout({
        virtual_w = 1920, virtual_h = 1080, safe_fraction = 0, node_x = 1280, node_y = 0,
        node_h = 90, banner_right = 1920, divider_y = 195, count = 2, cell_widths = { 380, 380 },
    })
    if wrapped.columns ~= 1 or wrapped.rows ~= 2 then
        return "#571 REGRESSION: oversized localized cells must wrap to one column/two rows"
    end
end

return M
