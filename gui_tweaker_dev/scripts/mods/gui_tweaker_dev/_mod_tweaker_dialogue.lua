-- #605 Character Dialogue adapter. Character Dialogue owns catalogue/search/
-- playback semantics; this module renders only a bounded virtual window.
local DialogueUI = {}

local function api()
    local cd = get_mod("character_dialogue")
    local value = cd and cd.character_dialogue_api
    return value and value.version >= 2 and value or nil
end

-- #880 transcript popup binder, loaded lazily through gut's own VMF dofile so
-- THIS module keeps loading engine-free (the unit suite dofiles it directly).
-- false caches a failed load so a broken module cannot re-log every rebuild.
local TranscriptBinder
local function transcript_binder()
    if TranscriptBinder == nil then
        local gut = get_mod("gut_dev")
        local ok, module = pcall(function()
            return gut and gut:dofile("scripts/mods/gui_tweaker_dev/_mod_tweaker_dialogue_transcript")
        end)
        if ok and type(module) == "table" then
            TranscriptBinder = module
        else
            TranscriptBinder = false
        end
    end
    if TranscriptBinder == false then return nil end
    return TranscriptBinder
end

function DialogueUI.is_category(category)
    local widget = category and category.widgets and category.widgets[1]
    return category and category.mod_id == "character_dialogue"
        and widget and widget.type == "dialogue_browser"
end

function DialogueUI.stop()
    local value = api()
    if value and value.stop then pcall(value.stop) end
end

local function state_text(value)
    if value == true then return "ENABLED" end
    if value == false then return "DISABLED" end
    return "DEFAULT"
end

local function group_key(id) return "character_dialogue:" .. tostring(id) end

-- #998 One fixed control row above the group list: the automatic-isolation
-- Yes/No toggle. It lives in THIS custom renderer because normal VMF widgets
-- do not render inside the Dialogue tab. Feature-detected so an older
-- Character Dialogue without the v6 staged-owner capability omits this row.
local ISOLATION_ROW_ID = group_key("auto_isolation")

local function isolation_lead(value)
    local setting = value and value.isolation_setting
    return (type(setting) == "table" and setting.version == 1
        and setting.setting_id == "auto_isolation"
        and type(value.get_auto_isolation) == "function") and 1 or 0
end

local function toggle_isolation(view, row, value)
    local current = view:get_staged(row._category, row._setting_id,
        value.get_auto_isolation() == true)
    row.content.flag = not current
    view:stage_set(row._category, row._setting_id, row.content.flag)
    view._dialogue_focus_id = ISOLATION_ROW_ID
    view._dialogue_focus_sequence, view._dialogue_focus_control = row._dialogue_sequence, 1
    printf("[gut:998] auto_isolation_staged value=%s", tostring(row.content.flag))
end
DialogueUI.stage_isolation = toggle_isolation

function DialogueUI.can_apply(category)
    local cd = get_mod("character_dialogue")
    local value = cd and cd.character_dialogue_api
    local owner = category and category._owners and category._owners.auto_isolation
    return isolation_lead(value) == 1 and owner and owner.mod_obj == cd
        and type(cd.set) == "function" and type(cd.on_settings_batch_changed) == "function"
end

-- Lua's `condition and value_if_true or value_if_false` idiom cannot represent
-- false or nil in its true branch.  Keep these tri-state transitions explicit:
-- #605 previously assigned `closing and nil or speaker`, which always resolved
-- back to `speaker` and made an opened character group impossible to close.
function DialogueUI.next_expanded(current, speaker)
    if current == speaker then return nil end
    return speaker
end

function DialogueUI.next_line_state(current)
    if current == nil then return true end
    if current == true then return false end
    return nil
end

function DialogueUI.build(view, category, defs)
    local value = api()
    view._dialogue_virtual_first = nil
    view._dialogue_virtual_last = nil
    view._dialogue_category = true
    view._build_nodes, view._build_depths, view._build_category = {}, {}, category
    if not value then
        local at = { 0, -10, 0 }
        local row = defs.create_section_title("Character Dialogue is unavailable", at, 0)
        row._readonly, row._list_y = true, at[2]
        view._rows[1], view._content_h = row, 80
        view:_recompute_scroll_bounds()
        return true
    end

    local query = view._search_str or ""
    local query_changed = view._dialogue_last_query ~= query
    view._dialogue_last_query = query
    local groups = value.browser_groups(query)
    local expanded = view._dialogue_expanded
    local line_count = 0
    if expanded then
        local _, total = value.browser_page(expanded, query, 0, 1)
        line_count = total or 0
        if line_count == 0 then
            -- Filtering the active character to zero is a real collapse edge.
            -- Stop its owned preview before removing the group from the view.
            value.stop()
            expanded = nil
            view._dialogue_expanded = nil
        end
    end
    -- #998 the isolation toggle occupies logical row 1; groups shift down one.
    local owner = get_mod("character_dialogue")
    local lead = isolation_lead(value)
    if not owner or type(owner.get) ~= "function" or type(owner.set) ~= "function"
        or type(owner.on_settings_batch_changed) ~= "function" then lead = 0 end
    -- The registered browser has no VMF owner by default. Without this exact
    -- route, Apply would write GUT's mt:: shadow namespace instead of CD.
    if lead == 1 then
        category._owners = category._owners or {}
        category._owners[value.isolation_setting.setting_id] = {
            mod_id = "character_dialogue", mod_obj = owner,
        }
    elseif category._owners then
        category._owners.auto_isolation = nil
    end
    local window = value.browser_window(groups, expanded, line_count,
        view._scroll_y or 0, view._visible_h or 680, 2, lead)
    view._dialogue_virtual_first, view._dialogue_virtual_last = window.first, window.last
    view._dialogue_logical_count = window.logical_count

    -- #880 transcript popups: resolve subtitle keys for the BOUNDED window's
    -- line rows only, at rebuild time (never per frame / per hover). Tests
    -- inject view._dialogue_localize; production uses the game's Localize.
    local binder = transcript_binder()
    local localize = view._dialogue_localize
    if localize == nil and binder then localize = binder.default_localizer() end
    local visible_groups, expanded_pos = {}, nil
    for i = 1, #groups do
        if groups[i].count > 0 then
            visible_groups[#visible_groups + 1] = groups[i]
            if groups[i].id == expanded then expanded_pos = #visible_groups end
        end
    end

    local first_line_offset, last_line_offset
    if expanded_pos then
        first_line_offset = math.max(0, window.first - expanded_pos - lead - 1)
        last_line_offset = math.min(line_count - 1, window.last - expanded_pos - lead - 1)
        if last_line_offset < first_line_offset then first_line_offset, last_line_offset = nil, nil end
    end
    local page, by_offset = {}, {}
    if first_line_offset then
        page = value.browser_page(expanded, query, first_line_offset,
            last_line_offset - first_line_offset + 1)
        for i = 1, #page do by_offset[first_line_offset + i - 1] = page[i] end
    end

    local visible_ids, visible_sequences = {}, {}
    for sequence = window.first, window.last do
        local base = { 0, -10 - (sequence - 1) * (value.browser_row_height or 32), 0 }
        local line_offset
        if expanded_pos and sequence > expanded_pos + lead and sequence <= expanded_pos + lead + line_count then
            line_offset = sequence - expanded_pos - lead - 1
        end
        if sequence <= lead then
            -- #998 automatic-isolation Yes/No control. create_checkbox draws a
            -- 32px row top-aligned in the 48px slot; the planner spacing stays
            -- uniform so scroll math is untouched.
            local label = (value.auto_isolation_label and value.auto_isolation_label())
                or "Isolate Audio During Playback"
            local row = defs.create_checkbox(label, base, 0)
            row._setting_id = value.isolation_setting.setting_id
            row.content.flag = view:get_staged(category, row._setting_id,
                value.get_auto_isolation() == true)
            row._is_dialogue_line = true -- routes clicks through DialogueUI.handle_row
            row._dialogue_isolation = true
            row._dialogue_row_id = ISOLATION_ROW_ID
            row._dialogue_sequence = sequence
            row._list_y = base[2]
            row._category = category
            local label_color = row.style and row.style.label and row.style.label.text_color
            if label_color then
                row._dialogue_base_label_color = { label_color[1], label_color[2], label_color[3], label_color[4] }
            end
            view._rows[#view._rows + 1] = row
            visible_ids[#visible_ids + 1] = ISOLATION_ROW_ID
            visible_sequences[#visible_sequences + 1] = sequence
        elseif line_offset ~= nil then
            local item = by_offset[line_offset]
            if item then
                -- #605 transcript rides INTO the row (inline preview) instead of
                -- existing only as a hover popup. The popup is kept for the full
                -- prose, because the inline line is truncated to keep rows compact.
                local row = defs.create_dialogue_row(item.event,
                    state_text(value.get_line_state(item.event)), base, 1, item.transcript,
                    value.browser_row_height)
                row._is_dialogue_line = true
                row._dialogue_event = item.event
                row._dialogue_speaker = item.speaker
                row._dialogue_row_id = item.id
                row._dialogue_sequence = sequence
                row._list_y = base[2]
                row._category = category
                -- #880: bind (or suppress) the hover transcript popup fields.
                if binder then
                    -- Group labels are conversation stems now, so the character
                    -- name comes from the line itself, not from its header.
                    binder.bind_row(row, item, item.speaker_label, localize)
                end
                view._rows[#view._rows + 1] = row
                visible_ids[#visible_ids + 1] = item.id
                visible_sequences[#visible_sequences + 1] = sequence
            end
        else
            local group_index = sequence - lead
            if expanded_pos and sequence > expanded_pos + lead + line_count then
                group_index = sequence - lead - line_count
            end
            local group = visible_groups[group_index]
            if group then
                local row = defs.create_group_header(
                    string.format("%s  (%d)", group.label, group.count),
                    group.id == expanded, base, 0)
                row._is_group = true
                row._is_dialogue_group = true
                row._dialogue_speaker = group.id
                row._dialogue_sequence = sequence
                row._dialogue_group_index = group_index
                row._dialogue_row_id = group_key(group.id)
                local label_color = row.style and row.style.label and row.style.label.text_color
                if label_color then
                    row._dialogue_base_label_color = { label_color[1], label_color[2], label_color[3], label_color[4] }
                end
                row._group_key = group_key(group.id)
                row._list_y = base[2]
                row._category = category
                view._rows[#view._rows + 1] = row
                visible_ids[#visible_ids + 1] = row._dialogue_row_id
                visible_sequences[#visible_sequences + 1] = sequence
            end
        end
    end

    if window.logical_count == lead then
        -- Empty result set: the lead control row (when present) stays; the
        -- notice appends beneath it instead of overwriting rows[1].
        local base = { 0, -10 - lead * (value.browser_row_height or 32), 0 }
        local row = defs.create_section_title("No dialogue lines match this search", base, 0)
        row._readonly, row._list_y = true, base[2]
        view._rows[#view._rows + 1] = row
    end
    view._content_h = window.content_height
    local target_sequence = view._dialogue_focus_target_sequence
    view._dialogue_focus_target_sequence = nil
    if target_sequence then
        for i = 1, #visible_sequences do
            if visible_sequences[i] == target_sequence then
                view._dialogue_focus_id = visible_ids[i]
                view._dialogue_focus_sequence = target_sequence
                break
            end
        end
    elseif query_changed then
        -- Filtering may move a sequence onto a different event. Reconcile by
        -- stable Wwise/group identity, falling back to the first visible row.
        local index, id = value.browser_reconcile_focus(visible_ids, view._dialogue_focus_id)
        view._dialogue_focus_id = id
        view._dialogue_focus_sequence = index and visible_sequences[index] or nil
    elseif not view._dialogue_focus_id and visible_ids[1] then
        view._dialogue_focus_id = visible_ids[1]
        view._dialogue_focus_sequence = visible_sequences[1]
    end
    view._dialogue_focus_sequence = math.clamp(
        view._dialogue_focus_sequence or window.first, 1, math.max(1, window.logical_count))
    view._dialogue_focus_control = math.clamp(view._dialogue_focus_control or 1, 1, 2)
    view:_recompute_scroll_bounds()
    view._scroll_y = math.clamp(view._scroll_y or 0, 0, view._max_scroll)
    return true
end

local function released(hotspot)
    return hotspot and (hotspot.on_release or hotspot.on_left_release)
end

local function once(row, key, down)
    row._dialogue_latches = row._dialogue_latches or {}
    local fire = down and not row._dialogue_latches[key]
    row._dialogue_latches[key] = down and true or false
    return fire
end

local function toggle_group(view, row, value, block_stale_mouse_release)
    local speaker = row._dialogue_speaker
    local closing = view._dialogue_expanded == speaker
    value.stop()
    view._dialogue_expanded = DialogueUI.next_expanded(view._dialogue_expanded, speaker)
    printf("[gut:605] dialogue_group action=%s speaker=%s",
        closing and "collapse" or "expand", tostring(speaker))
    view._dialogue_focus_id = group_key(speaker)
    view._dialogue_focus_sequence = row._dialogue_group_index or 1
    view._dialogue_focus_target_sequence = view._dialogue_focus_sequence
    view._dialogue_focus_control = 1
    view._scroll_y = 0
    -- Rebuilt shared-node rows must not consume the stale mouse release. Do not
    -- set this for controller confirm: it has no future Mouse.pressed edge.
    if block_stale_mouse_release then view._dd_block_until_press = true end
    view:_build_rows(view._categories[view._selected])
end

local function activate_line(view, row, value, control)
    local event = row._dialogue_event
    if control == 1 then
        local current = value.get_line_state(event)
        local next_value = DialogueUI.next_line_state(current)
        value.set_line_state(event, next_value)
        row.content.state_text = state_text(next_value)
    else
        local ok, err = value.toggle_pause(event)
        printf("[gut:605] media_click event=%s ok=%s err=%s", tostring(event), tostring(ok), tostring(err))
    end
end

function DialogueUI.handle_row(view, row)
    local value = api()
    if not value then return false end
    local content = row.content or {}
    if row._is_dialogue_group then
        local down = released(content.hotspot)
        if once(row, "group", down) then
            toggle_group(view, row, value, true)
            return true
        end
        return false
    end
    if row._dialogue_isolation then
        -- Whole row, left arrow, or right arrow: all one toggle, matching the
        -- native ON/OFF stepper feel.
        local down = released(content.hotspot) or released(content.dec) or released(content.inc)
        if once(row, "isolation", down) then
            toggle_isolation(view, row, value)
            return true
        end
        return false
    end
    if not row._is_dialogue_line then return false end
    if once(row, "state", released(content.state_hotspot)) then
        view._dialogue_focus_id = row._dialogue_row_id
        view._dialogue_focus_sequence, view._dialogue_focus_control = row._dialogue_sequence, 1
        activate_line(view, row, value, 1)
        return true
    end
    if once(row, "media", released(content.media_hotspot)) then
        view._dialogue_focus_id = row._dialogue_row_id
        view._dialogue_focus_sequence, view._dialogue_focus_control = row._dialogue_sequence, 2
        activate_line(view, row, value, 2)
        return true
    end
    return false
end

function DialogueUI.handle_controller(view, input_service)
    if not view._dialogue_category or not input_service or view._search_focused then return false end
    local count = view._dialogue_logical_count or 0
    if count == 0 then return false end
    local focus = math.clamp(view._dialogue_focus_sequence or 1, 1, count)
    local moved
    if input_service:get("move_up", true) then focus = math.max(1, focus - 1); moved = true
    elseif input_service:get("move_down", true) then focus = math.min(count, focus + 1); moved = true end
    if moved then
        view._dialogue_focus_sequence = focus
        view._dialogue_focus_control = 1
        view._dialogue_focus_target_sequence = focus
        local first, last = view._dialogue_virtual_first or 1, view._dialogue_virtual_last or count
        if focus < first + 1 or focus > last - 1 then
            local row_h = (api() and api().browser_row_height) or 32
            view._scroll_y = math.clamp((focus - 3) * row_h, 0, view._max_scroll or 0)
            view:_build_rows(view._categories[view._selected])
        else
            for i = 1, #(view._rows or {}) do
                local row = view._rows[i]
                if row._dialogue_sequence == focus then view._dialogue_focus_id = row._dialogue_row_id; break end
            end
            view._dialogue_focus_target_sequence = nil
        end
        return true
    end
    local focused_row
    for i = 1, #(view._rows or {}) do
        if view._rows[i]._dialogue_sequence == focus
           and view._rows[i]._dialogue_row_id == view._dialogue_focus_id then
            focused_row = view._rows[i]
            break
        end
    end
    if not focused_row then return false end
    if focused_row._is_dialogue_line and not focused_row._dialogue_isolation then
        local control = view._dialogue_focus_control or 1
        if input_service:get("move_left", true) then
            view._dialogue_focus_control = math.max(1, control - 1); return true
        elseif input_service:get("move_right", true) then
            view._dialogue_focus_control = math.min(2, control + 1); return true
        end
    end
    if input_service:get("confirm", true) then
        local value = api()
        if focused_row._dialogue_isolation then toggle_isolation(view, focused_row, value)
        elseif focused_row._is_dialogue_group then toggle_group(view, focused_row, value, false)
        else activate_line(view, focused_row, value, view._dialogue_focus_control or 1) end
        return true
    end
    return false
end

function DialogueUI.refresh_row(row, view)
    if not row then return end
    local selected = view and row._dialogue_sequence == view._dialogue_focus_sequence
        and row._dialogue_row_id == view._dialogue_focus_id
    if row._is_dialogue_group then
        local color = row.style and row.style.label and row.style.label.text_color
        if color then
            local base = row._dialogue_base_label_color or { 255, 255, 168, 0 }
            if selected then color[1], color[2], color[3], color[4] = 255, 255, 255, 255
            else color[1], color[2], color[3], color[4] = base[1], base[2], base[3], base[4] end
        end
        return
    end
    if row._dialogue_isolation then
        local value = api()
        if value and value.get_auto_isolation then
            -- Live changes are visible only when this view has no draft.
            row.content.flag = view:get_staged(row._category, row._setting_id,
                value.get_auto_isolation() == true)
        end
        local color = row.style and row.style.label and row.style.label.text_color
        if color then
            local base = row._dialogue_base_label_color or { 255, 255, 255, 255 }
            -- Focused control renders gold, matching the line rows' focused
            -- state/media treatment (they use 255,255,168,0 when selected).
            if selected then color[1], color[2], color[3], color[4] = 255, 255, 168, 0
            else color[1], color[2], color[3], color[4] = base[1], base[2], base[3], base[4] end
        end
        return
    end
    if not row._is_dialogue_line then return end
    local value = api()
    if not value then return end
    local event, paused = view._dialogue_preview_event, view._dialogue_preview_paused
    local active = event == row._dialogue_event
    row.content.state_text = state_text(value.get_line_state(row._dialogue_event))
    row.content.media_is_playing = active and not paused
    row.content.progress_visible = active
    local progress = active and (view._dialogue_preview_progress or 0) or 0
    local progress_style = row.style and row.style.progress_fill
    if progress_style then
        progress_style.size[1] = (row.style._dialogue_progress_width or 0) * math.clamp(progress, 0, 1)
    end
    local state_color = row.style and row.style.state_text and row.style.state_text.text_color
    if state_color then
        if selected and (view._dialogue_focus_control or 1) == 1 then
            state_color[1], state_color[2], state_color[3], state_color[4] = 255, 255, 168, 0
        else
            state_color[1], state_color[2], state_color[3], state_color[4] = 255, 160, 146, 101
        end
    end
    local focused_media = selected and (view._dialogue_focus_control or 1) == 2
    for _, style_id in ipairs({ "play_glyph", "pause_bar_left", "pause_bar_right" }) do
        local color = row.style and row.style[style_id] and row.style[style_id].color
        if color then
            if focused_media then color[1], color[2], color[3], color[4] = 255, 255, 168, 0
            else color[1], color[2], color[3], color[4] = 255, 160, 146, 101 end
        end
    end
end

function DialogueUI.refresh_window(view)
    if not view._dialogue_category then return false end
    local value = api()
    if not value then return false end
    view._dialogue_preview_event, view._dialogue_preview_paused,
        view._dialogue_preview_playing_id, view._dialogue_preview_progress,
        view._dialogue_preview_duration, view._dialogue_preview_elapsed = value.preview_state()
    local first = math.max(1, math.floor((view._scroll_y or 0) / (value.browser_row_height or 32)) + 1 - 2)
    if first ~= view._dialogue_virtual_first then
        view:_build_rows(view._categories[view._selected])
        return true
    end
    return false
end

return DialogueUI
