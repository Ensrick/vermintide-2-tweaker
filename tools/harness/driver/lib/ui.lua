-- tools/harness/driver/lib/ui.lua: UI helpers (WP-H-06 group "UI"): T.open_view, T.close_view, T.widget, T.press.
--
-- A helper group (tools/harness/API.md). No OS input: views open and close through IngameUI transitions and a press
-- sets a hotspot field, the way the game's own test hooks do. A view this case opened and left open is closed at
-- cleanup. Closing the hero view makes the game commit (HeroView.post_update_on_exit,
-- Vermintide-2-Source-Code/scripts/ui/views/hero_view/hero_view.lua:516-528); the write shield holds the official rows.

return function (T, ctx)
	local case = ctx.case

	-- UIManager.ingame_ui (scripts/managers/ui/ui_manager.lua:240), set by create_ingame_ui (:17-26) in StateIngame
	local function ingame_ui()
		local ui = Managers.ui

		return ui and ui.ingame_ui and ui:ingame_ui()
	end

	-- Waits up to `seconds` for fn() to be truthy without counting a FAIL (the caller decides with T.require).
	local function poll(fn, seconds)
		local deadline = ctx.now() + seconds

		while true do
			local ok, value = pcall(fn)

			if ok and value then
				return value
			end

			if ctx.now() >= deadline then
				return nil
			end

			T.frames(1)
		end
	end

	local function close_open_view(ui, reason)
		local open = ui.current_view

		ui:handle_transition("exit_menu")
		ctx.out("VIEW CLOSE id=%s view=%s by=%s", case.id, tostring(open), reason)
	end

	-- Opens the IngameUI view `view_name` (a key of ingame_ui.views, e.g. "hero_view") with
	-- IngameUI.handle_transition (scripts/ui/views/ingame_ui.lua:919-974), by default through the "<view>_force"
	-- transition, which marks the view to return to the game when it closes (ingame_ui_settings.lua:441-443); the
	-- game's own test snippet opens the hero view the same way (scripts/tests/testify_snippets.lua:76-86). params go to
	-- the view's on_enter (hero_view: menu_state_name, menu_sub_state_name). Waits until it is the current view
	-- (ingame_ui_testify.lua:7-10) and returns the view. A missing UI, view or transition, or a transition the UI
	-- refuses, makes the case INCONCLUSIVE.
	function T.open_view(view_name, params, transition, timeout)
		local ui = ingame_ui()

		T.require(ui ~= nil, "ingame UI exists")
		T.require(type(ui.views) == "table" and ui.views[view_name] ~= nil, "view " .. tostring(view_name) .. " exists")

		transition = transition or (tostring(view_name) .. "_force")

		local ran, err = T.main(function ()
			return pcall(ui.handle_transition, ui, transition, params or {})
		end)

		T.require(ran, "transition " .. transition .. " accepted (" .. tostring(err) .. ")")

		if not case.view_cleanup then
			case.view_cleanup = true
			case.cleanups[#case.cleanups + 1] = function ()
				local now = ingame_ui()

				if now and now.current_view ~= nil and case.views_opened[now.current_view] then
					close_open_view(now, "cleanup")
				end
			end
		end

		case.views_opened = case.views_opened or {}
		case.views_opened[view_name] = true

		local view = poll(function ()
			local now = ingame_ui()

			return now and now.current_view == view_name and now.views[view_name]
		end, timeout or 10)

		T.require(view ~= nil, "view " .. tostring(view_name) .. " opened through " .. transition)
		ctx.out("VIEW OPEN id=%s view=%s transition=%s", case.id, tostring(view_name), transition)

		return view
	end

	-- Closes the current view with the "exit_menu" transition (ingame_ui_settings.lua:506-518; HeroView.exit uses the
	-- same one, hero_view.lua:576-589) and waits until no view is current. True at once when none is open.
	function T.close_view(timeout)
		local ui = ingame_ui()

		T.require(ui ~= nil, "ingame UI exists")

		if ui.current_view == nil then
			return true
		end

		T.main(close_open_view, ui, "T.close_view")

		local closed = poll(function ()
			return ingame_ui().current_view == nil
		end, timeout or 10)

		T.require(closed, "the view closed")

		return true
	end

	-- A widget of an open view, one of its states or one of its windows: owner is the view's name (a key of
	-- ingame_ui.views), or any of those tables; views keep widgets in _widgets_by_name (e.g.
	-- hero_view_state_overview.lua:177-190) or widgets_by_name. INCONCLUSIVE when there is no such widget.
	function T.widget(owner, name)
		if type(owner) == "string" then
			local ui = ingame_ui()

			owner = ui and type(ui.views) == "table" and ui.views[owner]
		end

		T.require(type(owner) == "table", "widget owner exists")

		local by_name = owner._widgets_by_name or owner.widgets_by_name
		local widget = type(by_name) == "table" and by_name[name]

		T.require(type(widget) == "table" and type(widget.content) == "table", "widget " .. tostring(name) .. " exists")

		return widget
	end

	-- Presses a widget's hotspot with no OS input: sets one field of content[hotspot] to true in the main update, the
	-- way the game's own test hook sets on_right_click (hero_window_cosmetics_inventory_testify.lua:7-9). field
	-- defaults to "on_release", the one UIUtils.is_button_pressed reads and clears (scripts/helpers/ui_utils.lua:381-389);
	-- hotspot defaults to the widget's button_hotspot, else hotspot (as ui_utils.lua:384 picks).
	-- Call as T.press(owner, widget_name[, hotspot[, field]]) or T.press(widget[, hotspot[, field]]).
	-- Waits up to `frames` updates (default 10) for the field to go false again and returns whether it did. Something
	-- reset it: the view's handler, or the UI's own hotspot pass; the case asserts the effect it expects.
	function T.press(owner, widget_name, hotspot_name, field, frames)
		local widget

		if type(owner) == "table" and type(owner.content) == "table" then
			widget, frames, field, hotspot_name = owner, field, hotspot_name, widget_name
			widget_name = widget.name or "?"
		else
			widget = T.widget(owner, widget_name)
		end

		local content = widget.content

		hotspot_name = hotspot_name or (content.button_hotspot and "button_hotspot" or "hotspot")

		local hotspot = content[hotspot_name]

		T.require(type(hotspot) == "table", "hotspot " .. tostring(hotspot_name) .. " of widget " .. tostring(widget_name))

		field = field or "on_release"

		T.main(function ()
			hotspot[field] = true
		end)

		local cleared = false

		for _ = 1, frames or 10 do
			T.frames(1)

			if not hotspot[field] then
				cleared = true

				break
			end
		end

		if not cleared then
			T.main(function ()
				hotspot[field] = false
			end)
		end

		ctx.out("PRESS id=%s widget=%s hotspot=%s field=%s cleared=%s", case.id, tostring(widget_name), tostring(hotspot_name), field, tostring(cleared))

		return cleared
	end
end
