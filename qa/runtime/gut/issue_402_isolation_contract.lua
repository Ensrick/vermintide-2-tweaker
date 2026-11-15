-- WP-GUT-04 (advances #402): Tweaker: GUI publishes loadout isolation contract 1, its functional
-- writer probe is answered by the live capture hooks in the modded realm, and an ordinary equip
-- leaves the official loadout rows (`_career_data`) unchanged and equal to the committed mirror.
--
-- Modded realm only (in the official realm an equip is a real official write). STORE mode.
--
-- Engine reads:
--   mirror._career_data / mirror._career_data_mirror: the rows the commit diffs
--     Vermintide-2-Source-Code/scripts/managers/backend_playfab/playfab_mirror_base.lua:2885-2891
--   BackendUtils.set_loadout_item / get_loadout_item_id  scripts/managers/backend/backend_utils.lua:14-28
--   items:get_all_backend_items  scripts/managers/backend_playfab/backend_interface_item_playfab.lua:431
--   necklace items: slot_type "necklace"  scripts/settings/equipment/item_master_list_exported.lua:7831
return {
	issue = 402,
	arena = "keep",
	timeout = 60,
	run = function(T)
		local mod_id = get_mod("gut_dev") and "gut_dev" or "gut"
		local m = get_mod(mod_id)
		T.require(m ~= nil, "gut or gut_dev loaded")
		T.require(rawget(_G, "MODDED_REALM") == true, "modded realm")
		-- STORE mode. T.set restores the value after the case; until the driver has it, set
		-- directly (gut reads the setting per call; the rig profile is a copy).
		if T.set then
			T.set(mod_id, "gut_use_non_modded_loadouts", false)
		else
			T.note("t_set", "missing; used " .. mod_id .. ":set")
			m:set("gut_use_non_modded_loadouts", false)
		end
		T.note("mod", mod_id)

		T.step("contract")
		local iso = m.loadout_isolation
		T.require(type(iso) == "table", "contract published")
		T.expect_eq(iso.contract, 1, "contract version")
		local status = iso.status()
		T.note("reason", status.reason)
		T.expect_eq(status.realm_modded, true, "realm reported modded")
		T.expect_eq(status.mode, "store", "store mode")
		T.expect(status.chokepoint_owned == true, "writer probe answered by the capture hooks")
		T.expect_eq((iso.safe_to_write_loadout()), true, "safe to write")
		if T.expect_rt then
			T.expect_rt(mod_id, "issue402_isolation_contract")
		else
			T.note("t_expect_rt", "missing; the suite sweep (WP-H-03) records issue402_isolation_contract")
		end

		local items = Managers.backend:get_interface("items")
		local mirror = items and items._backend_mirror
		T.require(mirror ~= nil, "backend mirror")
		local player = Managers.player:local_player()
		local career = player and player:career_name()
		T.require(career ~= nil, "local career")
		T.note("career", career)

		local function deep_copy(value)
			if type(value) ~= "table" then return value end
			local out = {}
			for k, v in pairs(value) do out[k] = deep_copy(v) end
			return out
		end
		local function deep_equal(a, b)
			if a == b then return true end
			if type(a) ~= "table" or type(b) ~= "table" then return false end
			for k, v in pairs(a) do
				if not deep_equal(v, b[k]) then return false end
			end
			for k in pairs(b) do
				if a[k] == nil then return false end
			end
			return true
		end

		local official_copy = deep_copy(mirror._career_data)
		local store_before = m:get("native_loadouts")
		T.require(type(store_before) == "table" and type(store_before[career]) == "table", "store seeded")
		local sel = store_before[career].selected_index
		T.require(sel ~= nil and type(store_before[career].loadouts) == "table"
			and type(store_before[career].loadouts[sel]) == "table", "selected store row")
		local stored_necklace = store_before[career].loadouts[sel].slot_necklace

		local current = BackendUtils.get_loadout_item_id(career, "slot_necklace")
		local second
		for backend_id, item in pairs(items:get_all_backend_items()) do
			local data = item.data
			if backend_id ~= current and item.rarity ~= "magic" and data and data.slot_type == "necklace" then
				second = backend_id
				break
			end
		end
		T.require(second ~= nil, "second necklace owned")
		T.note("current", current)
		T.note("second", second)

		T.step("equip a second necklace")
		BackendUtils.set_loadout_item(second, career, "slot_necklace")
		-- Everything after the equip runs under pcall so the cleanup below always runs. No yields.
		local ok, err = pcall(function()
			local after = iso.status()
			T.note("reason_after", after.reason)
			T.expect(after.official_rows_clean == true, "official rows equal the committed mirror")
			T.expect(deep_equal(official_copy, mirror._career_data), "official rows unchanged by the equip")
			local stored = m:get("native_loadouts")[career].loadouts[sel].slot_necklace
			T.expect_eq(stored, second, "equip captured into the modded store")
		end)

		T.step("cleanup")
		mirror:set_character_data(career, "slot_necklace", stored_necklace)
		Managers.backend:dirtify_interfaces()
		T.expect_eq(m:get("native_loadouts")[career].loadouts[sel].slot_necklace, stored_necklace, "store necklace restored")
		T.expect(deep_equal(official_copy, mirror._career_data), "official rows still unchanged")

		if not ok then
			error(err, 0)
		end
	end,
}
