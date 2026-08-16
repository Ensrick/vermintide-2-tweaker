-- Behavioral coverage for the Allow Duplicate Careers host-authority core
-- (issue #1150): drives the REAL shipped _gt_dupc_policy.lua. The two report
-- directions are pinned: host ON / client OFF allows, host OFF (or unknown) /
-- client ON blocks.
return function(H, repo_root)
    local path = repo_root
        .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_dupc_policy.lua"
    local Policy = assert(loadfile(path))()

    H.test("gt dupc host follows its own local setting", function()
        H.equal(Policy.effective_session(true, true, nil), true)
        H.equal(Policy.effective_session(true, false, nil), false)
        -- A stray advertised value never overrides the host's own state.
        H.equal(Policy.effective_session(true, false, "1"), false)
        H.equal(Policy.effective_session(true, true, "0"), true)
    end)

    H.test("gt dupc issue 1150: host ON / client OFF allows the duplicate", function()
        H.equal(Policy.effective_session(false, false, "1"), true)
    end)

    H.test("gt dupc issue 1150: host OFF or unknown / client ON blocks", function()
        H.equal(Policy.effective_session(false, true, "0"), false)
        -- Unknown host state (vanilla host, flag unreadable): fail closed.
        H.equal(Policy.effective_session(false, true, nil), false)
        H.equal(Policy.effective_session(false, true, "garbage"), false)
    end)

    H.test("gt dupc lobby-scoped gate prefers the evaluated lobby's own flag", function()
        -- Browsing another host's lobby: its flag wins over everything local.
        H.equal(Policy.effective_for_lobby("1", false, false, "0"), true)
        H.equal(Policy.effective_for_lobby("0", false, true, "1"), false)
        -- Id-less fallback on the HOST: the only id-less caller is the host's
        -- own session surface, so the host's local setting applies there.
        H.equal(Policy.effective_for_lobby(nil, true, true, nil), true)
        H.equal(Policy.effective_for_lobby(nil, true, false, nil), false)
        -- Client with an id-less (makeshift) table: session semantics.
        H.equal(Policy.effective_for_lobby(nil, false, false, "1"), true)
        H.equal(Policy.effective_for_lobby(nil, false, true, nil), false)
    end)

    H.test("gt dupc serialize/parse round-trip and garbage rejection", function()
        H.equal(Policy.parse(Policy.serialize(true)), true)
        H.equal(Policy.parse(Policy.serialize(false)), false)
        H.equal(Policy.parse(nil), nil)
        H.equal(Policy.parse(""), nil)
        H.equal(Policy.parse("yes"), nil)
        H.equal(Policy.LOBBY_KEY, "gtw_dupc")
    end)
end
