local function read(path)
	local file = assert(io.open(path, "rb"))
	local content = file:read("*a")
	file:close()
	return content
end

local function count_plain(text, needle)
	local count, at = 0, 1
	while true do
		local found = text:find(needle, at, true)
		if not found then return count end
		count = count + 1
		at = found + #needle
	end
end

local function catalog_names(source, local_name)
	local marker = "local " .. local_name .. " = {"
	local first = assert(source:find(marker, 1, true), local_name .. " marker missing")
	local last = assert(source:find("\n}", first, true), local_name .. " terminator missing")
	local names = {}
	for name in source:sub(first, last):gmatch('"([^"]+)"') do
		names[#names + 1] = name
	end
	return names
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

		local _, _, invalid_name = M.register({}, "")
		H.equal(invalid_name, "name_invalid")

		local _, _, invalid_table_name = M.register_named({}, "", "modded")
		H.equal(invalid_table_name, "network_lookup_missing")
		H.truthy(read(canonical_path):find("append_slot_occupied", 1, true),
			"the defensive occupied-append rejection was removed")
	end)

	H.test("Career Tweaker #428 shared registration preserves all 36 legacy rows", function()
		local balance_source = read(repo_root
			.. "/career_tweaker/scripts/mods/career_tweaker/career_tweaker_balance.lua")
		local tourney_source = read(repo_root
			.. "/career_tweaker/scripts/mods/career_tweaker/career_tweaker_tourney.lua")
		local names = catalog_names(balance_source, "_CRT_BUFF_NAMES")
		local tourney_names = catalog_names(tourney_source, "_TRN_BUFF_NAMES")
		for i = 1, #tourney_names do names[#names + 1] = tourney_names[i] end
		H.equal(#names, 36, "Career Tweaker's two network catalogs drifted")

		local reference = { "vanilla" }
		reference.vanilla = 1
		local shared = { "vanilla" }
		shared.vanilla = 1
		for i = 1, #names do
			local name = names[i]
			-- Exact pre-#428 reference algorithm, retained only in this test.
			if not rawget(reference, name) then
				local index = #reference + 1
				reference[index] = name
				reference[name] = index
			end
			local index, inserted, reason = M.register(shared, name)
			H.equal(index, i + 1)
			H.equal(inserted, true)
			H.equal(reason, "registered")
		end
		for i = 1, #reference do
			H.equal(shared[i], reference[i], "numeric row drift at " .. i)
			H.equal(shared[reference[i]], reference[reference[i]],
				"reverse row drift for " .. reference[i])
		end
	end)

	H.test("Career Tweaker #428 loads one helper before both registration owners", function()
		local career_consumer = repo_root
			.. "/career_tweaker/scripts/mods/career_tweaker/_lib_network_lookup.lua"
		H.equal(read(career_consumer), read(canonical_path),
			"Career Tweaker helper copy drifted")
		local manifest = read(repo_root .. "/tools/shared_lib/manifest.psd1")
		H.truthy(manifest:find(
			'"career_tweaker/scripts/mods/career_tweaker/_lib_network_lookup.lua"',
			1, true), "Career Tweaker helper is absent from the manifest")

		local entry = read(repo_root
			.. "/career_tweaker/scripts/mods/career_tweaker/career_tweaker.lua")
		local balance = read(repo_root
			.. "/career_tweaker/scripts/mods/career_tweaker/career_tweaker_balance.lua")
		local tourney = read(repo_root
			.. "/career_tweaker/scripts/mods/career_tweaker/career_tweaker_tourney.lua")
		H.equal(count_plain(entry, "scripts/mods/career_tweaker/_lib_network_lookup"), 1)
		local helper_at = assert(entry:find("scripts/mods/career_tweaker/_lib_network_lookup", 1, true))
		local balance_at = assert(entry:find("scripts/mods/career_tweaker/career_tweaker_balance", 1, true))
		local tourney_at = assert(entry:find("scripts/mods/career_tweaker/career_tweaker_tourney", 1, true))
		H.truthy(helper_at < balance_at and helper_at < tourney_at,
			"the canonical helper must load before both catalog owners")
		H.truthy(balance:find("network_lookup.register", 1, true))
		H.truthy(tourney:find("network_lookup.register", 1, true))
		H.equal(balance:find("local idx = #NL.buff_templates + 1", 1, true), nil)
		H.equal(tourney:find("local idx = #NetworkLookup.buff_templates + 1", 1, true), nil)
	end)

	H.test("Career Tweaker #428 registration rejection reaches the exact-catalog floor", function()
		local Catalog = assert(loadfile(repo_root
			.. "/career_tweaker/scripts/mods/career_tweaker/_lib_wire_catalog.lua"))()
		local lookup = { "vanilla" }
		lookup.vanilla = 1
		lookup.crt_rejected = 1
		local index, inserted, reason = M.register(lookup, "crt_rejected")
		H.equal(index, nil)
		H.equal(inserted, false)
		H.equal(reason, "pair_asymmetric")
		local identity, err = Catalog.build_identity(
			"crt.buff_templates", { crt_rejected = true }, lookup)
		H.equal(identity, nil)
		H.truthy(err:find("lookup%-mismatch") ~= nil,
			"a rejected row must keep the exact wire identity unavailable")
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
