return function(H, repo_root)
    local mod_root = repo_root .. "/event_tweaker/scripts/mods/event_tweaker"
    local path = mod_root .. "/_evt_diag_tzeentch_twins.lua"
    local old_path = mod_root .. "/_evt_issue1309_probe.lua"
    local owner_path = mod_root .. "/_evt_diagnostics.lua"
    local Probe = dofile(path)

    local function read(source_path)
        local file = assert(io.open(source_path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local function count_literal(source, needle)
        local count = 0
        local cursor = 1
        while true do
            local found = source:find(needle, cursor, true)
            if not found then return count end
            count = count + 1
            cursor = found + #needle
        end
    end

    H.test("Tzeentch diagnostic has one role-owned runtime consumer", function()
        local old = io.open(old_path, "rb")
        if old then old:close() end
        H.equal(old, nil, "legacy probe path must stay absent")

        local owner = read(owner_path)
        H.equal(count_literal(owner,
            'require("scripts/mods/event_tweaker/_evt_diag_tzeentch_twins")'), 1)
        H.equal(count_literal(owner, 'ET.rt_register("issue1309_tzeentch_diag_armed"'), 1)

        local diagnostic = read(path)
        H.equal(count_literal(diagnostic, 'M.PREFIX = "[et:1149t]"'), 1)
        H.equal(count_literal(diagnostic, "M.RECEIPT_CAP = 10"), 1)
    end)

    H.test("Tzeentch diagnostic keeps the receipt prefix issue 1309 names", function()
        H.equal(Probe.PREFIX, "[et:1149t]")
        H.equal(Probe.CURSE, "curse_change_of_tzeentch")
        H.equal(Probe.SPLIT_CHANCE, 0.25)
        H.equal(Probe.RECEIPT_CAP, 10)
    end)

    H.test("Tzeentch roll classifier matches the template's early return", function()
        H.equal(Probe.classify_roll(0), "pass")
        H.equal(Probe.classify_roll(0.24), "pass")
        H.equal(Probe.classify_roll(Probe.SPLIT_CHANCE), "pass")
        H.equal(Probe.classify_roll(0.2500001), "fail")
        H.equal(Probe.classify_roll(0.9), "fail")
        H.equal(Probe.classify_roll(nil), "unknown")
        H.equal(Probe.classify_roll("0.1"), "unknown")
    end)

    H.test("Tzeentch activation receipt fires once and records the seed", function()
        local state = Probe.new_session()
        H.equal(state.armed, false)

        local first = Probe.arm(state, "host", 90210, true)
        H.truthy(first)
        H.truthy(first:find("[et:1149t] activated role=host seed=90210 template_active=true", 1, true))
        H.truthy(first:find("cap=10", 1, true))
        H.equal(state.armed, true)
        H.equal(state.role, "host")

        H.equal(Probe.arm(state, "host", 90210, true), nil)
        H.equal(state.armed, true)
    end)

    H.test("Tzeentch activation reports a nil seed rather than hiding it", function()
        local state = Probe.new_session()
        local line = Probe.arm(state, "client", nil, false)
        H.truthy(line:find("seed=nil", 1, true))
        H.truthy(line:find("template_active=false", 1, true))
        H.equal(state.seed, nil)
    end)

    H.test("Tzeentch role naming reports a listen host as the host", function()
        H.equal(Probe.role_name(true), "host")
        H.equal(Probe.role_name(false), "client")
        H.equal(Probe.role_name(nil), "client")
    end)

    H.test("Tzeentch host receipt reports roll, enqueue and seed advance", function()
        local state = Probe.new_session()
        Probe.arm(state, "host", 5, true)

        local pass = Probe.host_kill(state, "peer_a", "skaven_storm_vermin", 0.1, 2, 5, 6)
        H.truthy(pass:find("role=host", 1, true))
        H.truthy(pass:find("killer_peer=peer_a", 1, true))
        H.truthy(pass:find("breed=skaven_storm_vermin", 1, true))
        H.truthy(pass:find("verdict=pass", 1, true))
        H.truthy(pass:find("enqueued=2", 1, true))
        H.truthy(pass:find("seed_advanced=true", 1, true))

        local fail = Probe.host_kill(state, "peer_b", "chaos_marauder", 0.8, 0, 6, 7)
        H.truthy(fail:find("verdict=fail", 1, true))
        H.truthy(fail:find("enqueued=0", 1, true))

        local stuck = Probe.host_kill(state, "peer_b", "chaos_marauder", nil, nil, 7, 7)
        H.truthy(stuck:find("verdict=unknown", 1, true))
        H.truthy(stuck:find("enqueued=nil", 1, true))
        H.truthy(stuck:find("seed_advanced=false", 1, true))

        H.equal(state.kills_rolled, 3)
        H.equal(state.splits_spawned, 2)
    end)

    H.test("Tzeentch per-kill receipts are capped but counters keep running", function()
        local state = Probe.new_session()
        Probe.arm(state, "host", 1, true)
        local emitted = 0
        for i = 1, 40 do
            if Probe.host_kill(state, "peer", "skaven_clan_rat", 0.1, 1, i, i + 1) then
                emitted = emitted + 1
            end
        end
        H.equal(emitted, Probe.RECEIPT_CAP)
        H.equal(state.receipts, Probe.RECEIPT_CAP)
        H.equal(state.kills_rolled, 40)
        H.equal(state.splits_spawned, 40)
    end)

    H.test("Tzeentch client matches a replicated split inside the window", function()
        local state = Probe.new_session()
        Probe.arm(state, "client", nil, true)

        local line = Probe.client_death(state, "skaven_storm_vermin", "skaven_clan_rat", 100)
        H.truthy(line:find("role=client", 1, true))
        H.truthy(line:find("expected_split=skaven_clan_rat", 1, true))
        H.equal(state.deaths_seen, 1)

        H.equal(Probe.observe_spawn(state, "skaven_clan_rat", 100.5), true)
        H.equal(state.splits_matched, 1)
        H.equal(state.spawns_in_window, 1)
        H.equal(#state.pending, 0)
    end)

    H.test("Tzeentch client counts an unmatched spawn without claiming a split", function()
        local state = Probe.new_session()
        Probe.arm(state, "client", nil, true)
        Probe.client_death(state, "skaven_storm_vermin", "skaven_clan_rat", 100)

        H.equal(Probe.observe_spawn(state, "chaos_marauder", 100.5), false)
        H.equal(state.splits_matched, 0)
        H.equal(state.spawns_in_window, 1)
        H.equal(#state.pending, 1)
    end)

    H.test("Tzeentch client drops expectations once the window closes", function()
        local state = Probe.new_session()
        Probe.arm(state, "client", nil, true)
        Probe.client_death(state, "skaven_storm_vermin", "skaven_clan_rat", 100)

        local late = 100 + Probe.OBSERVE_WINDOW + 1
        H.equal(Probe.observe_spawn(state, "skaven_clan_rat", late), false)
        H.equal(state.splits_matched, 0)
        H.equal(state.spawns_in_window, 0)
        H.equal(#state.pending, 0)
    end)

    H.test("Tzeentch client records no expectation for an unresolvable breed", function()
        local state = Probe.new_session()
        Probe.arm(state, "client", nil, true)
        Probe.client_death(state, "skaven_loot_rat", nil, 100)
        H.equal(state.deaths_seen, 1)
        H.equal(#state.pending, 0)
        H.equal(Probe.observe_spawn(state, "skaven_clan_rat", 100.5), false)
        H.equal(state.spawns_in_window, 0)
    end)

    H.test("Tzeentch summary is one per peer and role-specific", function()
        local host = Probe.new_session()
        H.equal(Probe.summary(host), nil)

        Probe.arm(host, "host", 777, true)
        Probe.host_kill(host, "peer", "chaos_warrior", 0.1, 2, 1, 2)
        Probe.host_kill(host, "peer", "chaos_warrior", 0.9, 0, 2, 3)
        local host_line = Probe.summary(host)
        H.truthy(host_line:find("[et:1149t] summary role=host", 1, true))
        H.truthy(host_line:find("seed=777", 1, true))
        H.truthy(host_line:find("kills_rolled=2", 1, true))
        H.truthy(host_line:find("splits_spawned=2", 1, true))
        H.equal(Probe.summary(host), nil)

        local client = Probe.new_session()
        Probe.arm(client, "client", nil, true)
        client.tier_map_state = "resolved"
        Probe.client_death(client, "skaven_storm_vermin", "skaven_clan_rat", 10)
        Probe.observe_spawn(client, "skaven_clan_rat", 10.5)
        local client_line = Probe.summary(client)
        H.truthy(client_line:find("[et:1149t] summary role=client", 1, true))
        H.truthy(client_line:find("template_active=true", 1, true))
        H.truthy(client_line:find("deaths_seen=1", 1, true))
        H.truthy(client_line:find("splits_matched=1", 1, true))
        H.truthy(client_line:find("tier_map=resolved", 1, true))
        H.equal(client_line:find("kills_rolled", 1, true), nil)
        H.equal(Probe.summary(client), nil)
    end)

    H.test("Tzeentch session reset restores a clean unarmed session", function()
        local state = Probe.new_session()
        Probe.arm(state, "host", 12, true)
        Probe.host_kill(state, "peer", "chaos_warrior", 0.1, 2, 1, 2)
        Probe.summary(state)

        Probe.reset(state)
        H.equal(state.armed, false)
        H.equal(state.role, nil)
        H.equal(state.seed, nil)
        H.equal(state.receipts, 0)
        H.equal(state.kills_rolled, 0)
        H.equal(state.splits_spawned, 0)
        H.equal(state.summary_emitted, false)
        H.equal(#state.pending, 0)
        H.equal(state.tier_map_state, "unread")
        H.truthy(Probe.arm(state, "client", 3, false))
    end)

    H.test("Tzeentch probe tolerates a missing session table", function()
        H.equal(Probe.arm(nil, "host", 1, true), nil)
        H.equal(Probe.host_kill(nil, "peer", "breed", 0.1, 1, 1, 2), nil)
        H.equal(Probe.client_death(nil, "breed", "split", 1), nil)
        H.equal(Probe.observe_spawn(nil, "breed", 1), false)
        H.equal(Probe.summary(nil), nil)
        H.equal(Probe.take_receipt(nil), false)
        Probe.reset(nil)
    end)
end
