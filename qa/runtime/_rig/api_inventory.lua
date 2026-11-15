-- API self-test, loadout part (WP-H-06 group "inventory and career"): T.loadout and T.backend_items read the
-- current career's loadout and owned items, T.equip puts a second owned vanilla melee item in slot_melee and the
-- hero holds it; the next case (api_inventory_restored.lua) checks the case end put the old item back.
-- The change sits in the backend mirror only; the write shield (WP-H-14) holds it back from any commit.
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
		T.require(OM.baseline_clean(), "official mirror clean at case start")

		local career = T.local_player():career_name()
		local before = T.loadout()

		T.require(before.slot_melee ~= nil, "a melee item is equipped")
		T.note("career", career)

		T.step("T.backend_items: a second owned vanilla melee item this career can wield")
		local candidates = T.backend_items(function(item)
			local data = item.data

			if item.backend_id == before.slot_melee or type(data) ~= "table" or data.slot_type ~= "melee" then
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

		local pick = candidates[1].backend_id
		local inventory = T.ext(hero, "inventory_system")

		T.step("T.equip it in slot_melee")
		T.expect_eq(T.equip(nil, "slot_melee", pick), pick, "T.equip returns the backend id")
		T.expect_eq(T.loadout().slot_melee, pick, "the loadout holds the new item")

		-- create_equipment_in_slot queues the spawn (simple_inventory_extension.lua:1372-1410); the slot's item_data
		-- carries the backend id (BackendUtils.get_item_from_masterlist, backend_utils.lua:63-72)
		T.wait_until(function()
			local slot = inventory:get_slot_data("slot_melee")

			return slot and slot.item_data and slot.item_data.backend_id == pick
		end, 15, "the hero holds the new melee item")
	end,
}
