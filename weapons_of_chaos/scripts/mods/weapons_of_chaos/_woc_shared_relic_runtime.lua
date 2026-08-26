-- Runtime owner for issue #934's lobby-unique Blightreaper lease.
--
-- The pure state machine lives in _woc_shared_relic.lua. This module owns the
-- VMF hooks, same-mod channels, backend/live-slot convergence, transition
-- rehydration, and transient keep-trophy presentation.
local M = {}

function M.new(context)
	local mod = assert(context and context.mod, "shared relic runtime requires mod")
	local _shared_relic_policy = assert(context.policy,
		"shared relic runtime requires policy")
	local BACKEND_ID = assert(context.backend_id,
		"shared relic runtime requires backend id")
	local ITEM_KEY = assert(context.item_key,
		"shared relic runtime requires item key")
	local _remote_blightreaper = assert(context.remote_identity,
		"shared relic runtime requires remote identity cache")
	local _rt_register = assert(context.rt_register,
		"shared relic runtime requires regression registrar")
	local _identity_listener = context.identity_listener

	-- Issue #934: one Blightreaper may be actively equipped in a WOC lobby.  The
	-- host owns the lease and the exact render identity carried in its monotonic
	-- snapshots. No WOC identifier enters a vanilla RPC, so peers without WOC
	-- retain the existing `es_1h_sword` fallback.
	local _relic_lease_authority = _shared_relic_policy.new_state()
	local _relic_lease_view = {
		authority_peer = nil,
		authority_epoch = 0,
		generation = 0,
		holder = nil,
		holder_melee = false,
		holder_ranged = false,
		host = nil,
	}
	local _relic_lease_authority_epoch = 0
	local _relic_lease_epoch_counter = 0
	local _relic_lease_seen_epochs = {}
	local _relic_lease_client_session_counter = 0
	local _relic_lease_client_session_epoch = 0
	local _relic_lease_local_active = {}
	local _relic_lease_pending = {}
	local _relic_lease_rollback_retry = {}
	local _relic_lease_rollback = false
	local _relic_lease_migration_reservation_time = nil
	local _relic_lease_diag_budget = 24
	local _relic_lease_state_active = false
	local _relic_lease_missing_time = 0
	local _relic_lease_query_time = 0
	local _relic_lease_query_attempts = 0
	local _relic_lease_query_complete = false
	local _relic_lease_seeded = false
	local _relic_trophy_extensions = setmetatable({}, { __mode = "k" })
	local _relic_trophy_refreshing = false
	local _lease_enforce_local_denial

	local function _lease_diag(fmt, ...)
		if _relic_lease_diag_budget <= 0 then return end
		_relic_lease_diag_budget = _relic_lease_diag_budget - 1
		pcall(printf, "[WOC:934] " .. fmt, ...)
	end

	local function _lease_local_peer_id()
		local network = rawget(_G, "Network")
		if network and type(network.peer_id) == "function" then
			local ok, peer_id = pcall(network.peer_id)
			if ok and type(peer_id) == "string" and peer_id ~= "" then return peer_id end
		end
		local pm = Managers and Managers.player
		if pm and pm.network_manager and type(pm.local_player) == "function" then
			local ok, player = pcall(pm.local_player, pm, 1)
			local peer_id = ok and player and player.peer_id
			if type(peer_id) == "string" and peer_id ~= "" then return peer_id end
		end
		return nil
	end

	local function _lease_local_career_name()
		local pm = Managers and Managers.player
		if not (pm and type(pm.local_player) == "function") then return nil end
		local ok, player = pcall(pm.local_player, pm, 1)
		if not ok or not player then return nil end
		if type(player.career_name) == "function" then
			local career_ok, career_name = pcall(player.career_name, player)
			if career_ok and type(career_name) == "string"
					and career_name ~= "" then
				return career_name
			end
		end
		if type(player.profile_index) ~= "function"
				or type(player.career_index) ~= "function" then return nil end
		local profile_ok, profile_index = pcall(player.profile_index, player)
		local career_ok, career_index = pcall(player.career_index, player)
		local profile = profile_ok and SPProfiles and SPProfiles[profile_index]
		local career = career_ok and profile and profile.careers
			and profile.careers[career_index]
		return career and career.name or nil
	end

	local function _lease_host_peer_id()
		local mechanism = Managers and Managers.mechanism
		if mechanism and type(mechanism.server_peer_id) == "function" then
			local ok, peer_id = pcall(mechanism.server_peer_id, mechanism)
			if ok and type(peer_id) == "string" and peer_id ~= "" then return peer_id end
		end
		local nm = Managers and Managers.state and Managers.state.network
		local peer_id = nm and ((nm.network_client and nm.network_client.server_peer_id)
			or (nm.network_server and nm.network_server.server_peer_id))
		return type(peer_id) == "string" and peer_id ~= "" and peer_id or nil
	end

	local function _lease_is_server()
		local nm = Managers and Managers.state and Managers.state.network
		return nm and nm.is_server == true
	end

	local function _lease_identity_snapshot(peer_id)
		if not _relic_lease_state_active
				or type(peer_id) ~= "string" or peer_id == ""
				or type(_relic_lease_view.authority_peer) ~= "string"
				or _relic_lease_view.authority_peer == ""
				or type(_relic_lease_view.authority_epoch) ~= "number"
				or _relic_lease_view.authority_epoch < 1 then return nil end
		local holder = _relic_lease_view.holder == peer_id
		return {
			key = ITEM_KEY,
			peer_id = peer_id,
			authority_peer = _relic_lease_view.authority_peer,
			authority_epoch = _relic_lease_view.authority_epoch,
			generation = _relic_lease_view.generation,
			slot_melee = holder and _relic_lease_view.holder_melee == true or false,
			slot_ranged = holder and _relic_lease_view.holder_ranged == true or false,
		}
	end

	local function _lease_notify_identity(peer_id, reason)
		if type(_identity_listener) ~= "function" then return end
		local snapshot = _lease_identity_snapshot(peer_id)
		if snapshot then pcall(_identity_listener, peer_id, snapshot, reason) end
	end

	local function _lease_refresh_trophies(reason)
		if _relic_trophy_refreshing then return end
		_relic_trophy_refreshing = true
		local count = 0
		for extension in pairs(_relic_trophy_extensions) do
			local requested = extension._woc934_requested_trophy
			if requested and type(extension._load_trophy) == "function" then
				local ok = pcall(extension._load_trophy, extension, requested)
				if ok then count = count + 1 end
			end
		end
		_relic_trophy_refreshing = false
		if count > 0 then
			_lease_diag("trophy refresh reason=%s holder=%s count=%d",
				tostring(reason), tostring(_relic_lease_view.holder or "none"), count)
		end
	end

	local function _lease_rewield_remote_peer(peer_id)
		local local_peer = _lease_local_peer_id()
		if peer_id == local_peer then return end
		local pm = Managers and Managers.player
		local ok, player = false, nil
		if pm and type(pm.player_from_peer_id) == "function" then
			ok, player = pcall(pm.player_from_peer_id, pm, peer_id, 1)
		end
		local unit = ok and player and player.player_unit
		if not (unit and Unit.alive(unit)) then return end
		local inventory
		pcall(function()
			inventory = ScriptUnit.has_extension(unit, "inventory_system")
		end)
		if inventory and _shared_relic_policy.is_valid_slot(inventory.wielded_slot)
				and type(inventory.wield) == "function" then
			pcall(inventory.wield, inventory, inventory.wielded_slot)
		end
	end

	-- Render identity is part of the authenticated host snapshot, never a
	-- client-authored sideband. Replacing the complete cache makes state/identity
	-- ordering atomic: a delayed rival packet has no independent write surface.
	local function _lease_apply_authoritative_remote_identity(
			holder, holder_melee, holder_ranged)
		local touched = {}
		for peer_id, slots in pairs(_remote_blightreaper) do
			if type(slots) == "table" then
				local melee = peer_id == holder and holder_melee == true
				local ranged = peer_id == holder and holder_ranged == true
				if slots.slot_melee ~= melee or slots.slot_ranged ~= ranged then
					slots.slot_melee = melee
					slots.slot_ranged = ranged
					touched[peer_id] = true
				end
			else
				_remote_blightreaper[peer_id] = nil
			end
		end
		if holder and (holder_melee or holder_ranged) then
			local slots = _remote_blightreaper[holder]
			if type(slots) ~= "table" then
				slots = {}
				_remote_blightreaper[holder] = slots
			end
			if slots.slot_melee ~= holder_melee
					or slots.slot_ranged ~= holder_ranged then
				slots.slot_melee = holder_melee
				slots.slot_ranged = holder_ranged
				touched[holder] = true
			end
		end
		for peer_id in pairs(touched) do
			_lease_rewield_remote_peer(peer_id)
		end
		return touched
	end

	local function _lease_begin_authority_epoch(reason)
		local local_peer = _lease_local_peer_id()
		_relic_lease_epoch_counter = _relic_lease_epoch_counter + 1
		_relic_lease_authority_epoch = _relic_lease_epoch_counter
		_relic_lease_view.authority_epoch = _relic_lease_authority_epoch
		_relic_lease_view.authority_peer = local_peer
		_relic_lease_view.generation = 0
		_relic_lease_view.holder = nil
		_relic_lease_view.holder_melee = false
		_relic_lease_view.holder_ranged = false
		if local_peer then
			_relic_lease_seen_epochs[local_peer] = _relic_lease_authority_epoch
		end
		_lease_diag("authority epoch reason=%s epoch=%d",
			tostring(reason), _relic_lease_authority_epoch)
	end

	local function _lease_accept_authority_epoch(sender_peer_id, incoming_epoch)
		if not _relic_lease_state_active then return false, "inactive-session" end
		if type(sender_peer_id) ~= "string" or sender_peer_id == "" then
			return false, "invalid-authority"
		end
		if type(incoming_epoch) ~= "number" or incoming_epoch < 1
				or incoming_epoch ~= math.floor(incoming_epoch) then
			return false, "invalid-epoch"
		end
		local seen = _relic_lease_seen_epochs[sender_peer_id] or 0
		if incoming_epoch < seen then return false, "old-session" end
		local authority_changed =
			_relic_lease_view.authority_peer ~= sender_peer_id
		if incoming_epoch == seen
				and (_relic_lease_view.authority_epoch == 0
					or authority_changed) then
			return false, "closed-session-replay"
		end
		if authority_changed then
			_relic_lease_seen_epochs[sender_peer_id] = incoming_epoch
			_relic_lease_view.authority_peer = sender_peer_id
			_relic_lease_view.authority_epoch = incoming_epoch
			_relic_lease_view.generation = 0
			_relic_lease_view.holder = nil
			_relic_lease_view.holder_melee = false
			_relic_lease_view.holder_ranged = false
			return true, "authority-changed"
		end
		if _relic_lease_view.authority_epoch ~= 0
				and incoming_epoch < _relic_lease_view.authority_epoch then
			return false, "old-authority"
		end
		if incoming_epoch > seen then
			_relic_lease_seen_epochs[sender_peer_id] = incoming_epoch
		end
		if incoming_epoch > _relic_lease_view.authority_epoch then
			_relic_lease_view.authority_epoch = incoming_epoch
			_relic_lease_view.generation = 0
			_relic_lease_view.holder = nil
			_relic_lease_view.holder_melee = false
			_relic_lease_view.holder_ranged = false
		end
		return incoming_epoch == _relic_lease_view.authority_epoch,
			incoming_epoch == _relic_lease_view.authority_epoch
				and "current" or "epoch-conflict"
	end

	local function _lease_apply_view(authority_peer_id, authority_epoch,
			generation, holder, holder_melee, holder_ranged, reason)
		local prior = {
			authority_peer = _relic_lease_view.authority_peer,
			authority_epoch = _relic_lease_view.authority_epoch,
			generation = _relic_lease_view.generation,
			holder = _relic_lease_view.holder,
			holder_melee = _relic_lease_view.holder_melee,
			holder_ranged = _relic_lease_view.holder_ranged,
		}
		local holder_present = type(holder) == "string" and holder ~= ""
		if type(holder_melee) ~= "boolean" or type(holder_ranged) ~= "boolean"
				or (not holder_present and (holder_melee or holder_ranged)) then
			return false, "invalid-holder-slots"
		end
		local epoch_ok, epoch_verdict = _lease_accept_authority_epoch(
			authority_peer_id, authority_epoch)
		if not epoch_ok then
			_lease_diag("snapshot dropped reason=%s verdict=%s epoch=%s gen=%s holder=%s",
				tostring(reason), tostring(epoch_verdict), tostring(authority_epoch),
				tostring(generation), tostring(holder))
			return false, epoch_verdict
		end
		local accepted, verdict, next_generation, next_holder =
			_shared_relic_policy.accept_snapshot(
				_relic_lease_view.generation, _relic_lease_view.holder,
				generation, holder)
		if not accepted then
			_lease_diag("snapshot dropped reason=%s verdict=%s gen=%s holder=%s",
				tostring(reason), tostring(verdict), tostring(generation), tostring(holder))
			return false, verdict
		end
		local changed = next_generation ~= _relic_lease_view.generation
			or next_holder ~= _relic_lease_view.holder
		_relic_lease_view.generation = next_generation
		_relic_lease_view.holder = next_holder
		_relic_lease_view.holder_melee = holder_melee
		_relic_lease_view.holder_ranged = holder_ranged
		_relic_lease_query_complete = true
		local touched = _lease_apply_authoritative_remote_identity(
			next_holder, holder_melee, holder_ranged)
		-- TeamPreviewer consumers use the same accepted host snapshot as gameplay
		-- husks. A new authority/generation remains a new consumer token even when
		-- its slot bits equal the prior cache, so include the current holder in that
		-- case. Equal complete replays produce neither another rewield nor another
		-- preview request.
		local identity_changed = prior.authority_peer ~= _relic_lease_view.authority_peer
			or prior.authority_epoch ~= _relic_lease_view.authority_epoch
			or prior.generation ~= next_generation
			or prior.holder ~= next_holder
			or prior.holder_melee ~= holder_melee
			or prior.holder_ranged ~= holder_ranged
		local notify = {}
		for peer_id in pairs(touched) do notify[peer_id] = true end
		if identity_changed and next_holder and (holder_melee or holder_ranged) then
			notify[next_holder] = true
		end
		for peer_id in pairs(notify) do
			_lease_notify_identity(peer_id, reason)
		end
		if changed then
			_lease_diag("lease state reason=%s generation=%d holder=%s",
				tostring(reason), next_generation, tostring(next_holder or "none"))
			_lease_refresh_trophies(reason)
		end
		if _lease_enforce_local_denial then
			_lease_enforce_local_denial("authority-applied:" .. tostring(reason))
		end
		return true, verdict
	end

	local function _lease_publish_state(recipient, reason, target_session_epoch)
		local holder = _relic_lease_authority.holder or ""
		local claims = _relic_lease_authority.holder
			and _relic_lease_authority.claims[_relic_lease_authority.holder]
		local holder_melee = type(claims) == "table"
			and claims.slot_melee == true
		local holder_ranged = type(claims) == "table"
			and claims.slot_ranged == true
		pcall(mod.network_send, mod, "woc_relic_lease_state_v1",
			recipient or "others", _shared_relic_policy.SCHEMA,
			_relic_lease_authority_epoch,
			_relic_lease_authority.generation, holder,
			target_session_epoch or 0,
			holder_melee and 1 or 0, holder_ranged and 1 or 0)
		_lease_apply_view(_lease_local_peer_id(), _relic_lease_authority_epoch,
			_relic_lease_authority.generation, holder,
			holder_melee, holder_ranged, reason)
	end

	local function _lease_apply_host_identity(peer_id, slot_name, active, reason)
		if not _relic_lease_state_active or not _lease_is_server()
				or _relic_lease_authority_epoch < 1 then return end
		local changed, verdict = _shared_relic_policy.apply_identity(
			_relic_lease_authority, peer_id, slot_name, active)
		if not _shared_relic_policy.is_migration_reserved(_relic_lease_authority) then
			_relic_lease_migration_reservation_time = nil
		end
		_lease_diag("identity peer=%s slot=%s active=%s verdict=%s",
			tostring(peer_id), tostring(slot_name), tostring(active), tostring(verdict))
		-- A denied simultaneous claimant needs the unchanged authoritative state too.
		if changed or verdict == "denied" then
			_lease_publish_state("others", reason or verdict)
		elseif _lease_enforce_local_denial then
			_lease_enforce_local_denial("host-identity:" .. tostring(reason))
		end
	end

	local function _lease_readback(career_name, slot_name)
		if not (rawget(_G, "BackendUtils")
				and type(BackendUtils.get_loadout_item_id) == "function") then
			return nil, "readback-unavailable"
		end
		local ok, backend_id = pcall(BackendUtils.get_loadout_item_id,
			career_name, slot_name)
		if not ok then return nil, "readback-error" end
		return backend_id, "readback"
	end

	local function _lease_local_inventory()
		local pm = Managers and Managers.player
		if not (pm and type(pm.local_player) == "function") then return nil end
		local ok, player = pcall(pm.local_player, pm, 1)
		local unit = ok and player and player.player_unit
		if not (unit and Unit.alive(unit)) then return nil end
		local inventory
		if type(ScriptUnit.has_extension) == "function" then
			local extension_ok, value = pcall(
				ScriptUnit.has_extension, unit, "inventory_system")
			if extension_ok then inventory = value end
		end
		return inventory
	end

	local function _lease_live_backend_id(inventory, slot_name)
		if not inventory then return nil, nil, "inventory-unavailable" end
		local equipment = inventory and inventory._equipment
		local slots = equipment and equipment.slots
		if type(slots) ~= "table" then
			return nil, nil, "equipment-unavailable"
		end
		local slot_data = slots[slot_name]
		if slot_data == nil then return nil, nil, "empty" end
		local item_data = slot_data and (slot_data.item_data or slot_data.master_item)
		if type(item_data) ~= "table" then
			return nil, nil, "item-unavailable"
		end
		local backend_id = item_data.backend_id or item_data.ItemId
		if type(backend_id) ~= "string" or backend_id == "" then
			return nil, item_data, "backend-id-unavailable"
		end
		return backend_id, item_data, "exact"
	end

	local function _lease_live_read_verified(status)
		return status == "exact" or status == "empty"
	end

	local function _lease_item_backend_id(item)
		if type(item) ~= "table" then return nil end
		return item.backend_id or item.ItemId
	end

	local function _lease_recreate_exact_live(slot_name, backend_id)
		local inventory = _lease_local_inventory()
		if not (inventory and type(inventory.create_equipment_in_slot) == "function") then
			return false, "inventory-unavailable"
		end
		local live_backend = _lease_live_backend_id(inventory, slot_name)
		if live_backend == backend_id then return true, "already-live" end
		_relic_lease_rollback = true
		local ok, result = pcall(inventory.create_equipment_in_slot,
			inventory, slot_name, backend_id)
		_relic_lease_rollback = false
		if not ok or result == false then
			return false, ok and "live-write-rejected" or "live-write-error"
		end
		return true, "live-spawn-queued"
	end

	local function _lease_empty_exact_relic_live(slot_name)
		local inventory = _lease_local_inventory()
		if not inventory then return false, "inventory-unavailable" end
		local live_backend, _, live_status =
			_lease_live_backend_id(inventory, slot_name)
		if live_status == "empty" then return true, "already-empty" end
		if live_status ~= "exact" then return false, live_status end
		if live_backend ~= BACKEND_ID then return true, "already-replaced" end
		if type(inventory.destroy_slot) ~= "function" then
			return false, "destroy-unavailable"
		end
		_relic_lease_rollback = true
		local ok, result = pcall(inventory.destroy_slot, inventory, slot_name, true)
		_relic_lease_rollback = false
		if not ok or result == false then
			return false, ok and "destroy-rejected" or "destroy-error"
		end
		local remaining, _, remaining_status =
			_lease_live_backend_id(inventory, slot_name)
		if not _lease_live_read_verified(remaining_status) then
			return false, remaining_status
		end
		if remaining == BACKEND_ID then
			return false, "relic-remained-live"
		end
		return true, "emptied"
	end

	local function _lease_complete_local_release(slot_name, career, reason,
			mode, target_backend_id, persisted_backend_id, live_backend_id,
			persisted_read_verified, live_read_verified)
		if not _shared_relic_policy.rollback_converged(
				mode, target_backend_id, persisted_backend_id, live_backend_id,
				persisted_read_verified, live_read_verified) then
			_lease_diag("release blocked reason=%s slot=%s mode=%s target=%s persisted=%s live=%s",
				tostring(reason), tostring(slot_name), tostring(mode),
				tostring(target_backend_id), tostring(persisted_backend_id),
				tostring(live_backend_id))
			return false
		end
		_relic_lease_local_active[slot_name] = false
		_relic_lease_pending[slot_name] = nil
		_relic_lease_rollback_retry[slot_name] = nil
		local peer_id = _lease_local_peer_id()
		if peer_id and _lease_is_server() then
			_lease_apply_host_identity(peer_id, slot_name, false, reason)
		else
			local host = _lease_host_peer_id()
			if host and _relic_lease_view.authority_epoch > 0 then
				pcall(mod.network_send, mod, "woc_relic_lease_intent_v1", host,
					_shared_relic_policy.SCHEMA,
					_relic_lease_view.authority_peer,
					_relic_lease_view.authority_epoch, slot_name, 0)
			end
		end
		_lease_diag("rollback complete reason=%s slot=%s career=%s mode=%s persisted=%s live=%s",
			tostring(reason), tostring(slot_name), tostring(career), tostring(mode),
			tostring(persisted_backend_id), tostring(live_backend_id))
		return true
	end

	local function _lease_attempt_local_rollback(slot_name, reason)
		local local_peer = _lease_local_peer_id()
		if not local_peer or not _shared_relic_policy.should_rollback(
				_relic_lease_view.holder, local_peer,
				_relic_lease_local_active[slot_name]) then
			_relic_lease_rollback_retry[slot_name] = nil
			return false
		end
		local retry = _relic_lease_rollback_retry[slot_name]
		if not retry then
			retry = { elapsed = 0, attempts = 0, delay = 0 }
			_relic_lease_rollback_retry[slot_name] = retry
		end
		retry.attempts = retry.attempts + 1
		retry.elapsed = 0
		retry.delay = _shared_relic_policy.rollback_retry_delay(retry.attempts)
		retry.fail_closed =
			_shared_relic_policy.rollback_is_terminal_fail_closed(retry.attempts)

		local pending = _relic_lease_pending[slot_name]
		if not pending then
			pending = { career = _lease_local_career_name(), previous = nil }
			_relic_lease_pending[slot_name] = pending
		end
		local career = pending.career or _lease_local_career_name()
		pending.career = career
		retry.career = career
		local current, read_reason
		if career then
			current, read_reason = _lease_readback(career, slot_name)
		else
			read_reason = "career-unavailable"
		end
		local live_inventory = _lease_local_inventory()
		local live_backend, _, live_status =
			_lease_live_backend_id(live_inventory, slot_name)
		if retry.phase and _shared_relic_policy.rollback_converged(
				retry.phase, retry.target, current, live_backend,
				read_reason == "readback",
				_lease_live_read_verified(live_status)) then
			return _lease_complete_local_release(slot_name, career,
				"verified-persisted-and-live", retry.phase, retry.target,
				current, live_backend, read_reason == "readback", true)
		end

		-- Denial is a live fail-closed boundary, independent of backend health.
		-- Remove the rival unit on every attempt before touching durable state;
		-- the direct-spawn and backend hooks continue rejecting recreation while
		-- the bounded-backoff retry remains pending.
		if live_backend == BACKEND_ID then
			_lease_empty_exact_relic_live(slot_name)
			live_inventory = _lease_local_inventory()
			live_backend, _, live_status =
				_lease_live_backend_id(live_inventory, slot_name)
		end

		local resolution, fallback = _shared_relic_policy.loser_resolution(
			pending.previous, current)
		retry.phase = resolution
		retry.target = fallback

		if resolution == "clear-persisted" then
			if not (career and rawget(_G, "BackendUtils")
					and type(BackendUtils.set_loadout_item) == "function") then
				_lease_diag("durable clear deferred reason=%s slot=%s career=%s read=%s attempt=%d fail_closed=%s next=%.2f",
					tostring(reason), tostring(slot_name), tostring(career),
					tostring(read_reason), retry.attempts,
					tostring(retry.fail_closed), retry.delay)
				return false
			end
			_relic_lease_rollback = true
			local ok, result = pcall(BackendUtils.set_loadout_item,
				nil, career, slot_name)
			_relic_lease_rollback = false
			local cleared_backend, cleared_reason =
				_lease_readback(career, slot_name)
			local cleared = _shared_relic_policy.clear_verified(
				ok and result ~= false, cleared_backend, cleared_reason)
			if not cleared then
				_lease_diag("durable clear unverified reason=%s slot=%s career=%s result=%s read=%s attempt=%d fail_closed=%s next=%.2f",
					tostring(reason), tostring(slot_name), tostring(career),
					tostring(result), tostring(cleared_backend), retry.attempts,
					tostring(retry.fail_closed), retry.delay)
				return false
			end
			local emptied, empty_reason = _lease_empty_exact_relic_live(slot_name)
			local cleared_inventory = _lease_local_inventory()
			local cleared_live, _, cleared_live_status = _lease_live_backend_id(
				cleared_inventory, slot_name)
			if emptied and _shared_relic_policy.rollback_converged(
					resolution, nil, cleared_backend, cleared_live,
					cleared_reason == "readback",
					_lease_live_read_verified(cleared_live_status)) then
				return _lease_complete_local_release(slot_name, career,
					"durable-clear:" .. tostring(empty_reason),
					resolution, nil, cleared_backend, cleared_live,
					true, true)
			end
			_lease_diag("durable clear live deferred reason=%s slot=%s detail=%s live=%s attempt=%d fail_closed=%s next=%.2f",
				tostring(reason), tostring(slot_name), tostring(empty_reason),
				tostring(cleared_live), retry.attempts,
				tostring(retry.fail_closed), retry.delay)
			return false
		end

		if resolution == "align-persisted" and fallback then
			local queued, queue_reason =
				_lease_recreate_exact_live(slot_name, fallback)
			local aligned_inventory = _lease_local_inventory()
			local aligned_live, _, aligned_live_status = _lease_live_backend_id(
				aligned_inventory, slot_name)
			if _shared_relic_policy.rollback_converged(
					resolution, fallback, current, aligned_live,
					read_reason == "readback",
					_lease_live_read_verified(aligned_live_status)) then
				return _lease_complete_local_release(slot_name, career,
					"aligned-persisted-live", resolution, fallback,
					current, aligned_live, true, true)
			end
			_lease_diag("persisted alignment deferred reason=%s slot=%s target=%s queued=%s detail=%s live=%s attempt=%d fail_closed=%s next=%.2f",
				tostring(reason), tostring(slot_name), tostring(fallback),
				tostring(queued), tostring(queue_reason), tostring(aligned_live),
				retry.attempts, tostring(retry.fail_closed), retry.delay)
			return false
		end

		if not (resolution == "restore-exact" and fallback and career
				and rawget(_G, "BackendUtils")
				and type(BackendUtils.set_loadout_item) == "function") then
			_lease_diag("rollback deferred reason=%s slot=%s career=%s resolution=%s read=%s attempt=%d fail_closed=%s next=%.2f",
				tostring(reason), tostring(slot_name), tostring(career),
				tostring(resolution), tostring(read_reason), retry.attempts,
				tostring(retry.fail_closed), retry.delay)
			return false
		end

		_relic_lease_rollback = true
		local ok, result = pcall(BackendUtils.set_loadout_item,
			fallback, career, slot_name)
		_relic_lease_rollback = false
		local read_back, verify_reason = _lease_readback(career, slot_name)
		local write_ok = ok and result ~= false
		local restored = _shared_relic_policy.rollback_verified(
			write_ok, fallback, read_back)
		if restored then
			retry.phase = "restore-exact"
			retry.target = fallback
			local queued, queue_reason =
				_lease_recreate_exact_live(slot_name, fallback)
			local restored_inventory = _lease_local_inventory()
			local restored_live, _, restored_live_status = _lease_live_backend_id(
				restored_inventory, slot_name)
			_lease_diag("backend rollback verified; live replacement reason=%s slot=%s target=%s queued=%s detail=%s",
				tostring(reason), tostring(slot_name), tostring(fallback),
				tostring(queued), tostring(queue_reason))
			if _shared_relic_policy.rollback_converged(
					"restore-exact", fallback, read_back, restored_live,
					verify_reason == "readback",
					_lease_live_read_verified(restored_live_status)) then
				return _lease_complete_local_release(slot_name, career, reason,
					"restore-exact", fallback, read_back, restored_live,
					true, true)
			end
			return false
		end
		_lease_diag("rollback unverified reason=%s slot=%s career=%s fallback=%s result=%s read=%s verify=%s attempt=%d fail_closed=%s next=%.2f",
			tostring(reason), tostring(slot_name), tostring(career), tostring(fallback),
			tostring(result), tostring(read_back), tostring(verify_reason),
			retry.attempts, tostring(retry.fail_closed), retry.delay)
		return false
	end

	_lease_enforce_local_denial = function(reason)
		local local_peer = _lease_local_peer_id()
		if not local_peer then return end
		for slot_name, active in pairs(_relic_lease_local_active) do
			if _shared_relic_policy.should_rollback(
					_relic_lease_view.holder, local_peer, active) then
				_lease_attempt_local_rollback(slot_name, reason)
			end
		end
	end

	local function _lease_on_local_identity(slot_name, active)
		if not _shared_relic_policy.is_valid_slot(slot_name) then return end
		_relic_lease_local_active[slot_name] = active and true or false
		local peer_id = _lease_local_peer_id()
		if peer_id and _lease_is_server() then
			_lease_apply_host_identity(peer_id, slot_name, active,
				active and "host-equip" or "host-unequip")
		elseif peer_id then
			local host = _lease_host_peer_id()
			if host and _relic_lease_view.authority_epoch > 0 then
				pcall(mod.network_send, mod, "woc_relic_lease_intent_v1", host,
					_shared_relic_policy.SCHEMA,
					_relic_lease_view.authority_peer,
					_relic_lease_view.authority_epoch,
					slot_name, active and 1 or 0)
			end
		end
		if not active then
			_relic_lease_pending[slot_name] = nil
			_relic_lease_rollback_retry[slot_name] = nil
		end
	end

	local function _lease_is_local_human(player)
		if type(player) ~= "table" then return false end
		if player.bot_player == true then return false end
		local local_peer = _lease_local_peer_id()
		local local_player_id
		if type(player.local_player_id) == "function" then
			local ok, value = pcall(player.local_player_id, player)
			if ok then local_player_id = value end
		elseif type(player.local_player_id) == "number" then
			local_player_id = player.local_player_id
		elseif type(player._local_player_id) == "number" then
			local_player_id = player._local_player_id
		end
		return local_peer ~= nil and player.peer_id == local_peer
			and local_player_id == 1
	end

	-- The native Hero loadout action ignores BackendUtils.set_loadout_item's
	-- return and queues the clicked backend id for live spawning regardless. Gate
	-- that actual action before vanilla can persist or enqueue a rival relic.
	mod:hook("HeroViewStateOverview", "_set_loadout_item",
		function(func, self, item, strict_slot_name, ...)
			local backend_id = _lease_item_backend_id(item)
			local slot_name = strict_slot_name
			if not slot_name and type(item) == "table" and type(item.data) == "table" then
				local slot_type = item.data.slot_type
				slot_name = slot_type == "melee" and "slot_melee"
					or slot_type == "ranged" and "slot_ranged"
					or nil
			end
			local local_peer = _lease_local_peer_id()
			if local_peer and not _shared_relic_policy.can_equip_backend(
					_relic_lease_view.holder, local_peer, backend_id, slot_name) then
				_lease_diag("hero equip blocked holder=%s local=%s slot=%s",
					tostring(_relic_lease_view.holder), tostring(local_peer),
					tostring(slot_name))
				return false
			end
			return func(self, item, strict_slot_name, ...)
		end)

	-- A direct live-spawn caller can bypass the Hero view. If authority is already
	-- known, do not let the custom unit replace the current live equipment. The
	-- rollback state machine reconciles any backend write that happened first.
	mod:hook("SimpleInventoryExtension", "create_equipment_in_slot",
		function(func, self, slot_name, backend_id, ...)
			local local_peer = _lease_local_peer_id()
			if _lease_is_local_human(self and self.player) and local_peer
					and not _shared_relic_policy.can_equip_backend(
						_relic_lease_view.holder, local_peer, backend_id, slot_name) then
				_relic_lease_local_active[slot_name] = true
				_lease_diag("live equip blocked holder=%s local=%s slot=%s",
					tostring(_relic_lease_view.holder), tostring(local_peer),
					tostring(slot_name))
				_lease_attempt_local_rollback(slot_name, "live-equip-gate")
				return false
			end
			return func(self, slot_name, backend_id, ...)
		end)

	mod:network_register("woc_relic_lease_intent_v1",
		function(sender_peer_id, schema, authority_peer_id, authority_epoch,
				slot_name, active)
			if not _relic_lease_state_active
					or schema ~= _shared_relic_policy.SCHEMA
					or not _lease_is_server()
					or authority_peer_id ~= _lease_local_peer_id()
					or type(authority_epoch) ~= "number"
					or authority_epoch ~= _relic_lease_authority_epoch
					or authority_epoch < 1
					or (active ~= 0 and active ~= 1) then return end
			_lease_apply_host_identity(sender_peer_id, slot_name, active == 1,
				"remote-intent")
		end)

	mod:network_register("woc_relic_lease_state_v1",
		function(sender_peer_id, schema, authority_epoch, generation, holder,
				target_session_epoch, holder_melee, holder_ranged)
			if not _relic_lease_state_active
					or schema ~= _shared_relic_policy.SCHEMA
					or type(target_session_epoch) ~= "number"
					or (holder_melee ~= 0 and holder_melee ~= 1)
					or (holder_ranged ~= 0 and holder_ranged ~= 1)
					or (target_session_epoch ~= 0
						and target_session_epoch
							~= _relic_lease_client_session_epoch) then
				return
			end
			local host = _lease_host_peer_id()
			if not host or sender_peer_id ~= host then
				_lease_diag("state rejected sender=%s expected_host=%s",
					tostring(sender_peer_id), tostring(host))
				return
			end
			if _relic_lease_view.host ~= host then
				_relic_lease_view.host = host
				_relic_lease_query_time = 0
				_relic_lease_query_attempts = 0
				_relic_lease_query_complete = false
			end
			_lease_apply_view(sender_peer_id, authority_epoch,
				generation, holder, holder_melee == 1, holder_ranged == 1,
				"host-snapshot")
		end)

	mod:network_register("woc_relic_lease_query_v1",
		function(sender_peer_id, schema, authority_peer_id, authority_epoch,
				client_session_epoch)
			if not _relic_lease_state_active
					or schema ~= _shared_relic_policy.SCHEMA
					or not _lease_is_server()
					or authority_peer_id ~= _lease_local_peer_id()
					or type(authority_epoch) ~= "number"
					or type(client_session_epoch) ~= "number"
					or client_session_epoch < 1
					or client_session_epoch ~= math.floor(client_session_epoch)
					or (authority_epoch ~= 0
						and authority_epoch ~= _relic_lease_authority_epoch) then
				return
			end
			_lease_publish_state(sender_peer_id, "query-reply",
				client_session_epoch)
		end)

	-- Transient presentation only: never overwrite the player's selected trophy
	-- or vanilla keep game object. WOC peers render the already-resident empty
	-- trophy while a lease exists; peers without WOC retain vanilla presentation.
	mod:hook("KeepDecorationTrophyExtension", "_load_trophy",
		function(func, self, trophy, ...)
			_relic_trophy_extensions[self] = true
			if not _relic_trophy_refreshing then self._woc934_requested_trophy = trophy end
			local requested = self._woc934_requested_trophy or trophy
			local shown = _shared_relic_policy.trophy_for(
				requested, _relic_lease_view.holder)
			if shown ~= requested then
				_lease_diag("trophy substitute requested=%s shown=%s",
					tostring(requested), tostring(shown))
			end
			return func(self, shown, ...)
		end)

	-- Stable outer equip seam. It sees the canonical backend id even when another
	-- mod supplies a loadout-interface override. Known rival leases fail closed;
	-- a simultaneous race records the prior item so the host snapshot can roll the
	-- losing claimant back without persisting a second active relic.
	if rawget(_G, "BackendUtils") and type(BackendUtils.set_loadout_item) == "function" then
		mod:hook(BackendUtils, "set_loadout_item",
			function(func, backend_id, career_name, slot_name, ...)
				if not _relic_lease_rollback and backend_id == BACKEND_ID
						and _shared_relic_policy.is_valid_slot(slot_name) then
					local local_peer = _lease_local_peer_id()
					if local_peer and not _shared_relic_policy.can_equip_backend(
							_relic_lease_view.holder, local_peer,
							backend_id, slot_name) then
						_lease_diag("equip blocked holder=%s local=%s career=%s slot=%s",
							tostring(_relic_lease_view.holder), tostring(local_peer),
							tostring(career_name), tostring(slot_name))
						return false
					end
					local previous
					if type(BackendUtils.get_loadout_item_id) == "function" then
						local ok, value = pcall(BackendUtils.get_loadout_item_id,
							career_name, slot_name)
						if ok and value ~= BACKEND_ID then previous = value end
					end
					_relic_lease_pending[slot_name] = {
						career = career_name,
						previous = previous,
					}
				end
				return func(backend_id, career_name, slot_name, ...)
			end)
	end

	local function _lease_retry_rollbacks(dt)
		for slot_name, retry in pairs(_relic_lease_rollback_retry) do
			retry.elapsed = retry.elapsed + dt
			if retry.elapsed >= (retry.delay
					or _shared_relic_policy.rollback_retry_delay(retry.attempts)) then
				_lease_attempt_local_rollback(slot_name, "bounded-backoff-retry")
			end
		end
	end

	-- Rehydrate local identity from the active career's durable loadout and the
	-- exact live inventory slots once per game-state session. This makes a
	-- pre-equipped loser fail closed again after keep/mission transitions even
	-- when no fresh Hero-view equip action or loadout sync payload occurs.
	local function _lease_seed_local_slots()
		if _relic_lease_seeded then return true end
		local career = _lease_local_career_name()
		local inventory = _lease_local_inventory()
		if not career or not inventory then return false end
		local seeded = {}
		for _, slot_name in ipairs({ "slot_melee", "slot_ranged" }) do
			local persisted, persisted_status =
				_lease_readback(career, slot_name)
			local live, _, live_status =
				_lease_live_backend_id(inventory, slot_name)
			if persisted_status ~= "readback"
					or not _lease_live_read_verified(live_status) then
				return false
			end
			local active = persisted == BACKEND_ID or live == BACKEND_ID
			seeded[slot_name] = active
		end
		local became_active = false
		for slot_name, active in pairs(seeded) do
			local prior = _relic_lease_local_active[slot_name] == true
			_relic_lease_local_active[slot_name] = active
			if active and not prior then became_active = true end
			if active and not _relic_lease_pending[slot_name] then
				_relic_lease_pending[slot_name] = {
					career = career,
					previous = nil,
				}
			end
		end
		_relic_lease_seeded = true
		if _lease_is_server() then
			local peer_id = _lease_local_peer_id()
			if peer_id then
				for slot_name, active in pairs(seeded) do
					if active then
						_lease_apply_host_identity(peer_id, slot_name, true,
							"delayed-local-seed")
					end
				end
			end
		end
		if became_active then
			_lease_enforce_local_denial("delayed-local-seed")
		end
		_lease_diag("session identity seeded career=%s melee=%s ranged=%s",
			tostring(career),
			tostring(_relic_lease_local_active.slot_melee == true),
			tostring(_relic_lease_local_active.slot_ranged == true))
		return true
	end

	local function _lease_send_reassert_and_query(host)
		local authority_epoch = _relic_lease_view.authority_epoch
		local local_peer = _lease_local_peer_id()
		if authority_epoch > 0
				and (_relic_lease_view.holder == nil
					or _relic_lease_view.holder == local_peer) then
			for _, slot_name in ipairs({ "slot_melee", "slot_ranged" }) do
				local active = _relic_lease_local_active[slot_name] == true
				pcall(mod.network_send, mod, "woc_relic_lease_intent_v1", host,
					_shared_relic_policy.SCHEMA, host, authority_epoch,
					slot_name, active and 1 or 0)
			end
		end
		pcall(mod.network_send, mod, "woc_relic_lease_query_v1", host,
			_shared_relic_policy.SCHEMA, host, authority_epoch,
			_relic_lease_client_session_epoch)
	end

	local function _lease_needs_claim_reassert(local_peer)
		if not local_peer then return false end
		if _relic_lease_view.holder ~= nil
				and _relic_lease_view.holder ~= local_peer then
			return false
		end
		for _, slot_name in ipairs({ "slot_melee", "slot_ranged" }) do
			local local_active = _relic_lease_local_active[slot_name] == true
			local acknowledged = false
			if _relic_lease_view.holder == local_peer then
				if slot_name == "slot_melee" then
					acknowledged = _relic_lease_view.holder_melee
				else
					acknowledged = _relic_lease_view.holder_ranged
				end
			end
			if local_active ~= acknowledged then return true end
		end
		return false
	end

	local function _lease_update(dt)
		if not _relic_lease_state_active then return end
		dt = tonumber(dt) or 0
		_lease_seed_local_slots()
		_lease_retry_rollbacks(dt)
		local host = _lease_host_peer_id()
		local local_peer = _lease_local_peer_id()
		local host_changed = host ~= _relic_lease_view.host
		if host_changed then
			local previous_holder = _relic_lease_view.holder
			_relic_lease_view.host = host
			_relic_lease_view.generation = 0
			_relic_lease_view.holder = nil
			_relic_lease_view.holder_melee = false
			_relic_lease_view.holder_ranged = false
			if _lease_is_server() then
				if _relic_lease_authority_epoch < 1 then
					_lease_begin_authority_epoch("host-promotion")
				end
			else
				_relic_lease_authority_epoch = 0
				_relic_lease_view.authority_peer = nil
				_relic_lease_view.authority_epoch = 0
			end
			_relic_lease_query_time = 0
			_relic_lease_query_attempts = 0
			_relic_lease_query_complete = _lease_is_server()
			_lease_refresh_trophies("host-changed")
			if _lease_is_server() then
				local rebuilt, status = _shared_relic_policy.rebuild_authority(
					previous_holder, local_peer, _relic_lease_local_active,
					_remote_blightreaper)
				_relic_lease_authority = rebuilt
				_relic_lease_migration_reservation_time =
					status == "reserved" and 0 or nil
				_lease_diag("authority rebuilt host=%s previous=%s status=%s holder=%s",
					tostring(local_peer), tostring(previous_holder), tostring(status),
					tostring(rebuilt.holder or "none"))
			elseif host and host ~= local_peer then
				-- Send before an eager host-ready snapshot can mark the query complete.
				_relic_lease_query_attempts = 1
				_lease_send_reassert_and_query(host)
			end
		end

		if _lease_is_server() then
			if host_changed then _lease_publish_state("others", "host-ready") end
			if _shared_relic_policy.is_migration_reserved(
					_relic_lease_authority) then
				_relic_lease_migration_reservation_time =
					(_relic_lease_migration_reservation_time or 0) + dt
				if _relic_lease_migration_reservation_time >=
						_shared_relic_policy.MIGRATION_RESERVATION_SECONDS then
					local expired = _shared_relic_policy.expire_migration_reservation(
						_relic_lease_authority)
					_relic_lease_migration_reservation_time = nil
					if expired then
						_lease_publish_state("others", "migration-reservation-expired")
					end
				end
			end
			local holder = _relic_lease_authority.holder
			if not holder then
				_relic_lease_missing_time = 0
				return
			end
			local pm = Managers and Managers.player
			local ok, player = false, nil
			if pm and type(pm.player_from_peer_id) == "function" then
				ok, player = pcall(pm.player_from_peer_id, pm, holder, 1)
			end
			if ok and player then
				_relic_lease_missing_time = 0
			else
				_relic_lease_missing_time = _relic_lease_missing_time + dt
				if _shared_relic_policy.disconnect_expired(
						_relic_lease_authority, _relic_lease_missing_time) then
					local changed = _shared_relic_policy.forget_peer(
						_relic_lease_authority, holder)
					_relic_lease_missing_time = 0
					if changed then _lease_publish_state("others", "holder-disconnected") end
				end
			end
			return
		end

		if not host or host == local_peer
				or (_relic_lease_query_complete
					and not _lease_needs_claim_reassert(local_peer))
				or _relic_lease_query_attempts >= 4 then return end
		_relic_lease_query_time = _relic_lease_query_time + dt
		if _relic_lease_query_time < 1 then return end
		_relic_lease_query_time = 0
		_relic_lease_query_attempts = _relic_lease_query_attempts + 1
		-- Reassert before the snapshot request. Empty snapshots keep retrying while
		-- a local relic remains active; a rival-holder verdict switches to rollback.
		_lease_send_reassert_and_query(host)
	end

	local function _lease_reset(reason)
		_relic_lease_state_active = false
		_relic_lease_authority = _shared_relic_policy.new_state()
		_relic_lease_authority_epoch = 0
		_relic_lease_view.authority_peer = nil
		_relic_lease_view.authority_epoch = 0
		_relic_lease_view.generation = 0
		_relic_lease_view.holder = nil
		_relic_lease_view.holder_melee = false
		_relic_lease_view.holder_ranged = false
		_relic_lease_view.host = nil
		_relic_lease_local_active = {}
		_relic_lease_pending = {}
		_relic_lease_rollback_retry = {}
		_relic_lease_rollback = false
		_relic_lease_migration_reservation_time = nil
		_relic_lease_missing_time = 0
		_relic_lease_query_time = 0
		_relic_lease_query_attempts = 0
		_relic_lease_query_complete = false
		_relic_lease_seeded = false
		_relic_lease_client_session_epoch = 0
		_remote_blightreaper =
			_shared_relic_policy.clear_identity_cache(_remote_blightreaper)
		_lease_refresh_trophies(reason)
		_relic_trophy_extensions = setmetatable({}, { __mode = "k" })
	end

	local function _lease_activate_session(reason)
		if _relic_lease_state_active then return false end
		_relic_lease_state_active = true
		_relic_lease_client_session_counter =
			_relic_lease_client_session_counter + 1
		_relic_lease_client_session_epoch =
			_relic_lease_client_session_counter
		if _lease_is_server() and _relic_lease_authority_epoch < 1 then
			_lease_begin_authority_epoch(reason)
		end
		_relic_lease_query_time = 0
		_relic_lease_query_attempts = 0
		_relic_lease_query_complete = _lease_is_server()
		return true
	end

	mod:command("woc_relic_lease_audit",
		"Log the bounded shared-Blightreaper lease state",
		function()
			pcall(printf,
				"[WOC:934] audit host=%s local=%s server=%s epoch=%s generation=%s holder=%s melee=%s ranged=%s query=%d complete=%s",
				tostring(_lease_host_peer_id()), tostring(_lease_local_peer_id()),
				tostring(_lease_is_server()),
				tostring(_relic_lease_view.authority_epoch),
				tostring(_relic_lease_view.generation),
				tostring(_relic_lease_view.holder or "none"),
				tostring(_relic_lease_local_active.slot_melee == true),
				tostring(_relic_lease_local_active.slot_ranged == true),
				_relic_lease_query_attempts, tostring(_relic_lease_query_complete))
		end)

	_rt_register("issue934_shared_relic_lease_contract", function()
		if _shared_relic_policy.BACKEND_ID ~= BACKEND_ID
				or _shared_relic_policy.ITEM_KEY ~= ITEM_KEY then
			return "shared-relic identity diverged from the registered Blightreaper"
		end
		local state = _shared_relic_policy.new_state()
		local granted = _shared_relic_policy.apply_identity(
			state, "peer-a", "slot_melee", true)
		local changed, verdict = _shared_relic_policy.apply_identity(
			state, "peer-b", "slot_melee", true)
		if not granted or changed or verdict ~= "denied"
				or state.holder ~= "peer-a" then
			return "first-claimant host lease policy failed"
		end
		if not (rawget(_G, "BackendUtils")
				and type(BackendUtils.set_loadout_item) == "function") then
			return "BackendUtils.set_loadout_item unavailable -- equip gate did not install"
		end
		local hero_overview = rawget(_G, "HeroViewStateOverview")
		if not (hero_overview
				and type(hero_overview._set_loadout_item) == "function") then
			return "HeroViewStateOverview._set_loadout_item unavailable -- UI gate did not install"
		end
		local simple_inventory = rawget(_G, "SimpleInventoryExtension")
		if not (simple_inventory
				and type(simple_inventory.create_equipment_in_slot) == "function") then
			return "SimpleInventoryExtension.create_equipment_in_slot unavailable -- live gate did not install"
		end
		local resolution = _shared_relic_policy.loser_resolution(
			nil, BACKEND_ID)
		if resolution ~= "clear-persisted" then
			return "pre-equipped loser did not resolve to durable fail-closed state"
		end
		if _shared_relic_policy.rollback_converged(
				"clear-persisted", nil, nil, BACKEND_ID, true, true) then
			return "live relic incorrectly satisfied durable rollback convergence"
		end
	end)


	local runtime = {}

	function runtime:update(dt)
		_lease_update(dt)
	end

	function runtime:on_game_state_changed(status, state_name)
		if status == "enter" then
			_lease_activate_session("game-state-enter:" .. tostring(state_name))
		elseif status == "exit" then
			_relic_lease_state_active = false
			_lease_reset("game-state-exit:" .. tostring(state_name))
		end
	end

	function runtime:on_enabled(reason)
		return _lease_activate_session(reason or "mod-enabled")
	end

	function runtime:reset(reason)
		_lease_reset(reason)
	end

	-- LoadoutUtils rows are transport observations, not rollback proof. Only the
	-- exact local human may publish a lease intent; remote and bot replay stays
	-- on vanilla's wire-safe shadow and has no WOC identity write surface.
	function runtime:observe_loadout_sync(player, slot_name, is_blightreaper)
		local is_local_human = (slot_name == "slot_melee"
				or slot_name == "slot_ranged")
			and _lease_is_local_human(player)
		local rollback_pending = is_local_human
			and _relic_lease_rollback_retry[slot_name] ~= nil
		if is_local_human and not _relic_lease_rollback
				and not rollback_pending then
			_lease_on_local_identity(slot_name, is_blightreaper)
		end
		return is_local_human
	end

	function runtime:identity_for_peer(peer_id)
		return _lease_identity_snapshot(peer_id)
	end

	if context.test_api then
		function runtime:test_snapshot()
			local retries = {}
			for slot_name, retry in pairs(_relic_lease_rollback_retry) do
				retries[slot_name] = {
					attempts = retry.attempts,
					delay = retry.delay,
					fail_closed = retry.fail_closed,
				}
			end
			return {
				active = _relic_lease_state_active,
				authority_epoch = _relic_lease_authority_epoch,
				view_epoch = _relic_lease_view.authority_epoch,
				generation = _relic_lease_view.generation,
				holder = _relic_lease_view.holder,
				local_melee = _relic_lease_local_active.slot_melee == true,
				retries = retries,
			}
		end
	end

	return runtime
end

return M
