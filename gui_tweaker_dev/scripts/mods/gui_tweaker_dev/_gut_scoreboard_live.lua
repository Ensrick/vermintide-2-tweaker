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
local MAX_NAME = 18
local UTF8 = rawget(_G, "UTF8Utils")

local SCENEGRAPH = {
    root = {
        scale = "hud_scale_fit",
        position = { 0, 0, ((rawget(_G, "UILayer") or {}).hud or 100) + 20 },
        size = { 1920, 1080 },
    },
    panel = {
        parent = "root",
        vertical_alignment = "center",
        horizontal_alignment = "center",
        position = { 0, -210, 1 },
        size = { 1120, 420 },
    },
}

local PASSES = { { pass_type = "rect", style_id = "background" } }
local CONTENT = {}
local STYLE = {
    background = {
        scenegraph_id = "panel",
        color = { 220, 8, 10, 14 },
        offset = { 0, 0, 0 },
    },
}

local function _add_text(id, offset_x, width, alignment)
    PASSES[#PASSES + 1] = { pass_type = "text", text_id = id, style_id = id }
    CONTENT[id] = ""
    STYLE[id] = {
        scenegraph_id = "panel",
        font_type = "arial",
        font_size = 20,
        horizontal_alignment = alignment or "left",
        vertical_alignment = "top",
        text_color = { 255, 235, 235, 235 },
        offset = { offset_x, 14, 2 },
        size = { width, 390 },
        shadow_offset = { 1, 1, 0 },
    }
end

_add_text("labels", 22, 360, "left")
for i = 1, MAX_PLAYERS do _add_text("player" .. i, 372 + (i - 1) * 180, 170, "center") end

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
    local labels = { mod:localize("gut_scoreboard_live_title") }
    for i = 1, #page.topics do
        local key = page.topics[i].display_text
        labels[#labels + 1] = localize and localize(key) or key
    end
    widget.content.labels = table.concat(labels, "\n")

    for column = 1, MAX_PLAYERS do
        local player = page.players[column]
        local lines = {}
        if player then
            lines[1] = _truncate(player.name)
            for row = 1, #page.topics do
                local score = player.scores[page.topics[row].name]
                lines[#lines + 1] = type(score) == "number"
                    and tostring(math.floor(score + 0.5)) or "—"
            end
        end
        widget.content["player" .. column] = table.concat(lines, "\n")
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
