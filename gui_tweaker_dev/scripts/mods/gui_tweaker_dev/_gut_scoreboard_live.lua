-- _gut_scoreboard_live.lua - shared held-Tab and end-screen scoreboard presenter.
--
-- Owns the two existing draw seams, the fixed 11-by-4 widget, detached native
-- scalar reads, the exit-time end-screen sidecar, and the optional persisted
-- page callback. It owns no transport.
-- Owned by: gui_tweaker_dev.lua. Consumed via: mod:dofile from the entry point.
local mod = get_mod("gut_dev")
local Policy = mod:dofile("scripts/mods/gui_tweaker_dev/_gut_scoreboard_policy")

-- Issue #1414 / #272 phase 3: an opt-in paged presentation made from the
-- vanilla eleven-row snapshot plus two detached native scalar reads. It owns
-- no stat hooks, transport, or external-mod code.
mod._GUT272_NATIVE_TAB_MARKER = "gut-272-native-detached-four-page-model"

local UIRenderer = rawget(_G, "UIRenderer")
local UISceneGraph = rawget(_G, "UISceneGraph")
local UIWidget = rawget(_G, "UIWidget")
local CAPTURE_INTERVAL = 0.25
local MAX_PLAYERS = 4
local MAX_TOPICS = Policy.ROWS_PER_PAGE
local PAGE_EVIDENCE_CAP = 8
local SIDECAR_EVIDENCE_CAP = 8
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
local cached_model
local cached_at = -math.huge
local evidence_count = 0
local last_evidence
local external_reported = false
local last_page_count = 0
local runtime_model_reported = false
local mission_generation = 0
local captured_generation
local end_supplemental_scores
local sidecar_evidence_count = 0
local dummy_input = { get = function() return end, has = function() return end }
local render_settings = { snap_pixel_positions = true }

local function _enabled()
    return mod:get("gut_scoreboard_live_native") == true
end

-- (#272) An installed-but-DISABLED external scoreboard must not suppress gut's
-- page: VMF get_mod() returns the mod object even when the user toggled the mod
-- off, so gate on presence AND :is_enabled() (the _gut_uitweaks_sync.lua:91-100
-- pattern). An unreadable is_enabled counts as enabled, so a present-but-
-- uncheckable external mod still owns the surface (never double-draw).
-- `external` is injectable for the rt check; nil means the live lookup.
local function _external_scoreboard_active(external)
    external = external or get_mod("reikland-scoreboard")
    if not external then return false end
    if type(external.is_enabled) == "function" then
        local ok, enabled = pcall(external.is_enabled, external)
        if ok and enabled == false then return false end
    end
    return true
end

local function _is_adventure(game_mode_key)
    if game_mode_key == "adventure" then return true end
    local managers = rawget(_G, "Managers")
    local mechanism = managers and managers.mechanism
    return mechanism and mechanism:current_mechanism_name() == "adventure" or false
end

local function _visibility(topics)
    local visibility = {}
    for _, topic in ipairs(topics) do
        visibility[topic.name] = mod:get(
            "gut_scoreboard_topic_" .. topic.name .. "_visible") ~= false
    end
    return visibility
end

local function _model_options(topics)
    return {
        player_limit = MAX_PLAYERS,
        selected_page = mod:get("gut_scoreboard_live_page"),
        sort_topic = mod:get("gut_scoreboard_live_sort"),
        visibility = _visibility(topics),
    }
end

local function _build_model(players, helper, database, supplemental_scores)
    local topics = Policy.build_topic_registry(helper.scoreboard_topic_stats)
    local options = _model_options(topics)
    local provisional = Policy.build_native_model(players, topics, options)
    options.supplemental_scores = supplemental_scores
    if not supplemental_scores and database then
        options.supplemental_scores = Policy.read_supplemental_scores(
            provisional.players,
            function(stats_id, stat_type)
                return database:get_stat(stats_id, stat_type)
            end,
            MAX_PLAYERS)
    end
    return Policy.build_native_model(players, topics, options)
end

local function _snapshot(database, profile_synchronizer)
    local helper = rawget(_G, "ScoreboardHelper")
    local managers = rawget(_G, "Managers")
    local player_manager = managers and managers.player
    local network = managers and managers.state and managers.state.network
    local db = database
        or (player_manager and player_manager.statistics_db
            and player_manager:statistics_db())
    local synchronizer = profile_synchronizer
        or (network and network.profile_synchronizer)
    if type(helper) ~= "table" or type(helper.get_grouped_topic_statistics) ~= "function"
            or not db or not synchronizer then
        return nil
    end
    local ok, players = pcall(helper.get_grouped_topic_statistics, db, synchronizer, nil)
    if not ok then return nil end
    return _build_model(players, helper, db)
end

local function _copy_supplemental_scores(model)
    local scores = {}
    for _, player in ipairs(type(model) == "table" and model.players or {}) do
        local values = {}
        for _, topic in ipairs(Policy.SUPPLEMENTAL_TOPICS) do
            local value = type(player.scores) == "table"
                and player.scores[topic.name] or nil
            if type(value) == "number" then values[topic.name] = value end
        end
        scores[player.stats_key] = values
    end
    return scores
end

-- Normal Adventure level_end_view_context does not carry statistics_db
-- (state_ingame_running.lua:274-344), although EndViewStateScore assigns the
-- absent field (end_view_state_score.lua:23-29). Capture the only two extra
-- scalar leaves at the StateIngame exit edge while StatisticsDatabase rows are
-- still live. GameStateMachine notifies mods with the old state object before
-- running the native state transition (game_state_machine.lua:14-21), so that
-- object's database/synchronizer are the first-choice sources. The detached
-- sidecar is capped to the model's four player rows; it never modifies
-- players_session_score or any network payload.
local function _capture_end_sidecar(state_object)
    if not _enabled() or not _is_adventure() then
        end_supplemental_scores = nil
        return
    end
    local database = type(state_object) == "table"
        and state_object.statistics_db or nil
    local synchronizer = type(state_object) == "table"
        and state_object.profile_synchronizer or nil
    local model = _snapshot(database, synchronizer)
    end_supplemental_scores = model and _copy_supplemental_scores(model) or nil
    if sidecar_evidence_count < SIDECAR_EVIDENCE_CAP then
        sidecar_evidence_count = sidecar_evidence_count + 1
        pcall(printf,
            "[gut:1414] sidecar evidence=%d/%d generation=%d players=%d fp=%s",
            sidecar_evidence_count, SIDECAR_EVIDENCE_CAP, mission_generation,
            model and #model.players or 0,
            model and model.fingerprint or "unavailable")
    end
end

-- StateLoading carries a still-running LevelEndViewWrapper into the next
-- StateIngame through parent.loading_context.level_end_view_wrappers
-- (state_loading.lua:1671-1677; state_ingame.lua:347-380). The root
-- GameStateMachine enter callback runs after StateIngame.on_enter, so that
-- exact array remains visible on the new state object. Preserve the previous
-- mission's sidecar only across that one source-proven handoff.
local function _carries_end_view_wrapper(state_object)
    local parent = type(state_object) == "table"
        and rawget(state_object, "parent") or nil
    local loading_context = type(parent) == "table"
        and rawget(parent, "loading_context") or nil
    local wrappers = type(loading_context) == "table"
        and rawget(loading_context, "level_end_view_wrappers") or nil
    return type(wrappers) == "table" and rawget(wrappers, 1) ~= nil
end

-- Install one VMF lifecycle-chain owner after every earlier entry-point owner.
-- Capture precedes the previous exit chain so a later teardown cannot delete
-- the database rows first. Every StateIngame enter clears both Tab cache fields
-- before a new mission clock can be compared with the old one. The end sidecar
-- survives only the carried-wrapper enter; an ordinary StateIngame enter clears
-- it. Nested state notifications must remain neutral because StateInGameRunning
-- is constructed inside StateIngame.on_enter and can notify before the outer
-- StateIngame callback (state_ingame.lua:345-388; game_state_machine.lua:21-27).
local previous_state_changed = mod.on_game_state_changed
mod.on_game_state_changed = function(status, state_name, ...)
    if state_name == "StateIngame" then
        if status == "enter" then
            local state_object = select(1, ...)
            mission_generation = mission_generation + 1
            captured_generation = nil
            if not _carries_end_view_wrapper(state_object) then
                end_supplemental_scores = nil
            end
            cached_model = nil
            cached_at = -math.huge
            last_page_count = 0
        elseif status == "exit" and captured_generation ~= mission_generation then
            captured_generation = mission_generation
            local state_object = select(1, ...)
            local ok, err = pcall(_capture_end_sidecar, state_object)
            if not ok then
                end_supplemental_scores = nil
                if sidecar_evidence_count < SIDECAR_EVIDENCE_CAP then
                    sidecar_evidence_count = sidecar_evidence_count + 1
                    pcall(printf,
                        "[gut:1414] sidecar evidence=%d/%d generation=%d players=0 error=%s",
                        sidecar_evidence_count, SIDECAR_EVIDENCE_CAP,
                        mission_generation, tostring(err))
                end
            end
        end
    end
    if previous_state_changed then previous_state_changed(status, state_name, ...) end
end

local function _truncate(name)
    if UTF8 and type(UTF8.string_length) == "function"
            and type(UTF8.sub_string) == "function" then
        return UTF8.string_length(name) > MAX_NAME
            and UTF8.sub_string(name, 1, MAX_NAME - 3) .. "..." or name
    end
    return #name > MAX_NAME and name:sub(1, MAX_NAME - 3) .. "..." or name
end

local function _populate(model)
    local localize = rawget(_G, "Localize")
    local page = model.selected
    local title = mod:localize("gut_scoreboard_live_title")
    if model.all_hidden then
        title = title .. " - " .. mod:localize("gut_scoreboard_live_none_selected")
    else
        title = title .. " - " .. mod:localize("gut_scoreboard_live_page_label")
            .. " " .. tostring(model.selected_page) .. "/" .. tostring(model.page_count)
    end
    widget.content.title = title
    widget.content.stat_header = mod:localize("gut_scoreboard_live_statistic")
    for row = 1, MAX_TOPICS do
        local topic = page and page.topics[row]
        widget.content["label_" .. row] = topic
            and (topic.mod_localized and mod:localize(topic.display_text)
                or (localize and localize(topic.display_text) or topic.display_text)) or ""
    end

    for column = 1, MAX_PLAYERS do
        local player = model.players[column]
        widget.content["player_header_" .. column] = player
            and _truncate(player.name) or ""
        for row = 1, MAX_TOPICS do
            local topic = page and page.topics[row]
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

local function _render_model(renderer, input, dt, model, surface)
    if not renderer or not model or not UIRenderer or not UISceneGraph or not UIWidget then return end
    last_page_count = model.page_count
    local fingerprint = tostring(surface) .. ":" .. model.fingerprint
    if fingerprint ~= last_evidence and evidence_count < PAGE_EVIDENCE_CAP then
        evidence_count = evidence_count + 1
        last_evidence = fingerprint
        pcall(printf, "[gut:1414] page evidence=%d/%d surface=%s players=%d page=%d/%d topics=%d overflow=%d sort=%s fp=%s",
            evidence_count, PAGE_EVIDENCE_CAP, tostring(surface), #model.players,
            model.selected_page, model.page_count, #model.visible_topics,
            model.overflow_count, model.effective_sort, model.fingerprint)
    end

    if not scenegraph then scenegraph = UISceneGraph.init_scenegraph(SCENEGRAPH) end
    if not widget then widget = UIWidget.init(WIDGET_DEF) end
    _populate(model)
    UIRenderer.begin_pass(renderer, scenegraph, input or dummy_input, dt, nil, render_settings)
    UIRenderer.draw_widget(renderer, widget)
    UIRenderer.end_pass(renderer)
end

mod:hook_safe("IngamePlayerListUI", "_draw", function(self, dt)
    if not _enabled() then return end
    if _external_scoreboard_active() then
        if not external_reported then
            external_reported = true
            pcall(printf, "[gut:272] native_tab skipped reason=external_scoreboard_loaded")
        end
        return
    end
    local renderer = self._ui_top_renderer
    if not renderer then return end

    local managers = rawget(_G, "Managers")
    if not _is_adventure() then return end
    local time = managers and managers.time
    local now = time and time.time and time:time("game") or 0
    if not cached_model or now < cached_at
            or now - cached_at >= CAPTURE_INTERVAL then
        cached_model = _snapshot()
        cached_at = now
    end
    if not cached_model then return end

    local input = self._input_manager and self._input_manager:get_service("player_list_input")
        or dummy_input
    _render_model(renderer, input, dt, cached_model, "tab")
end)

-- EndViewStateScore already owns the session snapshot and its draw/input
-- lifecycle. Reuse the exact same detached model and renderer so live and final
-- pages cannot disagree about topic order or sorting.
mod:hook_safe("EndViewStateScore", "draw", function(self, input_service, dt)
    if not _enabled() or _external_scoreboard_active()
            or not _is_adventure(self.game_mode_key) then return end
    local helper = rawget(_G, "ScoreboardHelper")
    local players = self._context and self._context.players_session_score
    if type(helper) ~= "table" or type(players) ~= "table" then return end
    local model = _build_model(players, helper, nil, end_supplemental_scores)
    _render_model(self.ui_renderer, input_service, dt, model, "end")
end)

-- VMF owns keybind dispatch. This callback only advances persisted page state;
-- it adds no Tab/update/input hook and never mutates the cached native snapshot.
mod.gut_scoreboard_next_page = function()
    mod:set("gut_scoreboard_live_page", Policy.next_page(
        mod:get("gut_scoreboard_live_page"), last_page_count))
end

return {
    rt_checks = {
        {
            name = "issue272_native_live_scoreboard_page",
            fn = function()
                if mod._GUT272_NATIVE_TAB_MARKER
                        ~= "gut-272-native-detached-four-page-model" then
                    return "native live scoreboard marker missing"
                end
                local native = {}
                for i = 1, 11 do
                    native[i] = {
                        name = "native_" .. tostring(i),
                        display_text = "native_label_" .. tostring(i),
                        stat_type = "native_stat_" .. tostring(i),
                    }
                end
                local topics = Policy.build_topic_registry(native)
                local players = {
                    tester = {
                        name = "Tester",
                        stats_id = "tester",
                        group_scores = { offense = {} },
                    },
                }
                local options = {
                    selected_page = 2,
                    sort_topic = "aidings",
                    supplemental_scores = {
                        tester = { aidings = 7, times_revived = 3 },
                    },
                }
                local first = Policy.build_native_model(players, topics, options)
                local second = Policy.build_native_model(players, topics, options)
                if type(first) ~= "table" or type(second) ~= "table" then
                    return "synthetic model result missing"
                end
                local page_two = first.pages and first.pages[2] or nil
                if #topics ~= 13 or first.page_count ~= 2
                        or first.selected_page ~= 2 or type(page_two) ~= "table"
                        or type(page_two.topics) ~= "table" or #page_two.topics ~= 2 then
                    return "synthetic thirteen-topic paging failed"
                end
                local player = first.players and first.players[1]
                if page_two.topics[1].name ~= "aidings"
                        or page_two.topics[2].name ~= "times_revived"
                        or type(player) ~= "table" or type(player.scores) ~= "table"
                        or player.scores.aidings ~= 7 then
                    return "detached supplemental rows failed"
                end
                if first.effective_sort ~= "aidings"
                        or first.fingerprint ~= second.fingerprint
                        or type(first.fingerprint) ~= "string"
                        or not first.fingerprint:match("^[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]$") then
                    return "deterministic model verdict failed"
                end
                if not runtime_model_reported then
                    runtime_model_reported = true
                    pcall(printf, "[gut:1414] runtime verdict=PASS page=%d/%d topics=%d fp=%s",
                        first.selected_page, first.page_count,
                        #first.visible_topics, first.fingerprint)
                end
            end,
        },
        {
            name = "issue272_external_scoreboard_gate_respects_enabled",
            fn = function()
                if _external_scoreboard_active({ is_enabled = function() return false end }) then
                    return "disabled external scoreboard still suppresses the native page"
                end
                if not _external_scoreboard_active({ is_enabled = function() return true end }) then
                    return "enabled external scoreboard is not detected"
                end
                if not _external_scoreboard_active({}) then
                    return "external mod without is_enabled must count as present"
                end
            end,
        },
    },
}
