-- Pure TeamPreviewer identity boundary for Blightreaper presentation (#613).
--
-- TeamPreviewer rows retain profile/career but the end-view conversion drops
-- peer identity. Scoreboard rows also give bots their owner's peer id, so only
-- an exact player-controlled profile+career row with a complete peer/local
-- tuple may address WOC's human-only authenticated lease snapshot.
local M = {}

local function positive_integer(value, allow_zero)
	return type(value) == "number"
		and value == math.floor(value)
		and value >= (allow_zero and 0 or 1)
end

function M.resolve_score_peer(profile_index, career_index, scores)
	if profile_index == nil or career_index == nil or type(scores) ~= "table" then
		return nil, "score_snapshot_miss"
	end
	local match
	for _, row in pairs(scores) do
		if type(row) == "table"
				and row.profile_index == profile_index
				and row.career_index == career_index then
			if match then return nil, "score_snapshot_ambiguous" end
			match = row
		end
	end
	if not match then return nil, "score_snapshot_miss" end
	if match.is_player_controlled ~= true then
		return nil, match.is_player_controlled == false
			and "score_snapshot_bot" or "score_snapshot_untrusted"
	end
	if type(match.peer_id) == "string" and match.peer_id ~= ""
			and positive_integer(match.local_player_id, true) then
		return match.peer_id, "score_snapshot"
	end
	return nil, "score_snapshot_untrusted"
end

-- `profile_for(player)` is the engine-facing seam. It must return both exact
-- indexes or nil; this pure owner never falls back to career-only matching.
function M.resolve_live_peer(profile_index, career_index, players, profile_for)
	if profile_index == nil or career_index == nil or type(players) ~= "table"
			or type(profile_for) ~= "function" then
		return nil, "live_unavailable"
	end
	local matched_peer
	for _, player in pairs(players) do
		if type(player) == "table" and player.bot_player ~= true
				and type(player.peer_id) == "string" and player.peer_id ~= "" then
			local resolved_profile, resolved_career = profile_for(player)
			if resolved_profile == profile_index
					and resolved_career == career_index then
				if matched_peer then return nil, "live_ambiguous" end
				matched_peer = player.peer_id
			end
		end
	end
	return matched_peer, matched_peer and "live_profile" or "live_miss"
end

function M.snapshot_token(snapshot, peer_id, item_key)
	if type(snapshot) ~= "table"
			or type(peer_id) ~= "string" or peer_id == ""
			or type(item_key) ~= "string" or item_key == ""
			or snapshot.peer_id ~= peer_id
			or snapshot.key ~= item_key
			or type(snapshot.authority_peer) ~= "string"
			or snapshot.authority_peer == ""
			or not positive_integer(snapshot.authority_epoch, false)
			or not positive_integer(snapshot.generation, true)
			or type(snapshot.slot_melee) ~= "boolean"
			or type(snapshot.slot_ranged) ~= "boolean" then
		return nil
	end
	return table.concat({
		snapshot.authority_peer, tostring(snapshot.authority_epoch),
		tostring(snapshot.generation), peer_id, item_key,
		snapshot.slot_melee and "1" or "0",
		snapshot.slot_ranged and "1" or "0",
	}, ":")
end

function M.active_for_slot(snapshot, peer_id, item_key, slot_name)
	if not M.snapshot_token(snapshot, peer_id, item_key) then return false end
	if slot_name == "slot_melee" or slot_name == "melee" then
		return snapshot.slot_melee == true
	end
	if slot_name == "slot_ranged" or slot_name == "ranged" then
		return snapshot.slot_ranged == true
	end
	return false
end

return M
