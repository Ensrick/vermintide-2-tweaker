-- Exact native 6.13.0 source excerpt, not a UI reimplementation.
-- Source commit: 93dea911a4cc464a0eb51cfdc3a443297bfc4550
-- scripts/ui/views/hero_view/windows/hero_window_gotwf_overview.lua:818-895
-- Both complete bodies remain byte-identical after LF normalization.
local HeroWindowGotwfOverview = {}

HeroWindowGotwfOverview._claim_daily_reward = function (self, reward_offset)
	local num_allowed_old_segments_to_claim = self._login_rewards.num_allowed_old_segments_to_claim

	if num_allowed_old_segments_to_claim < math.abs(reward_offset) or reward_offset > 0 then
		return
	end

	local peddler_interface = Managers.backend:get_interface("peddler")
	local index = #self._login_rewards.rewards + (reward_offset or 0)
	local claimed_rewards = self._login_rewards.claimed_rewards

	if claimed_rewards[index] > 0 then
		return
	end

	peddler_interface:claim_login_rewards(callback(self, "_claim_reward_result_cb", index), reward_offset)

	self._force_index = #self._login_rewards.rewards + (reward_offset or 0)
	self._awaiting_result = true

	self._parent:block_input()
	self:_play_sound("Play_hud_gotwf_claim")
end

HeroWindowGotwfOverview._claim_reward_result_cb = function (self, reward_index, login_rewards)
	if not self._ui_animator then
		return
	end

	if login_rewards.event_type ~= "calendar" then
		self._awaiting_result = false

		self._parent:unblock_input()
		Managers.ui:handle_transition("close_active", {
			fade_in_speed = 1,
			fade_out_speed = 1,
			use_fade = true,
		})

		return
	end

	self._login_rewards = login_rewards

	local rewards = self._login_rewards.rewards[reward_index]
	local num_rewards = rewards and #rewards or 0

	if num_rewards == 0 then
		self._awaiting_result = false

		self._parent:unblock_input()

		return
	end

	self._replacement_presentation_data = self:_gather_replacement_presentation_data(reward_index)

	local item_widget = self._item_widgets[reward_index]

	item_widget.content.visible = false

	self:_update_claim_button_visibility()
	self:_reset_current_item()
	self:_start_transition_animation("hide_item_list")
	self:_start_transition_animation("lock_open")

	self._ui_animations_callbacks.lock_open = callback(self, "_start_transition_animation", "lock_close")
	self._ui_animations_callbacks.lock_close = callback(self, "_start_transition_animation", "reveal")

	self._ui_animations_callbacks.reveal = function ()
		self:_update_daily_rewards(reward_index)
		self:_start_transition_animation("show_item_list")
		self:_trigger_replacement_rewards()
	end

	Managers.backend:commit()
	self:_play_sound("Play_hud_gotwf_animation_start")
end

return HeroWindowGotwfOverview
