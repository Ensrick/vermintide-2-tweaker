-- _gut_dx12_fence630.lua -- bounded diagnostics for issue #630.
--
-- The captured crash is a native D3D12 fence wait in end_frame, not a Lua
-- exception or Lua-heap exhaustion. This probe therefore changes no renderer,
-- focus, or tab behavior. It records only lifecycle edges around Mod Tweaker's
-- borrowed-renderer pass so the next reproduction can distinguish:
--   * an unmatched Mod Tweaker begin/end call,
--   * a focus transition while the pass remains balanced, or
--   * a stall after Lua returned a balanced pass to the engine.
--
-- Diagnostics are automatic in the dev stream, issue-prefixed, edge-triggered,
-- and hard-capped. Remove this module and its two presentation call sites when
-- issue #630 is closed.

local M = {}

local DEFAULT_LINE_CAP = 48

local function _bool(value)
    if value == nil then return "?" end
    return value and "true" or "false"
end

local function _value(value)
    if value == nil then return "?" end
    return tostring(value)
end

local function _count_visible(rows)
    local visible = 0
    for i = 1, #(rows or {}) do
        if rows[i]._middle_visible == true then visible = visible + 1 end
    end
    return visible
end

function M.new(options)
    options = options or {}
    local emit = options.emit or function() end
    local state = {
        line_cap = options.line_cap or DEFAULT_LINE_CAP,
        lines = 0,
        capped = false,
        session = 0,
        active = false,
        owner = nil,
        presentation = nil,
        draw_begins = 0,
        draw_ends = 0,
        in_draw = false,
        imbalance_count = 0,
        last_focus = nil,
        last_tab = nil,
    }

    local function log(message)
        if state.lines >= state.line_cap then
            state.capped = true
            return false
        end
        state.lines = state.lines + 1
        emit("[gut:630] " .. message)
        return true
    end

    local probe = {}

    function probe:enter(info)
        info = info or {}
        if state.active then
            state.imbalance_count = state.imbalance_count + 1
            log(string.format("anomaly=reenter previous=%s in_draw=%s", _value(state.presentation), _bool(state.in_draw)))
        end
        state.session = state.session + 1
        state.active = true
        state.owner = info.owner or info.view
        state.presentation = info.presentation or "?"
        state.draw_begins = 0
        state.draw_ends = 0
        state.in_draw = false
        state.last_focus = nil
        state.last_tab = nil
        log(string.format(
            "enter session=%d presentation=%s view=%s renderer=%s top_renderer=%s scenegraph=%s wt_enabled=%s wt_1p=%s wt_3p=%s wt_live=%s",
            state.session, _value(state.presentation), _value(info.view),
            _value(info.renderer), _value(info.top_renderer), _value(info.scenegraph),
            _value(info.wt_enabled), _value(info.wt_1p), _value(info.wt_3p),
            _value(info.wt_live)))
    end

    function probe:before_draw(info)
        info = info or {}
        if state.in_draw then
            state.imbalance_count = state.imbalance_count + 1
            log(string.format("anomaly=draw_reentry begins=%d ends=%d", state.draw_begins, state.draw_ends))
        end
        state.draw_begins = state.draw_begins + 1
        state.in_draw = true

        if state.draw_begins == 1 then
            log(string.format("first_draw rows=%s visible_previous=%s", _value(info.rows), _value(info.visible)))
        end
        if info.focus ~= state.last_focus then
            state.last_focus = info.focus
            log(string.format("focus=%s draw=%d tab=%s", _bool(info.focus), state.draw_begins, _value(info.tab)))
        end
        if info.tab ~= state.last_tab then
            state.last_tab = info.tab
            log(string.format("tab=%s draw=%d rows=%s visible_previous=%s", _value(info.tab),
                state.draw_begins, _value(info.rows), _value(info.visible)))
        end
    end

    function probe:after_draw()
        state.draw_ends = state.draw_ends + 1
        state.in_draw = false
        if state.draw_ends > state.draw_begins then
            state.imbalance_count = state.imbalance_count + 1
            log(string.format("anomaly=extra_draw_end begins=%d ends=%d", state.draw_begins, state.draw_ends))
        elseif state.draw_ends == 1 then
            log("first_draw_end balance=0")
        end
    end

    function probe:leave(reason, owner)
        if owner and state.owner and owner ~= state.owner then
            log(string.format("ignore_stale_exit reason=%s active_presentation=%s", _value(reason), _value(state.presentation)))
            return
        end
        local balance = state.draw_begins - state.draw_ends
        if balance ~= 0 or state.in_draw then state.imbalance_count = state.imbalance_count + 1 end
        log(string.format(
            "exit session=%d presentation=%s reason=%s begins=%d ends=%d balance=%d in_draw=%s anomalies=%d",
            state.session, _value(state.presentation), _value(reason), state.draw_begins,
            state.draw_ends, balance, _bool(state.in_draw), state.imbalance_count))
        state.active = false
        state.owner = nil
        state.presentation = nil
        state.in_draw = false
    end

    function probe:snapshot()
        return {
            line_cap = state.line_cap,
            lines = state.lines,
            capped = state.capped,
            session = state.session,
            active = state.active,
            presentation = state.presentation,
            draw_begins = state.draw_begins,
            draw_ends = state.draw_ends,
            in_draw = state.in_draw,
            imbalance_count = state.imbalance_count,
            last_focus = state.last_focus,
            last_tab = state.last_tab,
        }
    end

    return probe
end


local function _safe_setting(mod_obj, setting_id)
    if not (mod_obj and type(mod_obj.get) == "function") then return nil end
    local ok, value = pcall(mod_obj.get, mod_obj, setting_id)
    return ok and value or nil
end

function M.runtime_info(owner, presentation)
    local focus
    local window = rawget(_G, "Window")
    if window and type(window.has_focus) == "function" then
        local ok, value = pcall(window.has_focus)
        if ok then focus = value == true end
    end

    local category = owner and owner._categories and owner._categories[owner._selected or 1]
    local wt
    local get_mod_fn = rawget(_G, "get_mod")
    if type(get_mod_fn) == "function" then
        local ok_dev, dev = pcall(get_mod_fn, "wt_dev")
        if ok_dev then wt = dev end
        if not wt then
            local ok_stable, stable = pcall(get_mod_fn, "wt")
            if ok_stable then wt = stable end
        end
    end

    return {
        presentation = presentation,
        view = owner,
        owner = owner,
        renderer = owner and owner.ui_renderer,
        top_renderer = owner and owner.ui_top_renderer,
        scenegraph = owner and owner.ui_scenegraph,
        focus = focus,
        tab = category and (category.mod_id or category.label),
        rows = owner and #(owner._rows or {}) or 0,
        visible = owner and _count_visible(owner._rows) or 0,
        wt_enabled = _safe_setting(wt, "wt_dev_hp_enabled"),
        wt_1p = _safe_setting(wt, "wt_dev_hp_enable_1p"),
        wt_3p = _safe_setting(wt, "wt_dev_hp_enable_3p"),
        wt_live = _safe_setting(wt, "wt_dev_hp_live_apply"),
    }
end

M.DEFAULT_LINE_CAP = DEFAULT_LINE_CAP
M.count_visible = _count_visible

return M
