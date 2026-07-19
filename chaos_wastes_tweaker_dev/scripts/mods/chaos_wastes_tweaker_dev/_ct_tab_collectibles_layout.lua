-- _ct_tab_collectibles_layout.lua — Chaos Wastes hold-Tab collectible placement (#571).
--
-- Vanilla computes mission-widget offsets once from widget-local sizes and text
-- widths in IngamePlayerListUI._setup_mission_data.  Do not derive placement
-- from scenegraph world_position: banner_right animates while the Tab pane opens,
-- so those coordinates are presentation state rather than layout geometry.
--
-- Owned by: chaos_wastes_tweaker_dev.lua. Consumed via: mod:dofile contract.
local mod = get_mod("ct_dev")
local M = {}
local LAYOUT_MARKER = "cw_tab_collectibles_exact_native_offsets"

-- Pure, engine-free port of the offset loop at
-- scripts/ui/views/ingame_player_list_ui_v2.lua:448-500.
-- Each input row supplies the atlas icon size and the already-measured title
-- width.  The returned offsets use the same two-per-row policy, longest-text
-- spacing, and first-row positive Y offset as vanilla.
function mod._ct_compute_native_collectible_offsets(rows)
    local entries_per_row = 2
    local longest_row_text = 0
    local offset_x = 0
    local offsets = {}
    local bounds = {}
    local right_edge = 0

    for i, geometry in ipairs(rows or {}) do
        local size_w = math.max(0, tonumber(geometry.icon_w) or 0)
        local size_h = math.max(0, tonumber(geometry.icon_h) or 0)
        local measured_text_w = math.max(0, tonumber(geometry.text_w) or 0)
        local text_width = measured_text_w + 20

        if longest_row_text < text_width then
            longest_row_text = text_width
        end

        local mission_index = i - 1
        local row = math.floor(mission_index / entries_per_row)
        local column = mission_index % entries_per_row

        if column > 0 then
            offset_x = offset_x + size_w + longest_row_text
            longest_row_text = 0
        else
            offset_x = 0
        end

        local offset_y = -(row - 1) * size_h
        offsets[i] = { offset_x, offset_y, 0 }
        local entry_right = offset_x + size_w + measured_text_w
        bounds[i] = {
            icon_w = size_w,
            icon_h = size_h,
            text_w = measured_text_w,
            right_edge = entry_right,
        }
        right_edge = math.max(right_edge, entry_right)
    end

    return {
        offsets = offsets,
        bounds = bounds,
        count = #offsets,
        rows = math.ceil(#offsets / entries_per_row),
        right_edge = right_edge,
        source = "IngamePlayerListUI._setup_mission_data",
    }
end

local function format_offsets(offsets)
    local out = {}
    for i, offset in ipairs(offsets) do
        out[i] = string.format("%d:(%.1f,%.1f)", i, offset[1], offset[2])
    end
    return table.concat(out, ";")
end

-- Single construction boundary for CT's normal setup wrapper and the draw-time
-- cross-mod hook-order fence. A failed build is latched until the next
-- _setup_mission_data call so a missing atlas cannot create per-frame retries
-- or log spam.
function mod._ct_ensure_deus_collectibles(self, source)
    local mechanism = Managers and Managers.mechanism
    local game_mechanism = mechanism and mechanism.game_mechanism
        and mechanism:game_mechanism()
    local deus = game_mechanism and game_mechanism.get_deus_run_controller
        and game_mechanism:get_deus_run_controller()
    if not self or self._is_in_inn or not deus then return false end
    if self._ct_deus_collectibles then return true end
    if self._ct_deus_collectibles_build_failed then return false end
    local ok, built = pcall(mod._ct_build_deus_collectibles)
    if not ok or type(built) ~= "table" then
        self._ct_deus_collectibles_build_failed = true
        pcall(printf, "[ct:533] deus collectibles build failed source=%s (pane remains vanilla): %s",
            tostring(source), tostring(built))
        return false
    end
    self._ct_deus_collectibles = built
    pcall(printf,
        "[ct:533] Tab-hold collectibles -> deus counters source=%s (Chests of Trials + Pilgrim's Coins); adventure tome/grim/dice counters suppressed",
        tostring(source))
    return true
end

-- Called from the existing consolidated IngamePlayerListUI._draw seam.  It
-- waits until a renderer exists so text widths can be measured, then writes
-- only widget-local offsets.  Resolution/UI-scale/safe-rectangle transforms
-- remain entirely owned by vanilla's banner_right scenegraph.
function mod._ct_layout_deus_collectibles(self)
    local cw = self and self._ct_deus_collectibles
    local rows = cw and cw.rows
    local renderer = self and (self._ui_renderer or self._ui_top_renderer)
    if not (rows and renderer and UIUtils and UIUtils.get_text_width) then return end
    if cw.layout_signature == LAYOUT_MARKER then return end

    local geometry = {}
    for i, row in ipairs(rows) do
        local widget = row.widget
        local styles = widget and widget.style
        local icon = styles and styles.icon
        local text = styles and styles.text
        local texture_size = icon and icon.texture_size
        if not (widget and text and texture_size) then return end

        local ok, text_w = pcall(UIUtils.get_text_width, renderer, text, row.title)
        if not ok or type(text_w) ~= "number" then return end
        geometry[i] = {
            icon_w = texture_size[1],
            icon_h = texture_size[2],
            text_w = text_w,
        }
    end

    local layout = mod._ct_compute_native_collectible_offsets(geometry)
    for i, offset in ipairs(layout.offsets) do
        local widget_offset = rows[i].widget.offset
        widget_offset[1], widget_offset[2], widget_offset[3] = offset[1], offset[2], offset[3]
    end

    local sg = self._ui_scenegraph
    local loot = sg and sg.loot_objective
    local banner = sg and sg.banner_right
    local local_x = loot and loot.position and tonumber(loot.position[1]) or 0
    local banner_w = banner and banner.size and tonumber(banner.size[1]) or 0
    local available_w = math.max(0, banner_w - local_x)
    layout.available_w = available_w
    layout.fits_banner = available_w == 0 or layout.right_edge <= available_w
    cw.layout_signature = LAYOUT_MARKER
    cw.layout = layout

    pcall(printf,
        "[ct:571] native collectible offsets count=%d rows=%d offsets=[%s] right=%.1f available=%.1f fit=%s source=IngamePlayerListUI._setup_mission_data",
        layout.count, layout.rows, format_offsets(layout.offsets), layout.right_edge,
        available_w, tostring(layout.fits_banner))
end

function M.regression()
    if LAYOUT_MARKER ~= "cw_tab_collectibles_exact_native_offsets" then
        return "#571 REGRESSION: layout marker mismatch"
    end
    if type(mod._ct_compute_native_collectible_offsets) ~= "function"
        or type(mod._ct_layout_deus_collectibles) ~= "function"
        or type(mod._ct_ensure_deus_collectibles) ~= "function" then
        return "#571 REGRESSION: native layout helpers missing"
    end

    local two = mod._ct_compute_native_collectible_offsets({
        { icon_w = 80, icon_h = 80, text_w = 120 },
        { icon_w = 80, icon_h = 80, text_w = 200 },
    })
    if two.count ~= 2 or two.rows ~= 1
        or two.offsets[1][1] ~= 0 or two.offsets[1][2] ~= 80
        or two.offsets[2][1] ~= 300 or two.offsets[2][2] ~= 80 then
        return "#571 REGRESSION: two-entry offsets differ from vanilla"
    end

    local four = mod._ct_compute_native_collectible_offsets({
        { icon_w = 80, icon_h = 80, text_w = 100 },
        { icon_w = 80, icon_h = 80, text_w = 120 },
        { icon_w = 80, icon_h = 80, text_w = 90 },
        { icon_w = 80, icon_h = 80, text_w = 110 },
    })
    if four.rows ~= 2 or four.offsets[3][1] ~= 0 or four.offsets[3][2] ~= 0
        or four.offsets[4][1] ~= 210 or four.offsets[4][2] ~= 0 then
        return "#571 REGRESSION: second-row offsets differ from vanilla"
    end
end

return M
