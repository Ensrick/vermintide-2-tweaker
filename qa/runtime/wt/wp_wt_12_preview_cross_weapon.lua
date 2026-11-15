-- WP-WT-12: with the dead pre-spawn validator deleted, previewing a
-- cross-career staff on a Kruber body raises no missing-node error: preview
-- links go through GearUtils.link -> link_units, which wt guards
-- (Vermintide-2-Source-Code/scripts/ui/views/world_hero_previewer.lua:1101;
-- scripts/unit_extensions/default_player_unit/inventory/gear_utils.lua:288-291).
-- Plan: start as es_mercenary in the keep.
-- Engine path used here: hero view transition "hero_view_force" with the
-- equipment sub-state (scripts/ui/views/ingame_ui.lua:629-636), the
-- equipment layout's character_preview window at index 2
-- (scripts/ui/views/hero_view/states/hero_window_layout.lua:47-56), its
-- world_previewer + hero_unit_spawned (hero_window_character_preview.lua:171-182),
-- HeroPreviewer.equip_item (world_hero_previewer.lua:649), state accessor
-- (scripts/ui/views/hero_view/hero_view.lua:441), exit_menu
-- (scripts/ui/views/ingame_ui_settings.lua:506).
return {
	card = "WP-WT-12",
	issue = 0,
	class = "R",
	arena = "keep",
	mods = { "wt" },
	timeout = 120,
	host_forbid_log = { "Unit.node", "has no node" },
	run = function(T)
		local wt = get_mod("wt")
		T.require(wt ~= nil and type(wt._wt) == "table", "wt is loaded")
		local player = Managers.player and Managers.player:local_player()
		local career = player and player:career_name()
		T.note("career", tostring(career))
		T.require(career == "es_mercenary", "plan starts as es_mercenary")

		T.step("enable the cross-career staff")
		local setting = "unlock_es_mercenary_bw_skullstaff_fireball"
		if T.set then
			T.set("wt", setting, true)
		else
			T.note("t_set", "missing; used wt:set (rig profile is a copy)")
			wt:set(setting, true)
		end
		wt.on_setting_changed(setting)

		T.step("in-mod node guards pass")
		local function expect_rt(name)
			if T.expect_rt then return T.expect_rt("wt", name) end
			local verdict
			for _, row in ipairs(wt._wt.run_regression()) do
				if row.name == name then verdict = row end
			end
			T.expect(verdict ~= nil, name .. " is registered")
			T.expect_eq(verdict and verdict.result, "PASS", name .. ": " .. tostring(verdict and verdict.detail))
		end
		expect_rt("link_units_node_guard")
		expect_rt("issue269_unwielded_staff_hip_fallback")

		T.step("open the hero view on the equipment screen")
		local params = { menu_state_name = "overview", menu_sub_state_name = "equipment" }
		local ingame_ui = Managers.ui and Managers.ui._ingame_ui
		if T.open_view then
			T.open_view("hero_view", params)
		else
			T.require(ingame_ui ~= nil, "ingame UI exists")
			ingame_ui:handle_transition("hero_view_force", params)
		end
		local previewer = T.wait_until(function()
			local ui = Managers.ui and Managers.ui._ingame_ui
			local view = ui and ui.views and ui.views.hero_view
			local machine = view and view._machine
			local state = machine and machine:state()
			local windows = state and state._active_windows
			local preview = windows and windows[2]
			if preview and preview.world_previewer and preview.hero_unit_spawned then
				return preview.world_previewer
			end
			return nil
		end, 30, "hero preview spawned")
		T.require(previewer ~= nil, "hero preview spawned")

		T.step("preview the staff on the Kruber body")
		local ok, err = pcall(previewer.equip_item, previewer, "bw_skullstaff_fireball",
			InventorySettings.slots_by_name.slot_ranged)
		T.expect(ok, "preview equip did not raise: " .. tostring(err))
		T.wait(3)
		if T.shot then T.shot("kruber_staff_preview") end

		T.step("close the hero view")
		if ingame_ui then ingame_ui:handle_transition("exit_menu") end
		T.wait(1)
	end,
}
