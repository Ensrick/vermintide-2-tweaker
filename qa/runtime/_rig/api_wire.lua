-- API self-test, wire part (WP-H-06 group "wire"): T.transmit_spy records rpc_add_equipment while T.equip puts a
-- second owned vanilla melee item on the hero. The solo host still calls the sender
-- (SimpleInventoryExtension._spawn_resynced_loadout, Vermintide-2-Source-Code/scripts/unit_extensions/
-- default_player_unit/inventory/simple_inventory_extension.lua:1443-1456: send_rpc_clients("rpc_add_equipment",
-- unit_go_id, slot_id, item_id, weapon_skin_id)), and the recorded item id decodes through NetworkLookup.item_names to
-- the equipped item's key (item_data.name = key, scripts/settings/equipment/item_master_list.lua:111-112).
return {
	issue = 0,
	arena = "keep",
	class = "R",
	timeout = 60,
	run = function(T)
		local OM = T.shared("official_mirror")
		local hero = T.local_hero(30)

		T.require(hero ~= nil, "local hero alive")
		T.require(T.shield().installed, "backend write shield installed")

		local career = T.local_player():career_name()
		local current = T.loadout().slot_melee
		local candidates = T.backend_items(function(item)
			local data = item.data

			if item.backend_id == current or type(data) ~= "table" or data.slot_type ~= "melee" then
				return false
			end

			if item.rarity == "magic" or data.rarity == "magic" or OM.minted(item.backend_id) or type(data.can_wield) ~= "table" then
				return false
			end

			for _, name in ipairs(data.can_wield) do
				if name == career then
					return true
				end
			end

			return false
		end)

		T.require(#candidates > 0, "a second owned vanilla melee item for " .. tostring(career))

		local item = candidates[1]
		local inventory = T.ext(hero, "inventory_system")

		T.step("spy rpc_add_equipment, equip the item")
		local transmit = Managers.state.network.network_transmit
		local own_before = rawget(transmit, "send_rpc_clients")
		local spy = T.transmit_spy("rpc_add_equipment")

		T.equip(nil, "slot_melee", item.backend_id)
		T.wait_until(function()
			local slot = inventory:get_slot_data("slot_melee")

			return slot and slot.item_data and slot.item_data.backend_id == item.backend_id
		end, 15, "the hero holds the new melee item")
		T.frames(5)
		spy.stop()

		T.note("calls", spy.count())
		T.expect(spy.count("rpc_add_equipment") >= 1, "rpc_add_equipment recorded")

		local decoded

		for _, call in ipairs(spy.calls) do
			if call.via == "send_rpc_clients" and call.n == 4 then
				decoded = NetworkLookup.item_names[call.args[3]]
			end
		end

		T.expect_eq(decoded, item.key, "the recorded item id decodes to the equipped item's key")
		T.expect(rawget(transmit, "send_rpc_clients") == own_before, "spy.stop put the sender back")
	end,
}
