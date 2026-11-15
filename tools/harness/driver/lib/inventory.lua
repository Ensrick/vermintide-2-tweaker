-- tools/harness/driver/lib/inventory.lua: career and loadout helpers (WP-H-06 group "inventory and career").
--
-- A helper group (tools/harness/API.md). Every change goes through the game's own setters, the ones the hero view
-- and the game's test hooks use; nothing here calls a backend commit. A loadout or career change sits in the backend
-- mirror until the game itself commits, and the driver's write shield (WP-H-14) holds the official rows back then.
-- Each change is undone when the case ends (case.cleanups, newest first).

return function (T, ctx)
	local case = ctx.case

	local function hero_level(hero_name)
		local attributes = Managers.backend:get_interface("hero_attributes")
		local experience = attributes:get(hero_name, "experience") or 0

		return ExperienceSettings.get_level(experience)
	end

	local function career_settings(profile_name, career_name)
		local profile_index = FindProfileIndex(profile_name)
		local profile = profile_index and SPProfiles[profile_index]

		if not profile then
			return nil, "profile " .. tostring(profile_name) .. " exists"
		end

		for career_index, career in ipairs(profile.careers) do
			if career.name == career_name then
				return career, nil, profile_index, career_index, profile
			end
		end

		return nil, "career " .. tostring(career_name) .. " belongs to " .. tostring(profile_name)
	end

	local function current_career()
		local player = ctx.local_player()

		return player and player:profile_display_name(), player and player:career_name()
	end

	local function request(profile_name, career_name)
		-- the game's own test hook does the same (Vermintide-2-Source-Code/scripts/game_state/state_ingame_testify.lua:98)
		Managers.state.network:request_profile(1, profile_name, career_name, true)
	end

	-- Switches the local hero to profile_name / career_name (e.g. "empire_soldier", "es_mercenary") with
	-- GameNetworkManager.request_profile (scripts/managers/network/game_network_manager.lua:358) and waits until the
	-- player reports that career with a living unit. INCONCLUSIVE when the career is not unlocked for the account
	-- (CareerSettings is_unlocked_function, scripts/settings/profiles/career_settings.lua:23-39). The game records the
	-- selection with hero_attributes:set(hero, "career", ...) (scripts/game_state/components/profile_synchronizer.lua:747),
	-- which only the next commit would send: the shield holds it back. The career held before the first T.career of
	-- the case is requested again at cleanup (without waiting).
	function T.career(profile_name, career_name, timeout)
		local career, why = career_settings(profile_name, career_name)

		T.require(career ~= nil, why)

		local unlocked = T.main(function ()
			return career:is_unlocked_function(profile_name, hero_level(profile_name))
		end)

		T.require(unlocked, "career " .. career_name .. " unlocked for this account")

		local from_profile, from_career = current_career()

		if not case.career_saved and from_career then
			case.career_saved = true
			case.cleanups[#case.cleanups + 1] = function ()
				local _, now = current_career()

				if now ~= from_career then
					request(from_profile, from_career)
					ctx.out("CAREER RESTORE id=%s career=%s", case.id, from_career)
				end
			end
		end

		if from_career == career_name then
			return ctx.local_hero()
		end

		local old_unit = ctx.local_hero()
		local began = ctx.now()

		T.main(request, profile_name, career_name)

		local unit = T.wait_until(function ()
			local _, now = current_career()
			local hero = ctx.local_hero()

			return now == career_name and hero ~= nil and hero ~= old_unit and hero
		end, timeout or 30, "hero respawned as " .. career_name)

		ctx.out("CAREER id=%s from=%s to=%s seconds=%.1f", case.id, tostring(from_career), career_name, ctx.now() - began)

		return unit
	end

	-- An owned backend item by backend id, or the first owned item with that item key
	-- (BackendInterfaceItemPlayfab.get_item_from_id / get_item_from_key, backend_interface_item_playfab.lua:384;
	-- BackendUtils.try_set_loadout_item uses get_item_from_key the same way, backend_utils.lua:47-58). Owned items carry
	-- backend_id, key and data (playfab_mirror_base.lua:1784-1786).
	local function owned_item(id_or_key)
		local items = Managers.backend:get_interface("items")

		return items:get_item_from_id(id_or_key) or items:get_item_from_key(id_or_key)
	end

	-- What the hero view does after it writes the loadout (HeroViewStateOverview._set_loadout_item and post_update,
	-- scripts/ui/views/hero_view/states/hero_view_state_overview.lua:1116-1131 and :705-724): weapons are re-created
	-- in their slot, attachments in theirs, a frame goes to the cosmetic system; a skin or pose change shows on the
	-- next spawn. The statistic write the hero view makes there (:1140-1145) is left out.
	local function show_on_hero(unit, slot_name, slot_type, backend_id, item_key)
		if slot_type == "melee" or slot_type == "ranged" then
			ScriptUnit.extension(unit, "inventory_system"):create_equipment_in_slot(slot_name, backend_id)
		elseif slot_type == "hat" or slot_type == "trinket" or slot_type == "ring" or slot_type == "necklace" then
			ScriptUnit.extension(unit, "attachment_system"):create_attachment_in_slot(slot_name, backend_id)
		elseif slot_type == "frame" then
			Managers.state.entity:system("cosmetic_system"):set_equipped_frame(unit, item_key)
		end

		Managers.state.event:trigger("event_set_loadout_items")
	end

	-- Equips an owned item (backend id or item key) in slot_name ("slot_melee", "slot_hat", ...) of career_name (nil:
	-- the local career) with BackendUtils.set_loadout_item (scripts/managers/backend/backend_utils.lua:22), then shows
	-- it on the local hero when that career is the one played. The item held before the case's first T.equip of that
	-- career and slot is put back the same way at cleanup. Returns the backend id equipped.
	function T.equip(career_name, slot_name, id_or_key)
		local _, local_career = current_career()

		career_name = career_name or local_career

		local slot = InventorySettings.slots_by_name[slot_name]

		T.require(slot ~= nil and slot.stored_in_backend, "slot " .. tostring(slot_name) .. " is a loadout slot")

		local item = owned_item(id_or_key)

		T.require(item ~= nil, "item " .. tostring(id_or_key) .. " owned")

		local backend_id = item.backend_id
		local previous = BackendUtils.get_loadout_item_id(career_name, slot_name)
		local key = tostring(career_name) .. "\n" .. slot_name

		case.equip_saved = case.equip_saved or {}

		if not case.equip_saved[key] and previous then
			case.equip_saved[key] = true
			case.cleanups[#case.cleanups + 1] = function ()
				BackendUtils.set_loadout_item(previous, career_name, slot_name)

				local _, now = current_career()
				local hero = ctx.local_hero()

				if now == career_name and hero then
					local was = owned_item(previous)

					show_on_hero(hero, slot_name, slot.type, previous, was and was.key)
				end

				ctx.out("EQUIP RESTORE id=%s career=%s slot=%s item=%s", case.id, tostring(career_name), slot_name, tostring(previous))
			end
		end

		T.main(function ()
			BackendUtils.set_loadout_item(backend_id, career_name, slot_name)

			local hero = ctx.local_hero()

			if career_name == local_career and hero then
				show_on_hero(hero, slot_name, slot.type, backend_id, item.key)
			end
		end)

		ctx.out("EQUIP id=%s career=%s slot=%s item=%s key=%s was=%s", case.id, tostring(career_name), slot_name, tostring(backend_id), tostring(item.key), tostring(previous))

		return backend_id
	end

	-- Read-only: the backend id in every loadout slot (stored_in_backend, scripts/settings/inventory_settings.lua:15-100)
	-- of a career's current loadout (BackendUtils.get_loadout_item_id, backend_utils.lua:14), keyed by slot name.
	function T.loadout(career_name)
		local _, local_career = current_career()
		local result = {}

		career_name = career_name or local_career

		for slot_name, slot in pairs(InventorySettings.slots_by_name) do
			if slot.stored_in_backend then
				result[slot_name] = BackendUtils.get_loadout_item_id(career_name, slot_name)
			end
		end

		return result
	end

	-- Read-only: owned backend items for which filter(item) is true (all when filter is nil), as a list
	-- (get_all_backend_items, backend_interface_item_playfab.lua:431).
	function T.backend_items(filter)
		local list = {}

		for _, item in pairs(Managers.backend:get_interface("items"):get_all_backend_items()) do
			if filter == nil or filter(item) then
				list[#list + 1] = item
			end
		end

		return list
	end
end
