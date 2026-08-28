local function raw_snapshot(value)
	local snapshot = { count = 0, values = {}, metatable = getmetatable(value) }
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
		H.equal(rawget(snapshot.values, key), entry, label .. " changed raw value")
	end
	H.equal(count, snapshot.count, label .. " changed raw key count")
	for key, entry in next, snapshot.values do
		H.equal(rawget(value, key), entry, label .. " removed a raw key")
	end
end

return function(H, repo_root)
	local rarity = dofile(repo_root
		.. "/weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_cursed_rarity.lua")
	local lookup_lib = dofile(repo_root
		.. "/weapons_of_chaos/scripts/mods/weapons_of_chaos/_lib_network_lookup.lua")

	local function paired(name)
		local value = { name }
		value[name] = 1
		return value
	end

	local function make_env()
		return {
			Colors = { color_definitions = {} },
			UISettings = {},
			RaritySettings = {},
			RarityIndex = {},
			ORDER_RARITY = paired("common"),
			NetworkLookup = { rarities = paired("common") },
			NetworkLookupLib = lookup_lib,
		}
	end

	local function tracked_tables(env)
		local result = { env }
		local function add(value)
			if type(value) == "table" then result[#result + 1] = value end
		end
		for _, key in ipairs({
			"Colors", "UISettings", "RaritySettings", "RarityIndex",
			"ORDER_RARITY", "NetworkLookup", "NetworkLookupLib",
		}) do add(rawget(env, key)) end
		local colors = rawget(env, "Colors")
		local ui = rawget(env, "UISettings")
		local network = rawget(env, "NetworkLookup")
		if type(colors) == "table" then add(rawget(colors, "color_definitions")) end
		if type(ui) == "table" then
			add(rawget(ui, "item_rarity_order"))
			add(rawget(ui, "item_rarities"))
			add(rawget(ui, "item_rarity_textures"))
		end
		if type(network) == "table" then add(rawget(network, "rarities")) end
		return result
	end

	local function expect_rejection_without_mutation(env, expected_reason, label)
		local tracked = tracked_tables(env)
		local snapshots = {}
		for index, value in ipairs(tracked) do snapshots[index] = raw_snapshot(value) end
		local call_ok, installed, reason = pcall(rarity.install, env)
		H.truthy(call_ok, label .. " threw: " .. tostring(installed))
		H.equal(installed, false, label .. " reported installation")
		H.equal(reason, expected_reason, label .. " returned wrong reason")
		for index, value in ipairs(tracked) do
			assert_raw_unchanged(H, value, snapshots[index], label .. " table " .. index)
		end
	end

	H.test("WOC Cursed rarity registers every local presentation table", function()
		local env = make_env()
		H.truthy(rarity.install(env))
		H.deep_equal(env.Colors.color_definitions.cursed, rarity.COLOR)
		H.equal(env.UISettings.item_rarity_order.cursed, 7)
		H.equal(env.UISettings.item_rarity_textures.cursed, "icon_bg_cursed")
		H.equal(env.RaritySettings.cursed.display_name, rarity.DISPLAY_KEY)
		H.equal(env.RaritySettings.cursed.order, 7)
		H.equal(env.RarityIndex.cursed, 7)
		H.equal(env.ORDER_RARITY[env.ORDER_RARITY.cursed], "cursed")
		H.equal(env.NetworkLookup.rarities[env.NetworkLookup.rarities.cursed], "cursed")
	end)

	H.test("WOC Cursed rarity install is idempotent and pool scrub is bounded", function()
		local env = make_env()
		rarity.install(env)
		rarity.install(env)
		H.equal(#env.UISettings.item_rarities, 1)
		H.equal(#env.ORDER_RARITY, 2)
		H.equal(#env.NetworkLookup.rarities, 2)
		local excludes = { common = true, cursed = true, future_mod = true }
		local removed = rarity.scrub_unknown_pool_rarities({ common = {} }, excludes)
		H.deep_equal(removed, { "cursed" })
		H.equal(excludes.common, true)
		H.equal(excludes.cursed, nil)
		H.equal(excludes.future_mod, true)
	end)

	H.test("WOC Cursed rarity fails closed until every engine table is ready", function()
		local ok, reason = rarity.install({})
		H.equal(ok, false)
		H.equal(reason, "Colors_unavailable")
		local env = make_env()
		env.Colors = {}
		ok, reason = rarity.install(env)
		H.equal(ok, false)
		H.equal(reason, "nested_tables_unavailable")
	end)

	H.test("WOC Cursed rarity requires the entry-owned canonical helper", function()
		local missing = make_env()
		missing.NetworkLookupLib = nil
		expect_rejection_without_mutation(missing, "NetworkLookupLib_unavailable",
			"missing helper")

		local invalid = make_env()
		invalid.NetworkLookupLib = { register = lookup_lib.register }
		expect_rejection_without_mutation(invalid, "network_lookup_helper_invalid",
			"invalid helper")
	end)

	H.test("WOC Cursed rarity rejects malformed lookup state without mutation", function()
		local cases = {
			{
				name = "asymmetric",
				lookup = { [1] = "common", common = 2 },
				reason = "network_rarities_pair_asymmetric",
			},
			{
				name = "sparse",
				lookup = { [1] = "common", [3] = "exotic", common = 1, exotic = 3 },
				reason = "network_rarities_numeric_side_sparse",
			},
			{
				name = "foreign key",
				lookup = { [1] = "common", common = 1, [true] = "foreign" },
				reason = "network_rarities_lookup_key_invalid",
			},
		}
		for _, case in ipairs(cases) do
			local env = make_env()
			env.UISettings.item_rarity_order = { sentinel = true }
			env.UISettings.item_rarities = { "sentinel" }
			env.UISettings.item_rarity_textures = { sentinel = true }
			env.NetworkLookup.rarities = case.lookup
			expect_rejection_without_mutation(env, case.reason, case.name)
		end
	end)

	H.test("WOC Cursed rarity rejects malformed ORDER_RARITY without mutation", function()
		local env = make_env()
		env.ORDER_RARITY = {
			[1] = "plentiful",
			[3] = "rare",
			plentiful = 1,
			rare = 3,
		}
		expect_rejection_without_mutation(env,
			"order_rarity_numeric_side_sparse", "sparse ORDER_RARITY")
	end)

	H.test("WOC Cursed rarity preflight contains helper errors and UI shape failures", function()
		local throwing = make_env()
		throwing.NetworkLookupLib = {
			register = lookup_lib.register,
			register_named = function() error("planted helper failure") end,
		}
		expect_rejection_without_mutation(throwing,
			"network_rarities_helper_error", "throwing helper")

		local second_call = make_env()
		local named_calls = 0
		second_call.NetworkLookupLib = {
			register = lookup_lib.register,
			register_named = function(...)
				named_calls = named_calls + 1
				if named_calls == 2 then error("planted commit failure") end
				return lookup_lib.register_named(...)
			end,
		}
		expect_rejection_without_mutation(second_call,
			"network_rarities_helper_error", "commit helper failure")

		local invalid_ui = make_env()
		invalid_ui.UISettings.item_rarities = "not-a-table"
		expect_rejection_without_mutation(invalid_ui,
			"item_rarities_invalid", "invalid UI child")
	end)
end
