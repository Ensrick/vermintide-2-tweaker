-- WP-GUT-01 (A7-F01, advances #354 #353 #375): at an exit edge a stored gear id that does not
-- resolve right now must stay in the modded loadout store. Before the fix the exit snapshot read
-- the official fallback as the "live" value and wrote it over the stored id (FAIL at
-- "stored id kept").
--
-- Modded realm only: there gut's set_character_data hook captures the write into its store and
-- never calls vanilla (gui_tweaker_dev _gut_native_loadouts.lua set_character_data hook). In the
-- official realm that call is the vanilla writer, so the case refuses to run there.
--
-- Engine reads:
--   mirror._career_data[career][mirror._career_loadouts[career]][slot]
--     Vermintide-2-Source-Code/scripts/managers/backend_playfab/playfab_mirror_base.lua:1927-1932
--   BackendUtils.get_loadout_item_id  scripts/managers/backend/backend_utils.lua:14-20
--   Managers.backend:dirtify_interfaces  scripts/managers/backend_playfab/backend_manager_playfab.lua:211-219
return {
	issue = 354,
	class = "R",
	arena = "keep",
	timeout = 60,
	run = function(T)
		local PROBE = "gut_rig_unresolvable_necklace"
		local mod_id = get_mod("gut_dev") and "gut_dev" or "gut"
		local m = get_mod(mod_id)
		T.require(m ~= nil, "gut or gut_dev loaded")
		T.require(rawget(_G, "MODDED_REALM") == true, "modded realm")
		-- The case needs STORE mode. T.set restores the value after the case; until the driver has
		-- it, set directly (gut reads the setting per call; the rig profile is a copy and is never
		-- written back).
		if T.set then
			T.set(mod_id, "gut_use_non_modded_loadouts", false)
		else
			T.note("t_set", "missing; used " .. mod_id .. ":set")
			m:set("gut_use_non_modded_loadouts", false)
		end
		T.require(type(m._gut_exit_snapshot) == "function", "seam present")

		local items = Managers.backend:get_interface("items")
		local mirror = items and items._backend_mirror
		T.require(mirror ~= nil, "backend mirror")
		local player = Managers.player:local_player()
		local career = player and player:career_name()
		T.require(career ~= nil, "local career")
		T.note("mod", mod_id)
		T.note("career", career)

		local before = m:get("native_loadouts")
		T.require(type(before) == "table" and type(before[career]) == "table", "store seeded")
		local sel = before[career].selected_index
		T.require(sel ~= nil and type(before[career].loadouts) == "table"
			and type(before[career].loadouts[sel]) == "table", "selected store row")
		local old = before[career].loadouts[sel].slot_necklace
		T.note("stored_before", old)

		local function official_necklace()
			return mirror._career_data[career][mirror._career_loadouts[career]].slot_necklace
		end
		local official_before = official_necklace()
		T.note("official_before", official_before)

		T.step("inject")
		mirror:set_character_data(career, "slot_necklace", PROBE)
		if not T.expect_eq(official_necklace(), official_before, "official row untouched") then
			-- Stop-and-escalate condition of WP-GUT-01: put the raw official field back at once.
			mirror._career_data[career][mirror._career_loadouts[career]].slot_necklace = official_before
			Managers.backend:dirtify_interfaces()
			return
		end

		-- Everything after the injection runs under pcall so the cleanup below always runs.
		-- No yields in here.
		local ok, err = pcall(function()
			Managers.backend:dirtify_interfaces()
			local served = BackendUtils.get_loadout_item_id(career, "slot_necklace")
			T.note("served", served)
			T.require(served ~= nil and served ~= PROBE, "fallback served")

			T.step("exit edge")
			m._gut_exit_snapshot("rig")

			local after = m:get("native_loadouts")
			local row = after and after[career] and after[career].loadouts and after[career].loadouts[sel]
			T.expect_eq(row and row.slot_necklace, PROBE, "stored id kept")
		end)

		T.step("cleanup")
		mirror:set_character_data(career, "slot_necklace", old)
		Managers.backend:dirtify_interfaces()
		local restored = m:get("native_loadouts")
		T.expect_eq(restored[career].loadouts[sel].slot_necklace, old, "stored necklace restored")
		T.expect_eq(official_necklace(), official_before, "official row still untouched")

		if not ok then
			error(err, 0)
		end
	end,
}
