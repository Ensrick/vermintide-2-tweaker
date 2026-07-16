return function(H, repo_root)
	local policy = dofile(repo_root
		.. "/weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_blightreaper_power.lua")

	local function relic(overrides)
		local item = {
			backend_id = "deus-random-91827",
			key = policy.BASE_ITEM,
			woc_unique_relic = true,
			data = { woc_item_key = policy.ITEM_KEY },
			CustomData = {},
		}
		for key, value in pairs(overrides or {}) do item[key] = value end
		return item
	end

	H.test("WOC Blightreaper recognizes marker/data identity, never Deus key alone", function()
		H.truthy(policy.is_relic({ woc_unique_relic = true }))
		H.truthy(policy.is_relic({ CustomData = { woc_unique_relic = "true" } }))
		H.truthy(policy.is_relic({ data = { woc_item_key = policy.ITEM_KEY } }))
		H.truthy(policy.is_relic({ key = policy.ITEM_KEY }))
		H.equal(policy.is_relic({
			backend_id = "woc_blightreaper_001",
			deus_item_key = policy.VANILLA_DEUS_KEY,
		}), false)
	end)

	H.test("WOC Blightreaper stamps fixed local and Deus power without id loss", function()
		local local_item = relic()
		H.truthy(policy.stamp_local(local_item))
		H.equal(local_item.power_level, 600)
		H.equal(local_item.rarity, "cursed")
		H.equal(local_item.CustomData.power_level, "600")
		H.equal(local_item.CustomData.rarity, "cursed")
		H.equal(local_item.backend_id, "deus-random-91827")
		H.equal(local_item.key, policy.BASE_ITEM)

		local deus_item = relic()
		H.truthy(policy.stamp_deus(deus_item))
		H.equal(deus_item.power_level, 900)
		H.equal(deus_item.rarity, "cursed")
		H.equal(deus_item.deus_item_key, "deus_es_1h_sword")
		H.equal(deus_item.backend_id, "deus-random-91827")
	end)

	H.test("WOC Deus install aliases only to the vanilla elf sword row", function()
		local master = { [policy.ITEM_KEY] = {} }
		local mapping = {}
		local weapons = { [policy.VANILLA_DEUS_KEY] = { base_item = policy.BASE_ITEM } }
		local before = 0
		for _ in pairs(weapons) do before = before + 1 end
		local ok = policy.install_deus(master, mapping, weapons)
		H.truthy(ok)
		H.equal(mapping[policy.ITEM_KEY], policy.VANILLA_DEUS_KEY)
		local after = 0
		for _ in pairs(weapons) do after = after + 1 end
		H.equal(after, before)
		H.equal(rawget(weapons, "deus_woc_blightreaper"), nil)
	end)

	H.test("WOC Deus setup identity is a non-mutating shallow shadow", function()
		local item = relic()
		local shadow = policy.setup_identity(item)
		H.truthy(shadow ~= item)
		H.equal(shadow.key, policy.ITEM_KEY)
		H.equal(shadow.ItemId, policy.ITEM_KEY)
		H.equal(item.key, policy.BASE_ITEM)
		H.equal(item.ItemId, nil)
		local observed = policy.with_setup_identity(item, function(value, suffix)
			return value.key .. suffix
		end, ":setup")
		H.equal(observed, policy.ITEM_KEY .. ":setup")
	end)

	H.test("WOC Deus serialization exposes only vanilla key and rarity", function()
		local item = relic({
			key = policy.ITEM_KEY,
			power_level = 600,
			rarity = "cursed",
			deus_item_key = policy.VANILLA_DEUS_KEY,
		})
		local serialized = policy.serialize_deus_weapon(item, function(value)
			return table.concat({
				"item_key=" .. value.deus_item_key,
				"powerlevel=" .. tostring(value.power_level),
				"rarity=" .. value.rarity,
			}, ",")
		end)
		H.equal(serialized,
			"item_key=deus_es_1h_sword,powerlevel=900,rarity=unique,woc=blightreaper")
		H.truthy(policy.has_serialization_marker(serialized))
		H.equal(policy.has_serialization_marker(serialized .. "s"), false)
		H.equal(policy.append_serialization_marker(serialized), serialized)
		H.equal(item.key, policy.ITEM_KEY)
		H.equal(item.power_level, 600)
		H.equal(item.rarity, "cursed")
	end)

	H.test("WOC Deus deserialization restores local identity and fixed power", function()
		local definition = { woc_item_key = policy.ITEM_KEY }
		local serialized =
			"item_key=deus_es_1h_sword,powerlevel=900,rarity=unique,woc=blightreaper"
		local item = policy.deserialize_deus_weapon(serialized, function(value)
			H.equal(value, serialized)
			return {
				backend_id = "deus-random-441",
				key = policy.BASE_ITEM,
				deus_item_key = policy.VANILLA_DEUS_KEY,
				power_level = 900,
				rarity = "unique",
			}
		end, definition)
		H.equal(item.backend_id, "deus-random-441")
		H.equal(item.key, policy.ITEM_KEY)
		H.equal(item.data, definition)
		H.equal(item.power_level, 900)
		H.equal(item.rarity, "cursed")
		H.equal(item.CustomData.rarity, "cursed")
		H.equal(item.deus_item_key, policy.VANILLA_DEUS_KEY)
	end)

	H.test("WOC Deus identity survives a non-WOC authority reserialization", function()
		local stripped =
			"item_key=deus_es_1h_sword,powerlevel=900,rarity=unique"
		local item = policy.deserialize_deus_weapon(stripped, function()
			return {
				backend_id = "remote-host-row",
				key = policy.BASE_ITEM,
				deus_item_key = policy.VANILLA_DEUS_KEY,
				power_level = 900,
				rarity = "unique",
			}
		end, { woc_item_key = policy.ITEM_KEY })
		H.truthy(policy.has_wire_signature(item))
		H.equal(item.key, policy.ITEM_KEY)
		H.equal(item.rarity, "cursed")
		H.equal(item.power_level, 900)
		H.equal(item.backend_id, "remote-host-row")

		H.equal(policy.has_wire_signature({
			deus_item_key = policy.VANILLA_DEUS_KEY,
			power_level = 700,
			rarity = "unique",
		}), false)
	end)

	H.test("WOC vanilla Deus items pass through without marker or upgrade block", function()
		local vanilla = {
			key = policy.BASE_ITEM,
			deus_item_key = policy.VANILLA_DEUS_KEY,
			power_level = 450,
			rarity = "rare",
		}
		local serialized = policy.serialize_deus_weapon(vanilla, function(value)
			H.equal(value, vanilla)
			return "item_key=" .. value.deus_item_key .. ",rarity=" .. value.rarity
		end)
		H.equal(serialized, "item_key=deus_es_1h_sword,rarity=rare")
		H.equal(policy.should_block_upgrade(vanilla), false)
		H.truthy(policy.should_block_upgrade(relic()))
		H.equal(policy.stamp_local(vanilla), false)
	end)

	H.test("WOC production wires fixed power through every Deus boundary", function()
		local path = repo_root
			.. "/weapons_of_chaos/scripts/mods/weapons_of_chaos/weapons_of_chaos.lua"
		local file = assert(io.open(path, "rb"))
		local source = file:read("*a")
		file:close()
		for _, needle in ipairs({
			'"DeusMechanism", "_setup_run"',
			'"BackendInterfaceItemPlayfab", "get_item_from_id"',
			'"generate_item_from_item_key"',
			'"serialize_weapon"',
			'"deserialize_weapon"',
			'"upgrade_item"',
			'"BackendInterfaceDeusBase", "grant_deus_weapon"',
			'"DeusChestExtension", "can_be_unlocked"',
			'"DeusRunController", "get_weapon_pool"',
		}) do
			H.truthy(source:find(needle, 1, true), "missing Deus boundary: " .. needle)
		end
	end)
end
