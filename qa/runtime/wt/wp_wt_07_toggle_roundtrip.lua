-- WP-WT-07: weapon-table owners run through one ordered registry.
-- (a) every balance toggle round-trips the affected Weapons[*].actions back to
-- the same contents; (b) disabling wt leaves no wt_* damage profile on any
-- sub-action; (c) after re-enabling, one registry reconcile runs clean.
-- Toggle path: VMF mod_state_changed (Vermintide-Mod-Framework/vmf/scripts/mods/vmf/modules/core/toggling.lua:55-66).
return {
	card = "WP-WT-07",
	issue = 0,
	class = "R",
	arena = "keep",
	mods = { "wt" },
	timeout = 180,
	run = function(T)
		local wt = get_mod("wt")
		T.require(wt ~= nil and type(wt._wt) == "table" and type(wt._wt.registry) == "table",
			"wt exposes its mutation registry")
		local vmf = get_mod("VMF")
		T.require(vmf ~= nil and type(vmf.mod_state_changed) == "function", "VMF mod_state_changed exists")

		local function copy(v, seen)
			if type(v) ~= "table" then return v end
			seen = seen or {}
			if seen[v] then return seen[v] end
			local c = {}
			seen[v] = c
			for k, x in pairs(v) do c[copy(k, seen)] = copy(x, seen) end
			return c
		end
		local function same(a, b, seen)
			if type(a) ~= "table" or type(b) ~= "table" then return a == b end
			seen = seen or {}
			if seen[a] == b then return true end
			seen[a] = b
			for k, x in pairs(a) do
				if not same(x, b[k], seen) then return false end
			end
			for k in pairs(b) do
				if a[k] == nil then return false end
			end
			return true
		end
		local function set(id, value)
			if T.set then T.set("wt", id, value) else wt:set(id, value) end
			wt.on_setting_changed(id)
		end

		local settings = {
			"wt_cog_hammer_heavy_speed_nerf", "wt_mace_sword_speed_nerf", "wt_one_hand_axe_cleave_nerf",
			"wt_executioner_light_headshot_bonus", "wt_priest_punch_buff", "wt_brett_sword_shield_buff",
			"wt_fire_sword_sweep_opener", "wt_fire_sword_nova_slowdown", "wt_bolt_staff_primary_overcharge_reduction",
		}
		local templates = {
			"two_handed_cog_hammers_template_1", "dual_wield_hammer_sword_template", "one_hand_axe_template_1",
			"one_hand_axe_template_2", "two_handed_swords_executioner_template_1", "two_handed_hammer_priest_template",
			"flaming_sword_template_1", "staff_spark_spear_template_1",
		}

		T.step("(a) every balance toggle round-trips the weapon actions")
		for _, id in ipairs(settings) do
			local before = {}
			for _, name in ipairs(templates) do
				local tpl = rawget(Weapons, name)
				before[name] = tpl and copy(tpl.actions)
			end
			local original = wt:get(id)
			set(id, true)
			set(id, original)
			for _, name in ipairs(templates) do
				local tpl = rawget(Weapons, name)
				T.expect(same(before[name], tpl and tpl.actions), id .. " round-trips " .. name)
			end
		end

		T.step("(b) disable wt: no wt_* damage profile remains")
		vmf.mod_state_changed("wt", false)
		T.frames(3)
		T.expect(wt:is_enabled() ~= true, "wt reports disabled")
		local leftovers = 0
		for name, tpl in pairs(Weapons) do
			local actions = type(tpl) == "table" and rawget(tpl, "actions")
			if type(actions) == "table" then
				for action_name, action in pairs(actions) do
					if type(action) == "table" then
						for sub_name, sub in pairs(action) do
							if type(sub) == "table" then
								local impact = type(sub.impact_data) == "table" and sub.impact_data.damage_profile
								for _, profile in ipairs({ sub.damage_profile, impact }) do
									if type(profile) == "string" and profile:sub(1, 3) == "wt_" then
										leftovers = leftovers + 1
										T.expect(false, name .. "." .. tostring(action_name) .. "." .. tostring(sub_name)
											.. " keeps " .. profile .. " after disable")
									end
								end
							end
						end
					end
				end
			end
		end
		T.note("wt_profiles_after_disable", leftovers)

		T.step("(c) re-enable wt: one reconcile runs clean")
		vmf.mod_state_changed("wt", true)
		T.frames(3)
		T.expect(wt:is_enabled() == true, "wt reports enabled")
		local ok, failed = wt._wt.registry.reconcile("rig")
		T.note("reconcile_failed", table.concat(failed or {}, ","))
		T.expect_eq(ok, true, "reconcile clean")
	end,
}
