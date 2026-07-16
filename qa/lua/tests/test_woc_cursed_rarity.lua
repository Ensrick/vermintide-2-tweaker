return function(H, repo_root)
	local rarity = dofile(repo_root
		.. "/weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_cursed_rarity.lua")

	H.test("WOC Cursed rarity registers every local presentation table", function()
		local env = {
			Colors = { color_definitions = {} },
			UISettings = {},
			RaritySettings = {},
			RarityIndex = {},
			ORDER_RARITY = {},
			NetworkLookup = { rarities = {} },
		}
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
		local env = {
			Colors = { color_definitions = {} }, UISettings = {}, RaritySettings = {},
			RarityIndex = {}, ORDER_RARITY = {}, NetworkLookup = { rarities = {} },
		}
		rarity.install(env)
		rarity.install(env)
		H.equal(#env.UISettings.item_rarities, 1)
		H.equal(#env.ORDER_RARITY, 1)
		H.equal(#env.NetworkLookup.rarities, 1)
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
		ok, reason = rarity.install({
			Colors = {}, UISettings = {}, RaritySettings = {}, RarityIndex = {},
			ORDER_RARITY = {}, NetworkLookup = { rarities = {} },
		})
		H.equal(ok, false)
		H.equal(reason, "nested_tables_unavailable")
	end)
end
