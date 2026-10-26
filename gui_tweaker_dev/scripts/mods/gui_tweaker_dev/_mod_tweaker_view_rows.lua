-- _mod_tweaker_view_rows.lua - setting-row and adjacent gear presentation.
--
-- Installs the standalone view's existing row factories and append tail. The
-- caller retains traversal, search, input, staged settings and lifecycle;
-- factories still own offset mutation and retain their original error bounds.
-- Owned by: _mod_tweaker_view.lua. Consumed once via its explicit dofile call.
local M = {}

function M.install(ModTweakerView, deps)
    local mod, defs, math = deps.mod, deps.defs, deps.math
    local _mt, _nf, _owner = deps.mt, deps.nf, deps.owner
    local _vmf_label, _vmf_tooltip = deps.vmf_label, deps.vmf_tooltip
    local _cat_get, _resolve_step = deps.cat_get, deps.resolve_step
    local _format_keybind_value = deps.format_keybind_value

    function ModTweakerView:_build_node_row(w, category, base_offset, depth, display_expanded)
        depth = depth or 0
        local MT = _mt()
        local setting_id = _nf(w, "setting_id")
        local wtype = _nf(w, "type")
        -- (#208) Resolve the node's OWNER mod_obj for label/tooltip localization (the merged
        -- Equipment tab spans four mods); for a normal category _owner returns category.mod_obj.
        local owner_mod_obj, row_owner_mod_id = _owner(category, setting_id)
        local label = category._flat and _vmf_label(w, owner_mod_obj)
                      or tostring(w.label or w.text or w.setting_id or "?")
        -- (#207) The node's localized tooltip DESCRIPTION (mod_obj may be nil for gut's own
        -- nested categories — _vmf_tooltip then just uses the raw string). Stored on the row
        -- below so the draw loop can show a hover popup; nil = no popup for this row.
        -- (#208) Localize against the node's OWNER mod (see owner_mod_obj above).
        local tooltip = _vmf_tooltip(w, owner_mod_obj)
        local row, err

        if wtype == "header" then
            row = nil  -- VMF synthesizes a per-mod header; the tab already names the mod.
        elseif wtype == "group" then
            -- Collapsible group header (default COLLAPSED). The caller handles expand state.
            local gid = self:_group_key(w, category)
            local expanded = display_expanded
            if expanded == nil then expanded = self._expanded[gid] and true or false end
            local ok, r = pcall(defs.create_group_header, label, expanded, base_offset, depth)
            if ok and r then
                row = r; row._is_group = true; row._group_key = gid
                row._display_expanded = display_expanded
            else err = r end
        elseif wtype == "checkbox" or wtype == "boolean" then
            local ok, r = pcall(defs.create_checkbox, label, base_offset, depth)
            if ok and r then
                row = r
                -- (v0.2.70-dev) buffer-first: show the staged value if an edit is pending.
                local live = _cat_get(category, setting_id)
                row.content.flag = self:get_staged(category, setting_id, live) and true or false
                row._last_flag = row.content.flag
            else err = r end
        elseif wtype == "radio" then
            local ok, r = pcall(defs.create_radio, label, base_offset, depth)
            if ok and r then
                row = r
                local group_id = _nf(w, "_mt_exclusive_group")
                local is_none = _nf(w, "_mt_exclusive_none") == true
                local selected = false
                if is_none then
                    selected = true
                    local members = MT and MT:get_exclusive_members(group_id)
                    for i = 1, #(members or {}) do
                        local member = members[i]
                        local live = _cat_get(category, member.setting_id)
                        if self:get_staged(category, member.setting_id, live) then
                            selected = false
                            break
                        end
                    end
                else
                    local live = _cat_get(category, setting_id)
                    selected = self:get_staged(category, setting_id, live) and true or false
                end
                row.content.selected = selected
                row._mt_radio_group = group_id
                row._mt_radio_none = is_none
                row._mt_radio_member_mod = _nf(w, "_mt_exclusive_member_mod")
            else err = r end
        elseif wtype == "slider" or wtype == "numeric" then
            local ok, r = pcall(defs.create_slider, label, "", base_offset, depth)
            if ok and r then
                row = r
                local range = _nf(w, "range")
                local min = (range and range[1]) or _nf(w, "min") or 0
                local max = (range and range[2]) or _nf(w, "max") or 1
                local dec = _nf(w, "decimals_number") or _nf(w, "num_decimals") or _nf(w, "decimals") or 0
                -- (v0.2.70-dev) buffer-first: show the staged value if an edit is pending.
                local val = self:get_staged(category, setting_id, _cat_get(category, setting_id))
                if type(val) ~= "number" then val = min end
                row.content.min, row.content.max, row.content.num_decimals = min, max, dec
                row.content.value = val
                row.content.internal_value = (max > min) and math.clamp((val - min) / (max - min), 0, 1) or 0
                -- (#164) Fixed per-click / snap increment for this slider. Resolved by
                -- _resolve_step: an explicit widget-def `step` field first, else the gut-side
                -- STEP_OVERRIDES registry (the working path for a foreign VMF mod — VMF strips a
                -- custom `step` field off foreign widgets, see STEP_OVERRIDES), else the natural
                -- unit (1 / 10^-decimals). The track/arrows step by this; _snap_and_clamp snaps the
                -- value to the grid (anchored at range min). A pre-existing off-step value (e.g. a
                -- 324-coin value dialed in VMF's own fine-grained menu) is shown as-is here and
                -- only snaps once the user moves it. #152: this replaced the old ~range/40 over-jump.
                -- (#389) The synthesized Equipment category is owned by gut_dev, but each
                -- row retains its real provider in category._owners.  Step policy belongs
                -- to that provider (for example CIM's Base Power Level = 25), so resolving
                -- against category.mod_id silently fell back to 1 for every merged row.
                local _, owner_mod_id = _owner(category, setting_id)
                local step = _resolve_step(w, owner_mod_id, setting_id or _nf(w, "setting_id"), dec)
                row.content.step = step
                mod:debug("[mt:num] '%s' bounds=%s..%s dec=%s step=%s val=%s",
                    tostring(setting_id), tostring(min), tostring(max), tostring(dec), tostring(step), tostring(val))
                row.content.value_text = string.format("%." .. dec .. "f", val)
                row._last_value = val
            else err = r end
        elseif wtype == "dropdown" then
            -- (v0.2.69-dev) REAL dropdown: a collapsed row (label + selected value + single
            -- down arrow) that opens a popup option list on click. Was a slider-arrow carousel.
            local options = _nf(w, "options")
            -- #605: large source-generated catalogues can be supplied lazily. The
            -- provider runs only when its tab is built, avoiding 34k dialogue option
            -- records at launcher/keep boot when the user never opens Dialogue.
            local options_provider = _nf(w, "options_provider")
            if type(options) ~= "table" and type(options_provider) == "function" then
                local ok_options, provided = pcall(options_provider)
                if ok_options and type(provided) == "table" then
                    options = provided
                else
                    mod:warning("[mt] options_provider failed for %s.%s: %s",
                        tostring(category.mod_id), tostring(setting_id), tostring(provided))
                end
            end
            local ok, r = pcall(defs.create_dropdown, label, base_offset, depth)
            if ok and r and type(options) == "table" and #options > 0 then
                row = r
                -- (v0.2.70-dev) buffer-first: show the staged selection if an edit is pending.
                local cur = self:get_staged(category, setting_id, _cat_get(category, setting_id))
                local values, texts, idx = {}, {}, 1
                for k = 1, #options do
                    local o = options[k]
                    values[k] = _nf(o, "value")
                    texts[k] = tostring(_nf(o, "text") or values[k])
                    if values[k] == cur then idx = k end
                end
                row._options_values, row._options_texts, row._option_idx = values, texts, idx
                row.content.value_text = texts[idx]
                row.content.active = false        -- popup closed at build time
            elseif ok and r then
                row = r; row._readonly = true; row.content.value_text = "?"
            else err = r end
        elseif wtype == "action" then
            -- #605: immediate local action row for media controls and other operations
            -- that are not persistent settings. Uses the resident dropdown field-box
            -- chrome, but never opens a popup or enters the Apply transaction.
            local ok, r = pcall(defs.create_dropdown, label, base_offset, depth,
                { no_arrow = true, field_box = true })
            if ok and r then
                row = r
                row._is_action = true
                row._action = _nf(w, "on_activate")
                row.content.value_text = tostring(_nf(w, "button_text") or "RUN")
            else err = r end
        elseif wtype == "keybind" then
            -- (#123) Interactive keybind row (dropdown row shape: label + clickable value).
            -- Click -> capture; on capture/clear we apply IMMEDIATELY like VMF (set value +
            -- add_mod_keybind + generate_keybinds), NOT staged. #95 format via _format_keybind_value.
            -- _keybind_def carries the widget fields VMF's add_mod_keybind needs (see VMF_AND_USER_SETTINGS.md).
            local val = setting_id and self:get_staged(category, setting_id, _cat_get(category, setting_id))
            local ok, r = pcall(defs.create_dropdown, label, base_offset, depth, { no_arrow = true, field_box = true })
            if ok and r then
                row = r
                row._is_keybind = true
                row.content.value_text = _format_keybind_value(val)
                row._keybind_def = {
                    keybind_type    = _nf(w, "keybind_type"),
                    keybind_trigger = _nf(w, "keybind_trigger"),
                    keybind_global  = _nf(w, "keybind_global"),
                    function_name   = _nf(w, "function_name"),
                    view_name       = _nf(w, "view_name"),
                    transition_data = _nf(w, "transition_data"),
                }
            else err = r end
        else
            -- text / unknown: read-only label + current value.
            -- (#95) A keybind's value is a Lua TABLE — the VMF key-combo array (e.g.
            -- {"left alt"} or {}). The old code tostring()'d it, printing the raw table
            -- address ("CYCLE HUD MODE: table: 0x..."). Render the combo instead (joined,
            -- upper-cased) or "unbound" when empty, and NEVER tostring() a raw table for
            -- any other read-only widget either.
            local val = setting_id and _cat_get(category, setting_id)
            local suffix
            if wtype == "keybind" or type(val) == "table" then
                suffix = ": " .. _format_keybind_value(val)
            elseif val ~= nil then
                suffix = ": " .. tostring(val)
            else
                suffix = wtype and ("  [" .. tostring(wtype) .. "]") or ""
            end
            local ok, r = pcall(defs.create_section_title, label .. suffix, base_offset, depth)
            if ok and r then row = r; row._readonly = true else err = r end
        end

        if row then
            if _nf(w, "disabled") == true then
                row._readonly = true
                row._disabled_in_vmf = true
                local color = row.style and row.style.label and row.style.label.text_color
                if color then color[1], color[2], color[3], color[4] = 128, 128, 128, 128 end
            end
            row._mod_id = row_owner_mod_id or category.mod_id
            row._setting_id = setting_id
            row._wtype = wtype
            row._category = category
            row._list_y = base_offset[2]  -- this row's Y (factory just decremented to it)
            -- (#207) Hover-popup text: TITLE = the row label, DESC = the localized tooltip.
            row._tip_title = label
            row._tip_desc = tooltip
            if MT and MT.apply_runtime_gate then MT:apply_runtime_gate(row, row._mod_id, setting_id) end
            -- (v0.2.157-dev diag, temp) Farm any residual "<...>" marker. If the RAW node data or the
            -- RESOLVED label/desc still contains a "<", printf it so the exact culprit + owning mod are
            -- named next time the menu opens. With the _vmf_label/_vmf_tooltip hardening this should
            -- fire ZERO times; if it does not fire yet the user still sees "<>", the marker is coming
            -- from some OTHER element (value/dropdown/etc.), which this rules in or out.
            local _rt = _nf(w, "tooltip")
            local _rtt = _nf(w, "title") or _nf(w, "text")
            local function _hasmark(x) return type(x) == "string" and string.find(x, "<") end
            if _hasmark(_rt) or _hasmark(_rtt) or _hasmark(label) or _hasmark(tooltip) then
                printf("[gut:desc] MARKER mod=%s sid=%s type=%s raw_title=%q raw_tt=%q -> label=%q desc=%q",
                    tostring(category.mod_id), tostring(setting_id), tostring(wtype),
                    tostring(_rtt), tostring(_rt), tostring(label), tostring(tooltip))
            end
        end
        return row, err, wtype, setting_id, label
    end

    -- Append a row (+ optional gear) to self._rows and log build failures. Shared tail
    -- of every row append so the drill view and normal list stay byte-identical.
    function ModTweakerView:_append_row(row, err, wtype, category, setting_id, base_offset, has_gear, parent_label)
        if row then
            self._rows[#self._rows + 1] = row
            if has_gear then
                -- Advanced-option parents are navigation/selection headers as well
                -- as settings: enabled gear parents take the warm-tan chrome accent,
                -- disabled VMF rows keep their grey (#611). The decision lives in the
                -- ONE shared policy site defs.apply_gear_parent_accent so the mission
                -- and keep twins can never drift apart again (#717 twin parity).
                defs.apply_gear_parent_accent(row, has_gear)
                -- Shrink the parent's full-width whole-row hotspot so it stops BEFORE the
                -- gear column — otherwise a click on the gear ALSO lands on the parent row's
                -- hotspot (they overlap) and would e.g. toggle a parent checkbox while
                -- drilling. The arrow/track hotspots sit left of the gear and are untouched.
                if row.style and row.style.hotspot and row.style.hotspot.size then
                    row.style.hotspot.size[1] = math.max(1, (defs.row_w or 800) - (defs.gear_col_w or 50))
                end
                -- 3rd-column gear: a SEPARATE widget at the SAME row Y; clicking it drills in.
                local ok, g = pcall(defs.create_gear_button, base_offset[2])
                if ok and g then
                    g._is_gear = true
                    g._list_y = base_offset[2]
                    g._drill_setting = setting_id
                    g._drill_label = parent_label or tostring(setting_id)
                    g._category = category
                    self._rows[#self._rows + 1] = g
                end
            end
        elseif wtype ~= "header" then
            mod:warning("[mt] row build failed for %s.%s (type=%s): %s",
                tostring(category.mod_id), tostring(setting_id), tostring(wtype), tostring(err))
        end
    end
end

return M
