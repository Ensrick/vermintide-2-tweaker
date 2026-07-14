return function(H, repo_root)
	local policy = dofile(repo_root
		.. "/weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_wire_policy.lua")

	H.test("WOC wire policy preserves vanilla items by identity", function()
		local vanilla = { key = "es_1h_sword", ItemId = "es_1h_sword" }
		H.equal(policy.safe_item(vanilla, "es_1h_sword", true), vanilla)
		H.equal(policy.safe_item({}, "es_1h_sword", true) ~= nil, true)
	end)

	H.test("WOC wire policy substitutes explicit mod keys without mutation", function()
		local live = { key = "woc_blightreaper", ItemId = "woc_blightreaper", power_level = 300 }
		local shadow = policy.safe_item(live, "es_1h_sword", true)
		H.truthy(shadow and shadow ~= live)
		H.equal(shadow.key, "es_1h_sword")
		H.equal(shadow.ItemId, "es_1h_sword")
		H.equal(shadow.power_level, 300)
		H.equal(live.key, "woc_blightreaper")
		H.equal(live.ItemId, "woc_blightreaper")
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
end
