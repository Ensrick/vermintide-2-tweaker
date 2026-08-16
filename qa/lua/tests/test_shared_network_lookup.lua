local function read(path)
	local file = assert(io.open(path, "rb"))
	local content = file:read("*a")
	file:close()
	return content
end

return function(H, repo_root)
	local canonical_path = repo_root .. "/tools/shared_lib/_lib_network_lookup.lua"
	local consumer_path = repo_root
		.. "/weapons_of_chaos/scripts/mods/weapons_of_chaos/_lib_network_lookup.lua"
	local entry_path = repo_root
		.. "/weapons_of_chaos/scripts/mods/weapons_of_chaos/weapons_of_chaos.lua"
	local M = assert(loadfile(canonical_path))()

	H.test("shared NetworkLookup registration creates a symmetric pair once", function()
		local lookup = { "vanilla" }
		lookup.vanilla = 1
		local index, inserted, reason = M.register(lookup, "modded")
		H.equal(index, 2)
		H.equal(inserted, true)
		H.equal(reason, "registered")
		H.equal(rawget(lookup, 2), "modded")
		H.equal(rawget(lookup, "modded"), 2)

		local again, inserted_again, again_reason = M.register(lookup, "modded")
		H.equal(again, 2)
		H.equal(inserted_again, false)
		H.equal(again_reason, "already_registered")
		H.equal(#lookup, 2)
	end)

	H.test("shared NetworkLookup registration fails closed on malformed state", function()
		local asymmetric = { "vanilla" }
		asymmetric.vanilla = 2
		local index, inserted, reason = M.register(asymmetric, "vanilla")
		H.equal(index, nil)
		H.equal(inserted, false)
		H.equal(reason, "pair_asymmetric")

		local bad_reverse = {}
		bad_reverse.modded = "one"
		local _, _, reverse_reason = M.register(bad_reverse, "modded")
		H.equal(reverse_reason, "reverse_not_numeric")

		local _, _, missing_reason = M.register_named({}, "item_names", "modded")
		H.equal(missing_reason, "lookup_missing")
	end)

	H.test("Enemy Tweaker owns and loads the exact canonical NetworkLookup helper", function()
		local et_consumer_path = repo_root
			.. "/enemy_tweaker/scripts/mods/enemy_tweaker/_lib_network_lookup.lua"
		H.equal(read(et_consumer_path), read(canonical_path), "et helper copy drifted")
		local manifest = read(repo_root .. "/tools/shared_lib/manifest.psd1")
		H.truthy(manifest:find(
			'"enemy_tweaker/scripts/mods/enemy_tweaker/_lib_network_lookup.lua"',
			1, true), "et helper is absent from the shared-library manifest")
		local consumer = read(repo_root
			.. "/enemy_tweaker/scripts/mods/enemy_tweaker/_et_boss_ideas.lua")
		H.truthy(consumer:find(
			'mod:dofile("scripts/mods/enemy_tweaker/_lib_network_lookup")',
			1, true), "et does not load its helper copy")
	end)

	H.test("WOC owns and loads the exact canonical NetworkLookup helper", function()
		H.equal(read(consumer_path), read(canonical_path), "WOC helper copy drifted")
		local manifest = read(repo_root .. "/tools/shared_lib/manifest.psd1")
		H.truthy(manifest:find(
			'"weapons_of_chaos/scripts/mods/weapons_of_chaos/_lib_network_lookup.lua"',
			1, true), "WOC helper is absent from the shared-library manifest")
		local entry = read(entry_path)
		H.truthy(entry:find(
			'mod:dofile("scripts/mods/weapons_of_chaos/_lib_network_lookup")',
			1, true), "WOC does not load its helper copy")
		H.equal(entry:find("local idx = #NetworkLookup.item_names + 1", 1, true), nil,
			"WOC still owns an inline item-name append")
	end)
end
