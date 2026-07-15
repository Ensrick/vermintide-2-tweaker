return function(H, repo_root)
	local policy = dofile(repo_root
		.. "/weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_relic_policy.lua")

	local function definition(key, backend_id)
		local row = {
			woc_item_key = key,
			rarity = "default",
			skin_combination_table = { "forbidden" },
			mod_data = {
				backend_id = backend_id,
				ItemInstanceId = backend_id,
				CustomData = { rarity = "default", skin = "forbidden" },
				rarity = "default",
				skin = "forbidden",
			},
		}
		return policy.mark_definition(row, backend_id)
	end

	H.test("WOC #637 provider definition is one immutable promo relic", function()
		local row = definition("woc_one", "woc_one_001")
		H.truthy(policy.is_definition(row))
		H.equal(row.rarity, "promo")
		H.equal(row.skin_combination_table, nil)
		H.equal(row.mod_data.rarity, "promo")
		H.equal(row.mod_data.CustomData.rarity, "promo")
		H.equal(row.mod_data.skin, nil)
		H.equal(row.mod_data.CustomData.skin, nil)
	end)

	H.test("WOC #637 repairs MoreItemsLibrary live rarity overwrite", function()
		local row = definition("woc_one", "woc_one_001")
		-- Exact MIL failure mode: top-level and CustomData rarity are overwritten.
		local live = {
			backend_id = "woc_one_001",
			ItemInstanceId = "woc_one_001",
			rarity = "default",
			CustomData = { rarity = "default", skin = "old_skin" },
			skin = "old_skin",
			data = row,
		}
		H.truthy(policy.enforce_instance(live, row, "woc_one_001"))
		H.truthy(policy.is_instance(live))
		H.equal(live.rarity, "promo")
		H.equal(live.CustomData.rarity, "promo")
		H.equal(live.skin, nil)
		H.equal(live.CustomData.skin, nil)
	end)

	H.test("WOC #637 reconciliation is generic and never deletes canonical ids", function()
		local one = definition("woc_one", "woc_one_001")
		local two = definition("woc_two", "woc_two_001")
		local definitions = {
			{ item_key = "woc_one", backend_id = "woc_one_001", master = one },
			{ item_key = "woc_two", backend_id = "woc_two_001", master = two },
		}
		local items = {
			woc_one_001 = { backend_id = "woc_one_001", data = one },
			duplicate_free = { backend_id = "duplicate_free", ItemId = "woc_one", data = one },
			duplicate_equipped = { backend_id = "duplicate_equipped", ItemId = "woc_two", data = two },
			foreign = { backend_id = "foreign", ItemId = "es_1h_sword" },
		}
		local plan = policy.plan_reconciliation(items, definitions, function(id)
			if id == "duplicate_free" then return false end
			if id == "duplicate_equipped" then return true end
			return nil
		end, function(id)
			if id == "duplicate_free" or id == "duplicate_equipped" then return true end
			return nil
		end)
		H.equal(#plan.canonical, 1)
		H.equal(plan.canonical[1], "woc_one_001")
		H.equal(#plan.removable, 1)
		H.equal(plan.removable[1], "duplicate_free")
		H.equal(#plan.deferred, 1)
		H.equal(plan.deferred[1], "duplicate_equipped")
		H.equal(#plan.missing, 1)
		H.equal(plan.missing[1], "woc_two_001")
		for _, id in ipairs(plan.removable) do
			H.equal(id == "woc_one_001" or id == "woc_two_001", false)
		end
	end)

	H.test("WOC #637 unknown duplicate ownership is retained fail-closed", function()
		local one = definition("woc_one", "woc_one_001")
		local plan = policy.plan_reconciliation({
			woc_one_001 = { backend_id = "woc_one_001", data = one },
			unknown_duplicate = {
				backend_id = "unknown_duplicate", ItemId = "woc_one", data = one,
			},
		}, {
			{ item_key = "woc_one", backend_id = "woc_one_001", master = one },
		}, function(id)
			return id == "unknown_duplicate" and false or nil
		end, function() return nil end)
		H.equal(#plan.removable, 0)
		H.equal(#plan.deferred, 1)
		H.equal(plan.deferred[1], "unknown_duplicate")
	end)
end
