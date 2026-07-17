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

	H.test("WT stable, dev, and WOC consume the provider-neutral integration", function()
		local function read(relative)
			local file = assert(io.open(repo_root .. "/" .. relative, "rb"))
			local source = file:read("*a")
			file:close()
			return source
		end
		local wt = read("weapon_tweaker/scripts/mods/weapon_tweaker/_wt_availability.lua")
		local wt_dev = read("weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/_wt_availability.lua")
		local woc = read("weapons_of_chaos/scripts/mods/weapons_of_chaos/weapons_of_chaos.lua")
		H.truthy(wt:find("_career_weapon_actions.install", 1, true))
		H.truthy(wt_dev:find("_career_weapon_actions.install", 1, true))
		H.truthy(woc:find("_career_weapon_actions.install", 1, true))
		H.equal(wt:find("activated_ability and cs.activated_ability[1]", 1, true), nil)
		H.equal(wt_dev:find("activated_ability and cs.activated_ability[1]", 1, true), nil)
	end)
end
