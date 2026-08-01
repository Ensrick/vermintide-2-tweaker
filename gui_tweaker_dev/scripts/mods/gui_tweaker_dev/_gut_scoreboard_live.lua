local mod = get_mod("gut_dev")
local Policy = mod:dofile("scripts/mods/gui_tweaker_dev/_gut_scoreboard_policy")

-- Issue #272 phase 2: an opt-in live page made only from ScoreboardHelper's
-- native snapshot. It owns no stat hooks, transport, or external-mod code.
mod._GUT272_NATIVE_TAB_MARKER = "gut-272-native-helper-snapshot-bounded-four-by-eleven"

local UIRenderer = rawget(_G, "UIRenderer")
local UISceneGraph = rawget(_G, "UISceneGraph")
local UIWidget = rawget(_G, "UIWidget")
local CAPTURE_INTERVAL = 0.25
local MAX_PLAYERS = 4
local MAX_TOPICS = 11
local MAX_NAME = 18
local UTF8 = rawget(_G, "UTF8Utils")
local PANEL_W = 1160
local PANEL_H = 590
local PAD_X = 20
local TITLE_H = 52
local HEADER_H = 44
local ROW_H = 42
local LABEL_W = 300
local PLAYER_W = 200

local SCENEGRAPH = {
    root = {
        is_root = true,
        scale = "hud_scale_fit",
        position = { 0, 0, ((rawget(_G, "UILayer") or {}).hud or 100) + 20 },
        size = { 1920, 1080 },
    },
    panel = {
        parent = "root",
        vertical_alignment = "center",
        horizontal_alignment = "center",
        position = { 0, 0, 1 },
        size = { PANEL_W, PANEL_H },
    },
}

local PASSES = {
    { pass_type = "rect", style_id = "background" },
    { pass_type = "border", style_id = "border" },
}
local CONTENT = {}
local STYLE = {
    background = {
        color = { 245, 8, 10, 14 },
        offset = { 0, 0, 0 },
        size = { PANEL_W, PANEL_H },
    },
    border = {
        color = { 255, 120, 108, 78 },
        thickness = 2,
    },
}

local function _add_rect(id, x, y, width, height, color, z)
    PASSES[#PASSES + 1] = { pass_type = "rect", style_id = id }
    STYLE[id] = {
        offset = { x, y, z or 1 },
        size = { width, height },
        color = color,
    }
end

local function _add_text(id, x, y, width, height, alignment, font_size, color)
    PASSES[#PASSES + 1] = { pass_type = "text", text_id = id, style_id = id }
    CONTENT[id] = ""
    STYLE[id] = {
        font_type = "hell_shark",
        font_size = font_size or 19,
        localize = false,
        upper_case = false,
        horizontal_alignment = alignment or "left",
        vertical_alignment = "center",
        text_color = color or { 255, 235, 235, 235 },
        offset = { x, y, 3 },
        size = { width, height },
        shadow_offset = { 1, 1, 0 },
    }
end

local title_y = PANEL_H - TITLE_H
local header_y = title_y - HEADER_H
_add_rect("title_background", 2, title_y, PANEL_W - 4, TITLE_H,
    { 255, 20, 24, 30 }, 1)
_add_rect("header_background", 2, header_y, PANEL_W - 4, HEADER_H,
    { 255, 35, 37, 42 }, 1)
_add_text("title", PAD_X, title_y, PANEL_W - PAD_X * 2, TITLE_H,
    "center", 25, { 255, 225, 195, 120 })
_add_text("stat_header", PAD_X, header_y, LABEL_W, HEADER_H,
    "left", 19, { 255, 215, 205, 175 })

for column = 1, MAX_PLAYERS do
    local x = PAD_X + LABEL_W + (column - 1) * PLAYER_W
    _add_rect("column_rule_" .. column, x - 1, 24,
        2, PANEL_H - TITLE_H - 24, { 150, 105, 105, 105 }, 2)
    _add_text("player_header_" .. column, x, header_y, PLAYER_W, HEADER_H,
        "center", 19, { 255, 235, 225, 195 })
end

for row = 1, MAX_TOPICS do
    local y = header_y - row * ROW_H
    _add_rect("row_background_" .. row, 2, y, PANEL_W - 4, ROW_H,
        row % 2 == 0 and { 225, 20, 22, 27 } or { 225, 13, 15, 19 }, 1)
    _add_text("label_" .. row, PAD_X, y, LABEL_W, ROW_H,
        "left", 18, { 255, 215, 215, 215 })
    for column = 1, MAX_PLAYERS do
        local x = PAD_X + LABEL_W + (column - 1) * PLAYER_W
        _add_text("player_" .. column .. "_row_" .. row,
            x, y, PLAYER_W, ROW_H, "center", 18,
            { 255, 240, 240, 240 })
    end
end

local WIDGET_DEF = {
    scenegraph_id = "panel",
    element = { passes = PASSES },
    content = CONTENT,
    style = STYLE,
}

local scenegraph
local widget
local cached_page
local cached_at = -math.huge
local evidence_count = 0
local last_evidence
local external_reported = false
local dummy_input = { get = function() return end, has = function() return end }
local render_settings = { snap_pixel_positions = true }

local function _enabled()
    return mod:get("gut_scoreboard_live_native") == true
end

local function _is_adventure(game_mode_key)
    if game_mode_key == "adventure" then return true end
    local managers = rawget(_G, "Managers")
    local mechanism = managers and managers.mechanism
    return mechanism and mechanism:current_mechanism_name() == "adventure" or false
end

local function _snapshot()
    local helper = rawget(_G, "ScoreboardHelper")
    local managers = rawget(_G, "Managers")
    local player_manager = managers and managers.player
    local network = managers and managers.state and managers.state.network
    local db = player_manager and player_manager.statistics_db and player_manager:statistics_db()
    local synchronizer = network and network.profile_synchronizer
    if type(helper) ~= "table" or type(helper.get_grouped_topic_statistics) ~= "function"
            or not db or not synchronizer then
        return nil
    end
    local ok, players = pcall(helper.get_grouped_topic_statistics, db, synchronizer, nil)
    if not ok then return nil end
    return Policy.build_native_page(players, helper.scoreboard_topic_stats,
        mod:get("gut_scoreboard_live_sort"), MAX_PLAYERS)
end

local function _truncate(name)
    if UTF8 and type(UTF8.string_length) == "function"
            and type(UTF8.sub_string) == "function" then
        return UTF8.string_length(name) > MAX_NAME
            and UTF8.sub_string(name, 1, MAX_NAME - 3) .. "..." or name
    end
    return #name > MAX_NAME and name:sub(1, MAX_NAME - 3) .. "..." or name
end

local function _populate(page)
    local localize = rawget(_G, "Localize")
    widget.content.title = mod:localize("gut_scoreboard_live_title")
    widget.content.stat_header = mod:localize("gut_scoreboard_live_statistic")
    for row = 1, MAX_TOPICS do
        local topic = page.topics[row]
        widget.content["label_" .. row] = topic
            and (localize and localize(topic.display_text) or topic.display_text) or ""
    end

    for column = 1, MAX_PLAYERS do
        local player = page.players[column]
        widget.content["player_header_" .. column] = player
            and _truncate(player.name) or ""
        for row = 1, MAX_TOPICS do
            local topic = page.topics[row]
            local value = ""
            if player and topic then
                local score = player.scores[topic.name]
                value = type(score) == "number"
                    and tostring(math.floor(score + 0.5)) or "—"
            end
            widget.content["player_" .. column .. "_row_" .. row] = value
        end
    end
end

local function _render_page(renderer, input, dt, page, surface)
    if not renderer or not page or not UIRenderer or not UISceneGraph or not UIWidget then return end
    local sort_topic = tostring(mod:get("gut_scoreboard_live_sort") or "player_name")
    local fingerprint = tostring(surface) .. ":" .. tostring(#page.players) .. ":" .. sort_topic
    if fingerprint ~= last_evidence and evidence_count < 8 then
        evidence_count = evidence_count + 1
        last_evidence = fingerprint
        mod:info("[gut:272] native_page evidence=%d/8 surface=%s players=%d topics=%d sort=%s",
            evidence_count, tostring(surface), #page.players, #page.topics, sort_topic)
    end

    if not scenegraph then scenegraph = UISceneGraph.init_scenegraph(SCENEGRAPH) end
    if not widget then widget = UIWidget.init(WIDGET_DEF) end
    _populate(page)
    UIRenderer.begin_pass(renderer, scenegraph, input or dummy_input, dt, nil, render_settings)
    UIRenderer.draw_widget(renderer, widget)
    UIRenderer.end_pass(renderer)
end

mod:hook_safe("IngamePlayerListUI", "_draw", function(self, dt)
    if not _enabled() then return end
    if get_mod("reikland-scoreboard") then
        if not external_reported then
            external_reported = true
            mod:info("[gut:272] native_tab skipped reason=external_scoreboard_loaded")
        end
        return
    end
    local renderer = self._ui_top_renderer
    if not renderer then return end

    local managers = rawget(_G, "Managers")
    if not _is_adventure() then return end
    local time = managers and managers.time
    local now = time and time.time and time:time("game") or 0
    if not cached_page or now - cached_at >= CAPTURE_INTERVAL then
        cached_page = _snapshot()
        cached_at = now
    end
    if not cached_page then return end

    local input = self._input_manager and self._input_manager:get_service("player_list_input")
        or dummy_input
    _render_page(renderer, input, dt, cached_page, "tab")
end)

-- EndViewStateScore already owns the session snapshot and its draw/input
-- lifecycle. Reuse the exact same detached model and renderer so live and final
-- pages cannot disagree about topic order or sorting.
mod:hook_safe("EndViewStateScore", "draw", function(self, input_service, dt)
    if not _enabled() or get_mod("reikland-scoreboard")
            or not _is_adventure(self.game_mode_key) then return end
    local helper = rawget(_G, "ScoreboardHelper")
    local players = self._context and self._context.players_session_score
    if type(helper) ~= "table" or type(players) ~= "table" then return end
    local page = Policy.build_native_page(players, helper.scoreboard_topic_stats,
        mod:get("gut_scoreboard_live_sort"), MAX_PLAYERS)
    _render_page(self.ui_renderer, input_service, dt, page, "end")
end)

return {
    rt_checks = {
        {
            name = "issue272_native_live_scoreboard_page",
            fn = function()
                if mod._GUT272_NATIVE_TAB_MARKER
                        ~= "gut-272-native-helper-snapshot-bounded-four-by-eleven" then
                    return "native live scoreboard marker missing"
                end
                local helper = rawget(_G, "ScoreboardHelper")
                if type(helper) ~= "table" or #helper.scoreboard_topic_stats ~= 11 then
                    return "native scoreboard topic catalog unavailable"
                end
            end,
        },
    },
}
