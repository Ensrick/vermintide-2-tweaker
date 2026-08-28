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

local function woc_cursed_adoption_errors(entry, owner_source, rarity_source)
	local errors = {}
	local helper_path = "scripts/mods/weapons_of_chaos/_lib_network_lookup"
	local helper_at = entry:find(
		'local _network_lookup = mod:dofile("' .. helper_path .. '")', 1, true)
	local owner_at = entry:find(
		'local _cursed = mod:dofile("scripts/mods/weapons_of_chaos/_woc_cursed_rarity")',
		1, true)
	if count_plain(entry, helper_path) ~= 1 then
		errors[#errors + 1] = "helper_load_count"
	end
	if not helper_at or not owner_at or helper_at >= owner_at then
		errors[#errors + 1] = "helper_load_order"
	end
	if not entry:find("NetworkLookupLib = _network_lookup,", 1, true) then
		errors[#errors + 1] = "helper_not_injected"
	end
	if not entry:find("network_lookup = _network_lookup,", 1, true) then
		errors[#errors + 1] = "retry_owner_context_missing"
	end
	if not owner_source:find("NetworkLookupLib = _network_lookup,", 1, true) then
		errors[#errors + 1] = "retry_helper_not_injected"
	end
	if owner_source:find("mod:dofile", 1, true) then
		errors[#errors + 1] = "retry_owner_private_dofile"
	end
	if not rarity_source:find(
		"plan.register_named, values.NetworkLookup, \"rarities\", M.NAME", 1, true) then
		errors[#errors + 1] = "shared_named_registration_absent"
	end
	if rarity_source:find("#lookup + 1", 1, true)
			or rarity_source:find("#env.NetworkLookup.rarities + 1", 1, true) then
		errors[#errors + 1] = "private_append_present"
	end
	if rarity_source:find("mod:dofile", 1, true) then
		errors[#errors + 1] = "owner_private_dofile"
	end
	return errors
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

local function same_value(left, right)
	if left == right then
		return true
	end
	return type(left) == "number" and left ~= left
		and type(right) == "number" and right ~= right
end

local function raw_snapshot(value)
	local snapshot = {
		count = 0,
		metatable = getmetatable(value),
		values = {},
	}
	for key, entry in next, value do
		snapshot.count = snapshot.count + 1
		rawset(snapshot.values, key, entry)
	end
	return snapshot
end

local function assert_raw_unchanged(H, value, snapshot, label)
	H.equal(getmetatable(value), snapshot.metatable, label .. " changed metatable")
	local count = 0
	for key, entry in next, value do
		count = count + 1
		local before = rawget(snapshot.values, key)
		H.truthy(before ~= nil, label .. " added a raw key")
		H.truthy(same_value(entry, before), label .. " changed a raw value")
	end
	H.equal(count, snapshot.count, label .. " changed raw key count")
	for key, entry in next, snapshot.values do
		local after = rawget(value, key)
		H.truthy(after ~= nil, label .. " removed a raw key")
		H.truthy(same_value(after, entry), label .. " changed a saved raw value")
	end
end

local function expect_rejection(H, M, lookup, name, expected_reason, label)
	local snapshot = raw_snapshot(lookup)
	local ok, index, inserted, reason = pcall(M.register, lookup, name)
	H.truthy(ok, label .. " threw: " .. tostring(index))
	H.equal(index, nil, label .. " returned an index")
	H.equal(inserted, false, label .. " reported insertion")
	H.equal(reason, expected_reason, label .. " returned the wrong reason")
	assert_raw_unchanged(H, lookup, snapshot, label)
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

	H.test("shared NetworkLookup rejects invalid target reverse ids without mutation", function()
		local invalid_ids = {
			0,
			-1,
			1.5,
			math.huge,
			-math.huge,
			math.huge - math.huge,
		}
		for i = 1, #invalid_ids do
			local lookup = {}
			rawset(lookup, "modded", invalid_ids[i])
			expect_rejection(H, M, lookup, "modded", "reverse_index_invalid",
				"invalid target reverse id " .. i)
		end
	end)

	H.test("shared NetworkLookup early target rejections preserve exact raw state", function()
		local valid = { "vanilla" }
		valid.vanilla = 1
		expect_rejection(H, M, valid, "", "name_invalid", "invalid requested name")

		local nonnumeric = { "vanilla" }
		nonnumeric.vanilla = 1
		nonnumeric.modded = "one"
		expect_rejection(H, M, nonnumeric, "modded", "reverse_not_numeric",
			"nonnumeric target reverse")

		local asymmetric = { "vanilla" }
		asymmetric.vanilla = 1
		asymmetric.modded = 1
		expect_rejection(H, M, asymmetric, "modded", "pair_asymmetric",
			"asymmetric target pair")
	end)

	H.test("shared NetworkLookup rejects invalid and sparse numeric axes without mutation", function()
		local invalid_keys = { 0, -1, 1.5, math.huge, -math.huge }
		for i = 1, #invalid_keys do
			local lookup = { "vanilla" }
			lookup.vanilla = 1
			rawset(lookup, invalid_keys[i], "invalid_numeric_row")
			expect_rejection(H, M, lookup, "modded", "numeric_key_invalid",
				"invalid numeric key " .. i)
		end

		local one_three = {
			[1] = "one",
			[3] = "three",
			one = 1,
			three = 3,
		}
		expect_rejection(H, M, one_three, "modded", "numeric_side_sparse",
			"sparse 1,3 numeric side")

		local only_two = { [2] = "two", two = 2 }
		expect_rejection(H, M, only_two, "modded", "numeric_side_sparse",
			"sparse numeric side starting at 2")

		local target_inside_sparse = {
			[1] = "modded",
			[3] = "three",
			modded = 1,
			three = 3,
		}
		expect_rejection(H, M, target_inside_sparse, "modded", "numeric_side_sparse",
			"valid target pair inside sparse table")
	end)

	H.test("shared NetworkLookup rejects malformed full-table pairs and foreign keys", function()
		local malformed = {}

		malformed[1] = { "one" }
		malformed[2] = { [1] = "one", one = 2 }
		malformed[3] = { [1] = "one", one = 1, alias = 1 }
		malformed[4] = { [1] = 42 }
		malformed[5] = { [1] = "", [""] = 1 }
		malformed[6] = { [1] = "one", one = 1, bad = 0 }

		for i = 1, #malformed do
			expect_rejection(H, M, malformed[i], "modded", "pair_asymmetric",
				"malformed pair table " .. i)
		end

		local foreign_key = { [1] = "one", one = 1 }
		rawset(foreign_key, true, "foreign")
		expect_rejection(H, M, foreign_key, "modded", "lookup_key_invalid",
			"foreign key type")
	end)

	H.test("shared NetworkLookup rejection precedence is deterministic", function()
		local target_first = { [0] = "invalid", modded = "one", [1] = "vanilla", vanilla = 1 }
		expect_rejection(H, M, target_first, "modded", "reverse_not_numeric",
			"target-specific reason precedence")

		local numeric_first = {
			[0] = "invalid",
			[1] = "one",
			[3] = "three",
			one = 1,
			three = 3,
			alias = 1,
		}
		rawset(numeric_first, true, "foreign")
		expect_rejection(H, M, numeric_first, "modded", "numeric_key_invalid",
			"numeric-key precedence")

		local foreign_first = {
			[1] = "one",
			[3] = "three",
			one = 1,
			three = 3,
			alias = 1,
		}
		rawset(foreign_first, true, "foreign")
		expect_rejection(H, M, foreign_first, "modded", "lookup_key_invalid",
			"foreign-key precedence")

		local sparse_first = { [1] = "one", [3] = "three", one = 1, three = 3, alias = 1 }
		expect_rejection(H, M, sparse_first, "modded", "numeric_side_sparse",
			"sparse precedence")
	end)

	H.test("shared NetworkLookup uses only raw access with strict metatables", function()
		local lookup = { "vanilla" }
		lookup.vanilla = 1
		local strict = {
			__index = function()
				error("strict __index reached")
			end,
			__newindex = function()
				error("strict __newindex reached")
			end,
		}
		setmetatable(lookup, strict)

		local index, inserted, reason = M.register(lookup, "modded")
		H.equal(index, 2)
		H.equal(inserted, true)
		H.equal(reason, "registered")
		H.equal(rawget(lookup, 2), "modded")
		H.equal(rawget(lookup, "modded"), 2)
		H.equal(getmetatable(lookup), strict)

		local again, inserted_again, again_reason = M.register(lookup, "modded")
		H.equal(again, 2)
		H.equal(inserted_again, false)
		H.equal(again_reason, "already_registered")
		H.equal(getmetatable(lookup), strict)
	end)

	H.test("shared named registration propagates validation without mutation", function()
		local child = {
			[1] = "one",
			[3] = "three",
			one = 1,
			three = 3,
		}
		local network_lookup = { item_names = child }
		local outer_snapshot = raw_snapshot(network_lookup)
		local child_snapshot = raw_snapshot(child)
		local ok, index, inserted, reason = pcall(
			M.register_named, network_lookup, "item_names", "modded")
		H.truthy(ok, "register_named threw: " .. tostring(index))
		H.equal(index, nil)
		H.equal(inserted, false)
		H.equal(reason, "numeric_side_sparse")
		assert_raw_unchanged(H, network_lookup, outer_snapshot, "named outer lookup")
		assert_raw_unchanged(H, child, child_snapshot, "named child lookup")
	end)

	H.test("shared named rejection bypasses strict outer and child metatables", function()
		local strict = {
			__index = function()
				error("strict __index reached")
			end,
			__newindex = function()
				error("strict __newindex reached")
			end,
		}
		local child = setmetatable({ [1] = "one", one = 1, modded = "one" }, strict)
		local network_lookup = setmetatable({ item_names = child }, strict)
		local outer_snapshot = raw_snapshot(network_lookup)
		local child_snapshot = raw_snapshot(child)
		local ok, index, inserted, reason = pcall(
			M.register_named, network_lookup, "item_names", "modded")
		H.truthy(ok, "strict register_named rejection threw: " .. tostring(index))
		H.equal(index, nil)
		H.equal(inserted, false)
		H.equal(reason, "reverse_not_numeric")
		assert_raw_unchanged(H, network_lookup, outer_snapshot, "strict named outer lookup")
		assert_raw_unchanged(H, child, child_snapshot, "strict named child lookup")
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

	H.test("Enemy Tweaker entry owns one helper before both registration owners", function()
		local et_consumer_path = repo_root
			.. "/enemy_tweaker/scripts/mods/enemy_tweaker/_lib_network_lookup.lua"
		H.equal(read(et_consumer_path), read(canonical_path), "et helper copy drifted")
		local manifest = read(repo_root .. "/tools/shared_lib/manifest.psd1")
		H.truthy(manifest:find(
			'"enemy_tweaker/scripts/mods/enemy_tweaker/_lib_network_lookup.lua"',
			1, true), "et helper is absent from the shared-library manifest")
		local entry = read(repo_root
			.. "/enemy_tweaker/scripts/mods/enemy_tweaker/enemy_tweaker.lua")
		local warlord = read(repo_root
			.. "/enemy_tweaker/scripts/mods/enemy_tweaker/_et_skaven_warlord_breed.lua")
		local chosen = read(repo_root
			.. "/enemy_tweaker/scripts/mods/enemy_tweaker/_et_boss_ideas.lua")
		local registrar = read(repo_root
			.. "/enemy_tweaker/scripts/mods/enemy_tweaker/_et_custom_breed_registrar.lua")
		local helper_path = "scripts/mods/enemy_tweaker/_lib_network_lookup"
		local registrar_path = "scripts/mods/enemy_tweaker/_et_custom_breed_registrar"
		H.equal(count_plain(entry, helper_path), 1,
			"Enemy entry must load the helper exactly once")
		local helper_at = assert(entry:find(
			'mod._et.NetworkLookupLib = mod:dofile("' .. helper_path .. '")', 1, true))
		local registrar_at = assert(entry:find(
			'mod._et.CustomBreedRegistrar = mod:dofile("' .. registrar_path .. '")', 1, true))
		local warlord_at = assert(entry:find(
			'mod:dofile("scripts/mods/enemy_tweaker/_et_skaven_warlord_breed")', 1, true))
		local chosen_at = assert(entry:find(
			'mod:dofile("scripts/mods/enemy_tweaker/_et_boss_ideas")', 1, true))
		H.truthy(helper_at < registrar_at and registrar_at < warlord_at
			and registrar_at < chosen_at,
			"Enemy helper and registrar must load once before both breed owners")
		H.equal(warlord:find(helper_path, 1, true), nil,
			"Warlord privately reloads the shared helper")
		H.equal(chosen:find(helper_path, 1, true), nil,
			"Chosen privately reloads the shared helper")
		H.truthy(warlord:find("local Registrar = ET.CustomBreedRegistrar", 1, true))
		H.truthy(chosen:find("local Registrar = ET.CustomBreedRegistrar", 1, true))
		H.equal(warlord:find("register_named", 1, true), nil)
		H.equal(chosen:find("register_named", 1, true), nil)
		H.truthy(registrar:find("runtime.lookup_lib.register_named", 1, true),
			"Enemy-local registrar must plan through the canonical helper")
		H.equal(warlord:find("local idx = #bl + 1", 1, true), nil)
		H.equal(warlord:find("local idx = #ds + 1", 1, true), nil)
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
		local rarity_source = read(repo_root
			.. "/weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_cursed_rarity.lua")
		local owner_source = read(repo_root
			.. "/weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_relic_registration_owner.lua")
		H.equal(#woc_cursed_adoption_errors(entry, owner_source, rarity_source), 0,
			"WOC Cursed rarity does not consume the entry-owned helper")
	end)

	H.test("WOC Cursed rarity adoption guard detects planted ownership regressions", function()
		local entry = read(entry_path)
		local rarity_source = read(repo_root
			.. "/weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_cursed_rarity.lua")
		local owner_source = read(repo_root
			.. "/weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_relic_registration_owner.lua")

		local missing_injection, replaced = entry:gsub(
			"NetworkLookupLib = _network_lookup,", "NetworkLookupLib = {},", 1)
		H.equal(replaced, 1, "injection mutation was not planted")
		H.truthy(#woc_cursed_adoption_errors(
			missing_injection, owner_source, rarity_source) > 0,
			"guard accepted a planted helper-injection regression")

		local missing_retry, retry_replaced = owner_source:gsub(
			"NetworkLookupLib = _network_lookup,", "NetworkLookupLib = {},", 1)
		H.equal(retry_replaced, 1, "retry injection mutation was not planted")
		H.truthy(#woc_cursed_adoption_errors(
			entry, missing_retry, rarity_source) > 0,
			"guard accepted a planted retry-helper regression")

		local missing_context, context_replaced = entry:gsub(
			"network_lookup = _network_lookup,", "network_lookup = {},", 1)
		H.equal(context_replaced, 1, "owner-context mutation was not planted")
		H.truthy(#woc_cursed_adoption_errors(
			missing_context, owner_source, rarity_source) > 0,
			"guard accepted a planted entry-to-owner context regression")

		local private_append = rarity_source
			.. "\nlocal function planted(lookup) local index = #lookup + 1 end\n"
		H.truthy(#woc_cursed_adoption_errors(entry, owner_source, private_append) > 0,
			"guard accepted a planted private append regression")

		local private_load = rarity_source
			.. '\nmod:dofile("scripts/mods/weapons_of_chaos/_lib_network_lookup")\n'
		H.truthy(#woc_cursed_adoption_errors(entry, owner_source, private_load) > 0,
			"guard accepted a planted module-owned helper load")
	end)
end
