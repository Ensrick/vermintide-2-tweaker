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

	local function donor_template()
		return {
			name = moveset.SOURCE_TEMPLATE,
			wwise_dep_right_hand = { "wwise/one_handed_swords" },
			actions = {
				action_one = {
					default = {
						kind = "melee_start",
						anim_event = "attack_swing_charge_left",
						anim_time_scale = 2,
						damage_profile = "light_slashing_smiter",
						lookup_data = { item_template_name = "donor" },
						allowed_chain_actions = {},
					},
					default_left = {
						kind = "melee_start",
						anim_event = "attack_swing_charge_left",
						allowed_chain_actions = {
							{ action = "action_one", input = "action_one_release",
								sub_action = "light_attack_last" },
							{ action = "action_one", input = "action_one_hold",
								sub_action = "heavy_attack_left" },
						},
					},
					light_attack = {
						kind = "sweep",
						anim_event = "attack_swing_heavy",
						damage_profile = "light_slashing_smiter",
						allowed_chain_actions = {},
					},
					light_attack_last = {
						kind = "sweep",
						anim_event = "attack_swing_stab",
						damage_profile = "light_slashing_smiter_stab_swords",
						allowed_chain_actions = {},
					},
					heavy_attack_left = {
						kind = "sweep",
						anim_event = "attack_swing_heavy_right",
						damage_profile = "heavy_slashing_smiter",
						allowed_chain_actions = {
							{ action = "action_one", input = "action_one",
								sub_action = "default" },
						},
					},
					block = {
						kind = "block",
						anim_time_scale = 0.8,
					},
				},
				action_two = {
					push = {
						kind = "push_stagger",
						anim_time_scale = 1.4,
						damage_profile = { internal = "must_not_be_cloned_or_rewritten" },
					},
				},
			},
		}
	end

	local function overhead_template()
		return {
			actions = {
				action_one = {
					light_attack_last = {
						kind = "sweep",
						anim_event = "attack_swing_down",
						damage_profile = "sword_1h_light_smiter_vertical",
						baked_sweep = { { 0.1, 1, 2, 3 } },
						allowed_chain_actions = {
							{ action = "action_one", input = "action_one",
								sub_action = "default" },
						},
					},
				},
			},
		}
	end

	local function donor_weapons(donor)
		return {
			[moveset.SOURCE_TEMPLATE] = donor or donor_template(),
			[moveset.OVERHEAD_SOURCE_TEMPLATE] = overhead_template(),
		}
	end

	H.test("WOC Blightreaper deep-clones elf Sword without damage-profile mutation", function()
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
		H.equal(report.attacks, 7)
		H.equal(clone_was_deep, true)
		H.truthy(installed ~= donor)
		H.deep_equal(donor, snapshot, "donor template changed")
		H.equal(installed.name, moveset.TEMPLATE)
		H.equal(installed.actions.action_one.default.anim_time_scale, 1.5)
		H.equal(installed.actions.action_one.light_attack.anim_time_scale, 0.75)
		H.equal(installed.actions.action_one.default.anim_event,
			"attack_swing_charge_left_diagonal")
		H.equal(installed.actions.action_one.light_attack.anim_event,
			"attack_swing_heavy_down")
		H.equal(installed.actions.action_one.light_attack.impact_sound_event,
			"axe_2h_hit")
		H.equal(installed.actions.action_one.light_attack.hit_effect,
			"melee_hit_axes_2h")
		H.equal(installed.actions.action_one.light_attack.no_damage_impact_sound_event,
			"blunt_hit_armour")
		H.equal(installed.actions.action_one.block.anim_time_scale, 0.8)
		H.equal(installed.actions.action_two.push.anim_time_scale, 1.4)
		H.equal(installed.buffs[moveset.POISON_BUFF_TEMPLATE], nil,
			"template-level poison would duplicate the trait proc owner")
		H.equal(installed.actions.action_one.default.damage_profile,
			"light_slashing_smiter")
		H.equal(installed.actions.action_one.light_attack.damage_profile,
			moveset.LIGHT_DAMAGE_PROFILE)
		H.equal(installed.actions.action_one.light_attack_last.anim_event,
			"attack_swing_down")
		H.equal(installed.actions.action_one.light_attack_last.damage_profile,
			moveset.LIGHT_DAMAGE_PROFILE)
		H.equal(installed.actions.action_one.light_attack_stab.damage_profile,
			moveset.LIGHT_DAMAGE_PROFILE)
		H.equal(installed.actions.action_one.heavy_attack_left.damage_profile,
			moveset.HEAVY_DAMAGE_PROFILE)
		H.equal(installed.actions.action_one.light_attack.additional_critical_strike_chance,
			moveset.INTRINSIC_CRIT_CHANCE)
		H.equal(installed.actions.action_one.heavy_attack_left.additional_critical_strike_chance,
			moveset.INTRINSIC_CRIT_CHANCE)
		H.equal(installed.actions.action_one.default_stab.allowed_chain_actions[1].sub_action,
			"light_attack_stab")
		H.equal(installed.actions.action_one.light_attack_last.allowed_chain_actions[1].sub_action,
			"default_stab")
		H.equal(installed.actions.action_one.heavy_attack_left.allowed_chain_actions[1].sub_action,
			"default_left")
		H.deep_equal(installed.actions.action_one.light_attack_last.baked_sweep,
			{ { 0.1, 1, 2, 3 } })
		H.deep_equal(installed.wwise_dep_right_hand,
			{ "wwise/one_handed_swords", moveset.EXECUTIONER_WWISE_DEP })
		H.deep_equal(installed.actions.action_two.push.damage_profile,
			{ internal = "must_not_be_cloned_or_rewritten" })

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

	H.test("WOC Blightreaper audio uses Greataxe impacts and 1H Axe-safe swings", function()
		H.equal(moveset.GREATAXE_IMPACT_SOUND, "axe_2h_hit")
		H.equal(moveset.GREATAXE_HIT_EFFECT, "melee_hit_axes_2h")
		H.equal(moveset.AXE_ARMOUR_IMPACT_SOUND, "blunt_hit_armour")
		H.equal(moveset.ONE_HAND_AXE_SWING_REMAP.attack_swing_charge_left,
			"attack_swing_charge_left_diagonal")
		H.equal(moveset.ONE_HAND_AXE_SWING_REMAP.attack_swing_charge_right_pose,
			"attack_swing_charge_right_diagonal_pose")
		H.equal(moveset.ONE_HAND_AXE_SWING_REMAP.attack_swing_charge_left_pose,
			"attack_swing_charge_left_diagonal_pose")
		H.equal(moveset.ONE_HAND_AXE_SWING_REMAP.attack_swing_heavy,
			"attack_swing_heavy_down")
		H.equal(moveset.ONE_HAND_AXE_SWING_REMAP.attack_swing_heavy_right,
			"attack_swing_heavy_down_right")
		H.equal(moveset.ONE_HAND_AXE_SWING_REMAP.attack_swing_right,
			"attack_swing_right_diagonal")
		H.equal(moveset.ONE_HAND_AXE_SWING_REMAP.attack_swing_down,
			"attack_swing_left")
		H.equal(moveset.ONE_HAND_AXE_SWING_REMAP.attack_swing_right_diagonal,
			"attack_swing_down_right")
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
			template, source, action_templates, "woc_private<-elf_sword")
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

	H.test("WOC Blightreaper has exactly six non-elf third-person remaps", function()
		local count = 0
		for source_event, target_event in pairs(moveset.THIRD_PERSON_REMAP) do
			count = count + 1
			local mapped, changed = moveset.remap_3p(
				source_event, "es_mercenary", moveset.TEMPLATE)
			H.equal(mapped, target_event)
			H.equal(changed, true)

			local elf_event, elf_changed = moveset.remap_3p(
				source_event, "we_waywatcher", moveset.TEMPLATE)
			H.equal(elf_event, source_event)
			H.equal(elf_changed, false)
		end
		H.equal(count, 6)

		local event, changed = moveset.remap_3p(
			"idle", "es_mercenary", moveset.TEMPLATE)
		H.equal(event, "idle")
		H.equal(changed, false)
		event, changed = moveset.remap_3p(
			"attack_swing_stab", "es_mercenary", "another_template")
		H.equal(event, "attack_swing_stab")
		H.equal(changed, false)
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
