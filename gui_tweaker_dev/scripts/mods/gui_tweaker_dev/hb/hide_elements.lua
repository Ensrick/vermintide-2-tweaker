local mod = get_mod("gut_dev")

-- ============================================================================
-- hide_elements.lua -- Phase-1 single-element hide hooks (UI Tweaks port)
-- ============================================================================
-- These hooks are copied VERBATIM (renamespaced get_mod("HideBuffs") ->
-- get_mod("gut_dev")) from HideBuffs.lua. This is the "hide an element" subset:
-- each hook returns early to suppress a HUD element / behavior when its setting
-- is enabled, or applies a small "unobtrusive" restyle.
--
-- HOOKS INCLUDED (exact list, hook vs hook_safe preserved from the original):
--   mod:hook  ChallengeTrackerUI._draw                          (GK quests offset/alpha)
--   mod:hook  TutorialUI.update                                 (NO_TUTORIAL_UI)
--   mod:hook  TutorialUI.update_mission_tooltip                 (NO_TUTORIAL_UI / UNOBTRUSIVE_MISSION_TOOLTIP)
--   mod:hook  TutorialUI.update_objective_tooltip_widget        (UNOBTRUSIVE_FLOATING_OBJECTIVE)
--   mod:hook  MissionObjectiveUI.draw                           (NO_MISSION_OBJECTIVE)
--   mod:hook  BossHealthUI._draw                                (HIDE_BOSS_HP_BAR + offsets)
--   mod:hook  GameModeManager.has_activated_mutator             (HIDE_HUD_WHEN_INSPECTING / keep_hud_hidden)
--   mod:hook  IngameHud._update_components_visibility           (realism LevelCountdownUI patch)
--   mod:hook  OutlineSystem.always                              (disable hero outlines)
--   mod:hook  DialogueSystem.trigger_sound_event_with_subtitles (DISABLE_OLESYA_UBERSREIK_AUDIO)
--   mod:hook  PlayerHud.set_current_location                    (HIDE_NEW_AREA_TEXT)
--   mod:hook_safe SubtitleGui.update                            (subtitle reposition)
--   mod:hook  TwitchVoteUI._draw                                (twitch vote reposition)
--   mod:hook  WaitForRescueUI.update                            (HIDE_WAITING_FOR_RESCUE)
--   mod:hook  TwitchIconView._draw                              (HIDE_TWITCH_MODE_ON_ICON)
--   mod:hook  UnitFrameUI._update_bar_flash                     (STOP_WHITE_HP_FLASHING)
--
-- SUPPORTING STATE / HELPERS brought along (referenced by the hooks above):
--   mod.persistent = mod:persistent_table("hb_persistent")   (renamespaced)
--   mod.reapply_pickup_ranges  (used by GameModeManager outline path + setting change)
--   mod.keep_hud_hidden        (toggled by mod.hide_hud)
--   mod.hide_hud               (Hide-HUD hotkey callback; keybind action = "hide_hud")
--   local disable_outlines     (module-local outline backup flag)
--   outline_ranges_backup init + initial reapply (from HideBuffs.lua EXECUTE block)
--
-- DEPENDENCY NOTE (see agent report D): mod.reapply_pickup_ranges references
-- OutlineSettings (engine global) and mod.persistent.outline_ranges_backup. The
-- HIDE_PICKUP_OUTLINES / HIDE_OTHER_OUTLINES settings are Phase-1 HIDE_UI_ELEMENTS
-- children, so this helper is fully self-contained here. The keybind ACTION
-- "hide_hud" must be registered against mod.hide_hud by the integrator (gut's
-- keybind widget `action` field), exactly as the original keybind option did.

-- Persistent table (renamespaced "persistent" -> "hb_persistent").
mod.persistent = mod:persistent_table("hb_persistent")

-- not making this mod.disable_outlines to attempt some optimization
-- since OutlineSystem.always gets called a crazy amount of times per frame
local disable_outlines = false

--- Grail Knight quests.
mod:hook(ChallengeTrackerUI, "_draw", function(func, self, ...)
	if not mod.SETTING_NAMES then
		return func(self, ...)
	end
	mod:pcall(function()
		-- position for GK quests
		local pivot = self._ui_scenegraph.pivot
		local local_position = pivot.local_position

		local original_local_position = pivot.original_local_position
		if not original_local_position then
			original_local_position = table.clone(pivot.local_position)
			pivot.original_local_position = original_local_position
		end

		-- Phase 1 ships these reposition hooks before their offset/alpha settings
		-- are registered (those land with the "Other UI Elements" phase), so guard
		-- the reads with defaults or the arithmetic crashes on nil.
		local_position[1] = original_local_position[1] + (mod:get(mod.SETTING_NAMES.GK_QUESTS_OFFSET_X) or 0)
		local_position[2] = original_local_position[2] + (mod:get(mod.SETTING_NAMES.GK_QUESTS_OFFSET_Y) or 0)

		-- alpha for GK quests, 200 is default
		local alpha = mod:get(mod.SETTING_NAMES.GK_QUESTS_ALPHA) or 200
		if alpha ~= 200 then
			for _, widget in pairs(self._data.widgets) do
				if widget.content.alpha_multiplier and widget.content.alpha_multiplier == 1 then
					local style = widget.style
					style.background_lilies.color[1] = alpha
					style.background_rect.color[1] = math.max(alpha-25, 0)
					style.lily.color[1] = math.min(255, alpha+55)
				end
			end
		end
	end)

	return func(self, ...)
end)

--- Hide or make less obtrusive the floating mission marker.
--- Used for "Set Free" on respawned player.
mod:hook(TutorialUI, "update_mission_tooltip", function(func, self, ...)
	if not mod.SETTING_NAMES then
		return func(self, ...)
	end
	if mod:get(mod.SETTING_NAMES.NO_TUTORIAL_UI) then
		return
	end

	func(self, ...)

	if mod:get(mod.SETTING_NAMES.UNOBTRUSIVE_MISSION_TOOLTIP) then
		mod:pcall(function()
			local widget_style = self.tooltip_mission_widget.style
			widget_style.texture_id.size = nil
			widget_style.texture_id.offset = { 0, 0 }
			if widget_style.text.text_color[1] ~= 0 then
				widget_style.texture_id.color[1] = 100
				widget_style.text.text_color[1] = 100
				widget_style.text_shadow.text_color[1] = 100
			else
				widget_style.texture_id.size = { 32, 32 }
				widget_style.texture_id.offset = { 16+16, 16 }
			end
		end)
	end
end)

mod:hook(TutorialUI, "update", function(func, self, ...)
	if not mod.SETTING_NAMES then
		return func(self, ...)
	end
	if mod:get(mod.SETTING_NAMES.NO_TUTORIAL_UI) then
		mod:pcall(function()
			self.active_tooltip_widget = nil
			for _, obj_tooltip in ipairs( self.objective_tooltip_widget_holders ) do
				obj_tooltip.updated = false
			end
		end)
	end
	return func(self, ...)
end)

--- Change size and transparency of floating objective icon.
mod:hook(TutorialUI, "update_objective_tooltip_widget", function(func, self, widget_holder, player_unit, dt)
	if not mod.SETTING_NAMES then
		return func(self, widget_holder, player_unit, dt)
	end

	func(self, widget_holder, player_unit, dt)

	if mod:get(mod.SETTING_NAMES.UNOBTRUSIVE_FLOATING_OBJECTIVE) then
		local widget = self.objective_tooltip_widget_holders[1].widget
		local icon_style = widget.style.texture_id
		icon_style.size = { 32, 32 }
		icon_style.offset = { 16, 16 }
		icon_style.color[1] = 75

		if widget.style.text.text_color[1] ~= 0 then
			widget.style.text.text_color[1] = 100
			widget.style.text_shadow.text_color[1] = 100
		end
	end
end)

mod:hook(MissionObjectiveUI, "draw", function(func, self, ...)
	if not mod.SETTING_NAMES then
		return func(self, ...)
	end
	if mod:get(mod.SETTING_NAMES.NO_MISSION_OBJECTIVE) then
		return
	end

	return func(self, ...)
end)

--- Hide or reposition boss hp bar.
mod:hook(BossHealthUI, "_draw", function(func, self, ...)
	if not mod.SETTING_NAMES then
		return func(self, ...)
	end
	if mod:get(mod.SETTING_NAMES.HIDE_BOSS_HP_BAR) then
		return
	end

	-- boss hp bar position
	local local_position = self.ui_scenegraph.pivot.local_position
	if not mod.boss_health_ui_default_position then
		mod.boss_health_ui_default_position = table.clone(local_position)
	end

	local_position[1] = mod.boss_health_ui_default_position[1]
		+ (mod:get(mod.SETTING_NAMES.OTHER_ELEMENTS_BOSS_HP_BAR_OFFSET_X) or 0)
	local_position[2] = mod.boss_health_ui_default_position[2]
		+ (mod:get(mod.SETTING_NAMES.OTHER_ELEMENTS_BOSS_HP_BAR_OFFSET_Y) or 0)

	return func(self, ...)
end)

--- Hide HUD when inspecting or when "Hide HUD" toggled with hotkey.
mod:hook(GameModeManager, "has_activated_mutator", function(func, self, name, ...)
	if not mod.SETTING_NAMES then
		return func(self, name, ...)
	end
	if name == "realism" then
		if mod:get(mod.SETTING_NAMES.HIDE_HUD_WHEN_INSPECTING) then
			local just_return
			pcall(function()
				local player_unit = Managers.player:local_player().player_unit
				local character_state_machine_ext = ScriptUnit.extension(player_unit, "character_state_machine_system")
				just_return = character_state_machine_ext:current_state() == "inspecting"
			end)

			local is_inpecting = not not just_return
			disable_outlines = is_inpecting
			if is_inpecting then
				return true
			end
		end

		if mod.keep_hud_hidden then
			return true
		end
	end

	return func(self, name, ...)
end)

--- Patch realism visibility_group to show LevelCountdownUI.
mod:hook(IngameHud, "_update_components_visibility", function(func, self, ...)
	if self._definitions then
		for _, visibility_group in ipairs( self._definitions.visibility_groups ) do
			if visibility_group.name == "realism" then
				visibility_group.visible_components["LevelCountdownUI"] = true
			end
		end
	end

	return func(self, ...)
end)

--- Disable hero outlines.
mod:hook(OutlineSystem, "always", function(func, self, ...)
	if disable_outlines then
		return false
	end

	return func(self, ...)
end)

--- Mute Olesya in the Ubersreik levels.
mod:hook(DialogueSystem, "trigger_sound_event_with_subtitles", function(func, self, sound_event, subtitle_event, speaker_name, ...)
	if not mod.SETTING_NAMES then
		return func(self, sound_event, subtitle_event, speaker_name, ...)
	end

	local level_key = Managers.state.game_mode and Managers.state.game_mode:level_key()

	if speaker_name == "ferry_lady"
	and level_key
	and mod.ubersreik_lvls:contains(level_key)
	and mod:get(mod.SETTING_NAMES.DISABLE_OLESYA_UBERSREIK_AUDIO)
	then
		return
	end

	return func(self, sound_event, subtitle_event, speaker_name, ...)
end)

--- Hide name of new location text.
mod:hook(PlayerHud, "set_current_location", function(func, self, ...)
	if not mod.SETTING_NAMES then
		return func(self, ...)
	end
	if mod:get(mod.SETTING_NAMES.HIDE_NEW_AREA_TEXT) then
		return
	end

	return func(self, ...)
end)

--- Reposition the subtitles -- ONLY when the user has dialed in a non-zero offset.
--- This is a hook_safe (runs AFTER vanilla positions the subtitle), so the old code
--- unconditionally writing offset = {x, y} every frame CLOBBERED vanilla's own
--- caption position with {0, 0} even when no offset was set (the subtitle offset
--- settings aren't exposed in gut's UI, so they're always 0). Reported as "messes
--- with captions even when the user hasn't changed any settings". Bail at defaults
--- so vanilla positioning is untouched.
mod:hook_safe(SubtitleGui, "update", function(self)
	if not mod.SETTING_NAMES then
		return
	end
	local ox = mod:get(mod.SETTING_NAMES.OTHER_ELEMENTS_SUBTITLES_OFFSET_X) or 0
	local oy = mod:get(mod.SETTING_NAMES.OTHER_ELEMENTS_SUBTITLES_OFFSET_Y) or 0
	if ox == 0 and oy == 0 then
		return
	end
	local subtitle_widget = self._subtitle_widget
	if not subtitle_widget then
		return
	end
	if not subtitle_widget.offset then
		subtitle_widget.offset = { 0, 0, 0 }
	end
	subtitle_widget.offset[1] = ox
	subtitle_widget.offset[2] = oy
end)

--- Reposition the Twitch voting UI.
mod:hook(TwitchVoteUI, "_draw", function(func, self, ...)
	if not mod.SETTING_NAMES then
		return func(self, ...)
	end

	local offset_x = mod:get(mod.SETTING_NAMES.OTHER_ELEMENTS_TWITCH_VOTE_OFFSET_X) or 0
	local offset_y = mod:get(mod.SETTING_NAMES.OTHER_ELEMENTS_TWITCH_VOTE_OFFSET_Y) or 0

	local local_position = self._ui_scenegraph.base_area.local_position
	local_position[1] = 0 + offset_x
	local_position[2] = 120 + offset_y

	local results_local_position = self._ui_scenegraph.result_area.local_position
	results_local_position[1] = 0 + offset_x
	results_local_position[2] = 200 + offset_y

	return func(self, ...)
end)

--- Hide the "Waiting for rescue" message.
mod:hook(WaitForRescueUI, "update", function(func, ...)
	if not mod.SETTING_NAMES then
		return func(...)
	end
	if mod:get(mod.SETTING_NAMES.HIDE_WAITING_FOR_RESCUE) then
		return
	end

	return func(...)
end)

--- Hide the Twitch mode icons in lower right.
mod:hook(TwitchIconView, "_draw", function(func, self, ...)
	if not mod.SETTING_NAMES then
		return func(self, ...)
	end
	if mod:get(mod.SETTING_NAMES.HIDE_TWITCH_MODE_ON_ICON) then
		return
	end

	return func(self, ...)
end)

--- Disable White HP flashing.
mod:hook(UnitFrameUI, "_update_bar_flash", function(func, self, ...)
	if not mod.SETTING_NAMES then
		return func(self, ...)
	end
	if mod:get(mod.SETTING_NAMES.STOP_WHITE_HP_FLASHING) then
		return
	end

	return func(self, ...)
end)

-- ----------------------------------------------------------------------------
-- SUPPORTING HELPERS (from HideBuffs.lua "MOD FUNCTIONS" + "EXECUTE" blocks).
-- ----------------------------------------------------------------------------

mod.reapply_pickup_ranges = function()
	if not mod.SETTING_NAMES then
		return
	end
	OutlineSettings.ranges = table.clone(mod.persistent.outline_ranges_backup)
	if mod:get(mod.SETTING_NAMES.HIDE_PICKUP_OUTLINES) then
		OutlineSettings.ranges.pickup = 0
	end
	if mod:get(mod.SETTING_NAMES.HIDE_OTHER_OUTLINES) then
		OutlineSettings.ranges.doors = 0
		OutlineSettings.ranges.objective = 0
		OutlineSettings.ranges.objective_light = 0
		OutlineSettings.ranges.interactable = 0
		OutlineSettings.ranges.revive = 0
		OutlineSettings.ranges.player_husk = 0
		OutlineSettings.ranges.elevators = 0
	end
end

--- Hide HUD hotkey callback. (keybind action = "hide_hud")
mod.hide_hud = function()
	mod.keep_hud_hidden = not mod.keep_hud_hidden
end

--- EXECUTE: back up the engine's default outline ranges once, then reapply with
--- our current hide settings (HideBuffs.lua tail).
mod.was_ingame_entered = mod.persistent.was_ingame_entered
if mod.was_ingame_entered then
	mod.was_reloaded = true -- was_ingame_entered will only be true after a reload
end

if not mod.persistent.outline_ranges_backup then
	mod.persistent.outline_ranges_backup = table.clone(OutlineSettings.ranges)
end

mod.reapply_pickup_ranges()
