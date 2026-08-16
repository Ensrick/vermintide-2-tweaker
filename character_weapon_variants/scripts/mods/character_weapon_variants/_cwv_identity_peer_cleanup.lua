-- Client-visible cleanup for the exact CWV appearance lifecycle (#914).
--
-- GameNetworkManager.remove_peer is server-side. A client observes the remote
-- human disappearing through PlayerManager.remove_player instead. Capture the
-- human before vanilla removes it, preserve vanilla, then clear only that
-- peer's semantic identity/delivery/dedupe routes. Level transitions also use
-- this seam; that is safe for this particular cache because the bounded
-- peer-ready pull reconstructs it after the next local inventory initializes.

local M = {}

function M.install(mod, lifecycle, player_manager_class, peer_resolver, print_fn,
		current_peer_id)
	if type(player_manager_class) ~= "table"
			or type(peer_resolver) ~= "table"
			or type(peer_resolver.peer_player) ~= "function"
			or type(lifecycle) ~= "table"
			or type(lifecycle.clear_peer) ~= "function" then
		return false
	end
	if mod._cwv914_client_peer_cleanup_installed then return true end

	mod:hook(player_manager_class, "remove_player", function(func, self,
			peer_id, local_player_id)
		local player = nil
		local local_peer = nil
		if type(current_peer_id) == "function" then
			local ok, value = pcall(current_peer_id)
			if ok then local_peer = value end
		end
		-- Humans always occupy local-player id 1 at their peer; host bots ride
		-- the host peer at ids 2..4 (game_object_destroyed_player removes them
		-- on clients with their real local_player_id). Without this gate,
		-- peer_player's players_at_peer fallback resolves a removed BOT to the
		-- still-present host HUMAN and a mid-session bot replacement would wipe
		-- the host's exact identity on every client (#914).
		if self and self.is_server == false and type(peer_id) == "string"
				and peer_id ~= "" and peer_id ~= local_peer
				and (local_player_id == nil or local_player_id == 1) then
			player = peer_resolver.peer_player(self, peer_id, local_player_id)
		end
		local r1, r2, r3, r4 = func(self, peer_id, local_player_id)
		if player then
			lifecycle:clear_peer(peer_id)
			pcall(print_fn,
				"[cwv:914] lifecycle=peer_remove adapter=client_player_manager peer=%s human=true cleared=true",
				tostring(peer_id))
		end
		return r1, r2, r3, r4
	end)
	mod._cwv914_client_peer_cleanup_installed = true
	return true
end

return M
