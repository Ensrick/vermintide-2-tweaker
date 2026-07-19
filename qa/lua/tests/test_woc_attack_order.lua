-- Attack-order picker: permutation-plan correctness over the Blightreaper's
-- private Crowbill clone. Exercises the real pipeline (moveset.install on a
-- faithful donor, then _woc_attack_order.apply from the chain descriptor):
-- identity under defaults, full reverse, duplicate selection, heavy
-- charge-pairing as one unit, transition topology preservation, baseline
-- restore, and fail-closed validation.

return function(H, repo_root)
	local moveset = dofile(repo_root
		.. "/weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_blightreaper_moveset.lua")
	local order = dofile(repo_root
		.. "/weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_attack_order.lua")

	local function deep_clone(value)
		if type(value) ~= "table" then return value end
		local copy = {}
		for key, child in pairs(value) do
			copy[deep_clone(key)] = deep_clone(child)
		end
		return copy
	end

	-- Faithful miniature of `one_handed_crowbill` (1h_crowbills.lua): all four
	-- charge nodes, four lights, three heavies, push + bopp, native chain
	-- targets, per-attack anim_time_scale products of time_mod 0.95, and the
	-- fire-flavored burn stab. Field values are distinct per attack so a split
	-- payload (anim moved without its sweep/windows/buffs) is detectable.
	local function charge_chain(light, heavy)
		return {
			{ action = "action_one", end_time = 0.3, input = "action_one_release",
				start_time = 0, sub_action = light },
			{ action = "action_one", input = "action_one_release",
				start_time = 0.5, sub_action = heavy },
			{ action = "action_two", input = "action_two_hold", start_time = 0,
				sub_action = "default" },
			{ blocker = true, end_time = 1.2, input = "action_one_hold", start_time = 0.5 },
			{ action = "action_one", auto_chain = true, start_time = 0.8,
				sub_action = heavy },
		}
	end

	local function attack_chain(next_charge)
		return {
			{ action = "action_one", input = "action_one",
				release_required = "action_one_hold", start_time = 0.55,
				sub_action = next_charge },
			{ action = "action_two", input = "action_two_hold", start_time = 0,
				sub_action = "default" },
		}
	end

	local heavy_enter = function() return "reset_release_input" end
	local end_condition = function() return true end

	local function donor_template()
		return {
			name = moveset.SOURCE_TEMPLATE,
			wield_anim = "to_1h_crowbill",
			wwise_dep_right_hand = { "wwise/one_handed_crowbills" },
			actions = {
				action_one = {
					default = {
						kind = "melee_start",
						anim_event = "attack_swing_charge_left",
						attack_hold_input = "action_one_hold",
						total_time = math.huge,
						buff_data = { { buff_name = "planted_charging_decrease_movement",
							external_multiplier = 0.5, start_time = 0 } },
						allowed_chain_actions = charge_chain("light_attack_last", "heavy_attack"),
					},
					default_right = {
						kind = "melee_start",
						anim_event = "attack_swing_charge_left_pose",
						total_time = math.huge,
						allowed_chain_actions = charge_chain("light_attack_upper", "heavy_attack_right_up"),
					},
					default_left = {
						kind = "melee_start",
						anim_event = "attack_swing_charge_right_pose",
						total_time = math.huge,
						allowed_chain_actions = charge_chain("light_attack_right", "heavy_attack_left"),
					},
					default_last = {
						kind = "melee_start",
						anim_event = "attack_swing_charge_left_pose",
						total_time = math.huge,
						allowed_chain_actions = charge_chain("light_attack_left", "heavy_attack_right_up"),
					},
					heavy_attack = {
						kind = "sweep",
						anim_event = "attack_swing_heavy_left_up",
						anim_time_scale = 0.95 * 1.2,
						damage_profile = "crowbill_1h_heavy_smiter",
						damage_window_start = 0.35,
						damage_window_end = 0.48,
						use_precision_sweep = true,
						impact_sound_event = "crowbill_stab_hit",
						no_damage_impact_sound_event = "blunt_hit_armour",
						hit_effect = "melee_hit_hammers_1h",
						enter_function = heavy_enter,
						anim_end_event_condition_func = end_condition,
						baked_sweep = { { 0.31, 1, 2, 3 } },
						buff_data = { { buff_name = "planted_charging_decrease_movement",
							end_time = 0.3, external_multiplier = 0.8, start_time = 0 } },
						allowed_chain_actions = attack_chain("default_left"),
					},
					heavy_attack_right_up = {
						kind = "sweep",
						anim_event = "attack_swing_heavy_left_diagonal",
						anim_time_scale = 0.95 * 1,
						damage_profile = "crowbill_1h_heavy_smiter_diag",
						damage_window_start = 0.15,
						damage_window_end = 0.28,
						use_precision_sweep = false,
						impact_sound_event = "crowbill_stab_hit",
						no_damage_impact_sound_event = "blunt_hit_armour",
						hit_effect = "melee_hit_hammers_1h",
						enter_function = heavy_enter,
						anim_end_event_condition_func = end_condition,
						baked_sweep = { { 0.42, 4, 5, 6 } },
						allowed_chain_actions = attack_chain("default"),
					},
					heavy_attack_left = {
						kind = "sweep",
						anim_event = "attack_swing_heavy_right",
						anim_time_scale = 0.95 * 1.15,
						damage_profile = "crowbill_1h_heavy_smiter",
						damage_window_start = 0.15,
						damage_window_end = 0.3,
						use_precision_sweep = false,
						impact_sound_event = "crowbill_stab_hit",
						no_damage_impact_sound_event = "blunt_hit_armour",
						hit_effect = "melee_hit_hammers_1h",
						enter_function = heavy_enter,
						anim_end_event_condition_func = end_condition,
						baked_sweep = { { 0.53, 7, 8, 9 } },
						allowed_chain_actions = attack_chain("default_last"),
					},
					light_attack_last = {
						kind = "sweep",
						anim_event = "attack_swing_down",
						anim_time_scale = 0.95 * 1.15,
						damage_profile = "light_pointy_smiter",
						damage_window_start = 0.35,
						damage_window_end = 0.5,
						use_precision_sweep = true,
						sweep_z_offset = 0.05,
						aim_assist_max_ramp_multiplier = 0.8,
						impact_sound_event = "crowbill_stab_hit",
						no_damage_impact_sound_event = "blunt_hit_armour",
						hit_effect = "melee_hit_hammers_1h",
						anim_end_event_condition_func = end_condition,
						baked_sweep = { { 0.11, 10, 11, 12 } },
						allowed_chain_actions = attack_chain("default_right"),
					},
					light_attack_upper = {
						kind = "sweep",
						anim_event = "attack_swing_left",
						anim_time_scale = 0.95 * 1.15,
						damage_profile = "crowbill_1h_light_smiter_flat",
						damage_window_start = 0.38,
						damage_window_end = 0.52,
						use_precision_sweep = false,
						reset_aim_on_attack = true,
						width_mod = 30,
						impact_sound_event = "crowbill_stab_hit",
						no_damage_impact_sound_event = "blunt_hit_armour",
						hit_effect = "melee_hit_hammers_1h",
						anim_end_event_condition_func = end_condition,
						baked_sweep = { { 0.22, 13, 14, 15 } },
						allowed_chain_actions = attack_chain("default_left"),
					},
					light_attack_right = {
						kind = "sweep",
						anim_event = "attack_swing_right_diagonal",
						anim_time_scale = 0.95 * 1.1,
						damage_profile = "crowbill_1h_light_smiter_diag",
						damage_window_start = 0.34,
						damage_window_end = 0.47,
						use_precision_sweep = false,
						impact_sound_event = "crowbill_stab_hit",
						no_damage_impact_sound_event = "blunt_hit_armour",
						hit_effect = "melee_hit_hammers_1h",
						anim_end_event_condition_func = end_condition,
						baked_sweep = { { 0.33, 16, 17, 18 } },
						allowed_chain_actions = attack_chain("default_last"),
					},
					light_attack_left = {
						kind = "sweep",
						anim_event = "attack_swing_stab",
						anim_time_scale = 0.95 * 0.95,
						damage_profile = "light_blunt_smiter_stab_burn",
						damage_window_start = 0.2,
						damage_window_end = 0.32,
						use_precision_sweep = true,
						armor_impact_sound_event = "fire_hit",
						impact_sound_event = "fire_hit",
						no_damage_impact_sound_event = "fire_hit_armour",
						hit_effect = "melee_hit_hammers_1h",
						anim_end_event_condition_func = end_condition,
						baked_sweep = { { 0.44, 19, 20, 21 } },
						allowed_chain_actions = attack_chain("default"),
					},
					light_attack_bopp = {
						kind = "sweep",
						anim_event = "attack_swing_up_left",
						anim_event_3p = "attack_swing_left",
						anim_time_scale = 0.95 * 1,
						damage_profile = "crowbill_1h_light_smiter_upper",
						damage_window_start = 0.17,
						damage_window_end = 0.32,
						use_precision_sweep = false,
						impact_sound_event = "crowbill_stab_hit",
						no_damage_impact_sound_event = "blunt_hit_armour",
						hit_effect = "melee_hit_hammers_1h",
						anim_end_event_condition_func = end_condition,
						baked_sweep = { { 0.55, 22, 23, 24 } },
						allowed_chain_actions = attack_chain("default_left"),
					},
					push = {
						kind = "push_stagger",
						anim_event = "attack_push",
						total_time = 0.8,
						impact_sound_event = "slashing_hit",
						allowed_chain_actions = {
							{ action = "action_one", input = "action_one_hold",
								start_time = 0.3, sub_action = "light_attack_bopp" },
							{ action = "action_two", input = "action_two_hold",
								start_time = 0, sub_action = "default" },
						},
					},
				},
				action_two = {
					default = {
						kind = "block",
						anim_event = "parry_pose",
					},
				},
			},
		}
	end

	-- Runs the real moveset install (0.83 speed, profile overrides, fire-sound
	-- normalization, lookup_data) and returns the prepared private clone.
	local function installed_template()
		local weapons = { [moveset.SOURCE_TEMPLATE] = donor_template() }
		local report = moveset.install(weapons, deep_clone)
		H.equal(report.installed, true, "moveset install must succeed")
		local template = weapons[moveset.TEMPLATE]
		H.truthy(type(template) == "table", "clone must be registered")
		return template
	end

	local descriptor = moveset.chain_descriptor()

	local function snapshot_actions(template)
		return deep_clone(template.actions.action_one)
	end

	local function chain_wiring_snapshot(template)
		local wiring = {}
		for slot, sub_action in pairs(template.actions.action_one) do
			wiring[slot] = deep_clone(sub_action.allowed_chain_actions)
		end
		return wiring
	end

	H.test("woc attack order: descriptor validates and matches the installed clone", function()
		local ok, reason = order.validate_descriptor(descriptor)
		H.equal(ok, true, tostring(reason))
		local template = installed_template()
		local actions = template.actions.action_one
		local pools = { descriptor.lights, descriptor.heavies, descriptor.push }
		for _, pool in ipairs(pools) do
			for _, unit in ipairs(pool) do
				H.truthy(type(actions[unit.slot]) == "table",
					"descriptor slot missing in clone: " .. unit.slot)
				if unit.charge_slot then
					H.truthy(type(actions[unit.charge_slot]) == "table",
						"descriptor charge slot missing in clone: " .. unit.charge_slot)
				end
			end
		end
		for _, charge in ipairs(descriptor.charge_nodes) do
			H.truthy(type(actions[charge]) == "table",
				"charge node missing in clone: " .. charge)
		end
	end)

	H.test("woc attack order: identity plan under default selections", function()
		local plan, reason = order.build_plan(descriptor, order.native_selections(descriptor))
		H.truthy(plan, tostring(reason))
		H.equal(plan.identity, true, "native selections must be an identity plan")
		local empty_plan = order.build_plan(descriptor, {})
		H.equal(empty_plan.identity, true, "missing selections must fall back to native")
	end)

	H.test("woc attack order: identity apply leaves the clone untouched", function()
		local template = installed_template()
		local before = snapshot_actions(template)
		local report, reason = order.apply(template, descriptor,
			order.native_selections(descriptor))
		H.truthy(report, tostring(reason))
		H.equal(report.identity, true, "default apply must report identity")
		H.deep_equal(template.actions.action_one, before,
			"identity apply must not change any sub_action")
	end)

	H.test("woc attack order: full reverse light order moves whole units", function()
		local template = installed_template()
		local selections = order.native_selections(descriptor)
		selections.lights = { "stab", "right_diagonal", "upper_left", "overhead" }
		local report, reason = order.apply(template, descriptor, selections)
		H.truthy(report, tostring(reason))
		local actions = template.actions.action_one
		-- Position 1 (slot light_attack_last) now plays the stab unit: anim,
		-- speed, windows, sweep, and normalized fire sounds all moved together.
		local p1 = actions.light_attack_last
		H.equal(p1.anim_event, "attack_swing_stab", "position 1 anim must be the stab")
		H.equal(p1.anim_time_scale, 0.95 * 0.95 * moveset.SPEED_MULTIPLIER,
			"stab speed must ride with the unit")
		H.equal(p1.damage_window_start, 0.2, "stab window start must ride")
		H.equal(p1.damage_window_end, 0.32, "stab window end must ride")
		H.deep_equal(p1.baked_sweep, { { 0.44, 19, 20, 21 } },
			"stab sweep volume must ride")
		H.equal(p1.impact_sound_event, moveset.CROWBILL_IMPACT_SOUND,
			"normalized stab impact must ride")
		H.equal(p1.armor_impact_sound_event, nil,
			"cleared armor impact must not resurrect")
		H.equal(p1.sweep_z_offset, nil,
			"overhead-only fields must leave with the overhead unit")
		-- Position 4 (slot light_attack_left) now plays the overhead unit.
		local p4 = actions.light_attack_left
		H.equal(p4.anim_event, "attack_swing_down", "position 4 anim must be the overhead")
		H.equal(p4.sweep_z_offset, 0.05, "overhead z offset must ride")
		H.equal(p4.aim_assist_max_ramp_multiplier, 0.8, "overhead aim assist must ride")
		H.deep_equal(p4.baked_sweep, { { 0.11, 10, 11, 12 } },
			"overhead sweep volume must ride")
		-- Position wiring stays put.
		H.equal(p1.kind, "sweep", "kind is position wiring")
		H.equal(p1.lookup_data.sub_action_name, "light_attack_last",
			"lookup_data is position wiring")
		H.equal(p1.allowed_chain_actions[1].sub_action, "default_right",
			"position 1 continuation must still reach charge node 2")
	end)

	H.test("woc attack order: heavy pair moves with its charge windup", function()
		local template = installed_template()
		local selections = order.native_selections(descriptor)
		-- Reverse the heavy chain: H1 <-> H3, H2 stays.
		selections.heavies = { "right_smash", "diagonal_smash", "left_up_smash" }
		local report, reason = order.apply(template, descriptor, selections)
		H.truthy(report, tostring(reason))
		local actions = template.actions.action_one
		-- Heavy position 1: right smash release + its charge windup on `default`.
		H.equal(actions.heavy_attack.anim_event, "attack_swing_heavy_right",
			"heavy 1 release must be the right smash")
		H.deep_equal(actions.heavy_attack.baked_sweep, { { 0.53, 7, 8, 9 } },
			"heavy 1 sweep must ride with the release")
		H.equal(actions.default.anim_event, "attack_swing_charge_right_pose",
			"charge node 1 must wind up into the right smash")
		-- Heavy position 3: left-up smash release + windup on `default_left`.
		H.equal(actions.heavy_attack_left.anim_event, "attack_swing_heavy_left_up",
			"heavy 3 release must be the left-up smash")
		H.equal(actions.default_left.anim_event, "attack_swing_charge_left",
			"charge node 3 must wind up into the left-up smash")
		-- Heavy position 2 untouched, including both of its charge nodes.
		H.equal(actions.heavy_attack_right_up.anim_event, "attack_swing_heavy_left_diagonal",
			"heavy 2 must keep the diagonal smash")
		H.equal(actions.default_right.anim_event, "attack_swing_charge_left_pose",
			"charge node 2 windup unchanged")
		H.equal(actions.default_last.anim_event, "attack_swing_charge_left_pose",
			"charge node 4 windup unchanged")
		-- Charge nodes keep their non-windup wiring and payload.
		H.equal(actions.default.attack_hold_input, "action_one_hold",
			"charge entry input is position wiring")
		H.equal(actions.default.allowed_chain_actions[2].sub_action, "heavy_attack",
			"charge node 1 must still release into the heavy 1 slot")
		H.equal(actions.default.total_time, math.huge, "charge total_time untouched")
	end)

	H.test("woc attack order: duplicate selection plays at both positions", function()
		local template = installed_template()
		local selections = order.native_selections(descriptor)
		selections.lights = { "overhead", "overhead", "right_diagonal", "stab" }
		local report, reason = order.apply(template, descriptor, selections)
		H.truthy(report, tostring(reason))
		local actions = template.actions.action_one
		H.equal(actions.light_attack_last.anim_event, "attack_swing_down",
			"position 1 must play the overhead")
		H.equal(actions.light_attack_upper.anim_event, "attack_swing_down",
			"position 2 must play the overhead too")
		H.deep_equal(actions.light_attack_upper.baked_sweep,
			actions.light_attack_last.baked_sweep,
			"both positions must carry the same sweep volume")
		H.truthy(actions.light_attack_upper.baked_sweep
			~= actions.light_attack_last.baked_sweep,
			"payload tables must be copies, never aliased")
	end)

	H.test("woc attack order: transition topology preserved under any permutation", function()
		local template = installed_template()
		local wiring_before = chain_wiring_snapshot(template)
		local selections = {
			lights = { "upper_left", "right_diagonal", "stab", "overhead" },
			heavies = { "diagonal_smash", "right_smash", "left_up_smash" },
			push = { "upper_bopp" },
		}
		local report, reason = order.apply(template, descriptor, selections)
		H.truthy(report, tostring(reason))
		for slot, wiring in pairs(chain_wiring_snapshot(template)) do
			H.deep_equal(wiring, wiring_before[slot],
				"allowed_chain_actions drifted on " .. slot)
		end
		local derived, derive_reason = order.derive_transitions(template, descriptor)
		H.truthy(derived, tostring(derive_reason))
		H.deep_equal(derived.after_light, descriptor.transitions.after_light,
			"light continuations must match the transition data layer")
		H.deep_equal(derived.after_heavy, descriptor.transitions.after_heavy,
			"heavy continuations must match the transition data layer")
		H.equal(derived.after_push_attack, descriptor.transitions.after_push_attack,
			"push follow-up continuation must match the transition data layer")
	end)

	H.test("woc attack order: descriptor transitions mirror the donor wiring", function()
		local template = installed_template()
		local derived, reason = order.derive_transitions(template, descriptor)
		H.truthy(derived, tostring(reason))
		H.deep_equal(derived, {
			entry = 1,
			after_light = { 2, 3, 4, 1 },
			after_heavy = { 3, 1, 4 },
			after_push_attack = 3,
		}, "native crowbill after-state map drifted")
	end)

	H.test("woc attack order: re-apply restores native order from the baseline", function()
		local template = installed_template()
		local native = snapshot_actions(template)
		local selections = order.native_selections(descriptor)
		selections.lights = { "stab", "right_diagonal", "upper_left", "overhead" }
		selections.heavies = { "right_smash", "diagonal_smash", "left_up_smash" }
		local report, reason = order.apply(template, descriptor, selections)
		H.truthy(report, tostring(reason))
		local back, back_reason = order.apply(template, descriptor,
			order.native_selections(descriptor))
		H.truthy(back, tostring(back_reason))
		H.deep_equal(template.actions.action_one, native,
			"defaults after a permutation must restore the native clone")
		H.truthy(type(template[order.BASELINE_KEY]) == "table",
			"baseline must ride the template for reload-safe re-apply")
	end)

	H.test("woc attack order: unknown unit fails closed without mutation", function()
		local template = installed_template()
		local before = snapshot_actions(template)
		local selections = order.native_selections(descriptor)
		selections.lights[2] = "no_such_unit"
		local report, reason = order.apply(template, descriptor, selections)
		H.equal(report, nil, "unknown unit must not apply")
		H.equal(reason, "unknown_light_unit:no_such_unit", "reason must name the pick")
		H.deep_equal(template.actions.action_one, before,
			"failed apply must not touch the clone")
		H.equal(template[order.BASELINE_KEY], nil,
			"failed apply must not stamp a baseline")
	end)

	H.test("woc attack order: descriptor validation fails closed on missing units", function()
		local broken = deep_clone(descriptor)
		broken.light_positions[3] = "not_a_unit"
		local ok, reason = order.validate_descriptor(broken)
		H.equal(ok, nil, "position naming a missing unit must fail")
		H.equal(reason, "light_position_3_unknown_native:not_a_unit",
			"validation must name the hole")
		local no_charge = deep_clone(descriptor)
		no_charge.heavies[1].charge_slot = nil
		local charge_ok, charge_reason = order.validate_descriptor(no_charge)
		H.equal(charge_ok, nil, "heavy without a charge pairing must fail")
		H.equal(charge_reason, "heavy_unit_missing_charge_slot:left_up_smash",
			"validation must name the unpaired heavy")
	end)

	H.test("woc attack order: template missing a slot fails closed", function()
		local template = installed_template()
		template.actions.action_one.light_attack_upper = nil
		local before = snapshot_actions(template)
		local report, reason = order.apply(template, descriptor,
			order.native_selections(descriptor))
		H.equal(report, nil, "missing slot must not apply")
		H.equal(reason, "slot_missing:light_attack_upper", "reason must name the slot")
		H.deep_equal(template.actions.action_one, before,
			"failed apply must not touch the remaining slots")
	end)

	H.test("woc attack order: describe_chains renders picks and topology", function()
		local template = installed_template()
		local selections = order.native_selections(descriptor)
		selections.lights[1] = "stab"
		order.apply(template, descriptor, selections)
		local lines, reason = order.describe_chains(template, descriptor, selections)
		H.truthy(lines, tostring(reason))
		H.equal(lines[1], "Chain entry: attacks start at position 1.")
		H.truthy(lines[2]:find('light "woc_atk_stab" then position 2', 1, true) ~= nil,
			"position 1 must render the picked stab and its continuation")
		H.truthy(lines[5]:find('heavy 2 "woc_atk_diagonal_smash" then position 1', 1, true) ~= nil,
			"position 4 must render the shared heavy 2")
		H.truthy(lines[#lines]:find('Push follow-up: "woc_atk_upper_bopp" then position 3', 1, true) ~= nil,
			"push follow-up line must render its continuation")
	end)

	H.test("woc attack order: registry accepts and serves the descriptor", function()
		local ok, reason = order.register(descriptor)
		H.equal(ok, true, tostring(reason))
		H.equal(order.get(descriptor.template_name), descriptor,
			"registry must serve the registered descriptor")
		H.deep_equal(order.registered_names(), { descriptor.template_name },
			"registry must list exactly the registered template")
	end)
end
