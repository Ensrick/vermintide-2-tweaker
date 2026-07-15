return function(H, repo_root)
	local policy = dofile(repo_root
		.. "/weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_appearance_policy.lua")

	H.test("WOC #613 owns explicit Blightreaper 1P and 3P units", function()
		H.equal(policy.UNIT_1P, "units/woc_blightreaper/blightreaper")
		H.equal(policy.UNIT_3P, "units/woc_blightreaper/blightreaper_3p")
		local one = assert(io.open(repo_root .. "/weapons_of_chaos/" .. policy.UNIT_1P .. ".unit", "rb"))
		one:close()
		local three = assert(io.open(repo_root .. "/weapons_of_chaos/" .. policy.UNIT_3P .. ".unit", "rb"))
		three:close()
	end)

	H.test("WOC #613 package collector aliases without changing render units", function()
		local names = { "before", policy.UNIT_1P, policy.UNIT_3P, "after" }
		local same, count = policy.alias_collected_packages(names)
		H.equal(same, names)
		H.equal(count, 2)
		H.equal(names[2], policy.VANILLA_1P)
		H.equal(names[3], policy.VANILLA_3P)
	end)

	H.test("WOC #613 network package aliases are forward-only", function()
		local lookup = {
			[policy.VANILLA_1P] = 41,
			[policy.VANILLA_3P] = 42,
			[41] = policy.VANILLA_1P,
			[42] = policy.VANILLA_3P,
		}
		H.equal(policy.install_network_package_aliases(lookup), 2)
		H.equal(lookup[policy.UNIT_1P], 41)
		H.equal(lookup[policy.UNIT_3P], 42)
		H.equal(lookup[41], policy.VANILLA_1P)
		H.equal(lookup[42], policy.VANILLA_3P)
	end)

	H.test("WOC #613 master package reaches model material and texture roots", function()
		local path = repo_root .. "/weapons_of_chaos/resource_packages/weapons_of_chaos/weapons_of_chaos.package"
		local file = assert(io.open(path, "rb"))
		local source = file:read("*a"); file:close()
		H.truthy(source:find('"units/woc_blightreaper/blightreaper"', 1, true))
		H.truthy(source:find('"units/woc_blightreaper/blightreaper_3p"', 1, true))
		H.truthy(source:find('"textures/woc_blightreaper/*"', 1, true))
	end)
end
