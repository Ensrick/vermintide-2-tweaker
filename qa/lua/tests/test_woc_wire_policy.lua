return function(H, repo_root)
	local policy = dofile(repo_root
		.. "/weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_wire_policy.lua")

	H.test("WOC wire policy preserves vanilla items by identity", function()
		local vanilla = { key = "es_1h_sword", ItemId = "es_1h_sword" }
		H.equal(policy.safe_item(vanilla, "es_1h_sword", true), vanilla)
		H.equal(policy.safe_item({}, "es_1h_sword", true) ~= nil, true)
	end)

	H.test("WOC wire policy strips protected traits from ordinary CIM items", function()
		local live = {
			key = "es_1h_sword", ItemId = "es_1h_sword",
			traits = { "melee_attack_speed_on_crit", "woc_poisoned_edge" },
		}
		local shadow = policy.safe_item(live, "es_1h_sword", true, "promo", {
			woc_poisoned_edge = true,
		})
		H.truthy(shadow ~= live)
		H.deep_equal(shadow.traits, { "melee_attack_speed_on_crit" })
		H.deep_equal(live.traits,
			{ "melee_attack_speed_on_crit", "woc_poisoned_edge" })

		local only_custom = { key = "es_1h_sword", traits = { "woc_poisoned_edge" } }
		local clean = policy.safe_item(only_custom, "es_1h_sword", true, "promo", {
			woc_poisoned_edge = true,
		})
		H.equal(clean.traits, nil)
	end)

	H.test("WOC wire policy substitutes explicit mod keys without mutation", function()
		local live = {
			key = "woc_blightreaper", ItemId = "woc_blightreaper",
			power_level = 600, rarity = "cursed",
			properties = { woc_power_vs_order = 1, woc_intrinsic_crit = 1 },
			traits = { "woc_future_trait" },
		}
		local shadow = policy.safe_item(live, "es_1h_sword", true)
		H.truthy(shadow and shadow ~= live)
		H.equal(shadow.key, "es_1h_sword")
		H.equal(shadow.ItemId, "es_1h_sword")
		H.equal(shadow.power_level, 600)
		H.equal(shadow.rarity, "promo")
		H.equal(shadow.properties, nil)
		H.equal(shadow.traits, nil)
		H.equal(live.rarity, "cursed")
		H.equal(live.properties.woc_power_vs_order, 1)
		H.equal(live.traits[1], "woc_future_trait")
		H.equal(live.key, "woc_blightreaper")
		H.equal(live.ItemId, "woc_blightreaper")
	end)

	H.test("WOC wire policy shadows marker-owned vanilla keys and Cursed rarity", function()
		local live = {
			key = "es_1h_sword", ItemId = "es_1h_sword", rarity = "cursed",
			woc_unique_relic = true,
			properties = { woc_power_vs_order = 1 },
		}
		local shadow = policy.safe_item(live, "es_1h_sword", true, "promo")
		H.truthy(shadow ~= live)
		H.equal(shadow.key, "es_1h_sword")
		H.equal(shadow.rarity, "promo")
		H.equal(shadow.properties, nil)
		H.equal(live.rarity, "cursed")
		H.equal(live.properties.woc_power_vs_order, 1)
	end)

	H.test("WOC wire policy fails closed without a resolvable vanilla base", function()
		local live = { key = "woc_future_weapon", ItemId = "woc_future_weapon" }
		H.equal(policy.safe_item(live, "es_1h_sword", false), nil)
		H.equal(policy.safe_item(live, nil, true), nil)
	end)

	H.test("WOC issue 509 runtime evidence covers registration and live equip", function()
		local path = repo_root
			.. "/weapons_of_chaos/scripts/mods/weapons_of_chaos/weapons_of_chaos.lua"
		local f = assert(io.open(path, "rb"))
		local source = f:read("*a")
		f:close()
		H.truthy(source:find("issue509_registered_blightreaper_wire_contract", 1, true))
		H.truthy(source:find("_blightreaper_sync_seen = true", 1, true))
		H.truthy(source:find("rawget(names, woc_id) ~= ITEM_KEY", 1, true))
	end)

	H.test("WOC issue 595 packages helpers and guards module load failure", function()
		local package_path = repo_root
			.. "/weapons_of_chaos/resource_packages/weapons_of_chaos/weapons_of_chaos.package"
		local package_file = assert(io.open(package_path, "rb"))
		local package_source = package_file:read("*a")
		package_file:close()
		H.truthy(package_source:find(
			'"scripts/mods/weapons_of_chaos/_woc_wire_policy"', 1, true))
		H.truthy(package_source:find(
			'"scripts/mods/weapons_of_chaos/_lib_appearance_fade"', 1, true))
		H.truthy(package_source:find(
			'"scripts/mods/weapons_of_chaos/_lib_resource_residency"', 1, true))

		local main_path = repo_root
			.. "/weapons_of_chaos/scripts/mods/weapons_of_chaos/weapons_of_chaos.lua"
		local main_file = assert(io.open(main_path, "rb"))
		local main_source = main_file:read("*a")
		main_file:close()
		H.truthy(main_source:find('type(_wire_policy.safe_item) ~= "function"', 1, true))
		H.truthy(main_source:find("[WOC:595] wire policy unavailable", 1, true))
		H.truthy(main_source:find("_appearance.load_runtime_helpers", 1, true))

		local policy_path = repo_root
			.. "/weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_appearance_policy.lua"
		local policy_file = assert(io.open(policy_path, "rb"))
		local policy_source = policy_file:read("*a")
		policy_file:close()
		H.truthy(policy_source:find("issue595_required_runtime_helpers_loaded", 1, true))
	end)
end
