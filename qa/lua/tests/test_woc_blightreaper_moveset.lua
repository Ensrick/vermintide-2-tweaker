return function(H, repo_root)
	local moveset = dofile(repo_root
		.. "/weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_blightreaper_moveset.lua")

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
			actions = {
				action_one = {
					default = {
						kind = "melee_start",
						anim_time_scale = 2,
						damage_profile = "light_slashing_smiter",
						lookup_data = { item_template_name = "donor" },
					},
					light_attack = {
						kind = "sweep",
						damage_profile = "light_slashing_smiter",
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

	H.test("WOC Blightreaper deep-clones elf Sword without damage-profile mutation", function()
		local donor = donor_template()
		local snapshot = deep_clone(donor)
		local weapons = { [moveset.SOURCE_TEMPLATE] = donor }
		local clone_was_deep = false
		local report = moveset.install(weapons, function(value, deep)
			clone_was_deep = deep
			return deep_clone(value)
		end)
		local installed = weapons[moveset.TEMPLATE]

		H.truthy(report.installed)
		H.equal(report.attacks, 2)
		H.equal(clone_was_deep, true)
		H.truthy(installed ~= donor)
		H.deep_equal(donor, snapshot, "donor template changed")
		H.equal(installed.name, moveset.TEMPLATE)
		H.equal(installed.actions.action_one.default.anim_time_scale, 1.5)
		H.equal(installed.actions.action_one.light_attack.anim_time_scale, 0.75)
		H.equal(installed.actions.action_one.block.anim_time_scale, 0.8)
		H.equal(installed.actions.action_two.push.anim_time_scale, 1.4)
		H.truthy(installed.buffs[moveset.POISON_BUFF_TEMPLATE] ~= nil)
		H.equal(installed.actions.action_one.default.damage_profile,
			"light_slashing_smiter")
		H.equal(installed.actions.action_one.light_attack.damage_profile,
			"light_slashing_smiter")
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

	H.test("WOC Blightreaper install is idempotent and fails closed", function()
		local existing = { sentinel = true }
		local weapons = {
			[moveset.SOURCE_TEMPLATE] = donor_template(),
			[moveset.TEMPLATE] = existing,
		}
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
end
