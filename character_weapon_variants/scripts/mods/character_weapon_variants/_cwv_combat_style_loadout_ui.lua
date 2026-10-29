-- Adds one contextual control to the mouse/keyboard hero loadout bar. The
-- vanilla module captures these definition tables by reference, so mutating
-- the cached tables before a HeroWindowLoadout instance is created is enough;
-- no copied view or custom renderer is introduced.
return function(M, console_row, mod, runtime)
	if M._ui_installed or type(runtime) ~= "table" then return false end
	local emit_mission_ui = M.new_mission_ui_probe_sink(function(probe, count, cap)
		pcall(printf, "[cwv:774] surface=%s stage=%s item=%s raw_id=%s identity=%s family=%s style=%s row=%s detail=%s event=%d/%d",
			probe.surface, probe.stage, probe.item_key, probe.raw_identity, probe.identity,
			probe.family, probe.style, probe.row, probe.detail, count, cap)
	end)
	local function mission_view_active()
		local managers = rawget(_G, "Managers")
		local game_mode = managers and managers.state and managers.state.game_mode
		local in_keep = rawget(_G, "DamageUtils") and DamageUtils.is_in_inn or false
		return game_mode ~= nil and not in_keep
	end
	local function report_mission_ui(surface, stage, item, row, suffix, detail)
		if not mission_view_active() then return false end
		local probe = M.mission_ui_probe(surface, stage, item, row, suffix, detail)
		return emit_mission_ui(probe)
	end
	local desktop_ok, definitions = pcall(local_require,
		"scripts/ui/views/hero_view/windows/definitions/hero_window_loadout_definitions")
	local scenegraph = desktop_ok and definitions and definitions.scenegraph_definition
	local widgets = desktop_ok and definitions and definitions.widgets

	if type(scenegraph) == "table" and type(widgets) == "table" then
		scenegraph.cwv_combat_style_button = scenegraph.cwv_combat_style_button or {
		parent = "loadout_background",
		horizontal_alignment = "center",
		vertical_alignment = "bottom",
		size = { 390, 46 },
		position = { 0, 122, 30 },
	}
		widgets.cwv_combat_style_button = widgets.cwv_combat_style_button or {
		scenegraph_id = "cwv_combat_style_button",
		element = { passes = {
			{ pass_type = "hotspot", content_id = "button_hotspot", content_check_function = function(content) return content.visible end },
			{ pass_type = "rect", style_id = "background", content_check_function = function(content) return content.visible end },
			{ pass_type = "rect", style_id = "border", content_check_function = function(content) return content.visible end },
			{ pass_type = "text", text_id = "button_text", style_id = "button_text", content_check_function = function(content) return content.visible end },
			{ pass_type = "text", text_id = "button_text", style_id = "button_text_shadow", content_check_function = function(content) return content.visible end },
		} },
		content = { visible = false, button_hotspot = {}, button_text = "" },
		style = {
			background = { color = { 220, 32, 38, 40 }, offset = { 2, 2, 2 }, size = { 386, 42 } },
			border = { color = { 255, 160, 146, 101 }, offset = { 0, 0, 1 }, size = { 390, 46 } },
			button_text = { font_type = "hell_shark", font_size = 22,
				horizontal_alignment = "center", vertical_alignment = "center",
				text_color = { 255, 255, 255, 255 }, offset = { 0, 2, 4 }, size = { 390, 46 } },
			button_text_shadow = { font_type = "hell_shark", font_size = 22,
				horizontal_alignment = "center", vertical_alignment = "center",
				text_color = { 255, 0, 0, 0 }, offset = { 2, 0, 3 }, size = { 390, 46 } },
		},
		}
		scenegraph.cwv_combat_style_status = scenegraph.cwv_combat_style_status or {
			parent = "loadout_background",
			horizontal_alignment = "center",
			vertical_alignment = "bottom",
			size = { 390, 24 },
			position = { 0, 172, 31 },
		}
		widgets.cwv_combat_style_status = widgets.cwv_combat_style_status or {
			scenegraph_id = "cwv_combat_style_status",
			element = { passes = {
				{ pass_type = "text", text_id = "status_text", style_id = "status_text",
					content_check_function = function(content) return content.visible end },
				{ pass_type = "text", text_id = "status_text", style_id = "status_text_shadow",
					content_check_function = function(content) return content.visible end },
			} },
			content = { visible = false, status_text = "" },
			style = {
				status_text = { font_type = "hell_shark", font_size = 17,
					horizontal_alignment = "center", vertical_alignment = "center",
					text_color = { 235, 225, 215, 190 }, offset = { 0, 1, 2 }, size = { 390, 24 } },
				status_text_shadow = { font_type = "hell_shark", font_size = 17,
					horizontal_alignment = "center", vertical_alignment = "center",
					text_color = { 190, 0, 0, 0 }, offset = { 1, 0, 1 }, size = { 390, 24 } },
			},
		}
	end

	local function selected(window)
		-- The native loadout window, not this viewer's active unit, owns selection.
		local parent = window and window.parent
		local index = parent and parent.get_selected_loadout_slot_index
			and parent:get_selected_loadout_slot_index()
		local item = index and window._equipment_items and window._equipment_items[index]
		return item, index
	end
	local function selected_actor(window)
		return type(runtime.loadout_actor) == "function" and runtime:loadout_actor(window) or nil
	end

	local function refresh(window)
		local item, index = selected(window)
		local widget = window and window._widgets_by_name
			and window._widgets_by_name.cwv_combat_style_button
		local status_widget = window and window._widgets_by_name
			and window._widgets_by_name.cwv_combat_style_status
		if not widget then
			report_mission_ui("desktop", "widget_missing", item, nil, index)
			return
		end
		local row = item and runtime:describe(item, item.backend_id, selected_actor(window))
		if item then
			report_mission_ui("desktop", row and "selected_supported" or "selected_unresolved",
				item, row, index)
		end
		widget.content.visible = row ~= nil
		if status_widget then status_widget.content.visible = row ~= nil end
		if row == nil and type(runtime.member_key) == "function" and M.is_sword_item(runtime:member_key(item)) then
			widget.content.button_hotspot.on_pressed = false
			widget.content.button_hotspot.on_release = false
		end
		if row then
			local next_id, next_style
			if type(runtime.next_style) == "function" then
				next_id, next_style = runtime:next_style(row.item_key, row.style_id)
			else
				_, next_style = M.next_style(row.item_key, row.style_id)
			end
			if M.is_sword_item(row.item_key) and (next_id == nil or next_id == row.style_id) then
				widget.content.visible = false
				if status_widget then status_widget.content.visible = false end
				widget.content.button_hotspot.on_pressed = false
				widget.content.button_hotspot.on_release = false
				return
			end
			widget.content.button_text = "Switch to: " .. (next_style and next_style.label or row.style.label)
			widget.content.button_hotspot.disable_button = false
			if status_widget then
				status_widget.content.status_text = runtime:moveset_indicator(
					row.item_key, row.style_id) or ""
			end
		end
	end

	local function on_ui_transition_complete(window, changed)
		if not changed then return end
		local parent = window and window.parent
		if parent then parent.loadout_sync_id = (parent.loadout_sync_id or 0) + 1 end
		pcall(function() window:_play_sound("play_gui_equipment_selection_click") end)
	end

	if type(scenegraph) == "table" and type(widgets) == "table" then
		mod:hook("HeroWindowLoadout", "_populate_loadout", function(func, self, ...)
			local result = func(self, ...)
			refresh(self)
			return result
		end)
		mod:hook("HeroWindowLoadout", "_handle_input", function(func, self, ...)
			local r1, r2, r3, r4 = func(self, ...)
			refresh(self)
			local widget = self._widgets_by_name and self._widgets_by_name.cwv_combat_style_button
			local hotspot = widget and widget.content and widget.content.button_hotspot
			local selected_item, selected_index = selected(self)
			local selected_row = selected_item and runtime:describe(selected_item,
				selected_item.backend_id, selected_actor(self))
			if hotspot and hotspot.on_pressed then
				report_mission_ui("desktop", "input_pressed", selected_item, selected_row,
					selected_index)
			end
			if widget and widget.content.visible and hotspot and hotspot.on_release then
				hotspot.on_release = false
				local item = selected(self)
				local row = item and runtime:describe(item, item.backend_id, selected_actor(self))
				report_mission_ui("desktop", "input_release", item, row, selected_index)
				if item then
					local callback_called = false
					local accepted, err = runtime:cycle_item(item, item.backend_id,
						"inventory_button", true, function(changed, complete_err)
						callback_called = true
						on_ui_transition_complete(self, changed)
						report_mission_ui("desktop", changed and "transition_complete"
							or "transition_rejected", item,
							runtime:describe(item, item.backend_id, selected_actor(self)), selected_index,
							complete_err)
					end, selected_actor(self))
					if not accepted and not callback_called then
						report_mission_ui("desktop", err == "transition pending"
							and "transition_deferred" or "transition_rejected", item, row,
							selected_index, err)
					end
				end
				refresh(self)
			end
			return r1, r2, r3, r4
		end)
	end

	local console_ok, console_definitions = pcall(local_require,
		"scripts/ui/views/hero_view/windows/definitions/hero_window_loadout_console_definitions")
	local console_installed = false
	if console_ok and type(console_definitions) == "table"
			and type(console_definitions.create_loadout_grid_func) == "function" then
		local original_create_grid = console_definitions.create_loadout_grid_func
		console_definitions.create_loadout_grid_func = function(...)
			local widget_def = original_create_grid(...)
			M.decorate_console_grid(widget_def, runtime)
			return widget_def
		end

		local actions = console_definitions.generic_input_actions
		for _, pair in ipairs({ { "default", "cwv_style" },
				{ "default_no_customization", "cwv_style_no_customization" } }) do
			local source = actions and actions[pair[1]]
			if type(source) == "table" then
				local list = M.bounded_style_actions(source, M.INPUT_DESCRIPTION_CAPACITY)
				actions[pair[2]] = list
			end
		end

		local function console_widget(window)
			return window and window._widgets_by_name and window._widgets_by_name.loadout_grid
		end

		local function selected_console_candidate(window)
			local widget = console_widget(window)
			local content = widget and widget.content
			if not content then return nil end
			for i = 1, tonumber(content.rows) or 0 do
				for k = 1, tonumber(content.columns) or 0 do
					local suffix = "_" .. tostring(i) .. "_" .. tostring(k)
					local slot = content["hotspot" .. suffix]
					if slot and slot.is_selected then
						local item = content["item" .. suffix]
						return item, suffix, console_row(runtime, content, suffix)
					end
				end
			end
			return nil
		end

		local function selected_console_item(window)
			local item, suffix, row = selected_console_candidate(window)
			if row then return item, suffix, row end
			return nil
		end

		local function refresh_console(window)
			local widget = console_widget(window)
			if widget and widget.content then widget.content.cwv_style_actor = selected_actor(window) end
			local item, suffix, row = selected_console_candidate(window)
			if not widget then
				report_mission_ui("console", "widget_missing", item, row, suffix)
				return 0
			end
			if item then
				report_mission_ui("console", row and "selected_supported"
					or "selected_unresolved", item, row, suffix)
			end
			return M.refresh_console_row_layout(widget, runtime)
		end

		mod:hook("HeroWindowLoadoutConsole", "_populate_loadout", function(func, self, ...)
			local result = func(self, ...)
			refresh_console(self)
			return result
		end)

		mod:hook("HeroWindowLoadoutConsole", "_update_input_description", function(func, self, ...)
			local result = func(self, ...)
			local item = selected_console_item(self)
			if item and self._menu_input_description then
				local customizable = self._is_selected_item_customizable
					and self:_is_selected_item_customizable()
				local wanted = customizable and "cwv_style" or "cwv_style_no_customization"
				local list = actions and actions[wanted]
				if list and self._current_input_desc ~= wanted then
					local widgets = self._menu_input_description.console_input_description_widgets
					local capacity = type(widgets) == "table" and #widgets
						or M.INPUT_DESCRIPTION_CAPACITY
					local safe_list = M.bounded_style_actions(list, capacity)
					self._menu_input_description:change_generic_actions(safe_list)
					self._current_input_desc = wanted
				end
			end
			return result
		end)

		mod:hook("HeroWindowLoadoutConsole", "_handle_input", function(func, self, ...)
			refresh_console(self)
			local widget = console_widget(self)
			local candidate, candidate_suffix, candidate_row = selected_console_candidate(self)
			local candidate_hotspot = widget and candidate_suffix and widget.content
				and widget.content["cwv_style_hotspot" .. candidate_suffix]
			if candidate_hotspot and candidate_hotspot.on_pressed then
				report_mission_ui("console", "input_pressed", candidate, candidate_row,
					candidate_suffix)
			end
			if candidate_hotspot and candidate_hotspot.on_release then
				report_mission_ui("console", "input_release", candidate, candidate_row,
					candidate_suffix)
			end
			local item, suffix, row
			if widget then item, suffix, row = M.consume_console_style_press(widget.content, runtime) end
			if item then
				local callback_called = false
				local accepted, err = runtime:cycle_item(item, item.backend_id,
					"equipment_style_button", true, function(changed, complete_err)
						callback_called = true
						on_ui_transition_complete(self, changed)
						report_mission_ui("console", changed and "transition_complete"
							or "transition_rejected", item,
							runtime:describe(item, item.backend_id, selected_actor(self)), suffix, complete_err)
						if changed then
							pcall(printf, "[cwv:620] equipment style button item=%s family=%s row=%s",
								tostring(row.identity), tostring(row.family_id), tostring(suffix))
						elseif complete_err then
							pcall(printf, "[cwv:620] equipment style button rejected item=%s reason=%s",
								tostring(row.identity), tostring(complete_err))
						end
					end, selected_actor(self))
				if not accepted and not callback_called then
					report_mission_ui("console", err == "transition pending"
						and "transition_deferred" or "transition_rejected", item, row,
						suffix, err)
					pcall(printf, "[cwv:620] equipment style button deferred item=%s reason=%s",
						tostring(row.identity), tostring(err))
				end
				return
			end
			return func(self, ...)
		end)

		mod:hook("HeroWindowLoadoutConsole", "_handle_gamepad_input", function(func, self, ...)
			refresh_console(self)
			local input = self._input_service and self:_input_service()
			local item, _, row = selected_console_item(self)
			if item and input and input:get("special_1", true) then
				report_mission_ui("console", "controller_pressed", item, row)
				local callback_called = false
				local accepted, err = runtime:cycle_item(item, item.backend_id,
					"equipment_style_controller", true, function(changed, complete_err)
						callback_called = true
						on_ui_transition_complete(self, changed)
						report_mission_ui("console", changed and "transition_complete"
							or "transition_rejected", item,
							runtime:describe(item, item.backend_id, selected_actor(self)), nil, complete_err)
						if not changed and complete_err then
							pcall(printf, "[cwv:620] controller style rejected item=%s reason=%s",
								tostring(row.identity), tostring(complete_err))
						end
					end, selected_actor(self))
				if not accepted and not callback_called then
					report_mission_ui("console", err == "transition pending"
						and "transition_deferred" or "transition_rejected", item, row,
						nil, err)
					pcall(printf, "[cwv:620] controller style deferred item=%s reason=%s",
						tostring(row.identity), tostring(err))
				end
				return
			end
			return func(self, ...)
		end)
		console_installed = true
	end

	M._ui_installed = (type(scenegraph) == "table" and type(widgets) == "table") or console_installed
	M._console_ui_installed = console_installed
	return M._ui_installed
end
