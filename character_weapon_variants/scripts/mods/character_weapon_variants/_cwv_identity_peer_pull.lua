-- Bounded receiver-ready pull for exact CWV appearance identity (#401/#914/#660).
--
-- `SimpleInventoryExtension.game_object_initialized` can broadcast before a
-- remote peer's VMF handler is ready.  This owner starts after vanilla finishes
-- local inventory initialization, requests every same-mod peer's current
-- identity, and routes replies through the existing fingerprint ACK ledger.

local M = {}

function M.slots_ready(slots)
	return type(slots) == "table"
		and (slots.slot_melee ~= nil or slots.slot_ranged ~= nil)
end

local function local_slots()
	local pm = Managers and Managers.player
	if not (pm and pm.local_player) then return nil, nil end
	local ok_player, player = pcall(pm.local_player, pm, 1)
	local unit = ok_player and player and player.player_unit
	if not unit or not Unit.alive(unit) then return nil, nil end
	local inventory
	pcall(function() inventory = ScriptUnit.extension(unit, "inventory_system") end)
	local equipment = inventory and inventory._equipment
	if inventory and type(inventory.equipment) == "function" then
		local ok_equipment, current = pcall(inventory.equipment, inventory)
		if ok_equipment and current then equipment = current end
	end
	local slots = equipment and equipment.slots
	return M.slots_ready(slots) and slots or nil, unit
end

-- #914: locality must be derived from the UNIT ITSELF at hook time. The pull
-- request fires from the `game_object_initialized` hook, but vanilla assigns
-- `player.player_unit` only AFTER that broadcast: spawn at
-- bulldozer_player.lua:365 -> unit_spawner.lua:349 `sync_unit_extensions`
-- (fires game_object_initialized) -> ownership at bulldozer_player.lua:393
-- `assign_unit_ownership`. A guard comparing against
-- `Managers.player:local_player(1).player_unit` therefore NEVER passes at
-- request time and the whole peer pull goes dead. The inventory extension's
-- ownership fields are already set in `SimpleInventoryExtension.init`
-- (simple_inventory_extension.lua:31-32, before game_object_initialized):
-- the local human player is a BulldozerPlayer (`local_player = true`,
-- bulldozer_player.lua:9); bots carry `bot_player = true` (player_bot.lua:23).
local function unit_is_local_human(unit)
	if not unit then return false end
	local ok_alive, alive = pcall(function() return Unit.alive(unit) end)
	if not ok_alive or not alive then return false end
	local inventory
	pcall(function()
		inventory = ScriptUnit.has_extension
			and ScriptUnit.has_extension(unit, "inventory_system") or nil
	end)
	local player = inventory and inventory.player
	return player ~= nil and player.local_player == true
		and not inventory.is_bot and not player.bot_player
end

function M.bind(lifecycle, send_slots, policy, print_fn)
	local generation = 0
	local owner = {}

	function owner.request(unit, context)
		-- #914: derive locality from the unit's own inventory extension, not
		-- from `local_player(1).player_unit` (nil/stale until vanilla's later
		-- assign_unit_ownership -- see unit_is_local_human above).
		if not unit_is_local_human(unit) then return false end
		generation = generation % policy.MAX_REQUEST_GENERATION + 1
		local started = lifecycle:begin_request(generation,
			context or "peer_ready_request")
		pcall(print_fn,
			"[cwv:401/914/660] lifecycle=%s adapter=identity_request generation=%d started=%s max_attempts=%d",
			tostring(context), generation, tostring(started),
			policy.MAX_RETRY_ATTEMPTS)
		return started
	end

	function owner.accept(sender_peer_id, schema, payload)
		-- A request may arrive before this peer's local human inventory has any
		-- real slots. Do not burn the sender generation in that window: the next
		-- bounded retry must remain eligible after local initialization (#914).
		local slots = local_slots()
		if not slots then
			pcall(print_fn,
				"[cwv:914] lifecycle=peer_ready_reply peer=%s generation=%s ready=false accepted=false",
				tostring(sender_peer_id), tostring(payload and payload.generation))
			return false
		end
		if not lifecycle:accept_request(sender_peer_id, schema, payload) then
			return false
		end
		local tracked = lifecycle:track_delivery(sender_peer_id,
			slots, "peer_ready_reply")
		local sent = send_slots(slots,
			"peer_ready_reply", true, sender_peer_id)
		pcall(print_fn,
			"[cwv:401/914/660] lifecycle=peer_ready_reply peer=%s generation=%s slots=%d tracked=%d",
			tostring(sender_peer_id), tostring(payload.generation), sent, tracked)
		return true
	end

	function owner.step(dt)
		local sent, expired = lifecycle:step_request(dt)
		if sent > 0 then
			pcall(print_fn,
				"[cwv:401/914/660] lifecycle=peer_ready_request adapter=identity_send attempts=%d",
				sent)
		end
		if expired > 0 then
			pcall(print_fn,
				"[cwv:401/914/660] lifecycle=peer_ready_request adapter=identity_complete generations=%d",
				expired)
		end
		return sent, expired
	end

	return owner
end

return M
