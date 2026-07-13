return function(H, repo_root)
    local path = repo_root
        .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_score_identity.lua"
    local identity = assert(loadfile(path))()
    local resolve = identity.resolve_snapshot

    local scores = {
        human_gk = { peer_id = "host", local_player_id = 1,
            profile_index = 5, career_index = 4, is_player_controlled = true },
        human_merc = { peer_id = "client", local_player_id = 1,
            profile_index = 5, career_index = 1, is_player_controlled = true },
        bot_sienna = { peer_id = "host", local_player_id = 1,
            profile_index = 1, career_index = 4, is_player_controlled = false },
        bot_priest = { peer_id = "host", local_player_id = 1,
            profile_index = 2, career_index = 3, is_player_controlled = false },
    }

    H.test("score identity resolves exact human profile and career", function()
        local peer, source = resolve(5, 4, scores)
        H.equal(peer, "host")
        H.equal(source, "score_snapshot")

        peer, source = resolve(5, 1, scores)
        H.equal(peer, "client")
        H.equal(source, "score_snapshot")
    end)

    H.test("score identity rejects bots sharing the host peer", function()
        local peer, source = resolve(1, 4, scores)
        H.equal(peer, nil)
        H.equal(source, "score_snapshot_bot")

        peer, source = resolve(2, 3, scores)
        H.equal(peer, nil)
        H.equal(source, "score_snapshot_bot")
    end)

    H.test("score identity never falls back to career-only or incomplete rows", function()
        local peer = resolve(5, 3, scores)
        H.equal(peer, nil)
        peer = resolve(5, nil, scores)
        H.equal(peer, nil)
        peer = resolve(5, 4, {
            row = { peer_id = "host", local_player_id = 1,
                profile_index = 5, career_index = 4 },
        })
        H.equal(peer, nil)
    end)

    H.test("bot skeleton mismatch cannot purge its human owner's store", function()
        H.equal(identity.should_purge_mismatch(false), false)
        H.equal(identity.should_purge_mismatch(nil), false)
        H.equal(identity.should_purge_mismatch(true), true)
    end)
end
