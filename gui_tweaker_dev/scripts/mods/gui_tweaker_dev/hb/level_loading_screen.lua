local mod = get_mod("gut_dev")

-- ============================================================================
-- level_loading_screen.lua -- fork of HideBuffs/level_loading_screen.lua
-- ============================================================================
-- Renamespaced: get_mod("HideBuffs") -> get_mod("gut_dev"). Hook bodies verbatim.
--
-- Hooks (all mod:hook, as in the original):
--   StateLoading._trigger_sound_events   (DISABLE_LEVEL_INTRO_AUDIO)
--   LoadingView.setup_tip_text           (HIDE_LOADING_SCREEN_TIPS)
--   LoadingView.create_ui_elements       (HIDE_LOADING_SCREEN_SUBTITLES)
--
-- State brought along:
--   mod.original_num_subtitle_rows  (cached default NUM_SUBTITLE_ROWS so the
--                                    subtitle hide is reversible)

--- Disable level intro audio.
-- CHECK
-- StateLoading._trigger_sound_events = function (self, level_key)
mod:hook(StateLoading, "_trigger_sound_events", function(func, self, level_key)
	-- The BOOT loading screen can fire before hb_data.lua has populated
	-- mod.SETTING_NAMES; bail to vanilla until the table exists.
	if not mod.hb_fork_active() then
		return func(self, level_key)
	end

	if mod:get(mod.SETTING_NAMES.DISABLE_LEVEL_INTRO_AUDIO) then
		return
	end

	return func(self, level_key)
end)

--- Disable loading screen tips.
mod:hook(LoadingView, "setup_tip_text", function(func, ...)
	if not mod.hb_fork_active() then
		return func(...)
	end

	if mod:get(mod.SETTING_NAMES.HIDE_LOADING_SCREEN_TIPS) then
		return
	end

	return func(...)
end)

--- Hide loading screen subtitles.
mod:hook(LoadingView, "create_ui_elements", function(func, ...)
	-- CONFIRMED CRASH SITE (2026-06-24): the BOOT loading screen fires this hook
	-- before hb_data.lua has populated mod.SETTING_NAMES, so reading
	-- mod.SETTING_NAMES.HIDE_LOADING_SCREEN_SUBTITLES below indexed a nil value.
	-- Bail to vanilla until the table exists. (Regression marker: hb_setting_names_guarded)
	if not mod.hb_fork_active() then
		return func(...)
	end

	local definitions = local_require("scripts/ui/views/loading_view_definitions")

	if not mod.original_num_subtitle_rows then
		mod.original_num_subtitle_rows = definitions.NUM_SUBTITLE_ROWS
	end

	if mod:get(mod.SETTING_NAMES.HIDE_LOADING_SCREEN_SUBTITLES) then
		definitions.NUM_SUBTITLE_ROWS = 0
	else
		definitions.NUM_SUBTITLE_ROWS = mod.original_num_subtitle_rows
	end

	return func(...)
end)
