-- _ct_boon_preview_tooltip.lua
-- Pure canonical-description and measured pane-layout policy for issue #1004.

local M = {}

-- Localized text can be supplied by another mod, so every expensive dimension
-- is capped before renderer measurement begins. Normal game descriptions are
-- far below these ceilings. Oversized or pathological input fails neutral.
M.LIMITS = {
    max_description_bytes = 16384,
    max_pages = 16,
    max_measure_calls = 256,
}

-- Production scenegraph contract from ingame_player_list_ui_v2_definitions.lua:
-- banner_right is 660x1080; reward_divider is a 264x32 top-aligned child at
-- {20,-700}. Its bottom-left world Y is therefore 1080 - 700 - 32 = 348.
-- The #461 rows start 34px below that node and occupy 9x28px. The tooltip grows
-- upward from local Y 50 to local Y 700, leaving 32px below banner_right's top.
M.GEOMETRY = {
    banner_width = 660,
    banner_height = 1080,
    reward_divider_x = 20,
    reward_divider_y_from_top = 700,
    reward_divider_width = 264,
    reward_divider_height = 32,
    row_first_center_offset = -34,
    row_pitch = 28,
    row_count = 9,
    tooltip_x = 4,
    tooltip_y = 50,
    tooltip_width = 620,
    tooltip_top = 700,
    tooltip_min_height = 112,
    horizontal_padding = 16,
    title_chrome = 68,
    paged_chrome = 94,
    min_font_size = 14,
    max_font_size = 18,
}

local function valid_text(value)
    if type(value) ~= "string" or value == "" then return false end
    if value:match("^<[^<>]+>$") or value == "[Invalid String Format]" then return false end
    return true
end

-- Deliberately no template/localization reconstruction here. The instance,
-- profile, and career are passed to the exact helper used by native Deus cards.
-- If that boundary is absent or rejects a third-party registration, showing a
-- neutral unavailable string is safer than inventing plausible-but-wrong values.
function M.resolve_description(options)
    options = options or {}
    if type(options.canonical) == "function" then
        local ok, value = pcall(options.canonical, options.instance or {},
            options.profile_index, options.career_index)
        if ok and valid_text(value) then
            if #value <= M.LIMITS.max_description_bytes then
                return value, "canonical"
            end
            local unavailable = options.unavailable
            if not valid_text(unavailable) then unavailable = "Description unavailable." end
            return unavailable, "oversize"
        end
    end

    local unavailable = options.unavailable
    if not valid_text(unavailable) then unavailable = "Description unavailable." end
    return unavailable, "unavailable"
end

local function measured_height(measure, text, width, font_size, budget)
    if type(measure) ~= "function" then return nil end
    if budget then
        if budget.calls >= budget.limit then return nil, "measurement limit exceeded" end
        budget.calls = budget.calls + 1
    end
    local ok, height = pcall(measure, text, width, font_size)
    if not ok or type(height) ~= "number" or height < 0
        or height ~= height or height == math.huge then
        return nil, "measurement unavailable"
    end
    return height
end

local function utf8_end_offsets(text)
    local offsets = {}
    local i, n = 1, #text
    while i <= n do
        local byte = text:byte(i)
        local length = 1
        if byte and byte >= 0xF0 then length = 4
        elseif byte and byte >= 0xE0 then length = 3
        elseif byte and byte >= 0xC0 then length = 2 end
        i = math.min(n + 1, i + length)
        offsets[#offsets + 1] = i - 1
    end
    return offsets
end

-- Split only after measuring actual rendered substrings. Concatenating every
-- returned page reproduces the input byte-for-byte, including UTF-8 and spaces.
function M.paginate(description, width, font_size, max_height, measure, budget)
    local text = type(description) == "string" and description or ""
    if text == "" then return { "" }, 0 end
    if #text > M.LIMITS.max_description_bytes then
        return nil, nil, "description too long"
    end
    budget = budget or { calls = 0, limit = M.LIMITS.max_measure_calls }

    local pages = {}
    local remaining = text
    local tallest = 0
    while remaining ~= "" do
        if #pages >= M.LIMITS.max_pages then
            return nil, nil, "page limit exceeded"
        end
        local full_height, full_err = measured_height(
            measure, remaining, width, font_size, budget)
        if not full_height then return nil, nil, full_err end
        if full_height <= max_height then
            pages[#pages + 1] = remaining
            tallest = math.max(tallest, full_height)
            break
        end

        local offsets = utf8_end_offsets(remaining)
        local low, high, best, best_height = 1, #offsets, nil, nil
        while low <= high do
            local mid = math.floor((low + high) / 2)
            local candidate = remaining:sub(1, offsets[mid])
            local height, height_err = measured_height(
                measure, candidate, width, font_size, budget)
            if not height then return nil, nil, height_err end
            if height <= max_height then
                best, best_height = offsets[mid], height
                low = mid + 1
            else
                high = mid - 1
            end
        end

        -- A single glyph at the minimum font fits the 556px body in practice.
        -- Retain progress if a synthetic metric says otherwise.
        best = best or offsets[1]
        if not best_height then
            local measured, measured_err = measured_height(
                measure, remaining:sub(1, best), width, font_size, budget)
            if not measured then return nil, nil, measured_err end
            best_height = measured
        end

        -- Prefer a word boundary in the latter half without dropping the
        -- delimiter; page concatenation must remain byte-identical.
        local prefix = remaining:sub(1, best)
        local word_cut
        for pos in prefix:gmatch("()%s+") do word_cut = pos end
        if word_cut and word_cut >= math.floor(best / 2) then
            best = word_cut
            local word_height, word_err = measured_height(
                measure, remaining:sub(1, best), width, font_size, budget)
            if not word_height then return nil, nil, word_err end
            best_height = word_height
        end

        pages[#pages + 1] = remaining:sub(1, best)
        tallest = math.max(tallest, best_height)
        remaining = remaining:sub(best + 1)
    end

    return pages, tallest
end

-- Uses the game renderer's wrapped-font metric supplied by production. A
-- description first shrinks within a bounded 18..14 range. If it still cannot
-- fit, it is measured into bounded input-device pages whose content exactly
-- preserves the full supported localized description.
function M.layout_description(description, measure)
    local g = M.GEOMETRY
    if type(description) ~= "string" then return nil, "description unavailable" end
    if #description > M.LIMITS.max_description_bytes then
        return nil, "description too long"
    end
    local budget = { calls = 0, limit = M.LIMITS.max_measure_calls }
    local width = g.tooltip_width
    local body_width = width - g.horizontal_padding * 2
    local max_height = g.tooltip_top - g.tooltip_y
    local single_body_max = max_height - g.title_chrome

    for font_size = g.max_font_size, g.min_font_size, -1 do
        local height, height_err = measured_height(
            measure, description, body_width, font_size, budget)
        if not height then return nil, height_err end
        if height <= single_body_max then
            return {
                x = g.tooltip_x,
                y = g.tooltip_y,
                width = width,
                height = math.max(g.tooltip_min_height, g.title_chrome + height),
                body_width = body_width,
                body_height = height,
                font_size = font_size,
                pages = { description },
                measured_description_height = height,
                max_page_height = height,
            }
        end
    end

    local page_body_max = max_height - g.paged_chrome
    local pages, tallest, err = M.paginate(description, body_width,
        g.min_font_size, page_body_max, measure, budget)
    if not pages then return nil, err end
    return {
        x = g.tooltip_x,
        y = g.tooltip_y,
        width = width,
        height = max_height,
        body_width = body_width,
        body_height = page_body_max,
        font_size = g.min_font_size,
        pages = pages,
        measured_description_height = measured_height(
            measure, description, body_width, g.min_font_size, budget),
        max_page_height = tallest,
    }
end

function M.page_hint_key(gamepad_active)
    return gamepad_active and "ct_boon_preview_page_hint_controller"
        or "ct_boon_preview_page_hint_mouse"
end

-- right_press is already a platform "pressed" action, but the explicit hold
-- latch protects against a remap or input backend repeating the edge. Mouse
-- wheel remains bidirectional; controller right-shoulder advances and wraps.
function M.navigation_step(wheel_y, controller_pressed, controller_down, latched)
    local next_latched = latched == true
    if controller_down ~= true then next_latched = false end
    if controller_pressed == true and not next_latched then
        return 1, true, true
    end
    if controller_down == true then next_latched = true end
    if type(wheel_y) == "number" and wheel_y ~= 0 then
        return wheel_y < 0 and 1 or -1, next_latched, false
    end
    return 0, next_latched, false
end

function M.production_geometry()
    local g = M.GEOMETRY
    local divider_world_y = g.banner_height - g.reward_divider_y_from_top
        - g.reward_divider_height
    return {
        divider_world_y = divider_world_y,
        first_row_center_world_y = divider_world_y + g.reward_divider_height / 2
            + g.row_first_center_offset,
        last_row_center_world_y = divider_world_y + g.reward_divider_height / 2
            + g.row_first_center_offset - (g.row_count - 1) * g.row_pitch,
        tooltip_world_left = g.reward_divider_x + g.tooltip_x,
        tooltip_world_right = g.reward_divider_x + g.tooltip_x + g.tooltip_width,
        tooltip_world_bottom = divider_world_y + g.tooltip_y,
        tooltip_world_top = divider_world_y + g.tooltip_top,
    }
end

return M
