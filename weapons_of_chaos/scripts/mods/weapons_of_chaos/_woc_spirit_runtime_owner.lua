-- _woc_spirit_runtime_owner.lua
-- Sole owner for Blightreaper poison attribution and native Shyish spirit
-- spawn, chase, health-conversion, event, and cleanup lifecycle.

local M = {}

function M.new(ctx)
	local mod = assert(ctx.mod, "mod required")
	local _spirits = assert(ctx.spirits, "spirits required")
	local _power = assert(ctx.power, "power required")
	local _moveset = assert(ctx.moveset, "moveset required")
	local _remote_blightreaper = assert(ctx.remote_identity, "remote_identity required")
	local _backend_items = assert(ctx.backend_items, "backend_items required")
	local _ensure_spirit_package = assert(ctx.ensure_package, "ensure_package required")
	local _rt_register = assert(ctx.rt_register, "rt_register required")
	local _start_spirit_runtime
	local _stop_spirit_runtime
	local _mark_blight_poison
	local _owner_has_wielded_trait

-- ============================================================
-- Native Shyish death spirits (#632)
-- ============================================================

local _spirit_state = {
	active = {},
	count = 0,
	event_manager = nil,
	poison_sources = setmetatable({}, { __mode = "k" }),
	spawned = 0,
	converted = 0,
	dropped = 0,
	damage_index = 1,
}
local _spirit_diag_budget = 24
local _spirit_reject_diag_budget = 8

local function _spirit_now()
	local time = Managers and Managers.time
	if not time or type(time.time) ~= "function" then return 0 end
	local ok, value = pcall(time.time, time, "game")
	return ok and tonumber(value) or 0
end

local function _spirit_diag(fmt, ...)
	if _spirit_diag_budget <= 0 then return end
	_spirit_diag_budget = _spirit_diag_budget - 1
	pcall(printf, "[WOC:632] " .. fmt, ...)
end

-- Rejected-identity kills get a separate small budget so ordinary teammate
-- kills cannot consume the relevant [WOC:632] trace.
local function _spirit_reject_diag(fmt, ...)
	if _spirit_reject_diag_budget <= 0 then return end
	_spirit_reject_diag_budget = _spirit_reject_diag_budget - 1
	pcall(printf, "[WOC:632] " .. fmt, ...)
end

local function _player_peer_id(unit)
	local player
	pcall(function() player = Managers.player:owner(unit) end)
	if not player then return nil end
	return player.peer_id or (player.network_id and player:network_id())
end

local function _wielded_relic(unit)
	if not unit or not Unit.alive(unit) then return false, nil end
	local inventory = ScriptUnit.has_extension(unit, "inventory_system")
	if not inventory then return false, nil end
	local slot
	if type(inventory.get_wielded_slot_name) == "function" then
		local ok
		ok, slot = pcall(inventory.get_wielded_slot_name, inventory)
		if not ok then slot = nil end
	end
	if slot ~= "slot_melee" and slot ~= "slot_ranged" then return false, slot end
	local slot_data
	if type(inventory.get_wielded_slot_data) == "function" then
		pcall(function() slot_data = inventory:get_wielded_slot_data() end)
	end
	if slot_data and _power.is_relic(slot_data.item_data) then return true, slot end
	local peer_id = _player_peer_id(unit)
	local remote = peer_id and _remote_blightreaper[peer_id]
	return remote and remote[slot] == true or false, slot
end

local function _owner_trait_evidence(unit, trait_key)
	if not unit or not Unit.alive(unit) or type(trait_key) ~= "string" then
		return false, "invalid_owner", nil, nil
	end
	local inventory = ScriptUnit.has_extension(unit, "inventory_system")
	if not inventory then return false, "inventory_missing", nil, nil end
	local slot_data
	if type(inventory.get_wielded_slot_data) == "function" then
		pcall(function() slot_data = inventory:get_wielded_slot_data() end)
	end
	local item_data = slot_data and slot_data.item_data
	local backend_id = item_data and item_data.backend_id
	local items = backend_id and _backend_items()
	local item
	if items then pcall(function() item = items:get_item_from_id(backend_id) end) end
	if _moveset.item_has_trait(item, trait_key) then
		return true, "live_backend_trait", backend_id,
			item and (item.key or item.ItemId)
	end
	-- Blightreaper's same-mod remote identity cannot carry its custom trait on
	-- vanilla loadout transport. Its exact relic identity is the bounded
	-- semantic fallback for the intrinsic Shyish row only.
	local relic, slot = _wielded_relic(unit)
	if trait_key == _moveset.SHYISH_CURSE_TRAIT and relic then
		return true, "exact_relic_identity:" .. tostring(slot), backend_id,
			item_data and (item_data.key or item_data.ItemId)
	end
	return false, item and "live_backend_trait_absent"
		or backend_id and "backend_item_missing"
		or "backend_id_missing", backend_id,
		item_data and (item_data.key or item_data.ItemId)
end

_owner_has_wielded_trait = function(unit, trait_key)
	local has_trait = _owner_trait_evidence(unit, trait_key)
	return has_trait
end

_mark_blight_poison = function(hit_unit, owner_unit)
	local network = Managers and Managers.state and Managers.state.network
	if not (network and network.is_server and hit_unit and owner_unit
		and Unit.alive(hit_unit) and Unit.alive(owner_unit)) then return end
	_spirit_state.poison_sources[hit_unit] = {
		owner = owner_unit,
		t = _spirit_now(),
	}
	_spirit_diag("poison marker armed peer=%s ttl=%.1f",
		tostring(_player_peer_id(owner_unit)), _spirits.POISON_ATTRIBUTION_TTL)
end

-- Client-owned Hagbane applications already traverse this native RPC with the
-- native buff-template id and attacker params.  Observe it after vanilla has
-- accepted the buff; do not add traffic and do not transmit WOC lookup ids.
-- Pre-flight: WOC has no other hook on (BuffSystem,rpc_add_buff_synced_params).
mod:hook_safe("BuffSystem", "rpc_add_buff_synced_params", function(self, channel_id,
		target_unit_id, template_name_id)
	local network = Managers and Managers.state and Managers.state.network
	if not (network and network.is_server) then return end
	local template_name = NetworkLookup and NetworkLookup.buff_templates
		and NetworkLookup.buff_templates[template_name_id]
	if template_name ~= _moveset.DOT_TEMPLATE then return end
	local channel_to_peer = rawget(_G, "CHANNEL_TO_PEER_ID")
	local peer_id = channel_to_peer and channel_to_peer[channel_id]
	local player = peer_id and Managers.player.player_from_peer_id
		and Managers.player:player_from_peer_id(peer_id)
	local owner_unit = player and player.player_unit
	local is_relic = owner_unit
		and _owner_has_wielded_trait(owner_unit, _moveset.SHYISH_CURSE_TRAIT)
	local target_unit = self.unit_storage and self.unit_storage:unit(target_unit_id)
	if is_relic and target_unit then _mark_blight_poison(target_unit, owner_unit) end
end)

local function _spirit_delete(entry, reason, explode)
	local unit = entry and entry.unit
	if unit and Unit.alive(unit) then
		local entity = Managers and Managers.state and Managers.state.entity
		if explode and entity then
			local position = Unit.local_position(unit, 0)
			local rotation = Unit.world_rotation(unit, 0)
			local area = entity:system("area_damage_system")
			local audio = entity:system("audio_system")
			if area then area:create_explosion(unit, position, rotation,
				_spirits.EXPLOSION, 1, "undefined", 0, false) end
			if audio then audio:play_audio_unit_event(_spirits.EXPLODE_SOUND, unit) end
		end
		local spawner = Managers and Managers.state and Managers.state.unit_spawner
		if spawner then spawner:mark_for_deletion(unit) end
	end
	if entry then _spirit_state.active[entry] = nil end
	_spirit_state.count = math.max(_spirit_state.count - 1, 0)
	if reason and reason ~= "hit" and reason ~= "expired" then
		_spirit_diag("spirit removed reason=%s active=%d", tostring(reason), _spirit_state.count)
	end
end

local function _spirit_live_position(unit)
	return Unit.local_position(unit, 0)
end

local function _spirit_is_vector(value)
	if value == nil or type(Vector3.to_elements) ~= "function" then return false end
	return pcall(Vector3.to_elements, value)
end

local function _spirit_position(unit)
	return _spirits.resolve_position(unit, _spirit_live_position,
		rawget(_G, "POSITION_LOOKUP"), _spirit_is_vector)
end

local function _spawn_spirit(killed_unit, target_unit, attribution)
	if _spirit_state.count >= _spirits.MAX_ACTIVE then
		_spirit_state.dropped = _spirit_state.dropped + 1
		_spirit_diag("spirit cap reached active=%d dropped=%d",
			_spirit_state.count, _spirit_state.dropped)
		return false
	end
	local packages = Managers and Managers.package
	local package_ready, package_reason = _spirits.package_ready(packages)
	if not package_ready then
		_spirit_state.dropped = _spirit_state.dropped + 1
		_spirit_diag("native Shyish package not ready; spawn skipped reason=%s",
			tostring(package_reason))
		return false
	end
	local spawner = Managers and Managers.state and Managers.state.unit_spawner
	local entity = Managers and Managers.state and Managers.state.entity
	local network = Managers and Managers.state and Managers.state.network
	local killed_pos, killed_pos_reason = _spirit_position(killed_unit)
	if not (spawner and entity and network and network.is_server and killed_pos
		and target_unit and Unit.alive(target_unit)) then
		_spirit_state.dropped = _spirit_state.dropped + 1
		_spirit_diag("spawn prerequisites unavailable attribution=%s position=%s",
			tostring(attribution), tostring(killed_pos_reason))
		return false
	end
	local spawn_position = killed_pos + Vector3(0, 0, _spirits.SPAWN_OFFSET_Z)
	local spirit_unit = spawner:spawn_network_unit(_spirits.UNIT,
		_spirits.UNIT_TEMPLATE, {}, spawn_position)
	if not spirit_unit then
		_spirit_state.dropped = _spirit_state.dropped + 1
		_spirit_diag("native spawn returned nil attribution=%s", tostring(attribution))
		return false
	end
	local entry = {
		unit = spirit_unit,
		target = target_unit,
		delay = _spirits.DELAY_TIME,
		chase = _spirits.CHASE_TIME,
		chase_logged = false,
	}
	_spirit_state.active[entry] = true
	_spirit_state.count = _spirit_state.count + 1
	_spirit_state.spawned = _spirit_state.spawned + 1
	local audio = entity:system("audio_system")
	if audio then
		audio:play_audio_position_event(_spirits.RELEASE_SOUND, spawn_position)
		audio:play_audio_unit_event(_spirits.LOOP_SOUND, spirit_unit)
	end
	_spirit_diag("spirit spawned attribution=%s active=%d total=%d",
		tostring(attribution), _spirit_state.count, _spirit_state.spawned)
	return true
end

local function _on_blightreaper_kill(killing_blow, _, killed_unit)
	local network = Managers and Managers.state and Managers.state.network
	if not (network and network.is_server and type(killing_blow) == "table"
		and killed_unit) then return end
	local indexes = rawget(_G, "DamageDataIndex")
	if type(indexes) ~= "table" then return end
	local owner_unit = killing_blow[indexes.SOURCE_ATTACKER_UNIT]
		or killing_blow[indexes.ATTACKER]
	if not owner_unit or not Unit.alive(owner_unit) then return end
	local wielding, identity_reason, backend_id, item_key = _owner_trait_evidence(
		owner_unit, _moveset.SHYISH_CURSE_TRAIT)
	local poison = _spirit_state.poison_sources[killed_unit]
	local poison_match = poison and poison.owner == owner_unit
	local poison_age = poison and (_spirit_now() - poison.t) or nil
	local damage_type = killing_blow[indexes.DAMAGE_TYPE]
	local attributable, reason = _spirits.kill_is_attributable(
		wielding, damage_type, poison_match, poison_age)
	local damage_source = killing_blow[indexes.DAMAGE_SOURCE]
	local report = (wielding or poison ~= nil)
		and _spirit_diag or _spirit_reject_diag
	report(
		"kill observed peer=%s damage=%s source=%s trait=%s identity=%s backend=%s item=%s poison_match=%s age=%s attributable=%s reason=%s",
		tostring(_player_peer_id(owner_unit)), tostring(damage_type),
		tostring(damage_source), tostring(wielding), tostring(identity_reason),
		tostring(backend_id), tostring(item_key), tostring(poison_match == true),
		poison_age and string.format("%.2f", poison_age) or "nil",
		tostring(attributable), tostring(reason))
	_spirit_state.poison_sources[killed_unit] = nil
	if attributable then _spawn_spirit(killed_unit, owner_unit, reason) end
end

function mod:_woc_on_blightreaper_kill(killing_blow, breed, killed_unit)
	_on_blightreaper_kill(killing_blow, breed, killed_unit)
end

_start_spirit_runtime = function()
	_ensure_spirit_package()
	local network = Managers and Managers.state and Managers.state.network
	local events = Managers and Managers.state and Managers.state.event
	if not (network and network.is_server and events) then return end
	if _spirit_state.event_manager == events then return end
	if _spirit_state.event_manager then
		pcall(_spirit_state.event_manager.unregister,
			_spirit_state.event_manager, "on_player_killed_enemy", mod)
	end
	events:register(mod, "on_player_killed_enemy", "_woc_on_blightreaper_kill")
	_spirit_state.event_manager = events
	_spirit_state.damage_index = 1
	_spirit_diag_budget = 24
	_spirit_reject_diag_budget = 8
	_spirit_diag("native Shyish listener armed cap=%d convert=%d delay=%.1f chase=%.1f/%.1f",
		_spirits.MAX_ACTIVE, _spirits.CONVERT_AMOUNT, _spirits.DELAY_TIME,
		_spirits.CHASE_SPEED, _spirits.CHASE_TIME)
end

_stop_spirit_runtime = function(reason)
	local events = _spirit_state.event_manager
	if events then pcall(events.unregister, events, "on_player_killed_enemy", mod) end
	_spirit_state.event_manager = nil
	local doomed = {}
	for entry in pairs(_spirit_state.active) do doomed[#doomed + 1] = entry end
	for i = 1, #doomed do _spirit_delete(doomed[i], reason or "stop", false) end
	_spirit_state.poison_sources = setmetatable({}, { __mode = "k" })
end

local function _update_spirits(dt)
	if _spirit_state.count == 0 then return end
	local doomed = {}
	for entry in pairs(_spirit_state.active) do
		local unit, target = entry.unit, entry.target
		if not (unit and Unit.alive(unit) and target and Unit.alive(target)) then
			doomed[#doomed + 1] = { entry, "dead_unit", false }
		else
			entry.delay = math.max(entry.delay - dt, 0)
			if entry.delay == 0 then
				local target_pos, target_pos_reason = _spirit_position(target)
				if not target_pos then
					doomed[#doomed + 1] = {
						entry, "target_position_invalid:" .. tostring(target_pos_reason), false,
					}
				else
					local position, position_reason = _spirit_position(unit)
					if not position then
						doomed[#doomed + 1] = {
							entry, "spirit_position_invalid:" .. tostring(position_reason), false,
						}
					else
						if not entry.chase_logged then
							entry.chase_logged = true
							_spirit_diag("spirit chase started remaining=%.1f", entry.chase)
						end
						local destination = target_pos + Vector3.up()
						local delta = destination - position
					local distance_sq = Vector3.length_squared(delta)
					local direction = Vector3.normalize(delta)
					if distance_sq <= _spirits.HIT_DISTANCE * _spirits.HIT_DISTANCE then
						local health = ScriptUnit.has_extension(target, "health_system")
						local damage_utils = rawget(_G, "DamageUtils")
						if health and type(health.current_permanent_health) == "function"
								and type(health.current_temporary_health) == "function"
								and type(damage_utils) == "table"
								and type(damage_utils.add_damage_network) == "function"
								and type(damage_utils.heal_network) == "function" then
							local permanent = health:current_permanent_health()
							local temporary = health:current_temporary_health()
							local amount = _spirits.contact_damage(permanent, temporary)
							local dealt = 0
							if amount > 0 then
								dealt = damage_utils.add_damage_network(target, unit, amount,
									"torso", _spirits.DAMAGE_TYPE, nil, direction,
									_spirits.DAMAGE_SOURCE, nil, nil, nil, nil, nil, nil,
									nil, nil, nil, nil, _spirit_state.damage_index) or 0
								_spirit_state.damage_index = _spirit_state.damage_index + 1
								if dealt > 0 then
									damage_utils.heal_network(target, target, dealt,
										_spirits.HEAL_TYPE)
								end
							end
							_spirit_state.converted = _spirit_state.converted + 1
							_spirit_diag(
								"spirit contact converted=%d requested=%d dealt=%.2f green=%.2f thp=%.2f",
								_spirit_state.converted, amount, dealt, permanent, temporary)
						else
							_spirit_diag("spirit contact skipped; native damage/heal seam unavailable")
						end
						doomed[#doomed + 1] = { entry, "hit", true }
					else
						entry.chase = math.max(entry.chase - dt, 0)
						Unit.set_local_position(unit, 0,
							position + direction * (dt * _spirits.CHASE_SPEED))
						if entry.chase == 0 then
							doomed[#doomed + 1] = { entry, "expired", true }
						end
					end
					end
				end
			end
		end
	end
	for i = 1, #doomed do
		_spirit_delete(doomed[i][1], doomed[i][2], doomed[i][3])
	end
end

_rt_register("issue632_blightreaper_shyish_spirit_contract", function()
	if _spirits.UNIT ~= "units/fx/vfx_animation_death_spirit_02"
		or _spirits.UNIT_TEMPLATE ~= "position_synched_dummy_unit" then
		return "native Shyish network-unit contract drifted"
	end
	if _spirits.SPIRIT_DAMAGE ~= 5 or _spirits.DELAY_TIME ~= 3
		or _spirits.CHASE_SPEED ~= 1 or _spirits.CHASE_TIME ~= 6 then
		return "rank-one Shyish conversion/chase values drifted"
	end
	if _spirits.MAX_ACTIVE ~= 32 then return "active spirit cap drifted" end
	local package_ready, package_reason = _spirits.package_ready(
		Managers and Managers.package)
	if not package_ready then
		return "source-backed Shyish package is not loaded: " .. tostring(package_reason)
	end
	local direct = _spirits.kill_is_attributable(true, "light_attack", false, nil)
	local dot = _spirits.kill_is_attributable(false, "arrow_poison_dot", true, 3)
	local stale = _spirits.kill_is_attributable(false, "arrow_poison_dot", true, 5)
	if not direct or not dot or stale then return "direct/DOT attribution policy regressed" end
	local position_key, live_position, lookup_position = {}, {}, {}
	local position, position_reason = _spirits.resolve_position(position_key,
		function() return live_position end,
		{ [position_key] = lookup_position },
		function(value) return value == live_position end)
	if position ~= live_position or position_reason ~= "live" then
		return "live spirit-position preference regressed"
	end
	position, position_reason = _spirits.resolve_position(position_key,
		function() error("unavailable") end,
		{ [position_key] = lookup_position },
		function(value) return value == lookup_position end)
	if position ~= lookup_position or position_reason ~= "lookup" then
		return "validated spirit-position fallback regressed"
	end
	if _spirits.contact_damage(10, 0) ~= 5
			or _spirits.contact_damage(3, 0) ~= 2
			or _spirits.contact_damage(2, 4) ~= 5 then
		return "native damage-to-mutator-heal contact amount regressed"
	end
	local audio = _spirits.audio_contract()
	if audio.release ~= "Play_winds_death_gameplay_spirit_release"
		or audio.loop ~= "Play_winds_death_gameplay_spirit_loop"
		or audio.explode ~= "Play_winds_death_gameplay_spirit_explode" then
		return "native Shyish audio contract drifted"
	end
end)

	local api = {}

	function api:start()
		return _start_spirit_runtime()
	end

	function api:stop(reason)
		return _stop_spirit_runtime(reason)
	end

	function api:update(dt)
		return _update_spirits(dt)
	end

	function api:mark_poison(hit_unit, owner_unit)
		return _mark_blight_poison(hit_unit, owner_unit)
	end

	function api:owner_has_wielded_trait(unit, trait_key)
		return _owner_has_wielded_trait(unit, trait_key)
	end

	return api
end

return M
