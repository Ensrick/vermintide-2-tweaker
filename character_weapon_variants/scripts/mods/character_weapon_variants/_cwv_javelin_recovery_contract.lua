-- Tuskgor Javelin recovery-pickup owner (#296).
--
-- Production registration and the named runtime proof deliberately share this
-- instance.  The proof drives the exact registered callbacks through the same
-- boundary vanilla Interactions uses: eligibility ->
-- SimpleInventoryExtension:add_ammo_from_pickup -> owned-pickup cleanup.
-- Engine physics still requires live verification; this contract proves that a
-- spawned ground or linked pickup is registered, eligible, consumable for +1,
-- and cleaned up without copying the callback logic into a test.
local M = {}

local function copy(source)
	local result = {}
	for key, value in pairs(source or {}) do result[key] = value end
	return result
end

local function fail(message)
	error(message, 0)
end

function M.new(deps)
	assert(type(deps) == "table", "javelin recovery requires dependencies")
	local state = {
		inventory_for = assert(deps.inventory_for, "javelin recovery requires inventory_for"),
		lookup_lib = assert(deps.lookup_lib, "javelin recovery requires lookup_lib"),
		peer_id = assert(deps.peer_id, "javelin recovery requires peer_id"),
		pickup_system = assert(deps.pickup_system, "javelin recovery requires pickup_system"),
		write = deps.write or rawset,
		debug = deps.debug or function() end,
	}
	assert(type(state.write) == "function", "javelin recovery requires write")
	local api = {}

	local function can_interact(interactor_unit)
		local inventory = state.inventory_for(interactor_unit)
		local eligible = inventory
			and inventory:has_ammo_consuming_weapon_equipped("throwing_javelin") or false
		state.debug("[cwv stick] can_interact_func -> %s (inv=%s)",
			tostring(eligible), tostring(inventory ~= nil))
		return eligible
	end

	local function outline_available(local_player_unit)
		local inventory = state.inventory_for(local_player_unit)
		return inventory
			and inventory:has_ammo_consuming_weapon_equipped("throwing_javelin") or false
	end

	local function on_pick_up(_world, _interactor_unit, _is_server, interactable_unit)
		state.debug("[cwv stick] on_pick_up_func fired")
		state.pickup_system():delete_limited_owned_pickup_unit(
			state.peer_id(), interactable_unit)
	end

	function api.register(args)
		assert(type(args) == "table", "javelin recovery register requires arguments")
		local pickups = assert(args.pickups, "javelin recovery requires pickups")
		local all_pickups = args.all_pickups
		local lookup = args.pickup_lookup
		if type(pickups) ~= "table" then return nil, nil, "pickups_invalid" end
		if all_pickups ~= nil and type(all_pickups) ~= "table" then
			return nil, nil, "all_pickups_invalid"
		end
		local keys = { assert(args.pickup_key), assert(args.link_pickup_key) }
		if keys[1] == keys[2] then return nil, nil, "pickup_keys_equal" end
		local base = {
			ammo_kind = "thrown",
			consumable_item = true,
			debug_pickup_category = "throwing_weapons",
			hud_description = "cwv_interaction_ammunition_javelin",
			local_pickup_sound = true,
			only_once = true,
			outline_distance = "small_pickup",
			pickup_sound_event = "pickup_ammo",
			refill_amount = 1,
			spawn_weighting = 1e-06,
			type = "ammo",
			can_interact_func = can_interact,
			outline_available_func = outline_available,
			on_pick_up_func = on_pick_up,
		}

		local settings_by_key = {}
		for _, key in ipairs(keys) do
			local settings = copy(base)
			settings.unit_name = assert(args.unit_name)
			settings.unit_template_name = "limited_owned_pickup_unit"
			settings.pickup_name = key
			settings_by_key[key] = settings
		end

		-- The two wire identities are one family.  Validate/register both before
		-- exposing either pickup row, then remove only rows inserted by this call
		-- if the second registration rejects or throws.
		local inserted = {}
		local published = {}
		for _, key in ipairs(keys) do
			published[#published + 1] = {
				target = pickups,
				key = key,
				had = rawget(pickups, key) ~= nil,
				value = rawget(pickups, key),
			}
			if all_pickups then
				published[#published + 1] = {
					target = all_pickups,
					key = key,
					had = rawget(all_pickups, key) ~= nil,
					value = rawget(all_pickups, key),
				}
			end
		end
		local function rollback_lookup()
			for i = #inserted, 1, -1 do
				local row = inserted[i]
				rawset(lookup, row.index, nil)
				rawset(lookup, row.key, nil)
			end
		end
		local function rollback_published()
			for i = #published, 1, -1 do
				local row = published[i]
				rawset(row.target, row.key, row.had and row.value or nil)
			end
		end
		for _, key in ipairs(keys) do
			local before_index = type(lookup) == "table" and rawget(lookup, key) or nil
			local ok, index, did_insert, reason = pcall(
				state.lookup_lib.register, lookup, key)
			if not ok or index == nil then
				-- A replacement helper must not be able to mutate then throw. Remove
				-- only a new exact pair for the current key; never touch a preimage.
				if before_index == nil and type(lookup) == "table" then
					local partial_index = rawget(lookup, key)
					if type(partial_index) == "number"
							and rawget(lookup, partial_index) == key then
						rawset(lookup, partial_index, nil)
						rawset(lookup, key, nil)
					end
				end
				rollback_lookup()
				return nil, nil, ok and reason or "lookup_register_threw:" .. tostring(index)
			end
			if did_insert then
				inserted[#inserted + 1] = { key = key, index = index }
			end
		end

		local publish_ok, publish_error = pcall(function()
			for _, key in ipairs(keys) do
				state.write(pickups, key, settings_by_key[key])
				if rawget(pickups, key) ~= settings_by_key[key] then
					error("Pickups.ammo rejected " .. tostring(key))
				end
				if all_pickups then
					state.write(all_pickups, key, settings_by_key[key])
					if rawget(all_pickups, key) ~= settings_by_key[key] then
						error("AllPickups rejected " .. tostring(key))
					end
				end
			end
		end)
		if not publish_ok then
			rollback_published()
			rollback_lookup()
			return nil, nil, "pickup_publish_threw:" .. tostring(publish_error)
		end
		return settings_by_key[keys[1]], settings_by_key[keys[2]]
	end

	-- Runtime-only executable boundary proof.  It temporarily substitutes only
	-- this instance's dependency table, never ScriptUnit/Managers/Network or any
	-- engine global, and restores every field on both success and failure.
	function api.exercise(args)
		local original = {
			inventory_for = state.inventory_for,
			peer_id = state.peer_id,
			pickup_system = state.pickup_system,
		}
		local function restore()
			state.inventory_for = original.inventory_for
			state.peer_id = original.peer_id
			state.pickup_system = original.pickup_system
		end

		local ok, result = pcall(function()
			local pickups = assert(args.pickups, "Pickups.ammo absent")
			local all_pickups = assert(args.all_pickups, "AllPickups absent")
			local skins = assert(args.skins, "WeaponSkins.skins absent")
			local template = assert(args.template, "tuskgor_javelin_template absent")
			local keys = { args.pickup_key, args.link_pickup_key }
			local player, pickup_unit = {}, {}
			local ammo, eligible_queries, deletions = 0, 0, 0
			local inventory = {}
			function inventory:has_ammo_consuming_weapon_equipped(ammo_type)
				eligible_queries = eligible_queries + 1
				return ammo_type == "throwing_javelin"
			end
			function inventory:add_ammo_from_pickup(settings)
				if settings.type ~= "ammo" then fail("pickup type is not ammo") end
				ammo = ammo + (settings.refill_amount or 0)
			end
			state.inventory_for = function(unit)
				if unit == player then return inventory end
			end
			state.peer_id = function() return "cwv-issue296-peer" end
			state.pickup_system = function()
				return {
					delete_limited_owned_pickup_unit = function(_, peer, unit)
						if peer ~= "cwv-issue296-peer" or unit ~= pickup_unit then
							fail("cleanup received the wrong peer or pickup unit")
						end
						deletions = deletions + 1
					end,
				}
			end

			for _, key in ipairs(keys) do
				local settings = assert(pickups[key], key .. " absent from Pickups.ammo")
				if all_pickups[key] ~= settings then fail(key .. " not mirrored by identity in AllPickups") end
				if settings.pickup_name ~= key then fail(key .. " pickup_name mismatch") end
				if settings.unit_name ~= args.unit_name
						or settings.unit_template_name ~= "limited_owned_pickup_unit" then
					fail(key .. " carrier or unit template mismatch")
				end
				if settings.type ~= "ammo" or settings.ammo_kind ~= "thrown"
						or settings.refill_amount ~= 1 then
					fail(key .. " recovery fields malformed")
				end
				if not settings.can_interact_func(player, pickup_unit, nil) then
					fail(key .. " rejected an eligible Tuskgor Javelin inventory")
				end
				if not settings.outline_available_func(player) then
					fail(key .. " hid its outline from an eligible inventory")
				end
				if settings.can_interact_func({}, pickup_unit, nil) then
					fail(key .. " accepted an inventory-less player")
				end
				-- This is the exact native consumption call made by interactions.lua
				-- after can_interact succeeds; use the registered settings object.
				inventory:add_ammo_from_pickup(settings)
				settings.on_pick_up_func(nil, player, true, pickup_unit)
			end
			if ammo ~= 2 then fail("ground + linked recovery did not each refill exactly one ammo") end
			if deletions ~= 2 then fail("ground + linked recovery did not each clean up exactly once") end
			if eligible_queries ~= 4 then fail("recovery callbacks did not run the expected eligibility queries") end

			for _, skin_key in ipairs(args.skin_keys or {}) do
				local skin = assert(skins[skin_key], skin_key .. " absent")
				if skin.pickup_template_name ~= keys[1]
						or skin.link_pickup_template_name ~= keys[2] then
					fail(skin_key .. " does not route both impact outcomes to recovery pickups")
				end
			end
			local thrown = 0
			for _, group in pairs(template.actions or {}) do
				for _, action in pairs(type(group) == "table" and group or {}) do
					if type(action) == "table" and action.kind == "thrown_projectile" then
						local impact = action.impact_data
						if not (impact and impact.link_pickup == true
								and impact.pickup_settings
								and impact.pickup_settings.use_weapon_skin == true) then
							fail("thrown action does not select the skin-qualified recovery pickup")
						end
						thrown = thrown + 1
					end
				end
			end
			if thrown == 0 then fail("Tuskgor Javelin template has no thrown action") end
			return true
		end)
		restore()
		if not ok then return nil, tostring(result) end
		return result
	end

	return api
end

return M
