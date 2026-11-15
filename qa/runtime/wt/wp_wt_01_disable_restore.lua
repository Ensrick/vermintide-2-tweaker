-- WP-WT-01: disabling wt in the VMF options restores every native career on its
-- own weapons, nothing is re-applied while disabled, and re-enabling re-applies
-- the saved settings.
-- Engine reads: ItemMasterList[<weapon>].can_wield
-- (Vermintide-2-Source-Code/scripts/settings/equipment/item_master_list_exported.lua:7273-7277
-- lists dr_ranger natively on dr_1h_axe). Toggle path: VMF mod_state_changed
-- (Vermintide-Mod-Framework/vmf/scripts/mods/vmf/modules/core/toggling.lua:55-66).
return {
	card = "WP-WT-01",
	issue = 0,
	arena = "keep",
	mods = { "wt" },
	timeout = 60,
	run = function(T)
		local function contains(list, wanted)
			for _, value in ipairs(list or {}) do
				if value == wanted then return true end
			end
			return false
		end
		local function can_wield(weapon)
			local item = rawget(ItemMasterList, weapon)
			return item and item.can_wield
		end

		local wt = get_mod("wt")
		T.require(wt ~= nil, "wt is loaded")
		T.require(type(wt._wt) == "table" and type(wt._wt.native_weapon_ownership) == "table",
			"wt exposes native_weapon_ownership")
		local vmf = get_mod("VMF")
		T.require(vmf ~= nil and type(vmf.mod_state_changed) == "function", "VMF mod_state_changed exists")

		local native_pairs = {}
		for career, row in pairs(wt._wt.native_weapon_ownership) do
			for weapon, is_native in pairs(row) do
				if is_native == true then
					native_pairs[#native_pairs + 1] = { career = career, weapon = weapon }
				end
			end
		end
		T.note("native_pairs", #native_pairs)

		local function expect_all_native_present(label)
			local missing = 0
			for _, pair in ipairs(native_pairs) do
				local ok = contains(can_wield(pair.weapon), pair.career)
				if not ok then
					missing = missing + 1
					T.note("missing_native:" .. label, pair.career .. "/" .. pair.weapon)
				end
				T.expect(ok, label .. ": " .. pair.career .. " in " .. pair.weapon .. ".can_wield")
			end
			T.note("missing_native_count:" .. label, missing)
		end

		T.step("(a) enabled: native pairs with their toggle on are wieldable")
		for _, pair in ipairs(native_pairs) do
			if wt:get("unlock_" .. pair.career .. "_" .. pair.weapon) == true then
				T.expect(contains(can_wield(pair.weapon), pair.career),
					"enabled: " .. pair.career .. " in " .. pair.weapon .. ".can_wield")
			end
		end

		T.step("(b) enabled: cross-career toggle applies")
		T.set("wt", "unlock_es_mercenary_wh_crossbow", true)
		wt.on_setting_changed("unlock_es_mercenary_wh_crossbow")
		T.expect(contains(can_wield("wh_crossbow"), "es_mercenary"),
			"enabled: es_mercenary in wh_crossbow.can_wield")

		T.step("(c) disable wt through VMF")
		vmf.mod_state_changed("wt", false)
		T.frames(3)
		T.expect(wt:is_enabled() ~= true, "wt reports disabled")
		expect_all_native_present("disabled")
		T.expect(not contains(can_wield("wh_crossbow"), "es_mercenary"),
			"disabled: es_mercenary absent from wh_crossbow.can_wield")

		T.step("(d) state change while disabled re-applies nothing")
		wt.on_game_state_changed("enter", "StateIngame")
		T.frames(3)
		expect_all_native_present("disabled_after_state_change")
		T.expect(not contains(can_wield("wh_crossbow"), "es_mercenary"),
			"disabled after state change: es_mercenary absent from wh_crossbow.can_wield")

		T.step("(e) re-enable wt re-applies the saved settings")
		vmf.mod_state_changed("wt", true)
		T.frames(3)
		T.expect(wt:is_enabled() == true, "wt reports enabled")
		T.expect(contains(can_wield("wh_crossbow"), "es_mercenary"),
			"re-enabled: es_mercenary in wh_crossbow.can_wield")
	end,
}
