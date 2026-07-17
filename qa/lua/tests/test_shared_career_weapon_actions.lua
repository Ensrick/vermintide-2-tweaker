return function(H, repo_root)
	local integration = dofile(repo_root
		.. "/tools/shared_lib/_lib_career_weapon_actions.lua")

	local careers = {
		"dr_ranger", "we_waywatcher", "wh_bountyhunter", "bw_scholar",
		"es_questingknight", "dr_engineer", "we_thornsister", "wh_priest",
		"bw_necromancer",
	}
	local by_career = {
		dr_ranger = { "action_career_dr_3" },
		we_waywatcher = {
			"action_career_we_3", "action_career_we_3_piercing",
		},
		wh_bountyhunter = { "action_career_wh_2" },
		bw_scholar = { "action_career_bw_1" },
		es_questingknight = { "action_career_es_4" },
		dr_engineer = { "action_career_dr_4" },
		we_thornsister = { "action_career_we_thornsister" },
		wh_priest = { "action_career_wh_priest" },
		bw_necromancer = { "action_career_bw_necromancer" },
	}
	local career_settings, action_templates = {}, {}
	for career, names in pairs(by_career) do
		local abilities = {}
		for _, name in ipairs(names) do
			abilities[#abilities + 1] = { action_name = name }
			action_templates[name] = { name = name }
		end
		career_settings[career] = { activated_ability = abilities }
	end

	H.test("career weapon actions install the full vanilla weapon-bound matrix", function()
		local existing = action_templates.action_career_dr_3
		local template = { actions = { action_career_dr_3 = existing } }
		local report = integration.install(
			template, careers, career_settings, action_templates)
		H.equal(report.ok, true)
		H.equal(report.required, 10)
		H.equal(report.installed, 9)
		H.equal(report.existing, 1)
		H.equal(template.actions.action_career_dr_3, existing)
		for _, names in pairs(by_career) do
			for _, name in ipairs(names) do
				H.equal(template.actions[name], action_templates[name], name)
			end
		end
	end)

	H.test("career weapon actions include alternate ability rows", function()
		local template = { actions = {} }
		local report = integration.install(template, { "we_waywatcher" },
			career_settings, action_templates)
		H.equal(report.ok, true)
		H.equal(report.required, 2)
		H.equal(template.actions.action_career_we_3,
			action_templates.action_career_we_3)
		H.equal(template.actions.action_career_we_3_piercing,
			action_templates.action_career_we_3_piercing)
	end)

	H.test("career weapon actions fail loudly on incomplete providers", function()
		local report = integration.install({ actions = {} },
			{ "missing_career" }, career_settings, action_templates)
		H.equal(report.ok, false)
		H.deep_equal(report.missing_careers, { "missing_career" })

		local broken = { dr_ranger = career_settings.dr_ranger }
		report = integration.install({ actions = {} }, { "dr_ranger" }, broken, {})
		H.equal(report.ok, false)
		H.deep_equal(report.missing_actions, { "action_career_dr_3" })
	end)

	H.test("career weapon action claims survive another provider releasing", function()
		-- Separate dofile results simulate the standalone copy bundled by each
		-- mod. Coordination must therefore live on the shared template, not in
		-- module-local state.
		local other = dofile(repo_root
			.. "/tools/shared_lib/_lib_career_weapon_actions.lua")
		local template = { actions = {} }
		local first = integration.install(template, { "dr_ranger" },
			career_settings, action_templates, "weapon_tweaker")
		local second = other.install(template, { "dr_ranger" },
			career_settings, action_templates, "weapons_of_chaos")
		H.equal(first.installed, 1)
		H.equal(second.existing, 1)
		H.equal(first.claimed, 1)
		H.equal(second.claimed, 1)

		local released = integration.release(template, "weapon_tweaker")
		H.deep_equal(released.retained_names, { "action_career_dr_3" })
		H.equal(template.actions.action_career_dr_3,
			action_templates.action_career_dr_3)
		released = other.release(template, "weapons_of_chaos")
		H.deep_equal(released.removed_names, { "action_career_dr_3" })
		H.equal(template.actions.action_career_dr_3, nil)
	end)

	H.test("career weapon action release preserves native and external rows", function()
		local native = action_templates.action_career_dr_3
		local template = { actions = { action_career_dr_3 = native } }
		integration.install(template, { "dr_ranger" }, career_settings,
			action_templates, "weapon_tweaker")
		integration.release(template, "weapon_tweaker")
		H.equal(template.actions.action_career_dr_3, native)

		template = { actions = {} }
		integration.install(template, { "dr_ranger" }, career_settings,
			action_templates, "weapon_tweaker")
		local replacement = { name = "external_replacement" }
		template.actions.action_career_dr_3 = replacement
		local released = integration.release(template, "weapon_tweaker")
		H.deep_equal(released.changed_names, { "action_career_dr_3" })
		H.equal(template.actions.action_career_dr_3, replacement)
	end)

	H.test("career weapon action reconciliation is idempotent per owner", function()
		local template = { actions = {} }
		for _ = 1, 3 do
			local report = integration.install(template, { "dr_ranger" },
				career_settings, action_templates, "weapon_tweaker")
			H.equal(report.claimed, 1)
		end
		local released = integration.release(template, "weapon_tweaker")
		H.deep_equal(released.removed_names, { "action_career_dr_3" })
		H.equal(template.actions.action_career_dr_3, nil)
	end)

	H.test("career weapon actions reject conflicting provider rows", function()
		local template = {
			actions = { action_career_dr_3 = { name = "wrong_provider" } },
		}
		local report = integration.install(template, { "dr_ranger" },
			career_settings, action_templates, "weapon_tweaker")
		H.equal(report.ok, false)
		H.deep_equal(report.conflicting_names, { "action_career_dr_3" })
	end)

	H.test("WOC #690 reconciles deep-cloned native actions before claiming them", function()
		local moveset = dofile(repo_root
			.. "/weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_blightreaper_moveset.lua")
		local canonical = action_templates.action_career_dr_3
		local donor = { actions = { action_career_dr_3 = canonical } }
		-- Simulate `table.clone(donor, true)`: structurally identical, but the
		-- executable career-action row no longer has canonical table identity.
		local private = {
			actions = {
				action_career_dr_3 = { name = canonical.name },
			},
		}
		local before = integration.install(private, { "dr_ranger" },
			career_settings, action_templates, "weapons_of_chaos")
		H.equal(before.ok, false)
		H.deep_equal(before.conflicting_names, { "action_career_dr_3" })

		local required = integration.collect({ "dr_ranger" },
			career_settings, action_templates)
		local restored = moveset.restore_inherited_career_action_identity(
			private, donor, required)
		H.equal(restored.ok, true)
		H.deep_equal(restored.restored_names, { "action_career_dr_3" })
		local after = integration.install(private, { "dr_ranger" },
			career_settings, action_templates, "weapons_of_chaos")
		H.equal(after.ok, true)
		H.equal(after.claimed, 1)
		H.equal(private.actions.action_career_dr_3, canonical)
	end)

	H.test("CWV reconciles every authored career after late item registration", function()
		local cwv = dofile(repo_root
			.. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_career_weapon_actions.lua")
		local template = { actions = {} }
		local items = {
			cwv_late_a = {
				template = "shared_private",
				can_wield = { "dr_ranger", "we_waywatcher" },
			},
		}
		local pending = { { def = { item_key = "cwv_late_a" } } }
		local report = cwv.install(pending, items,
			{ shared_private = template }, career_settings, action_templates,
			integration, "character_weapon_variants")
		H.equal(report.ok, true)
		H.equal(report.template_count, 1)
		H.equal(template.actions.action_career_dr_3,
			action_templates.action_career_dr_3)
		H.equal(template.actions.action_career_we_3,
			action_templates.action_career_we_3)
		H.equal(template.actions.action_career_we_3_piercing,
			action_templates.action_career_we_3_piercing)
	end)

	H.test("WT stable, dev, and WOC consume the provider-neutral integration", function()
		local function read(relative)
			local file = assert(io.open(repo_root .. "/" .. relative, "rb"))
			local source = file:read("*a")
			file:close()
			return source
		end
		local wt = read("weapon_tweaker/scripts/mods/weapon_tweaker/_wt_availability.lua")
		local wt_dev = read("weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/_wt_availability.lua")
		local wt_backend = read("weapon_tweaker/scripts/mods/weapon_tweaker/weapon_tweaker_backend.lua")
		local wt_dev_backend = read("weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/weapon_tweaker_backend.lua")
		local cwv = read("character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants.lua")
		local woc = read("weapons_of_chaos/scripts/mods/weapons_of_chaos/weapons_of_chaos.lua")
		H.truthy(wt:find("_career_weapon_actions.install", 1, true))
		H.truthy(wt_dev:find("_career_weapon_actions.install", 1, true))
		H.truthy(cwv:find("_cwv_career_weapon_actions.install", 1, true))
		H.truthy(woc:find("_career_weapon_actions.install", 1, true))
		H.equal(wt:find("activated_ability and cs.activated_ability[1]", 1, true), nil)
		H.equal(wt_dev:find("activated_ability and cs.activated_ability[1]", 1, true), nil)
		H.equal(cwv:find("ability = ability and ability[1]", 1, true), nil)
		H.truthy(wt:find("_career_weapon_actions.release", 1, true))
		H.truthy(wt_dev:find("_career_weapon_actions.release", 1, true))
		for _, source in ipairs({ wt_backend, wt_dev_backend }) do
			local deferred = source:match(
				"if mod%._wt368_deferred_availability then(.-)\n%s*end")
			H.truthy(deferred)
			local availability = deferred:find("apply_weapon_unlocks()", 1, true)
			local actions = deferred:find("patch_career_actions_on_weapons()", 1, true)
			H.truthy(availability)
			H.truthy(actions)
			H.truthy(availability < actions)
		end
	end)
end
