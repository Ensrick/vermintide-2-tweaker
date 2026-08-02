return function(H, repo_root)
	local moveset = dofile(repo_root
		.. "/weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_blightreaper_moveset.lua")
	local career_actions = dofile(repo_root
		.. "/tools/shared_lib/_lib_career_weapon_actions.lua")

	local function deep_clone(value)
		if type(value) ~= "table" then
			return value
		end
		local copy = {}
		for key, child in pairs(value) do
			copy[deep_clone(key)] = deep_clone(child)
		end
		return copy
	end

	-- Faithful miniature of the real `one_handed_crowbill` donor
	-- (`1h_crowbills.lua`): native chain targets, per-action anim_time_scale
	-- products of time_mod 0.95, crowbill impact identity, and the fire-flavored
	-- burn stab (`light_attack_left`).
	local function donor_template()
		return {
			name = moveset.SOURCE_TEMPLATE,
			wield_anim = "to_1h_crowbill",
			state_machine = "units/beings/player/first_person_base/state_machines/melee/1h_crowbill",
			wwise_dep_right_hand = { "wwise/one_handed_crowbills" },
			buffs = {
				change_dodge_distance = { external_optional_multiplier = 1.25 },
			},
			actions = {
				action_one = {
					default = {
						kind = "melee_start",
						anim_event = "attack_swing_charge_left",
						lookup_data = { item_template_name = "donor" },
						allowed_chain_actions = {
							{ action = "action_one", end_time = 0.3, input = "action_one_release",
								start_time = 0, sub_action = "light_attack_last" },
							{ action = "action_one", input = "action_one_release",
								start_time = 0.5, sub_action = "heavy_attack" },
							{ action = "action_one", auto_chain = true, start_time = 0.8,
								sub_action = "heavy_attack" },
						},
					},
					default_left = {
						kind = "melee_start",
						anim_event = "attack_swing_charge_right_pose",
						allowed_chain_actions = {
							{ action = "action_one", end_time = 0.3, input = "action_one_release",
								start_time = 0, sub_action = "light_attack_right" },
							{ action = "action_one", input = "action_one_release",
								start_time = 0.5, sub_action = "heavy_attack_left" },
						},
					},
					heavy_attack = {
						kind = "sweep",
						anim_event = "attack_swing_heavy_left_up",
						anim_time_scale = 0.95 * 1.2,
						damage_profile = "crowbill_1h_heavy_smiter",
						impact_sound_event = "crowbill_stab_hit",
						no_damage_impact_sound_event = "blunt_hit_armour",
						hit_effect = "melee_hit_hammers_1h",
						baked_sweep = { { 0.1, 1, 2, 3 } },
						allowed_chain_actions = {
							{ action = "action_one", input = "action_one",
								release_required = "action_one_hold", start_time = 0.55,
								sub_action = "default_left" },
						},
					},
					light_attack_left = {
						kind = "sweep",
						anim_event = "attack_swing_stab",
						anim_time_scale = 0.95 * 0.95,
						damage_profile = "light_blunt_smiter_stab_burn",
						armor_impact_sound_event = "fire_hit",
						impact_sound_event = "fire_hit",
						no_damage_impact_sound_event = "fire_hit_armour",
						hit_effect = "melee_hit_hammers_1h",
						allowed_chain_actions = {
							{ action = "action_one", end_time = 1.25, input = "action_one",
								start_time = 0.5, sub_action = "default" },
						},
					},
					light_attack_last = {
						kind = "sweep",
						anim_event = "attack_swing_down",
						anim_time_scale = 0.95 * 1.15,
						damage_profile = "light_pointy_smiter",
						impact_sound_event = "crowbill_stab_hit",
						no_damage_impact_sound_event = "blunt_hit_armour",
						baked_sweep = { { 0.2, 4, 5, 6 } },
						allowed_chain_actions = {
							{ action = "action_one", end_time = 1.25, input = "action_one",
								start_time = 0.55, sub_action = "default_right" },
						},
					},
					light_attack_bopp = {
						kind = "sweep",
						anim_event = "attack_swing_up_left",
						anim_event_3p = "attack_swing_left",
						anim_time_scale = 0.95 * 1,
						damage_profile = "crowbill_1h_light_smiter_upper",
						impact_sound_event = "crowbill_stab_hit",
						no_damage_impact_sound_event = "blunt_hit_armour",
						allowed_chain_actions = {},
					},
					push = {
						kind = "push_stagger",
						anim_event = "attack_push",
						impact_sound_event = "slashing_hit",
						damage_profile_inner = { internal = "must_not_be_cloned_or_rewritten" },
					},
				},
				action_two = {
					default = {
						kind = "block",
						anim_event = "parry_pose",
						anim_time_scale = 0.8,
					},
				},
			},
		}
	end

	local function donor_weapons(donor)
		return {
			[moveset.SOURCE_TEMPLATE] = donor or donor_template(),
		}
	end

	H.test("WOC Blightreaper deep-clones the Crowbill graph without donor mutation", function()
		local donor = donor_template()
		local snapshot = deep_clone(donor)
		local weapons = donor_weapons(donor)
		local clone_was_deep = false
		local report = moveset.install(weapons, function(value, deep)
			clone_was_deep = deep
			return deep_clone(value)
		end)
		local installed = weapons[moveset.TEMPLATE]

		H.truthy(report.installed)
		H.equal(report.attacks, 6)
		H.equal(clone_was_deep, true)
		H.truthy(installed ~= donor)
		H.deep_equal(donor, snapshot, "donor template changed")
		H.equal(installed.name, moveset.TEMPLATE)

		-- Speed multiplies the crowbill's own per-action timings; charge
		-- windups carry no authored scale and land at the bare multiplier.
		local a = installed.actions.action_one
		H.equal(a.default.anim_time_scale, moveset.SPEED_MULTIPLIER)
		H.equal(a.heavy_attack.anim_time_scale, (0.95 * 1.2) * moveset.SPEED_MULTIPLIER)
		H.equal(a.light_attack_left.anim_time_scale, (0.95 * 0.95) * moveset.SPEED_MULTIPLIER)
		H.equal(a.light_attack_last.anim_time_scale, (0.95 * 1.15) * moveset.SPEED_MULTIPLIER)
		H.equal(a.light_attack_bopp.anim_time_scale, (0.95 * 1) * moveset.SPEED_MULTIPLIER)
		H.equal(installed.actions.action_two.default.anim_time_scale, 0.8,
			"block is not an attack and must keep its authored scale")

		-- Native crowbill anim events are the point of the swap: no swing
		-- translation layer may rewrite them.
		H.equal(a.default.anim_event, "attack_swing_charge_left")
		H.equal(a.heavy_attack.anim_event, "attack_swing_heavy_left_up")
		H.equal(a.light_attack_left.anim_event, "attack_swing_stab")
		H.equal(a.light_attack_bopp.anim_event_3p, "attack_swing_left")

		-- Native chain transitions preserved verbatim (no retargeting).
		H.equal(a.default.allowed_chain_actions[1].sub_action, "light_attack_last")
		H.equal(a.default.allowed_chain_actions[2].sub_action, "heavy_attack")
		H.equal(a.default.allowed_chain_actions[3].sub_action, "heavy_attack")
		H.equal(a.default_left.allowed_chain_actions[1].sub_action, "light_attack_right")
		H.equal(a.default_left.allowed_chain_actions[2].sub_action, "heavy_attack_left")
		H.equal(a.heavy_attack.allowed_chain_actions[1].sub_action, "default_left")
		H.equal(a.light_attack_last.allowed_chain_actions[1].sub_action, "default_right")

		-- Relic damage/crit layers ride on top of the native graph.
		H.equal(a.light_attack_left.damage_profile, moveset.LIGHT_DAMAGE_PROFILE)
		H.equal(a.light_attack_last.damage_profile, moveset.LIGHT_DAMAGE_PROFILE)
		H.equal(a.light_attack_bopp.damage_profile, moveset.LIGHT_DAMAGE_PROFILE)
		H.equal(a.heavy_attack.damage_profile, moveset.HEAVY_DAMAGE_PROFILE)
		H.equal(a.default.damage_profile, nil,
			"charge windups have no damage profile to override")
		H.equal(a.heavy_attack.additional_critical_strike_chance,
			moveset.INTRINSIC_CRIT_CHANCE)
		H.equal(a.light_attack_left.additional_critical_strike_chance,
			moveset.INTRINSIC_CRIT_CHANCE)

		-- Every damaging sweep uses the requested native Greataxe impact family;
		-- the Crowbill graph/baked geometry remains intact.
		H.equal(a.heavy_attack.impact_sound_event, moveset.GREATAXE_IMPACT_SOUND)
		H.equal(a.heavy_attack.no_damage_impact_sound_event,
			moveset.GREATAXE_ARMOUR_IMPACT_SOUND)
		H.equal(a.heavy_attack.hit_effect, moveset.GREATAXE_HIT_EFFECT)
		H.equal(a.light_attack_left.impact_sound_event, moveset.GREATAXE_IMPACT_SOUND)
		H.equal(a.light_attack_left.no_damage_impact_sound_event,
			moveset.GREATAXE_ARMOUR_IMPACT_SOUND)
		H.equal(a.light_attack_left.armor_impact_sound_event, nil)
		H.equal(a.light_attack_left.hit_effect, moveset.GREATAXE_HIT_EFFECT)
		H.equal(a.push.impact_sound_event, "slashing_hit",
			"push is not a sweep and keeps its authored sounds")
		H.deep_equal(a.push.damage_profile_inner,
			{ internal = "must_not_be_cloned_or_rewritten" })
		H.deep_equal(a.heavy_attack.baked_sweep, { { 0.1, 1, 2, 3 } })
		H.deep_equal(a.light_attack_last.baked_sweep, { { 0.2, 4, 5, 6 } })

		-- Residency: the clone keeps the crowbill bank and appends the
		-- Executioner swing bank; both ride WeaponUtils.get_weapon_packages.
		H.deep_equal(installed.wwise_dep_right_hand,
			{ "wwise/one_handed_crowbills", moveset.EXECUTIONER_WWISE_DEP })
		H.equal(installed.state_machine,
			"units/beings/player/first_person_base/state_machines/melee/1h_crowbill")
		H.equal(installed.wield_anim, "to_1h_crowbill")

		-- The per-career 3P wield redirect is installed as a fresh copy.
		H.deep_equal(installed.wield_anim_career_3p, moveset.WIELD_ANIM_CAREER_3P)
		H.truthy(installed.wield_anim_career_3p ~= moveset.WIELD_ANIM_CAREER_3P,
			"wield table must be a copy, not the module constant")

		H.equal(installed.buffs[moveset.POISON_BUFF_TEMPLATE], nil,
			"template-level poison would duplicate the trait proc owner")
		H.deep_equal(installed.buffs.change_dodge_distance,
			{ external_optional_multiplier = 1.25 },
			"native crowbill dodge buff must survive the clone")

		for action_name, group in pairs(installed.actions) do
			for sub_action_name, sub_action in pairs(group) do
				H.deep_equal(sub_action.lookup_data, {
					item_template_name = moveset.TEMPLATE,
					action_name = action_name,
					sub_action_name = sub_action_name,
				})
			end
		end
	end)

	H.test("WOC Blightreaper impact constants match the Greataxe family", function()
		H.equal(moveset.SOURCE_ITEM, "bw_1h_crowbill")
		H.equal(moveset.SOURCE_TEMPLATE, "one_handed_crowbill")
		H.equal(moveset.GREATAXE_IMPACT_SOUND, "axe_2h_hit")
		H.equal(moveset.GREATAXE_HIT_EFFECT, "melee_hit_axes_2h")
		H.equal(moveset.GREATAXE_ARMOUR_IMPACT_SOUND, "blunt_hit_armour")
		-- Native Greataxe split per 2h_axes.lua: lights = Smiter rows
		-- (:469/:614/:760), heavies = Linesman rows (:189/:328). A 2026-07-22
		-- candidate tried to swap these; the decompiled source disproves it.
		H.equal(moveset.LIGHT_DAMAGE_PROFILE, "medium_slashing_smiter_2h")
		H.equal(moveset.HEAVY_DAMAGE_PROFILE, "heavy_slashing_axe_linesman")
		H.equal(moveset.EXECUTIONER_WWISE_DEP, "wwise/two_handed_swords")
		H.equal(moveset.SPEED_MULTIPLIER, 0.83)
	end)

	H.test("WOC Blightreaper doubles only its own derived sweep cleave", function()
		local action = {
			_max_targets_attack = 2,
			_max_targets_impact = 3,
			_max_targets = 3,
		}
		local applied, reason = moveset.apply_runtime_cleave(action, {
			lookup_data = { item_template_name = moveset.TEMPLATE },
		})
		H.equal(applied, true)
		H.equal(reason, "applied")
		H.equal(action._max_targets_attack, 4)
		H.equal(action._max_targets_impact, 6)
		H.equal(action._max_targets, 6)
		H.equal(moveset.CLEAVE_MULTIPLIER, 2)

		local foreign = {
			_max_targets_attack = 2, _max_targets_impact = 3, _max_targets = 3,
		}
		applied, reason = moveset.apply_runtime_cleave(foreign, {
			lookup_data = { item_template_name = "one_handed_crowbill" },
		})
		H.equal(applied, false)
		H.equal(reason, "foreign_action")
		H.equal(foreign._max_targets_attack, 2)

		applied, reason = moveset.apply_runtime_cleave({}, {
			lookup_data = { item_template_name = moveset.TEMPLATE },
		})
		H.equal(applied, false)
		H.equal(reason, "missing__max_targets_attack")
	end)

	H.test("WOC Blightreaper install is idempotent and fails closed", function()
		local existing = { sentinel = true }
		local weapons = donor_weapons()
		weapons[moveset.TEMPLATE] = existing
		local report = moveset.install(weapons, deep_clone)
		H.truthy(report.installed)
		H.truthy(report.existing)
		H.equal(weapons[moveset.TEMPLATE], existing)

		H.equal(moveset.install(nil, deep_clone).skipped, "tables_unavailable")
		H.equal(moveset.install({}, nil).skipped, "tables_unavailable")
		H.equal(moveset.install({}, deep_clone).skipped, "source_template_missing")
		H.equal(moveset.install({ [moveset.SOURCE_TEMPLATE] = {} }, function()
			return nil
		end).skipped, "clone_failed")
	end)

	H.test("WOC restores only donor-inherited canonical career-action identity", function()
		local canonical = { name = "action_career_es_1" }
		local foreign = { name = "foreign_provider" }
		local source = {
			actions = {
				action_career_es_1 = canonical,
				action_career_dr_1 = foreign,
			},
		}
		local template = deep_clone(source)
		local action_templates = {
				action_career_es_1 = canonical,
				action_career_dr_1 = { name = "action_career_dr_1" },
				action_career_we_1 = { name = "action_career_we_1" },
		}
		local cloned_dr = template.actions.action_career_dr_1
		local report = career_actions.prepare_inherited_clone(
			template, source, action_templates, "woc_private<-crowbill")
		H.equal(report.ok, true)
		H.deep_equal(report.restored_names, { "action_career_es_1" })
		H.equal(template.actions.action_career_es_1, canonical)
		H.equal(template.actions.action_career_dr_1, cloned_dr,
			"a genuine donor/provider mismatch must not be overwritten")
		H.equal(template.actions.action_career_we_1, nil)

		report = career_actions.prepare_inherited_clone(
			template, source, nil, "invalid")
		H.equal(report.ok, false)
		H.equal(report.skipped, "clone_provenance_unavailable")
	end)

	H.test("WOC Blightreaper intrinsic property rows are display-only", function()
		local properties = { properties = {} }
		local buffs = {}
		local ok, reason = moveset.install_intrinsic_property_rows(properties, buffs)
		H.equal(ok, true)
		H.equal(reason, "installed")
		H.equal(properties.properties[moveset.CRIT_PROPERTY].display_name,
			"woc_intrinsic_crit_property")
		H.equal(properties.properties[moveset.ORDER_PROPERTY].display_name,
			"woc_power_vs_order_property")
		H.equal(buffs[moveset.CRIT_PROPERTY_BUFF].buffs[1].name,
			moveset.CRIT_PROPERTY_BUFF)
		H.equal(buffs[moveset.CRIT_PROPERTY_BUFF].buffs[1].stat_buff, nil)
		H.equal(buffs[moveset.ORDER_PROPERTY_BUFF].buffs[1].stat_buff, nil)
		H.equal(moveset.install_intrinsic_property_rows(nil, buffs), false)
	end)

	H.test("WOC Blightreaper 3P remap reuses wt's per-receiver crowbill coverage", function()
		-- Table shape mirrors weapon_tweaker's proven `one_handed_crowbill`
		-- coverage: authored dr_ table, tester-baked es_/wh_ picks, wt's
		-- non-Sienna fallback for everyone else (reaches we_ receivers).
		local expected_shape = { dr_ = 6, es_ = 1, wh_ = 1, _default = 4 }
		for prefix, expected in pairs(expected_shape) do
			local remap = moveset.THIRD_PERSON_REMAP[prefix]
			local count = 0
			for _ in pairs(remap) do count = count + 1 end
			H.equal(count, expected, "remap entry count for " .. prefix)
		end

		H.deep_equal(moveset.THIRD_PERSON_REMAP.dr_, {
			attack_swing_stab                = "attack_swing_down",
			attack_swing_up_left             = "attack_swing_left",
			attack_swing_charge_left         = "attack_swing_charge_left_diagonal",
			attack_swing_heavy_left_up       = "attack_swing_heavy_down",
			attack_swing_charge_left_pose    = "attack_swing_charge_left_diagonal",
			attack_swing_heavy_left_diagonal = "attack_swing_heavy_down",
		})
		H.deep_equal(moveset.THIRD_PERSON_REMAP.es_,
			{ attack_swing_up_left = "attack_swing_left" })
		H.deep_equal(moveset.THIRD_PERSON_REMAP.wh_,
			{ attack_swing_up_left = "attack_swing_left" })
		H.deep_equal(moveset.THIRD_PERSON_REMAP._default, {
			attack_swing_stab                = "attack_swing_down",
			attack_swing_heavy_left_up       = "attack_swing_heavy",
			attack_swing_heavy_left_diagonal = "attack_swing_heavy",
			attack_swing_up_left             = "attack_swing_left",
		})

		-- Per-receiver resolution through the public remap entry point.
		local mapped, changed = moveset.remap_3p(
			"attack_swing_heavy_left_up", "dr_ironbreaker", moveset.TEMPLATE)
		H.equal(mapped, "attack_swing_heavy_down")
		H.equal(changed, true)
		mapped, changed = moveset.remap_3p(
			"attack_swing_up_left", "es_mercenary", moveset.TEMPLATE)
		H.equal(mapped, "attack_swing_left")
		H.equal(changed, true)
		mapped, changed = moveset.remap_3p(
			"attack_swing_stab", "es_mercenary", moveset.TEMPLATE)
		H.equal(mapped, "attack_swing_stab",
			"tester-baked es_ coverage leaves the stab native")
		H.equal(changed, false)
		mapped, changed = moveset.remap_3p(
			"attack_swing_up_left", "wh_priest", moveset.TEMPLATE)
		H.equal(mapped, "attack_swing_left")
		H.equal(changed, true)
		mapped, changed = moveset.remap_3p(
			"attack_swing_stab", "we_waywatcher", moveset.TEMPLATE)
		H.equal(mapped, "attack_swing_down")
		H.equal(changed, true)
		mapped, changed = moveset.remap_3p(
			"attack_swing_heavy_left_up", nil, moveset.TEMPLATE)
		H.equal(mapped, "attack_swing_heavy",
			"unknown career falls back to wt's non-Sienna default")
		H.equal(changed, true)

		-- Sienna's careers own the native vocabulary: never remapped.
		for _, career in ipairs({
			"bw_adept", "bw_scholar", "bw_unchained", "bw_necromancer",
		}) do
			for _, event in ipairs({
				"attack_swing_stab", "attack_swing_up_left",
				"attack_swing_heavy_left_up", "attack_swing_charge_left",
			}) do
				local bw_event, bw_changed = moveset.remap_3p(
					event, career, moveset.TEMPLATE)
				H.equal(bw_event, event)
				H.equal(bw_changed, false)
			end
		end

		-- Foreign template and unknown events pass through untouched.
		local event
		event, changed = moveset.remap_3p("idle", "es_mercenary", moveset.TEMPLATE)
		H.equal(event, "idle")
		H.equal(changed, false)
		event, changed = moveset.remap_3p(
			"attack_swing_stab", "es_mercenary", "another_template")
		H.equal(event, "attack_swing_stab")
		H.equal(changed, false)
	end)

	H.test("WOC Blightreaper wield redirect covers every non-Sienna career", function()
		local expected = {
			es_mercenary = "to_1h_sword", es_huntsman = "to_1h_sword",
			es_knight = "to_1h_sword", es_questingknight = "to_1h_sword",
			dr_ranger = "to_1h_sword", dr_ironbreaker = "to_1h_sword",
			dr_slayer = "to_1h_sword", dr_engineer = "to_1h_sword",
			we_waywatcher = "to_1h_sword", we_maidenguard = "to_1h_sword",
			we_shade = "to_1h_sword", we_thornsister = "to_1h_sword",
			wh_captain = "to_1h_sword", wh_bountyhunter = "to_1h_sword",
			wh_zealot = "to_1h_sword",
			wh_priest = "to_1h_hammer",
		}
		H.deep_equal(moveset.WIELD_ANIM_CAREER_3P, expected)
		for career in pairs(moveset.WIELD_ANIM_CAREER_3P) do
			H.equal(career:sub(1, 3) ~= moveset.NATIVE_3P_PREFIX, true,
				"bw_ careers must stay on the native wield_anim fallback")
		end
	end)

	H.test("WOC Blightreaper poison uses the native on-hit DOT contract", function()
		local descriptor = moveset.poison_buff_descriptor()
		local buff = descriptor.buffs[1]
		H.equal(buff.buff_func, moveset.POISON_PROC)
		H.equal(moveset.DOT_TEMPLATE, "arrow_poison_dot")
		H.equal(buff.event, "on_hit")
		H.equal(buff.name, moveset.POISON_BUFF_TEMPLATE)

		local second = moveset.poison_buff_descriptor()
		H.truthy(second ~= descriptor)
		H.truthy(second.buffs[1] ~= buff)

		local templates = {}
		local installed, reason = moveset.install_poison_buff(templates)
		H.equal(installed, true)
		H.equal(reason, "installed")
		H.deep_equal(templates[moveset.POISON_BUFF_TEMPLATE], descriptor)

		local existing = templates[moveset.POISON_BUFF_TEMPLATE]
		installed, reason = moveset.install_poison_buff(templates)
		H.equal(installed, true)
		H.equal(reason, "existing")
		H.equal(templates[moveset.POISON_BUFF_TEMPLATE], existing)

		installed, reason = moveset.install_poison_buff(nil)
		H.equal(installed, false)
		H.equal(reason, "buff_templates_unavailable")
	end)

	H.test("WOC Blightreaper intrinsic traits own poison and Shyish presentation", function()
		local weapon_traits = { traits = {} }
		local buffs = {}
		local ok, reason = moveset.install_intrinsic_trait_rows(weapon_traits, buffs)
		H.equal(ok, true)
		H.equal(reason, "installed")
		local poison = weapon_traits.traits[moveset.POISON_TRAIT]
		local curse = weapon_traits.traits[moveset.SHYISH_CURSE_TRAIT]
		H.equal(poison.buff_name, moveset.POISON_BUFF_TEMPLATE)
		H.equal(poison.icon, moveset.POISON_TRAIT_ICON)
		H.equal(curse.icon, "mutator_icon_death_spirits")
		H.equal(curse.crafting_disabled, true)
		H.equal(buffs[moveset.SHYISH_CURSE_BUFF].buffs[1].stat_buff, nil)
		H.deep_equal(moveset.intrinsic_traits(), {
			moveset.POISON_TRAIT, moveset.SHYISH_CURSE_TRAIT,
		})
		H.truthy(moveset.item_has_trait({ traits = moveset.intrinsic_traits() },
			moveset.POISON_TRAIT))
		H.equal(moveset.item_has_trait({}, moveset.POISON_TRAIT), false)
		H.equal(moveset.install_intrinsic_trait_rows(nil, buffs), false)
	end)
end
