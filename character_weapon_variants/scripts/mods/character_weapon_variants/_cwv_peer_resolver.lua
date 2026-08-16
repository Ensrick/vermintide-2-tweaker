-- Protected PlayerManager/ProfileSynchronizer lookups for CWV peer render state.
--
-- Do not write `local ok, value = manager and pcall(...)`: Lua adjusts a
-- logical expression to one result, so only pcall's success flag survives and
-- `value` is always nil. Keep every protected multi-return call in an explicit
-- branch and expose the result through this one engine-free policy (#786).
local M = {}

function M.alive_unit(value, unit_api)
	if type(value) ~= "userdata" or type(unit_api) ~= "table"
			or type(unit_api.alive) ~= "function" then return false end
	local ok, alive = pcall(unit_api.alive, value)
	return ok and alive == true
end

local function local_player_id(player)
	if type(player) ~= "table" then return nil end
	if type(player.local_player_id) == "function" then
		local ok, value = pcall(player.local_player_id, player)
		if ok and value ~= nil then return value end
	end
	return player._local_player_id
end

local function controlled(player)
	if type(player) ~= "table" then return false end
	if type(player.is_player_controlled) == "function" then
		local ok, value = pcall(player.is_player_controlled, player)
		-- An explicit false is authoritative: do not let a malformed/stale
		-- local-player id turn a known bot into a human transport identity.
		if ok and value ~= nil then return value == true end
	end
	-- Host bots share the human peer id but never local-player id 1.
	return local_player_id(player) == 1
end

function M.player_peer_id(player)
	if type(player) ~= "table" then return nil end
	if type(player.peer_id) == "string" and player.peer_id ~= "" then
		return player.peer_id
	end
	if type(player.network_id) == "function" then
		local ok, value = pcall(player.network_id, player)
		if ok and type(value) == "string" and value ~= "" then return value end
	end
	return nil
end

-- SimpleHuskInventoryExtension.init receives the exact RemotePlayer before
-- PlayerManager's unit-owner table is guaranteed to be populated. Prefer that
-- spawn-local fact only when it is a human and does not point at a different
-- unit; otherwise fall back to the ordinary manager lookup (#914).
function M.husk_owner(player_manager, owner_unit, hinted_player)
	if controlled(hinted_player) then
		local hinted_unit = hinted_player.player_unit
		if (hinted_unit == nil or hinted_unit == owner_unit)
				and M.player_peer_id(hinted_player) then
			return hinted_player, "husk_extension_player"
		end
	end
	return M.owner(player_manager, owner_unit)
end

function M.owner(player_manager, owner_unit)
	if type(player_manager) ~= "table" or type(player_manager.owner) ~= "function" then
		return nil, "owner resolver unavailable"
	end
	local ok, player = pcall(player_manager.owner, player_manager, owner_unit)
	if not ok then return nil, "owner resolver error" end
	if not player then return nil, "owner unavailable" end
	if not controlled(player) then return nil, "owner not human" end
	return player, "owner"
end

function M.local_player(player_manager, local_player_id_value)
	if type(player_manager) ~= "table"
			or type(player_manager.local_player) ~= "function" then
		return nil, "local player resolver unavailable"
	end
	local ok, player = pcall(player_manager.local_player, player_manager,
		local_player_id_value or 1)
	if not ok then return nil, "local player resolver error" end
	if not player then return nil, "local player unavailable" end
	if not controlled(player) then return nil, "local player not human" end
	return player, "local_player"
end

function M.peer_player(player_manager, peer_id, local_player_id_value)
	if type(player_manager) ~= "table" then
		return nil, "player manager unavailable"
	end
	if type(player_manager.player_from_peer_id) == "function" then
		local ok, player = pcall(player_manager.player_from_peer_id,
			player_manager, peer_id, local_player_id_value or 1)
		if ok and controlled(player) then return player, "player_from_peer_id" end
	end
	-- Every route is deliberately human-only. Host bots share the host peer id
	-- at local-player ids 2..4 and must never consume a human's style/mode state.
	if type(player_manager.players_at_peer) == "function" then
		local ok, players = pcall(player_manager.players_at_peer,
			player_manager, peer_id)
		if ok and type(players) == "table" then
			for _, player in pairs(players) do
				if controlled(player) then return player, "players_at_peer" end
			end
		end
	end
	return nil, "player unavailable"
end

function M.human_players(player_manager)
	if type(player_manager) ~= "table"
			or type(player_manager.human_players) ~= "function" then
		return nil, "human players unavailable"
	end
	local ok, players = pcall(player_manager.human_players, player_manager)
	if not ok or type(players) ~= "table" then
		return nil, "human players unavailable"
	end
	return players, "human_players"
end

function M.profile_by_peer(profile_synchronizer, peer_id, local_player_id_value)
	if type(profile_synchronizer) ~= "table"
			or type(profile_synchronizer.profile_by_peer) ~= "function" then
		return nil, nil, "profile resolver unavailable"
	end
	local ok, profile_index, career_index = pcall(
		profile_synchronizer.profile_by_peer, profile_synchronizer,
		peer_id, local_player_id_value or 1)
	if not ok then return nil, nil, "profile resolver error" end
	return profile_index, career_index,
		(profile_index ~= nil and career_index ~= nil) and "profile_by_peer"
			or "profile unavailable"
end

return M
