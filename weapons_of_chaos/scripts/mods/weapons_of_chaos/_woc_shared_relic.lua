-- Host-authoritative lease policy for lobby-unique Weapons of Chaos relics.
--
-- This module is deliberately engine-free.  The WOC entry point owns VMF RPC,
-- backend, player-manager, and keep-decoration seams; this file owns the
-- deterministic state machine those seams drive.

local M = {}

M.SCHEMA = 1
M.ITEM_KEY = "woc_blightreaper"
M.BACKEND_ID = "woc_blightreaper_001"
M.TROPHY = "hub_trophy_bogenhafen"
M.EMPTY_TROPHY = "hub_trophy_empty"
M.MIGRATION_RESERVATION_SECONDS = 4
M.DISCONNECT_GRACE_SECONDS = 3
M.ROLLBACK_RETRY_BASE_SECONDS = 0.5
M.ROLLBACK_RETRY_MAX_SECONDS = 8
M.ROLLBACK_FAIL_CLOSED_AFTER = 4

local VALID_SLOTS = {
	slot_melee = true,
	slot_ranged = true,
}
local ORDERED_SLOTS = {
	"slot_melee",
	"slot_ranged",
}

local function valid_peer(peer_id)
	return type(peer_id) == "string" and peer_id ~= ""
end

local function has_claim(claims)
	for _, active in pairs(claims or {}) do
		if active then return true end
	end
	return false
end

function M.new_state()
	return {
		generation = 0,
		holder = nil,
		claims = {},
	}
end

-- Rebuild a fresh authority epoch when the resolved host changes. Preserve the
-- previous authenticated holder first; if no snapshot was available, prefer
-- the promoted host's own live slot. A holder whose exact slot has not reached
-- the new host remains fail-closed under a bounded reservation until its
-- immediate migration reassertion arrives.
function M.rebuild_authority(previous_holder, local_peer, local_slots, remote_slots)
	local state = M.new_state()
	local holder = valid_peer(previous_holder) and previous_holder or nil
	if not holder and valid_peer(local_peer) then
		for i = 1, #ORDERED_SLOTS do
			if type(local_slots) == "table" and local_slots[ORDERED_SLOTS[i]] == true then
				holder = local_peer
				break
			end
		end
	end
	if not holder then return state, "empty" end

	local slots = holder == local_peer and local_slots
		or (type(remote_slots) == "table" and remote_slots[holder])
	local confirmed = false
	for i = 1, #ORDERED_SLOTS do
		local slot_name = ORDERED_SLOTS[i]
		if type(slots) == "table" and slots[slot_name] == true then
			M.apply_identity(state, holder, slot_name, true)
			confirmed = true
		end
	end
	if confirmed then return state, "confirmed" end

	state.holder = holder
	state.claims[holder] = { _migration_reservation = true }
	state.generation = 1
	return state, "reserved"
end

function M.is_migration_reserved(state)
	local claims = type(state) == "table" and state.holder
		and state.claims and state.claims[state.holder]
	return type(claims) == "table" and claims._migration_reservation == true
end

function M.expire_migration_reservation(state)
	if not M.is_migration_reserved(state) then return false, "not-reserved" end
	state.claims[state.holder] = nil
	state.holder = nil
	state.generation = state.generation + 1
	return true, "reservation-expired"
end

-- First accepted claimant owns the relic until its last equipped slot is
-- released. A rival claim is rejected and is never retained as a queue: the
-- player must equip again after the current holder releases it.
function M.apply_identity(state, peer_id, slot_name, active)
	if type(state) ~= "table" or not valid_peer(peer_id)
			or not VALID_SLOTS[slot_name] or type(active) ~= "boolean" then
		return false, "invalid"
	end

	if active then
		if state.holder and state.holder ~= peer_id then
			return false, "denied"
		end
		local claims = state.claims[peer_id]
		if not claims then
			claims = {}
			state.claims[peer_id] = claims
		end
		local changed = not claims[slot_name] or claims._migration_reservation == true
		claims._migration_reservation = nil
		claims[slot_name] = true
		if not state.holder then
			state.holder = peer_id
			state.generation = state.generation + 1
			return true, "granted"
		end
		if changed then
			state.generation = state.generation + 1
		end
		return changed, changed and "retained" or "duplicate"
	end

	local claims = state.claims[peer_id]
	if not claims or not claims[slot_name] then
		return false, "duplicate"
	end
	claims[slot_name] = nil
	if not has_claim(claims) then
		state.claims[peer_id] = nil
		if state.holder == peer_id then
			state.holder = nil
			state.generation = state.generation + 1
			return true, "released"
		end
	end
	state.generation = state.generation + 1
	return true, "slot-released"
end

function M.forget_peer(state, peer_id)
	if type(state) ~= "table" or not valid_peer(peer_id)
			or state.claims[peer_id] == nil then
		return false, "absent"
	end
	state.claims[peer_id] = nil
	if state.holder == peer_id then
		state.holder = nil
		state.generation = state.generation + 1
		return true, "disconnected"
	end
	return true, "forgot-nonholder"
end

function M.can_equip(holder, peer_id)
	return holder == nil or holder == "" or holder == peer_id
end

function M.can_equip_backend(holder, peer_id, backend_id, slot_name)
	if backend_id ~= M.BACKEND_ID or not M.is_valid_slot(slot_name) then
		return true
	end
	return M.can_equip(holder, peer_id)
end

function M.trophy_for(requested_trophy, holder)
	if requested_trophy == M.TROPHY and valid_peer(holder) then
		return M.EMPTY_TROPHY
	end
	return requested_trophy
end

-- Clients accept only monotonic authority snapshots. Equal generations are
-- harmless replays only when the holder is byte-identical.
function M.accept_snapshot(current_generation, current_holder,
		incoming_generation, incoming_holder)
	if type(incoming_generation) ~= "number"
			or incoming_generation < 0
			or incoming_generation ~= math.floor(incoming_generation) then
		return false, "invalid-generation"
	end
	if incoming_holder == "" then incoming_holder = nil end
	if incoming_holder ~= nil and not valid_peer(incoming_holder) then
		return false, "invalid-holder"
	end
	current_generation = tonumber(current_generation) or 0
	if incoming_generation < current_generation then
		return false, "stale"
	end
	if incoming_generation == current_generation then
		if incoming_holder ~= current_holder then
			return false, "conflict"
		end
		return true, "replay", current_generation, current_holder
	end
	return true, "advanced", incoming_generation, incoming_holder
end

function M.should_rollback(holder, peer_id, local_active)
	return local_active == true and valid_peer(holder) and holder ~= peer_id
end

-- A rollback may use only the exact item observed immediately before the
-- Blightreaper write. Pre-equipped joiners have no such observation and must
-- remain fail-closed until the player selects a known item; never guess from
-- inventory enumeration.
function M.rollback_target(previous_backend_id)
	if type(previous_backend_id) == "string" and previous_backend_id ~= ""
			and previous_backend_id ~= M.BACKEND_ID then
		return previous_backend_id, "exact-prior"
	end
	return nil, "deferred-no-prior"
end

-- A losing client that has no exact prior item must not guess one from an
-- inventory enumeration. Clear the persisted slot when it is empty or still
-- names the relic. A different persisted backend id is an exact user-selected
-- target and may be replayed into the live slot.
function M.loser_resolution(previous_backend_id, current_backend_id)
	local target = M.rollback_target(previous_backend_id)
	if target then return "restore-exact", target end
	if current_backend_id and current_backend_id ~= M.BACKEND_ID then
		return "align-persisted", current_backend_id
	end
	return "clear-persisted", nil
end

function M.rollback_verified(write_ok, expected_backend_id, read_back_backend_id)
	return write_ok == true
		and type(expected_backend_id) == "string"
		and expected_backend_id ~= ""
		and read_back_backend_id == expected_backend_id
end

function M.clear_verified(write_ok, read_back_backend_id, read_back_status)
	return write_ok == true
		and read_back_status == "readback"
		and read_back_backend_id == nil
end

-- Releasing the host lease requires convergence at both durable and live
-- boundaries. A LoadoutUtils payload is intentionally not an input: hotjoin
-- and queued sync payloads can describe an item that is not in the current
-- local inventory slot.
function M.rollback_converged(mode, target_backend_id,
		persisted_backend_id, live_backend_id,
		persisted_read_verified, live_read_verified)
	if persisted_read_verified ~= true or live_read_verified ~= true then
		return false
	end
	if mode == "restore-exact" or mode == "align-persisted" then
		return type(target_backend_id) == "string"
			and target_backend_id ~= ""
			and target_backend_id ~= M.BACKEND_ID
			and persisted_backend_id == target_backend_id
			and live_backend_id == target_backend_id
	end
	if mode == "clear-persisted" then
		return persisted_backend_id == nil
			and live_backend_id ~= M.BACKEND_ID
	end
	return false
end

-- A denied relic never ages out of rollback. Retries spread out
-- exponentially to avoid a per-frame backend loop, then remain at one bounded
-- maximum interval until durable and live state both converge.
function M.rollback_retry_delay(attempts)
	attempts = math.max(tonumber(attempts) or 0, 0)
	local exponent = math.max(math.floor(attempts) - 1, 0)
	local delay = M.ROLLBACK_RETRY_BASE_SECONDS * (2 ^ exponent)
	return math.min(delay, M.ROLLBACK_RETRY_MAX_SECONDS)
end

function M.rollback_is_terminal_fail_closed(attempts)
	return (tonumber(attempts) or 0) >= M.ROLLBACK_FAIL_CLOSED_AFTER
end

function M.disconnect_expired(state, missing_seconds)
	if M.is_migration_reserved(state) then return false end
	return (tonumber(missing_seconds) or 0) >= M.DISCONNECT_GRACE_SECONDS
end

function M.clear_identity_cache(cache)
	if type(cache) ~= "table" then return {} end
	for peer_id in pairs(cache) do cache[peer_id] = nil end
	return cache
end

function M.is_valid_slot(slot_name)
	return VALID_SLOTS[slot_name] == true
end

return M
