return function(H, repo_root)
	local identity = dofile(repo_root
		.. "/weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_team_preview_identity.lua")

	local scores = {
		human_merc = {
			peer_id = "peer-host", local_player_id = 1,
			profile_index = 5, career_index = 1,
			is_player_controlled = true,
		},
		human_gk = {
			peer_id = "peer-client", local_player_id = 1,
			profile_index = 5, career_index = 4,
			is_player_controlled = true,
		},
		bot_priest = {
			peer_id = "peer-host", local_player_id = 1,
			profile_index = 2, career_index = 3,
			is_player_controlled = false,
		},
	}

	H.test("WOC #613 score identity resolves only the exact human wearer", function()
		local peer, source = identity.resolve_score_peer(5, 4, scores)
		H.equal(peer, "peer-client")
		H.equal(source, "score_snapshot")

		peer, source = identity.resolve_score_peer(2, 3, scores)
		H.equal(peer, nil)
		H.equal(source, "score_snapshot_bot")

		peer = identity.resolve_score_peer(5, 3, scores)
		H.equal(peer, nil, "career-only fallback must remain impossible")
		peer = identity.resolve_score_peer(5, 4, {
			row = {
				peer_id = "peer-client", local_player_id = 1,
				profile_index = 5, career_index = 4,
			},
		})
		H.equal(peer, nil, "an incomplete score row is not authenticated identity")
		peer, source = identity.resolve_score_peer(5, 4, {
			one = scores.human_gk,
			two = {
				peer_id = "peer-rival", local_player_id = 1,
				profile_index = 5, career_index = 4,
				is_player_controlled = true,
			},
		})
		H.equal(peer, nil)
		H.equal(source, "score_snapshot_ambiguous")
	end)

	H.test("WOC #613 live identity rejects bots and profile-only matches", function()
		local human = { peer_id = "peer-human", profile = 5, career = 4 }
		local wrong_career = { peer_id = "peer-other", profile = 5, career = 1 }
		local bot = {
			peer_id = "peer-human", profile = 2, career = 3, bot_player = true,
		}
		local function profile_for(player)
			return player.profile, player.career
		end
		local peer, source = identity.resolve_live_peer(5, 4,
			{ human, wrong_career, bot }, profile_for)
		H.equal(peer, "peer-human")
		H.equal(source, "live_profile")
		peer, source = identity.resolve_live_peer(2, 3,
			{ human, wrong_career, bot }, profile_for)
		H.equal(peer, nil)
		H.equal(source, "live_miss")
		peer, source = identity.resolve_live_peer(5, 4,
			{ human, { peer_id = "peer-rival", profile = 5, career = 4 } },
			profile_for)
		H.equal(peer, nil)
		H.equal(source, "live_ambiguous")
	end)

	H.test("WOC #613 accepted snapshot token is peer generation and key bound", function()
		local snapshot = {
			key = "woc_blightreaper", peer_id = "peer-wearer",
			authority_peer = "peer-host", authority_epoch = 3,
			generation = 7, slot_melee = true, slot_ranged = false,
		}
		local token = identity.snapshot_token(
			snapshot, "peer-wearer", "woc_blightreaper")
		H.equal(token, "peer-host:3:7:peer-wearer:woc_blightreaper:1:0")
		H.truthy(identity.active_for_slot(
			snapshot, "peer-wearer", "woc_blightreaper", "slot_melee"))
		H.equal(identity.active_for_slot(
			snapshot, "peer-wearer", "woc_blightreaper", "slot_ranged"), false)
		H.equal(identity.snapshot_token(
			snapshot, "peer-rival", "woc_blightreaper"), nil)
		H.equal(identity.snapshot_token(
			snapshot, "peer-wearer", "different-key"), nil)
		H.equal(identity.snapshot_token(snapshot, "peer-wearer", nil), nil)
		local prior = token
		snapshot.authority_peer = "peer-promoted-host"
		H.equal(identity.snapshot_token(
			snapshot, "peer-wearer", "woc_blightreaper"),
			"peer-promoted-host:3:7:peer-wearer:woc_blightreaper:1:0")
		snapshot.authority_peer = nil
		H.equal(identity.snapshot_token(
			snapshot, "peer-wearer", "woc_blightreaper"), nil)
		snapshot.authority_peer = "peer-host"
		H.equal(identity.snapshot_token(
			snapshot, "peer-wearer", "woc_blightreaper"), prior)
		snapshot.slot_melee = 1
		H.equal(identity.snapshot_token(
			snapshot, "peer-wearer", "woc_blightreaper"), nil,
			"wire integers must not leak into the authenticated semantic view")
	end)
end
