return function(H, repo_root)
	local policy = dofile(repo_root
		.. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_cross_slot_filter.lua")

	local melee = { data = { key = "es_sword", slot_type = "melee" } }
	local ranged = { data = { key = "es_handgun", slot_type = "ranged" } }
	local musket = { data = { key = "cwv_es_musket_old", slot_type = "ranged" } }
	local items = { melee, ranged, musket }
	local function is_cross_slot(item)
		return item.data.key == "cwv_es_musket_old"
	end

	H.test("#935 filter classifier distinguishes combined equipment categories", function()
		H.equal(policy.kind("slot_type == melee"), "melee_only")
		H.equal(policy.kind("slot_type == ranged"), "ranged_only")
		H.equal(policy.kind("( slot_type == melee or slot_type == ranged ) and item_rarity ~= magic"),
			"combined")
		H.equal(policy.kind("item_rarity == exotic"), "unrelated")
		H.equal(policy.kind(nil), "unrelated")
	end)

	H.test("#935 combined Foot Knight secondary slot retains ordinary ranged weapons", function()
		local result, kept, dropped = policy.apply(items,
			"( slot_type == melee or slot_type == ranged ) and item_rarity ~= magic",
			"slot_ranged",
			is_cross_slot)
		H.equal(result, items)
		H.equal(#result, 3)
		H.equal(result[1], melee)
		H.equal(result[2], ranged)
		H.equal(result[3], musket)
		H.equal(kept, 0)
		H.equal(dropped, 0)
	end)

	H.test("#935 identical combined primary grid still narrows to CWV cross-slot items", function()
		local filter = "( slot_type == melee or slot_type == ranged ) and item_rarity ~= magic"
		H.truthy(policy.should_narrow(filter, "slot_melee"))
		H.equal(policy.should_narrow(filter, "slot_ranged"), false)
		H.equal(policy.should_narrow(filter, nil), false)

		local result, kept, dropped =
			policy.apply(items, filter, "slot_melee", is_cross_slot)
		H.equal(#result, 2)
		H.equal(result[1], melee)
		H.equal(result[2], musket)
		H.equal(kept, 2)
		H.equal(dropped, 1)
	end)

	H.test("#935 melee-only grid keeps native melee and CWV cross-slot items", function()
		local result, kept, dropped, examples =
			policy.apply(items, "slot_type == melee", nil, is_cross_slot)
		H.equal(#result, 2)
		H.equal(result[1], melee)
		H.equal(result[2], musket)
		H.equal(kept, 2)
		H.equal(dropped, 1)
		H.equal(#examples, 1)
		H.truthy(examples[1]:find("es_handgun", 1, true))
	end)

	H.test("#935 ranged-only and unrelated grids preserve the native result", function()
		local ranged_result = policy.apply(items, "slot_type == ranged", "slot_ranged", is_cross_slot)
		local unrelated_result = policy.apply(items, "item_rarity == exotic", nil, is_cross_slot)
		H.equal(ranged_result, items)
		H.equal(unrelated_result, items)
	end)

	H.test("#935 policy fails closed for invalid item collections", function()
		local result, kept, dropped = policy.apply(nil, "slot_type == melee", nil, is_cross_slot)
		H.equal(result, nil)
		H.equal(kept, 0)
		H.equal(dropped, 0)
	end)

	H.test("#935 production carries slot context and gates Javelin before CWV narrowing", function()
		local path = repo_root
			.. "/character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants.lua"
		local file = assert(io.open(path, "rb"))
		local source = file:read("*a")
		file:close()

		H.truthy(source:find('mod:hook("ItemGridUI", "_on_category_index_change"', 1, true))
		H.truthy(source:find('mod:hook("ItemGridUI", "_get_items_by_filter"', 1, true))
		H.truthy(source:find('_om._cwv_filter_slot_name = self._cwv_filter_slot_name', 1, true))
		H.truthy(source:find('_om._cwv_filter_slot_name = previous', 1, true))
		H.truthy(source:find('error(result)', 1, true))

		local hook = assert(source:find('mod:hook("BackendInterfaceItemPlayfab", "get_filtered_items"', 1, true))
		local gate = assert(source:find('_om.javelin_gate.filter_unavailable(items, state)', hook, true))
		local narrow = assert(source:find('_om.cross_slot_filter.should_narrow(filter, slot_name)', hook, true))
		H.truthy(gate < narrow)
	end)
end
