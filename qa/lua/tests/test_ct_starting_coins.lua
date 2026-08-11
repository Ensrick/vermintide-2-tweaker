return function(H, repo_root)
    local policy_path = repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_starting_coins_policy.lua"
    local Policy = assert(loadfile(policy_path))()

    H.test("CT issue 912 treats zero as an exact configured baseline", function()
        local value, configured = Policy.resolve(0, 175)
        H.equal(value, 0)
        H.equal(configured, true)
    end)

    H.test("CT issue 912 preserves every valid exact integer", function()
        for _, expected in ipairs({ 1, 25, 324, 3000 }) do
            local value, configured = Policy.resolve(expected, 999)
            H.equal(value, expected)
            H.equal(configured, true)
        end
    end)

    H.test("CT issue 912 fails malformed settings open to vanilla", function()
        for _, malformed in ipairs({ "0", -1, 3001, 1.5 }) do
            local value, configured = Policy.resolve(malformed, 175)
            H.equal(value, 175)
            H.equal(configured, false)
        end
        local value, configured = Policy.resolve(nil, 175)
        H.equal(value, 175)
        H.equal(configured, false)
    end)

    H.test("CT issue 912 runtime uses one policy at setup and join boundaries", function()
        local path = repo_root
            .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev.lua"
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()

        -- #1159 wave 14: the setup_run and host-RPC boundaries moved into
        -- _ct_run_creation_owner. The invariant is unchanged - FIVE call sites,
        -- ONE policy - it is now asserted across both files, with the per-file
        -- split pinned so a boundary cannot quietly grow a sixth resolve or lose
        -- one to a hand-rolled comparison.
        local owner_path = repo_root
            .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_run_creation_owner.lua"
        local of = assert(io.open(owner_path, "rb"))
        local owner_source = of:read("*a")
        of:close()
        local _, entry_resolves = source:gsub("_ct_starting_coins_policy%.resolve%(", "")
        local _, owner_resolves = owner_source:gsub("_ct_starting_coins_policy%.resolve%(", "")
        H.equal(entry_resolves + owner_resolves, 5,
            "setup, host RPC, command (local + host-effective), and runtime check must share policy")
        H.equal(owner_resolves, 2, "setup_run and the host RPC handler")
        H.equal(entry_resolves, 3, "the command's two readouts and the inline runtime check")
        H.equal(source:find("setting and setting > 0 and _starting_coins_applied_for_run ~= run_id",
            1, true), nil,
            "setup replay must not re-admit rollover currency")
        H.equal(Policy.MARKER, "starting_coins:exact-total-including-zero-v2",
            "zero-inclusive setter marker is missing")
        H.equal(source:find("raw_setting / 25", 1, true), nil,
            "runtime must not round exact VMF values to 25")
    end)

    -- #912 audit repair (2026-08-03): /verify_coins previously read only the
    -- LOCAL mod:get value while setup_run applies the HOST-BROADCAST
    -- effective_setting, so a client with a divergent local setting got a
    -- falsely reassuring readout. The command must report both, labeled.
    H.test("CT issue 912 verify_coins reports local AND host-effective values", function()
        local path = repo_root
            .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev.lua"
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()

        local cmd_pos = assert(source:find('mod:command("verify_coins"', 1, true),
            "/verify_coins command missing")
        local block = source:sub(cmd_pos, cmd_pos + 3200)
        H.truthy(block:find('mod:get("starting_coins")', 1, true),
            "raw local value must stay visible")
        H.truthy(block:find('effective_setting("starting_coins")', 1, true),
            "host-broadcast effective value (the one setup_run applies) must be read")
        H.truthy(block:find("host-effective=", 1, true),
            "output must label the host-effective value")
        H.truthy(block:find("APPLIED", 1, true),
            "output must mark which value is actually applied")
        H.truthy(block:find("MISMATCH", 1, true),
            "a local vs host divergence must be called out explicitly")
    end)
end
