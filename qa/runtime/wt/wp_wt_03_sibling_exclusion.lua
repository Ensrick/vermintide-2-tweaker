-- WP-WT-03: with public wt and friends-only wt_dev both enabled, public wt
-- turns itself off through VMF (one [wt:SIBLING] printf line) and wt_dev runs
-- alone, so availability follows wt_dev's settings.
-- Plan: load both wt and wt_dev enabled in the isolated profile.
-- Engine read: ItemMasterList[<weapon>].can_wield
-- (Vermintide-2-Source-Code/scripts/settings/equipment/item_master_list_exported.lua).
-- Toggle path: Vermintide-Mod-Framework/vmf/scripts/mods/vmf/modules/core/toggling.lua:55-66.
return {
	card = "WP-WT-03",
	issue = 0,
	class = "R",
	arena = "keep",
	mods = { "wt", "wt_dev" },
	timeout = 60,
	host_expect_log = { "[wt:SIBLING]" },
	run = function(T)
		local function contains(list, wanted)
			for _, value in ipairs(list or {}) do
				if value == wanted then return true end
			end
			return false
		end

		local wt, wt_dev = get_mod("wt"), get_mod("wt_dev")
		T.require(wt ~= nil and wt_dev ~= nil, "both wt and wt_dev are loaded")
		local vmf = get_mod("VMF")
		T.require(vmf ~= nil and type(vmf.mod_state_changed) == "function",
			"VMF mod_state_changed exists")

		T.step("public wt yields to wt_dev")
		T.wait(3)
		T.expect_eq(wt:is_enabled(), false, "public yielded")
		T.expect_eq(wt_dev:is_enabled(), true, "dev active")

		T.step("availability follows wt_dev settings")
		local pairs_to_check = {
			{ "es_mercenary", "wh_crossbow" },
			{ "wh_captain", "es_2h_hammer" },
			{ "we_waywatcher", "es_1h_mace" },
		}
		for _, pair in ipairs(pairs_to_check) do
			local career, weapon = pair[1], pair[2]
			local item = rawget(ItemMasterList, weapon)
			local present = item ~= nil and contains(item.can_wield, career)
			local wanted = wt_dev:get("unlock_" .. career .. "_" .. weapon) == true
			T.note(career .. "/" .. weapon, tostring(present) .. " want " .. tostring(wanted))
			T.expect_eq(present, wanted, career .. " in " .. weapon .. ".can_wield follows wt_dev")
		end
	end,
}
