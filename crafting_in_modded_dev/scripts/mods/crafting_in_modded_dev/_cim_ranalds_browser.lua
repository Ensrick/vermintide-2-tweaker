-- Own-scenegraph Ranald's Gift browser for CIM's Athanor overview (#1360).
-- The module owns no hooks. _cim_forge_ui_owner drives it from CIM's single
-- HeroViewStateWeaveForge.update seam.

local mod = get_mod("cim_dev")
local Browser = { built = false, open_state = false, page = 1, sort_mode = "likes" }

local PANEL_W, PANEL_H = 1240, 900
local ROW_W, ROW_H = 1080, 82
local FRAME_TEXTURE = "menu_frame_12"
local FRAME_TEX_SIZE = { 64, 64 }
local FRAME_TEX_SIZES = { corner = { 11, 11 }, vertical = { 5, 1 }, horizontal = { 1, 5 } }
local COL_BASE = { 245, 28, 23, 17 }
local COL_HOVER = { 255, 74, 58, 39 }
local COL_SELECTED = { 255, 115, 80, 42 }
local COL_DISABLED = { 190, 24, 24, 24 }
local FALLBACK = {
    opener = "COMMUNITY BUILDS",
    title = "RANALD'S GIFT COMMUNITY BUILDS",
    career_prev = "< CAREER",
    career_next = "CAREER >",
    sort_likes = "SORT: LIKES",
    sort_recent = "SORT: RECENT",
    page_prev = "< PAGE",
    page_next = "PAGE >",
    page_label = "PAGE %d / %d",
    import = "IMPORT SELECTED BUILD",
    loading = "Loading community builds...",
    load_failed = "Could not load builds: %s",
    request_failed = "Could not start request: %s",
    loaded = "Loaded %d community build(s)",
    ignored = "; ignored %d malformed",
    bounded = "; showing the bounded first 800",
    row = "%s\nby %s  |  Likes %d  |  %s",
    unknown_date = "Unknown date",
    importing = "Importing %s...",
    import_failed = "Import failed safely: %s",
    import_rejected = "Import rejected: %s",
    imported = "Imported and equipped: %s",
}

local function _loc(key, ...)
    local fallback = FALLBACK[key] or key
    if mod and type(mod.localize) == "function" then
        local ok, value = pcall(mod.localize, mod, "ranalds_" .. key, ...)
        if ok and type(value) == "string"
                and value ~= "<ranalds_" .. key .. ">" then
            return value
        end
    end
    if select("#", ...) > 0 then
        local ok, value = pcall(string.format, fallback, ...)
        if ok then return value end
    end
    return fallback
end

local function _node(parent, x, y, w, h, z)
    return {
        parent = parent or "root", horizontal_alignment = "center",
        vertical_alignment = "center", size = { w, h }, position = { x, y, z or 10 },
    }
end

local function _scenegraph_definition()
    local definition = {
        root = { is_root = true, size = { 1920, 1080 }, position = { 0, 0, 1 } },
        opener = _node("root", -705, 415, 390, 58, 20),
        scrim = _node("root", 0, 0, 1920, 1080, 100),
        panel = _node("root", 0, 0, PANEL_W, PANEL_H, 101),
        title = _node("panel", 0, 392, 880, 52, 5),
        close = _node("panel", 545, 392, 70, 52, 6),
        career_prev = _node("panel", -475, 310, 170, 54, 6),
        career_label = _node("panel", -175, 310, 400, 54, 6),
        career_next = _node("panel", 125, 310, 170, 54, 6),
        sort = _node("panel", 425, 310, 250, 54, 6),
        page_prev = _node("panel", -250, -315, 180, 54, 6),
        page_label = _node("panel", 0, -315, 260, 54, 6),
        page_next = _node("panel", 250, -315, 180, 54, 6),
        status = _node("panel", 0, -372, 1080, 42, 6),
        import = _node("panel", 0, -420, 430, 58, 6),
    }
    for i = 1, 5 do definition["row_" .. i] = _node("panel", 0, 215 - (i - 1) * 98, ROW_W, ROW_H, 6) end
    return definition
end

local function _frame_style(w, h, z)
    return {
        texture_size = FRAME_TEX_SIZE, texture_sizes = FRAME_TEX_SIZES,
        color = { 255, 255, 255, 255 }, offset = { 0, 0, z or 3 }, area_size = { w, h },
    }
end

local function _button(node, text, w, h, font_size)
    return {
        element = { passes = {
            { content_id = "hotspot", pass_type = "hotspot" },
            { pass_type = "rect", style_id = "rect" },
            { pass_type = "text", style_id = "text", text_id = "text" },
            { pass_type = "texture_frame", style_id = "frame", texture_id = "frame" },
        } },
        content = { hotspot = {}, text = text, frame = FRAME_TEXTURE },
        style = {
            rect = { size = { w, h }, color = { 245, 28, 23, 17 } },
            text = { font_size = font_size or 21, font_type = "hell_shark_header",
                horizontal_alignment = "center", vertical_alignment = "center",
                text_color = { 255, 245, 232, 215 }, offset = { 0, 0, 2 }, size = { w, h } },
            frame = _frame_style(w, h, 3),
        },
        scenegraph_id = node, offset = { 0, 0, 0 },
    }
end

local function _text(node, text, w, h, size)
    return {
        element = { passes = { { pass_type = "text", style_id = "text", text_id = "text" } } },
        content = { text = text },
        style = { text = { font_size = size or 22, font_type = "hell_shark",
            horizontal_alignment = "center", vertical_alignment = "center",
            text_color = { 255, 235, 225, 210 }, offset = { 0, 0, 2 }, size = { w, h } } },
        scenegraph_id = node, offset = { 0, 0, 0 },
    }
end

local function _rect(node, color, w, h, frame)
    local passes = { { pass_type = "rect", style_id = "rect" } }
    if frame then passes[#passes + 1] = { pass_type = "texture_frame", style_id = "frame", texture_id = "frame" } end
    return {
        element = { passes = passes }, content = { frame = FRAME_TEXTURE },
        style = { rect = { size = { w, h }, color = color }, frame = _frame_style(w, h, 2) },
        scenegraph_id = node, offset = { 0, 0, 0 },
    }
end

local function _build()
    if Browser.built then return true end
    local UISceneGraph, UIWidget = rawget(_G, "UISceneGraph"), rawget(_G, "UIWidget")
    if not UISceneGraph or not UIWidget then return false end
    local ok, scenegraph = pcall(UISceneGraph.init_scenegraph, _scenegraph_definition())
    if not ok then return false end
    Browser.scenegraph = scenegraph
    local definitions = {
        scrim = _rect("scrim", { 210, 0, 0, 0 }, 1920, 1080),
        panel = _rect("panel", { 252, 18, 15, 12 }, PANEL_W, PANEL_H, true),
        opener = _button("opener", _loc("opener"), 390, 58, 22),
        title = _text("title", _loc("title"), 880, 52, 30),
        close = _button("close", "X", 70, 52, 24),
        career_prev = _button("career_prev", _loc("career_prev"), 170, 54, 19),
        career_label = _text("career_label", "", 400, 54, 23),
        career_next = _button("career_next", _loc("career_next"), 170, 54, 19),
        sort = _button("sort", _loc("sort_likes"), 250, 54, 19),
        page_prev = _button("page_prev", _loc("page_prev"), 180, 54, 19),
        page_label = _text("page_label", _loc("page_label", 1, 1), 260, 54, 20),
        page_next = _button("page_next", _loc("page_next"), 180, 54, 19),
        status = _text("status", "", 1080, 42, 18),
        import = _button("import", _loc("import"), 430, 58, 21),
    }
    for i = 1, 5 do definitions["row_" .. i] = _button("row_" .. i, "", ROW_W, ROW_H, 19) end
    Browser.widgets = {}
    for name, definition in pairs(definitions) do
        local init_ok, widget = pcall(UIWidget.init, definition)
        if not init_ok then return false end
        Browser.widgets[name] = widget
    end
    Browser.built = true
    return true
end

function Browser.configure(ctx)
    Browser.catalog = assert(ctx.catalog, "Ranald browser requires catalog")
    Browser.fetcher = assert(ctx.fetcher, "Ranald browser requires fetcher")
    Browser.current_career_id = assert(ctx.current_career_id, "Ranald browser requires career resolver")
    Browser.career_label = assert(ctx.career_label, "Ranald browser requires career label")
    Browser.import_build = assert(ctx.import_build, "Ranald browser requires importer")
end

local function _sorted()
    return Browser.catalog.sort(Browser.builds or {}, Browser.sort_mode)
end

local function _max_page()
    local count = #(Browser.builds or {})
    return math.max(1, math.ceil(count / Browser.catalog.PAGE_SIZE))
end

local function _request()
    Browser.loading, Browser.builds, Browser.selected, Browser.page = true, {}, nil, 1
    Browser.status = _loc("loading")
    local accepted, err = Browser.fetcher.fetch(Browser.career_id, function(builds, fetch_err, meta)
        Browser.loading = false
        if not builds then
            Browser.status = _loc("load_failed", tostring(fetch_err))
            return
        end
        Browser.builds = builds
        Browser.status = _loc("loaded", #builds)
        if meta and meta.rejected > 0 then
            Browser.status = Browser.status .. _loc("ignored", meta.rejected)
        end
        if meta and meta.truncated then
            Browser.status = Browser.status .. _loc("bounded")
        end
    end)
    if not accepted then
        Browser.loading = false
        Browser.status = _loc("request_failed", tostring(err))
    end
end

function Browser.open()
    if not Browser.catalog then return false end
    Browser.open_state = true
    Browser.career_id = tonumber(Browser.current_career_id()) or 1
    if not Browser.catalog.CAREERS[Browser.career_id] then Browser.career_id = 1 end
    _request()
    return true
end

function Browser.close()
    Browser.open_state = false
    Browser.selected = nil
    if Browser.fetcher then Browser.fetcher.cancel() end
end

function Browser.is_open()
    return Browser.open_state == true
end

local function _consume(name)
    local widget = Browser.widgets[name]
    local hotspot = widget and widget.content and widget.content.hotspot
    if hotspot and hotspot.on_release then hotspot.on_release = false; return true end
    return false
end

local function _set_button_color(widget, selected, disabled)
    if not widget or not widget.style or not widget.style.rect then return end
    local hotspot = widget.content and widget.content.hotspot
    if disabled then widget.style.rect.color = COL_DISABLED
    elseif selected then widget.style.rect.color = COL_SELECTED
    elseif hotspot and (hotspot.is_hover or hotspot.is_held) then widget.style.rect.color = COL_HOVER
    else widget.style.rect.color = COL_BASE end
end

local function _refresh_content()
    local widgets = Browser.widgets
    if not Browser.open_state then return end
    widgets.career_label.content.text = Browser.career_label(Browser.career_id)
    widgets.sort.content.text = Browser.sort_mode == "likes"
        and _loc("sort_likes") or _loc("sort_recent")
    widgets.page_label.content.text = _loc("page_label", Browser.page, _max_page())
    widgets.status.content.text = Browser.status or ""
    local sorted = _sorted()
    local first = (Browser.page - 1) * Browser.catalog.PAGE_SIZE + 1
    for row = 1, 5 do
        local build = sorted[first + row - 1]
        local widget = widgets["row_" .. row]
        widget.content._cim_build = build
        widget.content.text = build and _loc("row",
            build.name, build.username, build.like_count,
            build.date_modified ~= "" and build.date_modified:sub(1, 10)
                or _loc("unknown_date")) or ""
        widget.content.visible = build ~= nil
        _set_button_color(widget, build and Browser.selected == build, build == nil)
    end
    _set_button_color(widgets.import, false, not Browser.selected or Browser.loading)
end

local function _handle_input()
    if not Browser.open_state then
        if _consume("opener") then Browser.open() end
        return
    end
    if _consume("close") then Browser.close(); return end
    local career_prev = _consume("career_prev")
    local career_next = _consume("career_next")
    if career_prev or career_next then
        local direction = career_prev and -1 or 1
        Browser.career_id = ((Browser.career_id - 1 + direction) % 20) + 1
        _request()
    end
    if _consume("sort") then
        Browser.sort_mode = Browser.sort_mode == "likes" and "recent" or "likes"
        Browser.page, Browser.selected = 1, nil
    end
    if _consume("page_prev") then Browser.page = math.max(1, Browser.page - 1); Browser.selected = nil end
    if _consume("page_next") then Browser.page = math.min(_max_page(), Browser.page + 1); Browser.selected = nil end
    for row = 1, 5 do
        local name = "row_" .. row
        if _consume(name) then Browser.selected = Browser.widgets[name].content._cim_build end
    end
    if _consume("import") and Browser.selected and not Browser.loading then
        Browser.status = _loc("importing", Browser.selected.name)
        local ok_call, imported, result = pcall(Browser.import_build, Browser.selected)
        if not ok_call then
            Browser.status = _loc("import_failed", tostring(imported))
        elseif not imported then
            Browser.status = _loc("import_rejected", tostring(result))
        else
            Browser.status = _loc("imported", tostring(result.build_name))
        end
    end
end

function Browser.draw(forge_state, overview, renderer, input_service, dt)
    if not _build() or not renderer then return end
    local visible = Browser.open_state or overview ~= nil
    if not visible then return end
    _refresh_content()
    local UISceneGraph, UIRenderer = rawget(_G, "UISceneGraph"), rawget(_G, "UIRenderer")
    pcall(UISceneGraph.update_scenegraph, Browser.scenegraph)
    local ok = pcall(UIRenderer.begin_pass, renderer, Browser.scenegraph,
        input_service, dt, nil, { snap_pixel_positions = true })
    if not ok then return end
    if Browser.open_state then
        for _, name in ipairs({ "scrim", "panel", "title", "close", "career_prev",
                "career_label", "career_next", "sort", "row_1", "row_2", "row_3",
                "row_4", "row_5", "page_prev", "page_label", "page_next", "status", "import" }) do
            local widget = Browser.widgets[name]
            if widget and (widget.content.visible ~= false) then pcall(UIRenderer.draw_widget, renderer, widget) end
        end
    else
        _set_button_color(Browser.widgets.opener, false, false)
        pcall(UIRenderer.draw_widget, renderer, Browser.widgets.opener)
    end
    pcall(UIRenderer.end_pass, renderer)
    _handle_input()
end

return Browser
