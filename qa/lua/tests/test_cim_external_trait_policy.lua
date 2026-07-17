return function(H, repo_root)
	local policy = dofile(repo_root
		.. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_cim_external_trait_policy.lua")

	H.test("CIM parks a WOC trait while its provider is absent", function()
		local active, parked = policy.partition({
			"melee_attack_speed_on_crit", "woc_poisoned_edge",
		}, {})
		H.deep_equal(active, { "melee_attack_speed_on_crit" })
		H.deep_equal(parked, { "woc_poisoned_edge" })
	end)

	H.test("CIM reactivates parked WOC traits with exact capability", function()
		local combined = policy.merge_traits(
			{ "melee_attack_speed_on_crit" },
			{ "woc_poisoned_edge", "woc_poisoned_edge" })
		local active, parked = policy.partition(combined, { WOC = true })
		H.deep_equal(active,
			{ "melee_attack_speed_on_crit", "woc_poisoned_edge" })
		H.deep_equal(parked, {})
		H.equal(policy.REQUIRED_CAPABILITY_BY_PROVIDER.WOC,
			"woc.poison_trait.v1")
	end)

	H.test("CIM adds an external trait to one eligible pool idempotently", function()
		local combinations = { melee = { { "melee_attack_speed_on_crit" } } }
		local ok, reason = policy.add_combination(
			combinations, "melee", "woc_poisoned_edge")
		H.equal(ok, true)
		H.equal(reason, "installed")
		H.deep_equal(combinations.melee[2], { "woc_poisoned_edge" })
		ok, reason = policy.add_combination(
			combinations, "melee", "woc_poisoned_edge")
		H.equal(ok, true)
		H.equal(reason, "existing")
		H.equal(#combinations.melee, 2)
		H.equal(policy.add_combination({}, "melee", "woc_poisoned_edge"), false)
	end)

	H.test("WOC+CIM integration remains sender-wire shadowed", function()
		local main = assert(io.open(repo_root
			.. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/crafting_in_modded_dev.lua", "rb"))
		local cim_source = main:read("*a")
		main:close()
		H.truthy(cim_source:find("_cim_register_external_trait_provider", 1, true))
		H.truthy(cim_source:find("external_traits = w.external_traits", 1, true))

		local woc = assert(io.open(repo_root
			.. "/weapons_of_chaos/scripts/mods/weapons_of_chaos/weapons_of_chaos.lua", "rb"))
		local woc_source = woc:read("*a")
		woc:close()
		H.truthy(woc_source:find("woc.poison_trait.v1", 1, true))
		H.truthy(woc_source:find("_WIRE_PROTECTED_TRAITS", 1, true))
		H.equal(woc_source:find("rawset(NetworkLookup.traits", 1, true), nil,
			"custom trait lookup registration is forbidden")
	end)
end
