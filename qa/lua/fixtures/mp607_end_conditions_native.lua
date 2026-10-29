-- Complete native 6.13.0 gm_event_end_conditions_met body, unchanged.
-- Source93dea911a4cc464a0eb51cfdc3a443297bfc4550; scripts/game_state/state_ingame_running.lua:510-762.
-- Caller globals are supplied by the offline test; no backend/Steam is contacted.
local StateInGameRunning = {}
StateInGameRunning.gm_event_end_conditions_met = function (self, reason, checkpoint_available, percentages_completed)
	if not self.is_server and self.game_mode_key == "versus" and Managers.mechanism:is_final_round() and not self._player_session_score_synced then
		self._player_session_score_synced_cb = callback(self, "gm_event_end_conditions_met", reason, checkpoint_available, percentages_completed)

		return
	end

	if not self._game_has_started then
		Managers.transition:hide_loading_icon()
		Managers.transition:fade_out(GameSettings.transition_fade_in_speed)
	end

	local is_server = self.is_server
	local player = self.player

	self.end_conditions_met = true

	local difficulty_key = Managers.state.difficulty:get_difficulty()
	local level_key = Managers.state.game_mode:level_key()
	local game_mode_key = self.game_mode_key
	local is_quickplay = self.is_quickplay
	local game_won, game_lost = Managers.state.game_mode:evaluate_end_condition_outcome(reason, player)
	local ingame_ui = Managers.ui:temporary_get_ingame_ui_called_from_state_ingame_running()
	local stats_id = player:stats_id()
	local statistics_db = self.statistics_db
	local previous_completed_difficulty_index = LevelUnlockUtils.completed_level_difficulty_index(statistics_db, stats_id, level_key) or 0

	ingame_ui:handle_transition("close_active")

	if Managers.twitch then
		Managers.twitch:deactivate_twitch_game_mode()
	end

	if not self.is_in_inn then
		DialogueSystem.stateless_global_context.last_level_played = level_key
		DialogueSystem.stateless_global_context.last_level_won = game_won
	end

	if ingame_ui.leave_game then
		statistics_db:reset_persistant_stats()
		StatisticsUtil.reset_mission_streak(player, statistics_db, stats_id)

		return
	end

	LoreBookHelper.save_new_pages()

	local mission_system = Managers.state.entity:system("mission_system")

	mission_system:set_percentage_completed(percentages_completed)

	local achievement_manager = Managers.state.achievement

	achievement_manager:evaluate_end_of_level_achievements(statistics_db, stats_id, level_key, difficulty_key)

	local stats_interface = Managers.backend:get_interface("statistics")
	local register_statistics = true
	local is_final_objective = Managers.mechanism:is_final_round()

	Managers.mechanism:load_end_screen_resources()

	if game_mode_key == "survival" then
		if game_won then
			print("Game won")
			mission_system:evaluate_level_end_missions()
			StatisticsUtil.register_complete_survival_level(statistics_db)
			stats_interface:save()
		end
	elseif game_won then
		print("Game won")

		if game_mode_key == "weave" then
			is_final_objective = not Managers.weave:calculate_next_objective_index()

			if is_final_objective then
				local weave_manager = Managers.weave
				local weave_tier = weave_manager:get_weave_tier()
				local score = weave_manager:get_score()
				local num_players = weave_manager:get_num_players()
				local weave_templates = WeaveSettings.templates_ordered
				local num_weave_templates = #weave_templates
				local personal_best = false

				for i = num_weave_templates, weave_tier, -1 do
					local stat_name = ScorpionSeasonalSettings.get_weave_score_stat(i, num_players)
					local previous_score = statistics_db:get_persistent_stat(stats_id, ScorpionSeasonalSettings.current_season_name, stat_name)
					local has_previous_score = previous_score and previous_score > 0

					if weave_tier == i then
						if has_previous_score and previous_score < score or not has_previous_score then
							personal_best = true

							break
						end
					elseif has_previous_score then
						break
					end
				end

				self._weave_personal_best_achieved = personal_best
				self._completed_weave = weave_manager:get_active_weave()

				StatisticsUtil.register_weave_complete(statistics_db, player, is_quickplay, difficulty_key)
			else
				local saved_scoreboard_stats = ScoreboardHelper.get_weave_stats(self.statistics_db, self.profile_synchronizer)

				self.parent.parent.loading_context.saved_scoreboard_stats = saved_scoreboard_stats
			end
		elseif game_mode_key == "versus" then
			register_statistics = is_final_objective
		end

		if is_final_objective then
			self.parent.parent.loading_context.saved_scoreboard_stats = nil
		end

		if register_statistics then
			if self._is_in_event_game_mode then
				StatisticsUtil.register_played_weekly_event_level(statistics_db, player, level_key, difficulty_key)
			end

			StatisticsUtil.register_complete_level(statistics_db, game_mode_key)

			if game_mode_key == "versus" and not self.is_in_inn then
				StatisticsUtil.register_versus_game_won(statistics_db, player, game_won)
			end
		end

		if is_final_objective and Managers.mechanism.on_final_round_won then
			Managers.mechanism:on_final_round_won(statistics_db, stats_id)
		end

		stats_interface:save()
	elseif game_lost then
		if game_mode_key == "versus" then
			if is_final_objective then
				if self._is_in_event_game_mode then
					StatisticsUtil.register_played_weekly_event_level(statistics_db, player, level_key, difficulty_key)
				end

				StatisticsUtil.register_complete_level(statistics_db, game_mode_key)

				if not self.is_in_inn then
					StatisticsUtil.register_versus_game_won(statistics_db, player, game_won)
				end
			end
		else
			is_final_objective = true
		end

		Managers.state.game_mode:game_lost(player)
		print("Game lost")

		self.parent.parent.loading_context.saved_scoreboard_stats = nil
		self.checkpoint_available = checkpoint_available

		if game_mode_key ~= "versus" then
			statistics_db:reset_persistant_stats()
		end

		StatisticsUtil.reset_mission_streak(player, statistics_db, stats_id)
		stats_interface:save()
	end

	if game_mode_key == "versus" then
		if self.is_server then
			local players_session_score = Managers.mechanism:get_players_session_score(self.statistics_db, self.profile_synchronizer, self._saved_scoreboard_stats)

			if is_final_objective then
				Managers.mechanism:sync_players_session_score(players_session_score)
			else
				self.parent.parent.loading_context.saved_scoreboard_stats = players_session_score
			end
		end

		stats_interface:save()
	end

	local screen_name, screen_config, screen_params = Managers.state.game_mode:get_end_screen_config(game_won, game_lost, player, reason)
	local is_game_mode_weave = game_mode_key == "weave"
	local weave_tier, score, num_players, weave_progress

	if is_game_mode_weave then
		weave_tier, score, num_players = self:_get_weave_scores()
		weave_progress = Managers.weave:current_bar_score()

		Managers.weave:store_saved_game_mode_data()
	end

	local function callback(status)
		if is_game_mode_weave and not GameSettingsDevelopment.read_only_backend and game_won and is_final_objective and is_server and not self.is_quickplay then
			self:_submit_weave_scores(weave_tier, score, num_players)
		end

		if status == "commit_error" then
			Managers.backend:commit_error()

			return
		end

		if ingame_ui.leave_game then
			return
		end

		if not self.parent then
			return
		end

		local game_mode_setting = GameModeSettings[game_mode_key]
		local end_mission_rewards = game_mode_setting.end_mission_rewards

		if end_mission_rewards then
			if not GameSettingsDevelopment.read_only_backend and (game_lost or is_final_objective) then
				self:_award_end_of_level_rewards(statistics_db, stats_id, game_won, difficulty_key, level_key)
			end

			print("end screen_name:", screen_name, screen_config, screen_params)
			ingame_ui:activate_end_screen_ui(screen_name, screen_config, screen_params)
		end

		if (game_won and is_final_objective or game_lost) and is_game_mode_weave then
			Managers.weave:clear_weave_name()
		end
	end

	local backend_manager = Managers.backend

	backend_manager:commit(true, callback)

	self.game_lost = game_lost
	self.game_won = game_won
	self.game_tied = not game_won and not game_lost

	if IS_PS4 then
		Managers.account:set_realtime_multiplay(false)
	end

	if self.is_in_inn or self.is_in_tutorial then
		return
	end

	if IS_XB1 then
		if not self._xbox_event_end_triggered then
			self:_xbone_end_of_round_events(statistics_db)
		end

		if not self.is_in_inn and not self.is_in_tutorial and not self.parent.hero_stats_updated then
			Managers.xbox_stats:update_hero_stats(game_won)

			self.parent.hero_stats_updated = true
		end
	end
end


return StateInGameRunning
