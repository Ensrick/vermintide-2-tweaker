-- API self-test, UI part (WP-H-06 group "UI"): T.open_view opens the hero view on its overview, T.widget finds the
-- overview's exit_button, and T.press presses it with no OS input; the overview then closes the view as a click
-- would (HeroViewStateOverview, Vermintide-2-Source-Code/scripts/ui/views/hero_view/states/hero_view_state_overview.lua:783-786).
-- Then the view is opened again and closed with T.close_view. Each close makes the game commit
-- (hero_view.lua:523); the write shield holds the official rows, so no updateHeroAttributes request may appear.
return {
	issue = 0,
	arena = "keep",
	class = "R",
	timeout = 90,
	run = function(T)
		T.require(T.local_hero(30) ~= nil, "local hero alive")
		T.require(T.shield().installed, "backend write shield installed")

		T.step("T.open_view the hero view on its overview")
		local view = T.open_view("hero_view", { menu_state_name = "overview" })
		-- HeroView.current_state (hero_view.lua:679-685); the overview's NAME (hero_view_state_overview.lua:49).
		-- Wait for the layout too: on_enter only asks for layout 1 (set_layout stores an index,
		-- hero_view_state_overview.lua:246-258, 362-364); the state's first update applies it (_update_set_layout, called
		-- first in update, :609-616) and only then sets _close_on_exit and _selected_game_mode_index (:366-411).
		-- Read before that, close_on_exit() is nil (lead run 20261122-024431-api-selftest: INCONCLUSIVE below).
		local state = T.wait_until(function()
			local current = view:current_state()

			return current and current.NAME == "HeroViewStateOverview" and current._widgets_by_name
				and current:get_selected_game_mode_index() ~= nil and current
		end, 15, "overview state ready with its layout applied")

		T.require(state ~= nil, "overview state ready with its layout applied")
		T.expect(T.widget(state, "exit_button") ~= nil, "T.widget finds exit_button")
		T.require(state:close_on_exit(), "this overview layout closes the view on exit")

		T.step("T.press exit_button")
		T.expect(T.press(state, "exit_button"), "the press was read")
		T.wait_until(function()
			return Managers.ui:ingame_ui().current_view == nil
		end, 15, "the hero view closed after the press")

		T.step("open again and T.close_view")
		T.wait(1)
		T.open_view("hero_view", { menu_state_name = "overview" })
		T.wait(1)
		T.expect(T.close_view(), "T.close_view closed the view")
		T.expect_eq(T.shield().saw_update_hero_attributes, 0, "no updateHeroAttributes request since the shield went up")
	end,
}
