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

local EQUIPMENT_GROUP_NAMES = {
    __equip_cosmetics = "cosmetics",
    __equip_crafting = "crafting",
    __equip_weapons = "weapons",
    __equip_cwv = "cwv",
}

local TEXTURE_PASS_TYPES = {
    texture = true,
    texture_uv = true,
    texture_frame = true,
    tiled_texture = true,
    shader_tiled_texture = true,
    gradient_mask_texture = true,
    multi_texture = true,
}

local function _bounded_token(value)
    local token = tostring(value or "?"):gsub("[%c%s]+", "_")
    return #token > 72 and token:sub(1, 72) or token
end

local function _append_value(out, seen, prefix, value)
    local function append(one)
        if type(one) ~= "string" or one == "" then return end
        local token = prefix .. _bounded_token(one)
        if not seen[token] then
            seen[token] = true
            out[#out + 1] = token
        end
    end
    if type(value) == "table" then
        for i = 1, #value do append(value[i]) end
    else
        append(value)
    end
end

local function _capped_join(values, cap)
    if #values == 0 then return "none" end
    local shown = {}
    for i = 1, math.min(#values, cap) do shown[#shown + 1] = values[i] end
    if #values > cap then shown[#shown + 1] = "+" .. tostring(#values - cap) end
    return table.concat(shown, ",")
end

-- Runs only after a focus/tab/Weapons-expansion edge, never every frame. The
-- returned set is the exact visible row identity plus the texture/font
-- candidates those widgets handed to UIRenderer in the completed Lua pass.
-- The native fence wait happens later in D3D12RenderDevice::end_frame, so this
-- is the deepest source-observable breadcrumb available before that wait.
local function _visible_draw_signature(owner)
    local rows, resources, seen = {}, {}, {}
    for index, row in ipairs(owner and owner._rows or {}) do
        if row and row._middle_visible == true then
            local row_id = row._setting_id or row._group_key or row._wtype or index
            rows[#rows + 1] = _bounded_token(row_id) .. ":" .. _bounded_token(row._wtype)
            local content = type(row.content) == "table" and row.content or {}
            local style = type(row.style) == "table" and row.style or {}
            local passes = row.element and row.element.passes or {}
            for pass_index = 1, #passes do
                local pass = passes[pass_index]
                if type(pass) == "table" then
                    local pass_content = content
                    if pass.content_id and type(content[pass.content_id]) == "table" then
                        pass_content = content[pass.content_id]
                    end
                    if TEXTURE_PASS_TYPES[pass.pass_type] then
                        _append_value(resources, seen, "texture:",
                            pass_content[pass.texture_id or "texture_id"])
                    elseif pass.pass_type == "text" then
                        local pass_style = pass.style_id and style[pass.style_id] or style
                        if type(pass_style) == "table" then
                            _append_value(resources, seen, "font:", pass_style.font_type)
                        end
                    end
                end
            end
        end
    end
    table.sort(resources)
    return _capped_join(rows, 12), _capped_join(resources, 16)
end

local function _equipment_state(owner)
    local rows = owner and owner._rows or {}
    local expanded = owner and owner._expanded or {}
    local exact, expansion = {}, {}
    for i = 1, #rows do
        local row = rows[i]
        local name = row and EQUIPMENT_GROUP_NAMES[row._setting_id]
        if name and row._wtype == "group" then
            local display = row._display_expanded
            local is_expanded = display
            local source = "forced"
            if display == nil then
                is_expanded = row._group_key and expanded[row._group_key] == true
                source = "stored"
            end
            local status = (is_expanded and "expanded-" or "collapsed-") .. source
            expansion[#expansion + 1] = name .. ":" .. status
            exact[#exact + 1] = name .. ":" .. status .. ":visible=" .. _bool(row._middle_visible)
        end
    end
    if #exact == 0 then return "none", "none" end
    return table.concat(exact, ";"), table.concat(expansion, ";")
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
        last_equipment_expanded = nil,
        pending_frame_evidence = false,
        evidence_owner = nil,
        last_visible_rows = nil,
        last_resource_candidates = nil,
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
        state.last_equipment_expanded = nil
        state.pending_frame_evidence = false
        state.evidence_owner = nil
        state.last_visible_rows = nil
        state.last_resource_candidates = nil
        log(string.format(
            "enter session=%d presentation=%s view=%s renderer=%s top_renderer=%s scenegraph=%s wt_enabled=%s wt_1p=%s wt_3p=%s wt_live=%s",
            state.session, _value(state.presentation), _value(info.view),
            _value(info.renderer), _value(info.top_renderer), _value(info.scenegraph),
            _value(info.wt_enabled), _value(info.wt_1p), _value(info.wt_3p),
            _value(info.wt_live)))
    end

    function probe:before_draw(info)
        info = info or {}
        local capture_frame_evidence = state.draw_begins == 0
        if state.in_draw then
            state.imbalance_count = state.imbalance_count + 1
            log(string.format("anomaly=draw_reentry begins=%d ends=%d", state.draw_begins, state.draw_ends))
        end
        state.draw_begins = state.draw_begins + 1
        state.in_draw = true

        if state.draw_begins == 1 then
            log(string.format("first_draw rows=%s visible_previous=%s",
                _value(info.rows), _value(info.visible)))
        end
        if info.focus ~= state.last_focus then
            state.last_focus = info.focus
            capture_frame_evidence = true
            log(string.format("focus=%s draw=%d tab=%s", _bool(info.focus), state.draw_begins, _value(info.tab)))
        end
        if info.tab ~= state.last_tab then
            state.last_tab = info.tab
            capture_frame_evidence = true
            if info.tab == "gut_equipment" then
                state.last_equipment_expanded = info.equipment_expanded
                log(string.format("tab=%s draw=%d rows=%s visible_previous=%s equipment_state=%s",
                    _value(info.tab), state.draw_begins, _value(info.rows), _value(info.visible),
                    _value(info.equipment_state)))
            else
                log(string.format("tab=%s draw=%d rows=%s visible_previous=%s", _value(info.tab),
                    state.draw_begins, _value(info.rows), _value(info.visible)))
            end
        elseif info.tab == "gut_equipment"
            and info.equipment_expanded ~= state.last_equipment_expanded then
            state.last_equipment_expanded = info.equipment_expanded
            capture_frame_evidence = true
            log(string.format("equipment_state=%s draw=%d", _value(info.equipment_state), state.draw_begins))
        end
        if capture_frame_evidence then
            state.pending_frame_evidence = true
            state.evidence_owner = info.owner
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
        if state.pending_frame_evidence then
            local rows, resources = _visible_draw_signature(state.evidence_owner)
            state.last_visible_rows = rows
            state.last_resource_candidates = resources
            log(string.format("frame_evidence draw=%d visible_rows=%s resource_candidates=%s",
                state.draw_ends, rows, resources))
            state.pending_frame_evidence = false
            state.evidence_owner = nil
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
            last_equipment_expanded = state.last_equipment_expanded,
            last_visible_rows = state.last_visible_rows,
            last_resource_candidates = state.last_resource_candidates,
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

    local equipment_state, equipment_expanded
    if category and category.mod_id == "gut_equipment" then
        equipment_state, equipment_expanded = _equipment_state(owner)
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
        equipment_state = equipment_state,
        equipment_expanded = equipment_expanded,
        wt_enabled = _safe_setting(wt, "wt_dev_hp_enabled"),
        wt_1p = _safe_setting(wt, "wt_dev_hp_enable_1p"),
        wt_3p = _safe_setting(wt, "wt_dev_hp_enable_3p"),
        wt_live = _safe_setting(wt, "wt_dev_hp_live_apply"),
    }
end

M.DEFAULT_LINE_CAP = DEFAULT_LINE_CAP
M.count_visible = _count_visible
M.equipment_state = _equipment_state
M.visible_draw_signature = _visible_draw_signature

return M
