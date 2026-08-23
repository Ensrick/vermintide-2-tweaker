return function(H, repo_root)
	local runtime_path = repo_root
		.. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_crowbill_runtime.lua"
	local runtime = dofile(runtime_path)
	local family = dofile(repo_root
		.. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_crowbill_family.lua")
	local policy = dofile(repo_root
		.. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_crowbill_hammer_mode.lua")
	local function read(path)
		local file = assert(io.open(path, "rb"))
		local value = file:read("*a")
		file:close()
		return value
	end

	H.test("CWV #798 runtime classifies every Crowbill family member implicitly", function()
		local cases = {
			{
				label = "Sienna Crowbill direct on Kruber",
				expected_key = family.SOURCE_ITEM,
				expected_identity = "kruber-sienna-direct",
				item = {
					backend_id = "kruber-sienna-direct",
					name = family.SOURCE_ITEM,
					template = family.SOURCE_TEMPLATE,
				},
			},
			{
				label = "Sienna Crowbill wrapped on Kruber",
				expected_key = family.SOURCE_ITEM,
				expected_identity = "kruber-sienna-wrapped",
				item = {
					backend_id = "kruber-sienna-wrapped",
					data = {
						backend_id = "sienna-donor-row",
						name = family.SOURCE_ITEM,
						template = family.SOURCE_TEMPLATE,
					},
				},
			},
			{
				label = "Imperial Crowbill direct on Sienna",
				expected_key = "cwv_es_imperial_crowbill",
				expected_identity = "sienna-imperial-direct",
				item = {
					backend_id = "sienna-imperial-direct",
					cwv_key = "cwv_es_imperial_crowbill",
					template = family.SOURCE_TEMPLATE,
				},
			},
			{
				label = "Imperial Crowbill wrapped on Bardin",
				expected_key = "cwv_es_imperial_crowbill",
				expected_identity = "bardin-imperial-wrapped",
				item = {
					backend_id = "bardin-imperial-wrapped",
					data = {
						backend_id = "imperial-donor-row",
						cwv_key = "cwv_es_imperial_crowbill",
						template = family.SOURCE_TEMPLATE,
					},
				},
			},
			{
				label = "Dawi Crowbill direct on Kruber",
				expected_key = "cwv_dr_dawi_crowbill",
				expected_identity = "kruber-dawi-direct",
				item = {
					backend_id = "kruber-dawi-direct",
					cwv_key = "cwv_dr_dawi_crowbill",
					template = family.SOURCE_TEMPLATE,
				},
			},
			{
				label = "Dawi Crowbill wrapped on Sienna",
				expected_key = "cwv_dr_dawi_crowbill",
				expected_identity = "sienna-dawi-wrapped",
				item = {
					backend_id = "sienna-dawi-wrapped",
					data = {
						backend_id = "dawi-donor-row",
						cwv_key = "cwv_dr_dawi_crowbill",
						template = family.SOURCE_TEMPLATE,
					},
				},
			},
		}
		for _, case in ipairs(cases) do
			local key, identity = runtime.classify(family, case.item, nil, nil)
			H.equal(key, case.expected_key, case.label .. " family")
			H.equal(identity, case.expected_identity, case.label .. " exact instance")
		end
	end)

	H.test("CWV #798 runtime preserves vanilla backend identity precedence", function()
		local wrapped = {
			backend_id = "outer-exact",
			data = {
				backend_id = "nested-donor",
				name = family.SOURCE_ITEM,
				template = family.SOURCE_TEMPLATE,
			},
		}
		local key, identity = runtime.classify(family, wrapped, "explicit-fallback", nil)
		H.equal(key, family.SOURCE_ITEM)
		H.equal(identity, "outer-exact",
			"item_data.backend_id must win over explicit fallback and nested donor")

		wrapped.backend_id = nil
		key, identity = runtime.classify(family, wrapped, "explicit-fallback", nil)
		H.equal(key, family.SOURCE_ITEM)
		H.equal(identity, "explicit-fallback",
			"explicit backend_id must win over a wrapped donor backend_id")
	end)

	H.test("CWV #604 wire envelope is fixed bounded and closed vocabulary", function()
		H.equal(runtime.valid_wire(policy, family, 1, "query", "", "", "", ""), true)
		H.equal(runtime.valid_wire(policy, family, 1, "state", "slot_melee", "hammer",
			"cwv_es_imperial_crowbill:123:slot_melee", "cwv_es_imperial_crowbill"), true)
		H.equal(runtime.valid_wire(policy, family, 2, "state", "slot_melee", "hammer",
			"id", "cwv_es_imperial_crowbill"), false)
		H.equal(runtime.valid_wire(policy, family, 1, "state", "slot_ranged", "hammer",
			"id", "cwv_es_imperial_crowbill"), false)
		H.equal(runtime.valid_wire(policy, family, 1, "state", "slot_melee", "axe",
			"id", "cwv_es_imperial_crowbill"), false)
		H.equal(runtime.valid_wire(policy, family, 1, "state", "slot_melee", "hammer",
			string.rep("x", 97), "cwv_es_imperial_crowbill"), false)
		H.equal(runtime.valid_wire(policy, family, 1, "state", "slot_melee", "hammer",
			"id", "cwv_fake_crowbill"), false)
	end)

	H.test("CWV #604 runtime owns transition hooks without polling or a vanilla RPC", function()
		local source = read(runtime_path)
		for _, marker in ipairs({
			"policy.build_pick_template(",
			"policy.build_hammer_template(",
			"template.actions.action_three",
			"mod:network_register(policy.CHANNEL",
			"state:apply_remote({",
			"M.request_states(\"peer_parity\")",
			"mod._cwv_old_musket_interrupt.install(template, \"action_three\")",
		}) do
			H.truthy(source:find(marker, 1, true), "missing runtime marker: " .. marker)
		end
		H.equal(source:find("mod.update", 1, true), nil)
		H.equal(source:find("network_transmit", 1, true), nil)
		H.equal(source:find("rpc_", 1, true), nil)
	end)

	H.test("CWV #604 main composes one template resolver and lifecycle owner", function()
		local source = require("cwv_source").combined(repo_root)
		for _, marker in ipairs({
			'_cwv_crowbill_runtime")',
			"_om.crowbill_runtime.install(mod, _om)",
			"_om.crowbill_runtime.resolve_template(item_data, backend_id)",
			"_om.crowbill_runtime.on_local_wield(self, slot_name, item_data)",
			"_om.crowbill_runtime.on_husk_wield(self, slot_name)",
			"_om.crowbill_runtime.request_states(\"game_state_enter:",
			"_om.crowbill_runtime.set_enabled(false)",
		}) do
			H.truthy(source:find(marker, 1, true), "missing main integration: " .. marker)
		end
		local _, backend_hooks = source:gsub('mod:hook%("BackendUtils", "get_item_template"', "")
		H.equal(backend_hooks, 1)
	end)

	H.test("CWV #798 retired vanilla setting cannot gate family enrollment", function()
		local data = read(repo_root
			.. "/character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants_data.lua")
		local localization = read(repo_root
			.. "/character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants_localization.lua")
		local main = require("cwv_source").combined(repo_root)
		for _, source in ipairs({ data, localization, main }) do
			H.equal(source:find("enable_cwv_vanilla_crowbill_hammer_mode", 1, true), nil)
		end
		H.equal(runtime.VANILLA_SETTING_ID, nil)
	end)

	H.test("CWV #604 install registers two templates and exact Weapon Special lookup", function()
		local function clone(value, seen)
			if type(value) ~= "table" then return value end
			seen = seen or {}
			if seen[value] then return seen[value] end
			local copy = {}
			seen[value] = copy
			for key, child in pairs(value) do copy[clone(key, seen)] = clone(child, seen) end
			return copy
		end
		local saved = {
			Weapons = _G.Weapons,
			DamageProfileTemplates = _G.DamageProfileTemplates,
			PowerLevelTemplates = _G.PowerLevelTemplates,
			NetworkLookup = _G.NetworkLookup,
			clone = table.clone,
		}
		local action_one, damage_profiles, power_levels = {}, {}, {}
		for action_name, class in pairs(policy.DIRECT_ACTIONS) do
			local profile = "fixture_" .. action_name
			action_one[action_name] = {
				kind = "sweep", damage_profile = profile, anim_time_scale = 1.1, total_time = 1.5,
				allowed_chain_actions = {},
			}
			damage_profiles[profile] = {
				cleave_distribution = "cleave_" .. profile,
				armor_modifier = "armor_" .. profile,
				default_target = "target_" .. profile,
				targets = "targets_" .. profile,
			}
			power_levels["cleave_" .. profile] = { attack = 1, impact = 1 }
			power_levels["armor_" .. profile] = { attack = { 1, 0.5, 1, 1, 1, 0.5 } }
			power_levels["target_" .. profile] = { power_distribution = { attack = 1, impact = 1 } }
			power_levels["targets_" .. profile] = {
				{ power_distribution = { attack = 1, impact = 1 } },
			}
		end
		_G.Weapons = { one_handed_crowbill = { actions = { action_one = action_one } } }
		_G.DamageProfileTemplates = damage_profiles
		_G.PowerLevelTemplates = power_levels
		_G.NetworkLookup = { damage_profiles = {} }
		table.clone = function(value) return clone(value) end
		local registered
		local fake_mod = {
			_cwv_old_musket_interrupt = {
				install = function(template)
					for _, action in pairs(template.actions.action_one) do
						action.allowed_chain_actions[#action.allowed_chain_actions + 1] = {
							action = "action_three", input = "action_three", start_time = 0,
						}
					end
				end,
			},
			-- A stale retired preference may still exist in VMF persistence. The
			-- runtime must never consult it.
			get = function() error("retired Crowbill setting was read") end,
			network_register = function(self, channel, callback)
				registered = { channel = channel, callback = callback }
			end,
		}
		local om = {
			crowbill_hammer_mode = policy,
			crowbill_family = family,
			_record_cwv_dp_source = function() end,
			_cwv_key_for_item = function(_, item)
				return item.cwv_key or (item.data and item.data.cwv_key)
			end,
		}
		local installed, err = runtime.install(fake_mod, om)
		H.truthy(installed, err)
		H.truthy(_G.Weapons.cwv_crowbill_hammer_template)
		H.equal(_G.Weapons.one_handed_crowbill.actions.action_three, nil)
		H.equal(_G.Weapons.cwv_crowbill_pick_template.actions.action_three.default.lookup_data.item_template_name,
			"cwv_crowbill_pick_template")
		H.equal(_G.Weapons.cwv_crowbill_hammer_template.actions.action_three.default.lookup_data.item_template_name,
			"cwv_crowbill_hammer_template")
		H.equal(registered.channel, policy.CHANNEL)
		local pick_cases = {
			{
				label = "Sienna native Crowbill normal face keeps burning donor",
				item = {
					name = family.SOURCE_ITEM,
					template = family.SOURCE_TEMPLATE,
					backend_id = "native-pick-test-001",
					mod_data = { cwv_crowbill_mode = "crowbill" },
				},
				expected = _G.Weapons.one_handed_crowbill,
			},
			{
				label = "Imperial Crowbill normal face uses non-burning pick clone",
				item = {
					cwv_key = "cwv_es_imperial_crowbill",
					backend_id = "imperial-pick-test-001",
					mod_data = { cwv_crowbill_mode = "crowbill" },
				},
				expected = _G.Weapons.cwv_crowbill_pick_template,
			},
			{
				label = "Dawi Crowbill normal face uses non-burning pick clone",
				item = {
					cwv_key = "cwv_dr_dawi_crowbill",
					backend_id = "dawi-pick-test-001",
					mod_data = { cwv_crowbill_mode = "crowbill" },
				},
				expected = _G.Weapons.cwv_crowbill_pick_template,
			},
		}
		for _, case in ipairs(pick_cases) do
			H.equal(runtime.resolve_template(case.item), case.expected, case.label)
		end
		local hammer_cases = {
			{
				label = "Sienna Crowbill direct",
				item = {
					name = family.SOURCE_ITEM,
					template = family.SOURCE_TEMPLATE,
					backend_id = "native-direct-test-001",
					mod_data = { cwv_crowbill_mode = "hammer" },
				},
			},
			{
				label = "Sienna Crowbill wrapped",
				item = {
					backend_id = "native-wrapped-test-001",
					data = {
						name = family.SOURCE_ITEM,
						template = family.SOURCE_TEMPLATE,
						mod_data = { cwv_crowbill_mode = "hammer" },
					},
				},
			},
			{
				label = "Imperial Crowbill direct",
				item = {
					cwv_key = "cwv_es_imperial_crowbill",
					backend_id = "imperial-direct-test-001",
					mod_data = { cwv_crowbill_mode = "hammer" },
				},
			},
			{
				label = "Imperial Crowbill wrapped",
				item = {
					backend_id = "imperial-wrapped-test-001",
					mod_data = { cwv_crowbill_mode = "hammer" },
					data = { cwv_key = "cwv_es_imperial_crowbill" },
				},
			},
			{
				label = "Dawi Crowbill direct",
				item = {
					cwv_key = "cwv_dr_dawi_crowbill",
					backend_id = "dawi-direct-test-001",
					mod_data = { cwv_crowbill_mode = "hammer" },
				},
			},
			{
				label = "Dawi Crowbill wrapped",
				item = {
					backend_id = "dawi-wrapped-test-001",
					data = {
						cwv_key = "cwv_dr_dawi_crowbill",
						mod_data = { cwv_crowbill_mode = "hammer" },
					},
				},
			},
		}
		for _, case in ipairs(hammer_cases) do
			H.equal(runtime.resolve_template(case.item),
				_G.Weapons.cwv_crowbill_hammer_template, case.label)
		end

		_G.Weapons = saved.Weapons
		_G.DamageProfileTemplates = saved.DamageProfileTemplates
		_G.PowerLevelTemplates = saved.PowerLevelTemplates
		_G.NetworkLookup = saved.NetworkLookup
		table.clone = saved.clone
	end)
end
